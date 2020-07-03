###
# AWS VPC
###

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "covidshield" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true

  tags = {
    Name                  = var.vpc_name
    (var.billing_tag_key) = var.billing_tag_value
  }
}

###
# AWS VPC Privatelink Endpoints
###

resource "aws_vpc_endpoint" "ecr-dkr" {
  vpc_id              = aws_vpc.covidshield.id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  private_dns_enabled = true
  security_group_ids = [
    "${aws_security_group.privatelink.id}",
  ]
  subnet_ids = data.aws_subnet_ids.ecr_endpoint_available.ids
}

resource "aws_vpc_endpoint" "ecr-api" {
  vpc_id              = aws_vpc.covidshield.id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  private_dns_enabled = true
  security_group_ids = [
    "${aws_security_group.privatelink.id}",
  ]
  subnet_ids = data.aws_subnet_ids.ecr_endpoint_available.ids
}

resource "aws_vpc_endpoint" "kms" {
  vpc_id              = aws_vpc.covidshield.id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${var.region}.kms"
  private_dns_enabled = true
  security_group_ids = [
    "${aws_security_group.privatelink.id}",
  ]
  subnet_ids = aws_subnet.covidshield_public.*.id
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.covidshield.id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  private_dns_enabled = true
  security_group_ids = [
    "${aws_security_group.privatelink.id}",
  ]
  subnet_ids = aws_subnet.covidshield_public.*.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.covidshield.id
  vpc_endpoint_type = "Gateway"
  service_name      = "com.amazonaws.${var.region}.s3"
  route_table_ids   = [aws_vpc.covidshield.main_route_table_id]
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.covidshield.id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${var.region}.logs"
  private_dns_enabled = true
  security_group_ids = [
    "${aws_security_group.privatelink.id}",
  ]
  subnet_ids = aws_subnet.covidshield_public.*.id
}

resource "aws_vpc_endpoint" "monitoring" {
  vpc_id              = aws_vpc.covidshield.id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${var.region}.monitoring"
  private_dns_enabled = true
  security_group_ids = [
    "${aws_security_group.privatelink.id}",
  ]
  subnet_ids = aws_subnet.covidshield_public.*.id
}

###
# AWS Internet Gateway
###

resource "aws_internet_gateway" "covidshield" {
  vpc_id = aws_vpc.covidshield.id

  tags = {
    Name                  = var.vpc_name
    (var.billing_tag_key) = var.billing_tag_value
  }
}

###
# AWS Subnets
###

resource "aws_subnet" "covidshield_private" {
  count = 3

  vpc_id            = aws_vpc.covidshield.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name                  = "Private Subnet 0${count.index + 1}"
    (var.billing_tag_key) = var.billing_tag_value
    Access                = "private"
  }
}

resource "aws_subnet" "covidshield_public" {
  count = 3

  vpc_id            = aws_vpc.covidshield.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, count.index + 3)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name                  = "Public Subnet 0${count.index + 1}"
    (var.billing_tag_key) = var.billing_tag_value
    Access                = "public"
  }
}

data "aws_subnet_ids" "ecr_endpoint_available" {
  vpc_id = aws_vpc.covidshield.id
  filter {
    name   = "tag:Access"
    values = ["public"]
  }
  filter {
    name   = "availability-zone"
    values = ["ca-central-1a", "ca-central-1b"]
  }
  depends_on = [aws_subnet.covidshield_public]
}

###
# AWS NAT GW
###

resource "aws_eip" "covidshield_natgw" {
  count      = 3
  depends_on = [aws_internet_gateway.covidshield]

  vpc = true

  tags = {
    Name                  = "${var.vpc_name} NAT GW ${count.index}"
    (var.billing_tag_key) = var.billing_tag_value
  }
}

resource "aws_nat_gateway" "covidshield" {
  count      = 3
  depends_on = [aws_internet_gateway.covidshield]

  allocation_id = aws_eip.covidshield_natgw.*.id[count.index]
  subnet_id     = aws_subnet.covidshield_public.*.id[count.index]

  tags = {
    Name                  = "${var.vpc_name} NAT GW"
    (var.billing_tag_key) = var.billing_tag_value
  }
}


###
# AWS Routes
###

resource "aws_route_table" "covidshield_public_subnet" {
  vpc_id = aws_vpc.covidshield.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.covidshield.id
  }

  tags = {
    Name                  = "Public Subnet Route Table"
    (var.billing_tag_key) = var.billing_tag_value
  }
}

resource "aws_route_table_association" "covidshield" {
  count = 3

  subnet_id      = aws_subnet.covidshield_public.*.id[count.index]
  route_table_id = aws_route_table.covidshield_public_subnet.id
}

resource "aws_route_table" "covidshield_private_subnet" {
  count = 3

  vpc_id = aws_vpc.covidshield.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.covidshield.*.id[count.index]
  }

  tags = {
    Name                  = "Private Subnet Route Table ${count.index}"
    (var.billing_tag_key) = var.billing_tag_value
  }
}

resource "aws_route_table_association" "covidshield_private_route" {
  count = 3

  subnet_id      = aws_subnet.covidshield_private.*.id[count.index]
  route_table_id = aws_route_table.covidshield_private_subnet.*.id[count.index]
}


###
# AWS Security Groups
###

resource "aws_security_group" "covidshield_key_retrieval" {
  name        = "covidshield-key-retrieval"
  description = "Ingress - CovidShield Key Retrieval App"
  vpc_id      = aws_vpc.covidshield.id

  ingress {
    protocol  = "tcp"
    from_port = 8001
    to_port   = 8001
    security_groups = [
      aws_security_group.covidshield_load_balancer.id
    ]
  }

  egress {
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
    security_groups = [
      aws_security_group.privatelink.id
    ]
  }

  tags = {
    (var.billing_tag_key) = var.billing_tag_value
  }
}

resource "aws_security_group" "covidshield_key_submission" {
  name        = "covidshield-key-submission"
  description = "Ingress - CovidShield Key Submission App"
  vpc_id      = aws_vpc.covidshield.id

  ingress {
    protocol  = "tcp"
    from_port = 8000
    to_port   = 8000
    security_groups = [
      aws_security_group.covidshield_load_balancer.id
    ]
  }

  egress {
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
    security_groups = [
      aws_security_group.privatelink.id
    ]
  }

  tags = {
    (var.billing_tag_key) = var.billing_tag_value
  }
}

resource "aws_security_group" "covidshield_load_balancer" {
  name        = "covidshield-load-balancer"
  description = "Ingress - CovidShield Load Balancer"
  vpc_id      = aws_vpc.covidshield.id

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "tcp"
    from_port   = 8001
    to_port     = 8001
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    protocol    = "tcp"
    from_port   = 8000
    to_port     = 8000
    cidr_blocks = [var.vpc_cidr_block]
  }

  tags = {
    (var.billing_tag_key) = var.billing_tag_value
  }
}

resource "aws_security_group" "covidshield_database" {
  name        = "covidshield-database"
  description = "Ingress - CovidShield Database"
  vpc_id      = aws_vpc.covidshield.id

  ingress {
    protocol  = "tcp"
    from_port = 3306
    to_port   = 3306
    security_groups = [
      aws_security_group.covidshield_key_retrieval.id,
      aws_security_group.covidshield_key_submission.id
    ]
  }

  tags = {
    (var.billing_tag_key) = var.billing_tag_value
  }
}

resource "aws_security_group" "covidshield_egress_anywhere" {
  name        = "egress-anywhere"
  description = "Egress - CovidShield Anywhere"
  vpc_id      = aws_vpc.covidshield.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    (var.billing_tag_key) = var.billing_tag_value
  }
}

resource "aws_security_group" "privatelink" {
  name        = "privatelink"
  description = "privatelink endpoints"
  vpc_id      = aws_vpc.covidshield.id

  tags = {
    (var.billing_tag_key) = var.billing_tag_value
  }
}

resource "aws_security_group_rule" "privatelink_retrieval_ingress" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.privatelink.id
  source_security_group_id = aws_security_group.covidshield_key_retrieval.id
}

resource "aws_security_group_rule" "privatelink_submission_ingress" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.privatelink.id
  source_security_group_id = aws_security_group.covidshield_key_submission.id
}

###
# AWS Network ACL
###

resource "aws_default_network_acl" "covidshield" {
  default_network_acl_id = aws_vpc.covidshield.default_network_acl_id

  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "deny"
    cidr_block = "0.0.0.0/0"
    from_port  = 3389
    to_port    = 3389
  }

  ingress {
    protocol   = -1
    rule_no    = 300
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    (var.billing_tag_key) = var.billing_tag_value
  }
}
