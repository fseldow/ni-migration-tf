#!/bin/bash
# Pre-migration checks and validation script

set -e

# Source environment variables
source /opt/migration-scripts/migration-env.sh

echo "=== Pre-Migration Validation ==="
echo "Date: $(date)"

# Check cluster connectivity
echo "Checking source cluster connectivity..."
if $KUBECTL_SOURCE get nodes > /dev/null 2>&1; then
    echo "✓ Source cluster is accessible"
    echo "Source cluster nodes:"
    $KUBECTL_SOURCE get nodes
else
    echo "✗ Cannot access source cluster"
    exit 1
fi

echo -e "\nChecking target cluster connectivity..."
if $KUBECTL_TARGET get nodes > /dev/null 2>&1; then
    echo "✓ Target cluster is accessible"
    echo "Target cluster nodes:"
    $KUBECTL_TARGET get nodes
else
    echo "✗ Cannot access target cluster"
    exit 1
fi

# Check cluster versions
echo -e "\nValidating cluster versions..."
SOURCE_VERSION=$($KUBECTL_SOURCE version --short | grep "Server Version" | cut -d' ' -f3)
TARGET_VERSION=$($KUBECTL_TARGET version --short | grep "Server Version" | cut -d' ' -f3)

echo "Source cluster version: $SOURCE_VERSION"
echo "Target cluster version: $TARGET_VERSION"

# Check networking between clusters
echo -e "\nValidating network connectivity..."
SOURCE_ENDPOINT=$(aws eks describe-cluster --name $SOURCE_CLUSTER --region $AWS_REGION --query 'cluster.endpoint' --output text)
TARGET_ENDPOINT=$(aws eks describe-cluster --name $TARGET_CLUSTER --region $AWS_REGION --query 'cluster.endpoint' --output text)

echo "Source endpoint: $SOURCE_ENDPOINT"
echo "Target endpoint: $TARGET_ENDPOINT"

# Check S3 bucket access
echo -e "\nValidating S3 bucket access..."
if aws s3 ls s3://$MIGRATION_S3_BUCKET > /dev/null 2>&1; then
    echo "✓ S3 bucket is accessible"
else
    echo "✗ Cannot access S3 bucket: $MIGRATION_S3_BUCKET"
    exit 1
fi

# Get workloads inventory from source cluster
echo -e "\nInventory of workloads in source cluster:"
echo "Namespaces:"
$KUBECTL_SOURCE get namespaces

echo -e "\nDeployments:"
$KUBECTL_SOURCE get deployments --all-namespaces

echo -e "\nStatefulSets:"
$KUBECTL_SOURCE get statefulsets --all-namespaces

echo -e "\nDaemonSets:"
$KUBECTL_SOURCE get daemonsets --all-namespaces

echo -e "\nServices:"
$KUBECTL_SOURCE get services --all-namespaces

echo -e "\nPersistentVolumes:"
$KUBECTL_SOURCE get pv

echo -e "\nPersistentVolumeClaims:"
$KUBECTL_SOURCE get pvc --all-namespaces

# Check storage classes
echo -e "\nStorage Classes:"
echo "Source cluster:"
$KUBECTL_SOURCE get storageclass

echo "Target cluster:"
$KUBECTL_TARGET get storageclass

echo -e "\n=== Pre-Migration Validation Complete ==="
echo "Review the above information before proceeding with migration."
echo "Run './migrate-workloads.sh' to begin the migration process."