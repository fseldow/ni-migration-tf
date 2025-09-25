# Security groups for network isolated cluster migration

# Security group for EKS clusters
resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.environment}-eks-cluster"
  vpc_id      = aws_vpc.migration_vpc.id
  description = "Security group for EKS cluster control plane"

  # Allow HTTPS traffic from within VPC
  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow traffic from allowed CIDR blocks
  ingress {
    description = "HTTPS from allowed networks"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-eks-cluster-sg"
  })
}

# Security group for EKS worker nodes
resource "aws_security_group" "eks_nodes" {
  name_prefix = "${var.environment}-eks-nodes"
  vpc_id      = aws_vpc.migration_vpc.id
  description = "Security group for EKS worker nodes"

  # Allow nodes to communicate with each other
  ingress {
    description = "Node to node communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  # Allow nodes to receive communication from cluster
  ingress {
    description     = "Cluster to node communication"
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  # Allow cluster control plane to communicate with nodes on HTTPS
  ingress {
    description     = "Cluster API to node communication"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-eks-nodes-sg"
  })
}

# Security group for migration tools
resource "aws_security_group" "migration_tools" {
  name_prefix = "${var.environment}-migration-tools"
  vpc_id      = aws_vpc.migration_vpc.id
  description = "Security group for migration tools and utilities"

  # Allow communication between clusters for migration
  ingress {
    description = "Inter-cluster migration traffic"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow HTTPS for API access
  ingress {
    description = "HTTPS API access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Allow SSH for troubleshooting (optional)
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-migration-tools-sg"
  })
}