# Network infrastructure for isolated cluster migration

# VPC for network isolation
resource "aws_vpc" "migration_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.environment}-migration-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "migration_igw" {
  vpc_id = aws_vpc.migration_vpc.id

  tags = merge(local.common_tags, {
    Name = "${var.environment}-migration-igw"
  })
}

# Public subnets for NAT gateways and load balancers
resource "aws_subnet" "public" {
  count = var.availability_zones

  vpc_id                  = aws_vpc.migration_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.environment}-public-subnet-${count.index + 1}"
    Type = "Public"
  })
}

# Private subnets for EKS clusters
resource "aws_subnet" "private" {
  count = var.availability_zones

  vpc_id            = aws_vpc.migration_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.environment}-private-subnet-${count.index + 1}"
    Type = "Private"
    # Required tags for EKS
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# Elastic IPs for NAT gateways
resource "aws_eip" "nat_gateway" {
  count = var.availability_zones

  domain     = "vpc"
  depends_on = [aws_internet_gateway.migration_igw]

  tags = merge(local.common_tags, {
    Name = "${var.environment}-nat-gateway-eip-${count.index + 1}"
  })
}

# NAT Gateways for private subnet internet access
resource "aws_nat_gateway" "migration_nat" {
  count = var.availability_zones

  allocation_id = aws_eip.nat_gateway[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${var.environment}-nat-gateway-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.migration_igw]
}

# Route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.migration_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.migration_igw.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-public-route-table"
  })
}

# Route table associations for public subnets
resource "aws_route_table_association" "public" {
  count = var.availability_zones

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route tables for private subnets
resource "aws_route_table" "private" {
  count = var.availability_zones

  vpc_id = aws_vpc.migration_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.migration_nat[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-private-route-table-${count.index + 1}"
  })
}

# Route table associations for private subnets
resource "aws_route_table_association" "private" {
  count = var.availability_zones

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}