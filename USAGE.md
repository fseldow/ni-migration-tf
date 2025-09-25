# Migration Usage Guide

This guide provides step-by-step instructions for using the network isolated cluster migration infrastructure.

## Phase 1: Infrastructure Setup

### 1.1 Prepare Environment

```bash
# Clone repository
git clone <repository-url>
cd ni-migration-tf

# Configure AWS credentials
aws configure

# Verify permissions
aws sts get-caller-identity
```

### 1.2 Configure Variables

```bash
# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit configuration for your environment
vi terraform.tfvars
```

Key configurations to review:
- `aws_region`: Your target AWS region
- `environment`: Environment name (will be used in resource naming)
- `vpc_cidr`: Ensure no conflicts with existing networks
- `allowed_cidr_blocks`: Networks allowed to access clusters

### 1.3 Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# Save outputs for later use
terraform output > terraform-outputs.txt
```

## Phase 2: Cluster Configuration

### 2.1 Configure kubectl

```bash
# Configure kubectl for source cluster
aws eks update-kubeconfig --region $(terraform output -raw aws_region) --name $(terraform output -raw source_cluster_id) --alias source

# Configure kubectl for target cluster  
aws eks update-kubeconfig --region $(terraform output -raw aws_region) --name $(terraform output -raw target_cluster_id) --alias target

# Verify connectivity
kubectl get nodes --context source
kubectl get nodes --context target
```

### 2.2 Deploy Test Workloads (Optional)

```bash
# Deploy test workloads to source cluster
kubectl apply -f examples/test-workloads.yaml --context source

# Verify deployment
kubectl get all -n test-migration --context source
```

## Phase 3: Migration Execution

### 3.1 Access Migration Tools

Option A - Use existing machine with tools installed:
```bash
# Ensure all required tools are installed
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
curl -fsSL https://github.com/vmware-tanzu/velero/releases/latest/download/velero-linux-amd64.tar.gz
```

Option B - Launch migration tools instance:
```bash
# Create EC2 instance using launch template
aws ec2 run-instances --launch-template LaunchTemplateName=$(terraform output -raw migration_tools_launch_template)
```

### 3.2 Run Migration

```bash
# Navigate to scripts directory
cd scripts

# Make scripts executable (if not already)
chmod +x *.sh

# Run pre-migration checks
./pre-migration-check.sh

# Execute migration
./migrate-workloads.sh

# Verify migration completed successfully
kubectl get all --all-namespaces --context target
```

## Phase 4: Validation and Testing

### 4.1 Application Testing

Test each migrated application:
```bash
# List all namespaces in target cluster
kubectl get namespaces --context target

# Check specific application
kubectl get all -n <namespace> --context target

# Test application functionality
kubectl port-forward -n <namespace> service/<service-name> 8080:80 --context target
```

### 4.2 Data Validation

For applications with persistent data:
```bash
# Check persistent volumes
kubectl get pv --context target

# Verify data integrity in pods
kubectl exec -it <pod-name> -n <namespace> --context target -- /bin/bash
```

### 4.3 Network Connectivity

Test service-to-service communication:
```bash
# Test internal service connectivity
kubectl run test-pod --image=busybox --rm -it --restart=Never --context target -- nslookup <service-name>.<namespace>.svc.cluster.local

# Test external connectivity (if applicable)
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never --context target -- curl -v <external-url>
```

## Phase 5: Cutover and Cleanup

### 5.1 DNS and Traffic Routing

Update external DNS records and load balancers:
```bash
# Update DNS records to point to new cluster
# Update ALB/NLB target groups
# Update API Gateway endpoints
```

### 5.2 Monitor Migration

```bash
# Monitor cluster health
kubectl top nodes --context target
kubectl top pods --all-namespaces --context target

# Check cluster events
kubectl get events --all-namespaces --context target --sort-by='.lastTimestamp'
```

### 5.3 Post-Migration Cleanup

```bash
# Run cleanup script
./post-migration-cleanup.sh

# Follow prompts to:
# - Scale down source cluster workloads
# - Remove migration tools
# - Clean up backups
# - Generate migration report
```

## Phase 6: Infrastructure Cleanup (Optional)

After successful migration and validation:

```bash
# Remove source cluster (CAREFUL!)
# terraform destroy -target=aws_eks_cluster.source
# terraform destroy -target=aws_eks_node_group.source

# Or destroy entire infrastructure
# terraform destroy
```

## Troubleshooting

### Common Issues

**Issue: Cannot access cluster**
```bash
# Check IAM permissions
aws iam get-user
aws iam list-attached-user-policies --user-name $(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2)

# Update kubeconfig
aws eks update-kubeconfig --region <region> --name <cluster-name> --alias <alias>
```

**Issue: Migration fails**
```bash
# Check Velero status
kubectl get pods -n velero --context source
kubectl get backups -n velero --context source
kubectl describe backup <backup-name> -n velero --context source

# Check logs
kubectl logs -n velero -l app.kubernetes.io/name=velero --context source
```

**Issue: Pods stuck in Pending**
```bash
# Check node resources
kubectl describe nodes --context target

# Check events
kubectl get events --all-namespaces --context target | grep -i error

# Check storage
kubectl get pv --context target
kubectl get storageclass --context target
```

### Rollback Procedure

If migration fails and rollback is needed:

```bash
# 1. Stop migration process
pkill -f velero

# 2. Clean up partial migration in target cluster
kubectl delete namespace <migrated-namespaces> --context target

# 3. Verify source cluster is still functional
kubectl get all --all-namespaces --context source

# 4. Resume operations on source cluster
# Scale up any scaled-down deployments
```

## Best Practices

1. **Always test in non-production first**
2. **Take additional backups before migration**
3. **Have a rollback plan ready**
4. **Monitor resource usage during migration**
5. **Validate each application thoroughly**
6. **Update documentation after migration**
7. **Keep migration logs for audit purposes**

## Support

For additional help:
- Review logs in `/var/log/migration-tools-setup.log`
- Check AWS CloudWatch logs for EKS clusters
- Review Velero documentation: https://velero.io/docs/
- Check Kubernetes troubleshooting guides