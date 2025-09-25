#!/bin/bash
# Workload migration script for network isolated cluster migration

set -e

# Source environment variables
source /opt/migration-scripts/migration-env.sh

# Configuration
MIGRATION_NAMESPACE="migration-tools"
VELERO_NAMESPACE="velero"
BACKUP_NAME="cluster-migration-$(date +%Y%m%d-%H%M%S)"

echo "=== Cluster Workload Migration ==="
echo "Date: $(date)"
echo "Backup name: $BACKUP_NAME"

# Function to install Velero on a cluster
install_velero() {
    local context=$1
    local cluster_name=$2
    
    echo "Installing Velero on $cluster_name..."
    
    # Create Velero namespace
    kubectl --context $context create namespace $VELERO_NAMESPACE --dry-run=client -o yaml | kubectl --context $context apply -f -
    
    # Install Velero using Helm (AWS provider)
    helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
    helm repo update
    
    helm install velero vmware-tanzu/velero \
        --namespace $VELERO_NAMESPACE \
        --context $context \
        --set-file credentials.secretContents.cloud=/dev/null \
        --set configuration.provider=aws \
        --set configuration.backupStorageLocation.bucket=$MIGRATION_S3_BUCKET \
        --set configuration.backupStorageLocation.config.region=$AWS_REGION \
        --set configuration.volumeSnapshotLocation.name=default \
        --set configuration.volumeSnapshotLocation.config.region=$AWS_REGION \
        --set initContainers[0].name=velero-plugin-for-aws \
        --set initContainers[0].image=velero/velero-plugin-for-aws:v1.8.0 \
        --set initContainers[0].volumeMounts[0].mountPath=/target \
        --set initContainers[0].volumeMounts[0].name=plugins \
        --set serviceAccount.server.create=true \
        --set serviceAccount.server.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/VeleroRole" \
        --wait
}

# Function to create backup
create_backup() {
    echo "Creating backup of source cluster..."
    
    # Create backup excluding certain namespaces
    $KUBECTL_SOURCE create -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: $BACKUP_NAME
  namespace: $VELERO_NAMESPACE
spec:
  excludedNamespaces:
  - kube-system
  - kube-public
  - kube-node-lease
  - velero
  includedResources:
  - "*"
  storageLocation: default
  volumeSnapshotLocations:
  - default
  ttl: 168h0m0s
EOF

    # Wait for backup to complete
    echo "Waiting for backup to complete..."
    while true; do
        phase=$($KUBECTL_SOURCE get backup $BACKUP_NAME -n $VELERO_NAMESPACE -o jsonpath='{.status.phase}')
        if [ "$phase" = "Completed" ]; then
            echo "✓ Backup completed successfully"
            break
        elif [ "$phase" = "Failed" ] || [ "$phase" = "PartiallyFailed" ]; then
            echo "✗ Backup failed with phase: $phase"
            $KUBECTL_SOURCE describe backup $BACKUP_NAME -n $VELERO_NAMESPACE
            exit 1
        else
            echo "Backup in progress... (phase: $phase)"
            sleep 30
        fi
    done
}

# Function to restore to target cluster
restore_backup() {
    echo "Restoring backup to target cluster..."
    
    # Create restore
    $KUBECTL_TARGET create -f - <<EOF
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: restore-$BACKUP_NAME
  namespace: $VELERO_NAMESPACE
spec:
  backupName: $BACKUP_NAME
  excludedResources:
  - nodes
  - events
  - events.events.k8s.io
  - backups.velero.io
  - restores.velero.io
  - resticrepositories.velero.io
  restorePVs: true
EOF

    # Wait for restore to complete
    echo "Waiting for restore to complete..."
    while true; do
        phase=$($KUBECTL_TARGET get restore restore-$BACKUP_NAME -n $VELERO_NAMESPACE -o jsonpath='{.status.phase}')
        if [ "$phase" = "Completed" ]; then
            echo "✓ Restore completed successfully"
            break
        elif [ "$phase" = "Failed" ] || [ "$phase" = "PartiallyFailed" ]; then
            echo "✗ Restore failed with phase: $phase"
            $KUBECTL_TARGET describe restore restore-$BACKUP_NAME -n $VELERO_NAMESPACE
            exit 1
        else
            echo "Restore in progress... (phase: $phase)"
            sleep 30
        fi
    done
}

# Function to validate migration
validate_migration() {
    echo "Validating migration..."
    
    echo "Comparing workloads between source and target clusters..."
    
    echo "Source cluster deployments:"
    $KUBECTL_SOURCE get deployments --all-namespaces --no-headers | wc -l
    
    echo "Target cluster deployments:"
    $KUBECTL_TARGET get deployments --all-namespaces --no-headers | wc -l
    
    echo "Source cluster services:"
    $KUBECTL_SOURCE get services --all-namespaces --no-headers | wc -l
    
    echo "Target cluster services:"
    $KUBECTL_TARGET get services --all-namespaces --no-headers | wc -l
    
    echo "Checking pod status in target cluster:"
    $KUBECTL_TARGET get pods --all-namespaces | grep -v "kube-system\|velero"
}

# Main migration process
main() {
    echo "Starting migration process..."
    
    # Run pre-migration checks
    echo "Running pre-migration checks..."
    ./pre-migration-check.sh
    
    # Install Velero on both clusters
    install_velero "source" "$SOURCE_CLUSTER"
    install_velero "target" "$TARGET_CLUSTER"
    
    # Wait for Velero to be ready
    echo "Waiting for Velero to be ready on both clusters..."
    $KUBECTL_SOURCE wait --for=condition=ready pod -l app.kubernetes.io/name=velero -n $VELERO_NAMESPACE --timeout=300s
    $KUBECTL_TARGET wait --for=condition=ready pod -l app.kubernetes.io/name=velero -n $VELERO_NAMESPACE --timeout=300s
    
    # Create backup and restore
    create_backup
    restore_backup
    
    # Validate migration
    validate_migration
    
    echo "=== Migration Complete ==="
    echo "Backup name: $BACKUP_NAME"
    echo "Please validate your applications are working correctly in the target cluster."
    echo "Use './post-migration-cleanup.sh' to clean up resources after validation."
}

# Run main function
main "$@"