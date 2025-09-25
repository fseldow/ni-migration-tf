# Network Isolated Cluster Migration with Terraform

This repository provides a comprehensive Terraform example for setting up and managing cluster migration in a network-isolated environment. It demonstrates best practices for migrating workloads between Kubernetes clusters while maintaining security and network isolation.

## Architecture Overview

The solution creates:
- **Isolated VPC**: A dedicated VPC with public and private subnets
- **Source EKS Cluster**: The existing cluster with workloads to be migrated
- **Target EKS Cluster**: The new cluster where workloads will be migrated to
- **Network Security**: Security groups and VPC endpoints for secure communication
- **Migration Tools**: Automated scripts and tools for workload migration

## Features

- ✅ **Network Isolation**: Fully isolated network environment with VPC endpoints
- ✅ **Security Best Practices**: Proper IAM roles, security groups, and encryption
- ✅ **Automated Migration**: Scripts for backup, restore, and validation
- ✅ **Multi-AZ Setup**: High availability across multiple availability zones
- ✅ **Monitoring Ready**: CloudWatch integration and logging enabled
- ✅ **Scalable Infrastructure**: Auto-scaling node groups and flexible configuration

## Quick Start

### Prerequisites

1. AWS CLI configured with appropriate permissions
2. Terraform >= 1.0 installed
3. kubectl installed
4. Helm installed (for migration tools)

### Deployment Steps

1. **Clone and Initialize**
   ```bash
   git clone <repository-url>
   cd ni-migration-tf
   terraform init
   ```

2. **Configure Variables**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

3. **Plan and Apply**
   ```bash
   terraform plan
   terraform apply
   ```

4. **Configure kubectl**
   ```bash
   # Use the output commands to configure kubectl
   terraform output source_cluster_kubectl_config
   terraform output target_cluster_kubectl_config
   ```

5. **Run Migration**
   ```bash
   # SSH into migration tools instance or run locally
   ./scripts/pre-migration-check.sh
   ./scripts/migrate-workloads.sh
   ./scripts/post-migration-cleanup.sh
   ```

## Configuration

### Key Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region for deployment | `us-west-2` |
| `environment` | Environment name | `migration-demo` |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `kubernetes_version` | EKS cluster version | `1.28` |
| `enable_private_clusters` | Create clusters in private subnets | `true` |
| `enable_vpc_endpoints` | Enable VPC endpoints | `true` |

### Customization

Create a `terraform.tfvars` file:

```hcl
aws_region = "us-east-1"
environment = "production-migration"
vpc_cidr = "172.16.0.0/16"
kubernetes_version = "1.28"
node_instance_type = "t3.large"
node_desired_capacity = 3
enable_private_clusters = true
enable_vpc_endpoints = true
allowed_cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12"]
```

## Migration Process

### 1. Pre-Migration Assessment
- Run connectivity tests
- Inventory existing workloads
- Validate cluster configurations
- Check storage requirements

### 2. Migration Execution
- Install backup/restore tools (Velero)
- Create comprehensive backups
- Restore to target cluster
- Validate data integrity

### 3. Post-Migration Activities
- Application testing
- DNS updates
- Cleanup old resources
- Documentation updates

## Security Considerations

### Network Security
- **Private Clusters**: EKS clusters deployed in private subnets
- **VPC Endpoints**: Secure access to AWS services without internet
- **Security Groups**: Restrictive rules for inter-cluster communication
- **NACLs**: Additional network-level security controls

### Access Control
- **IAM Roles**: Least privilege access for all components
- **RBAC**: Kubernetes role-based access control
- **Pod Security**: Security contexts and policies
- **Encryption**: Data encryption at rest and in transit

## Monitoring and Logging

The infrastructure includes:
- **CloudWatch Logs**: EKS cluster logging enabled
- **VPC Flow Logs**: Network traffic monitoring
- **Migration Metrics**: Custom metrics for migration progress
- **Alerting**: CloudWatch alarms for critical events

## Troubleshooting

### Common Issues

1. **Cluster Access Issues**
   ```bash
   # Verify IAM permissions
   aws sts get-caller-identity
   
   # Update kubeconfig
   aws eks update-kubeconfig --region <region> --name <cluster-name>
   ```

2. **Network Connectivity**
   ```bash
   # Check VPC endpoints
   aws ec2 describe-vpc-endpoints --region <region>
   
   # Verify security groups
   aws ec2 describe-security-groups --region <region>
   ```

3. **Migration Failures**
   ```bash
   # Check Velero logs
   kubectl logs -n velero -l app.kubernetes.io/name=velero
   
   # List backups and restores
   velero backup get
   velero restore get
   ```

## Cost Optimization

- Use Spot instances for non-critical workloads
- Configure cluster autoscaler
- Monitor and adjust node group sizes
- Use S3 lifecycle policies for backup retention

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests and documentation
5. Submit a pull request

## Support

For issues and questions:
- Review the troubleshooting section
- Check the migration logs
- Create an issue in the repository

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- AWS EKS documentation and best practices
- Velero backup and restore tool
- Kubernetes community guidelines
- Terraform AWS provider documentation