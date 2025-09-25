# Migration tools and utilities for cluster migration

# S3 bucket for migration data and backups
resource "aws_s3_bucket" "migration_data" {
  bucket = "${var.environment}-cluster-migration-${random_id.bucket_suffix.hex}"

  tags = merge(local.common_tags, {
    Name    = "${var.environment}-migration-data"
    Purpose = "cluster-migration"
  })
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "migration_data" {
  bucket = aws_s3_bucket.migration_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "migration_data" {
  bucket = aws_s3_bucket.migration_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "migration_data" {
  bucket = aws_s3_bucket.migration_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role for migration tools
resource "aws_iam_role" "migration_tools" {
  name = "${var.environment}-migration-tools-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for migration tools
resource "aws_iam_policy" "migration_tools" {
  name = "${var.environment}-migration-tools-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups"
        ]
        Resource = [
          aws_eks_cluster.source.arn,
          aws_eks_cluster.target.arn,
          "${aws_eks_cluster.source.arn}/*",
          "${aws_eks_cluster.target.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.migration_data.arn,
          "${aws_s3_bucket.migration_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "migration_tools" {
  role       = aws_iam_role.migration_tools.name
  policy_arn = aws_iam_policy.migration_tools.arn
}

# Instance profile for migration tools
resource "aws_iam_instance_profile" "migration_tools" {
  name = "${var.environment}-migration-tools-profile"
  role = aws_iam_role.migration_tools.name
}

# Key pair for migration tools (optional)
# To use this, create a public key file first:
# ssh-keygen -t rsa -b 4096 -f migration-key
# Then uncomment the resource below and update the public_key path

# resource "aws_key_pair" "migration_tools" {
#   key_name   = "${var.environment}-migration-tools"
#   public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... your-public-key-here"
#
#   tags = local.common_tags
# }

# Launch template for migration tools instances
resource "aws_launch_template" "migration_tools" {
  name_prefix   = "${var.environment}-migration-tools"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.medium"
  key_name      = null # Set to aws_key_pair.migration_tools.key_name if using SSH keys

  vpc_security_group_ids = [aws_security_group.migration_tools.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.migration_tools.name
  }

  user_data = base64encode(templatefile("${path.module}/scripts/migration-tools-userdata.sh", {
    region         = var.aws_region
    source_cluster = aws_eks_cluster.source.name
    target_cluster = aws_eks_cluster.target.name
    s3_bucket      = aws_s3_bucket.migration_data.bucket
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${var.environment}-migration-tools"
    })
  }
}

# Data source for Amazon Linux AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}