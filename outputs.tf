# Outputs for network isolated cluster migration

# VPC Information
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.migration_vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.migration_vpc.cidr_block
}

# Subnet Information
output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

# Source Cluster Information
output "source_cluster_id" {
  description = "ID of the source EKS cluster"
  value       = aws_eks_cluster.source.id
}

output "source_cluster_arn" {
  description = "ARN of the source EKS cluster"
  value       = aws_eks_cluster.source.arn
}

output "source_cluster_endpoint" {
  description = "Endpoint of the source EKS cluster"
  value       = aws_eks_cluster.source.endpoint
}

output "source_cluster_version" {
  description = "Version of the source EKS cluster"
  value       = aws_eks_cluster.source.version
}

output "source_cluster_security_group_id" {
  description = "Security group ID attached to the source EKS cluster"
  value       = aws_eks_cluster.source.vpc_config[0].cluster_security_group_id
}

# Target Cluster Information
output "target_cluster_id" {
  description = "ID of the target EKS cluster"
  value       = aws_eks_cluster.target.id
}

output "target_cluster_arn" {
  description = "ARN of the target EKS cluster"
  value       = aws_eks_cluster.target.arn
}

output "target_cluster_endpoint" {
  description = "Endpoint of the target EKS cluster"
  value       = aws_eks_cluster.target.endpoint
}

output "target_cluster_version" {
  description = "Version of the target EKS cluster"
  value       = aws_eks_cluster.target.version
}

output "target_cluster_security_group_id" {
  description = "Security group ID attached to the target EKS cluster"
  value       = aws_eks_cluster.target.vpc_config[0].cluster_security_group_id
}

# Migration Tools Information
output "migration_s3_bucket" {
  description = "Name of the S3 bucket for migration data"
  value       = aws_s3_bucket.migration_data.bucket
}

output "migration_tools_role_arn" {
  description = "ARN of the migration tools IAM role"
  value       = aws_iam_role.migration_tools.arn
}

# Kubectl Configuration Commands
output "source_cluster_kubectl_config" {
  description = "Command to configure kubectl for the source cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.source.name} --alias source"
}

output "target_cluster_kubectl_config" {
  description = "Command to configure kubectl for the target cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.target.name} --alias target"
}

# Migration Commands
output "migration_instructions" {
  description = "Basic migration instructions"
  value = {
    step_1 = "Configure kubectl for both clusters using the provided commands"
    step_2 = "Run 'kubectl get nodes --context source' to verify source cluster access"
    step_3 = "Run 'kubectl get nodes --context target' to verify target cluster access"
    step_4 = "Use the migration scripts in the scripts/ directory for workload migration"
    step_5 = "Monitor migration progress using the provided tools"
  }
}

# Security Group IDs
output "eks_cluster_security_group_id" {
  description = "Security group ID for EKS clusters"
  value       = aws_security_group.eks_cluster.id
}

output "eks_nodes_security_group_id" {
  description = "Security group ID for EKS worker nodes"
  value       = aws_security_group.eks_nodes.id
}

output "migration_tools_security_group_id" {
  description = "Security group ID for migration tools"
  value       = aws_security_group.migration_tools.id
}

# VPC Endpoints (if enabled)
output "vpc_endpoints" {
  description = "VPC endpoints created for network isolation"
  value = var.enable_vpc_endpoints ? {
    ecr_api = aws_vpc_endpoint.ecr_api[0].id
    ecr_dkr = aws_vpc_endpoint.ecr_dkr[0].id
    s3      = aws_vpc_endpoint.s3[0].id
    eks     = aws_vpc_endpoint.eks[0].id
    ec2     = aws_vpc_endpoint.ec2[0].id
  } : {}
}