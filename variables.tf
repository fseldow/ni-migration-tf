# Variables for network isolated cluster migration

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "migration-demo"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Number of availability zones to use"
  type        = number
  default     = 2
}

# EKS Cluster Configuration
variable "kubernetes_version" {
  description = "Kubernetes version for EKS clusters"
  type        = string
  default     = "1.28"
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_capacity" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_max_capacity" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4
}

variable "node_min_capacity" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

# Network Isolation Configuration
variable "enable_private_clusters" {
  description = "Whether to create clusters in private subnets only"
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for AWS services"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the clusters"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

# Migration Configuration
variable "enable_cross_cluster_networking" {
  description = "Enable networking between source and target clusters"
  type        = bool
  default     = true
}

variable "migration_tools_namespace" {
  description = "Namespace for migration tools and utilities"
  type        = string
  default     = "migration-tools"
}