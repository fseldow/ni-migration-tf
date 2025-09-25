# Network Isolated Cluster Migration Example
# This Terraform configuration demonstrates how to set up infrastructure
# for migrating workloads between clusters in a network-isolated environment

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
  }
}

# Configure AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "ni-cluster-migration"
      ManagedBy   = "terraform"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Local variables
locals {
  cluster_name_source = "${var.environment}-source-cluster"
  cluster_name_target = "${var.environment}-target-cluster"

  common_tags = {
    Environment = var.environment
    Project     = "ni-cluster-migration"
    ManagedBy   = "terraform"
  }
}