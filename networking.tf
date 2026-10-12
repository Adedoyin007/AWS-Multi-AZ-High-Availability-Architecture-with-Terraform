
# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

# Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  availability_zones = slice(
    data.aws_availability_zones.available.names,
    0,
    2
  )

  public_subnets = {
    public_a = {
      cidr = "10.0.1.0/24"
      az   = local.availability_zones[0]
    }
    public_b = {
      cidr = "10.0.2.0/24"
      az   = local.availability_zones[1]
    }
  }

  private_subnets = {
    private_a = {
      cidr    = "10.0.11.0/24"
      az      = local.availability_zones[0]
      nat_key = "a"
    }
    private_b = {
      cidr    = "10.0.12.0/24"
      az      = local.availability_zones[1]
      nat_key = "b"
    }
  }

  nat_gateways = {
    a = { public_subnet_key = "public_a" }
    b = { public_subnet_key = "public_b" }
  }
}

# Public subnets
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-${each.key}"
    Project = var.project_name
    Tier    = "public"
  }
}

# Private subnets
resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = {
    Name    = "${var.project_name}-${each.key}"
    Project = var.project_name
    Tier    = "private"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = "${var.project_name}-public-rt"
    Project = var.project_name
  }
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  for_each = local.nat_gateways

  domain = "vpc"

  tags = {
    Name    = "${var.project_name}-nat-eip-${each.key}"
    Project = var.project_name
  }
}

# One NAT Gateway per Availability Zone
resource "aws_nat_gateway" "this" {
  for_each = local.nat_gateways

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.value.public_subnet_key].id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name    = "${var.project_name}-nat-${each.key}"
    Project = var.project_name
  }
}

# Separate private route table for each AZ
resource "aws_route_table" "private" {
  for_each = local.private_subnets

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[each.value.nat_key].id
  }

  tags = {
    Name    = "${var.project_name}-${each.key}-rt"
    Project = var.project_name
    Tier    = "private"
  }
}

# Associate each private subnet with its own route table
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
