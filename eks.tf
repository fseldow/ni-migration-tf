# EKS clusters for network isolated migration

# IAM role for EKS clusters
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# IAM role for EKS node groups
resource "aws_iam_role" "eks_node_role" {
  name = "${var.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# Source EKS cluster
resource "aws_eks_cluster" "source" {
  name     = local.cluster_name_source
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.enable_private_clusters ? aws_subnet.private[*].id : concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    endpoint_private_access = true
    endpoint_public_access  = !var.enable_private_clusters
    public_access_cidrs     = var.enable_private_clusters ? [] : var.allowed_cidr_blocks
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  # Enable cluster logging
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]

  tags = merge(local.common_tags, {
    Name = local.cluster_name_source
    Role = "source-cluster"
  })
}

# Target EKS cluster
resource "aws_eks_cluster" "target" {
  name     = local.cluster_name_target
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.enable_private_clusters ? aws_subnet.private[*].id : concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    endpoint_private_access = true
    endpoint_public_access  = !var.enable_private_clusters
    public_access_cidrs     = var.enable_private_clusters ? [] : var.allowed_cidr_blocks
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  # Enable cluster logging
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]

  tags = merge(local.common_tags, {
    Name = local.cluster_name_target
    Role = "target-cluster"
  })
}

# Source cluster node group
resource "aws_eks_node_group" "source" {
  cluster_name    = aws_eks_cluster.source.name
  node_group_name = "${local.cluster_name_source}-nodes"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_capacity
    max_size     = var.node_max_capacity
    min_size     = var.node_min_capacity
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_registry_policy,
  ]

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name_source}-nodes"
    Role = "source-cluster-nodes"
  })
}

# Target cluster node group
resource "aws_eks_node_group" "target" {
  cluster_name    = aws_eks_cluster.target.name
  node_group_name = "${local.cluster_name_target}-nodes"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_capacity
    max_size     = var.node_max_capacity
    min_size     = var.node_min_capacity
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_registry_policy,
  ]

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name_target}-nodes"
    Role = "target-cluster-nodes"
  })
}