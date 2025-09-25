#!/bin/bash
# Post-migration cleanup script

set -e

# Source environment variables
source /opt/migration-scripts/migration-env.sh

echo "=== Post-Migration Cleanup ==="
echo "Date: $(date)"

# Function to prompt for confirmation
confirm() {
    read -p "$1 (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi
    return 0
}

# Function to cleanup source cluster
cleanup_source_cluster() {
    if confirm "Do you want to drain and remove workloads from the source cluster?"; then
        echo "Draining source cluster workloads..."
        
        # Get all deployments (excluding system namespaces)
        namespaces=$($KUBECTL_SOURCE get namespaces -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -v -E '^(kube-|default|velero)')
        
        for ns in $namespaces; do
            echo "Scaling down deployments in namespace: $ns"
            $KUBECTL_SOURCE scale deployments --all --replicas=0 -n $ns || true
            
            echo "Scaling down statefulsets in namespace: $ns"
            $KUBECTL_SOURCE scale statefulsets --all --replicas=0 -n $ns || true
        done
        
        echo "✓ Source cluster workloads drained"
    fi
}

# Function to cleanup migration tools
cleanup_migration_tools() {
    if confirm "Do you want to remove Velero from both clusters?"; then
        echo "Removing Velero from source cluster..."
        helm uninstall velero --namespace velero --kube-context source || true
        $KUBECTL_SOURCE delete namespace velero || true
        
        echo "Removing Velero from target cluster..."
        helm uninstall velero --namespace velero --kube-context target || true
        $KUBECTL_TARGET delete namespace velero || true
        
        echo "✓ Velero removed from both clusters"
    fi
}

# Function to cleanup old backups
cleanup_backups() {
    if confirm "Do you want to cleanup old migration backups from S3?"; then
        echo "Listing migration backups..."
        aws s3 ls s3://$MIGRATION_S3_BUCKET/backups/ --recursive | grep cluster-migration
        
        if confirm "Do you want to delete all migration backups?"; then
            aws s3 rm s3://$MIGRATION_S3_BUCKET/backups/ --recursive --exclude "*" --include "*cluster-migration*"
            echo "✓ Migration backups cleaned up"
        fi
    fi
}

# Function to provide migration summary
migration_summary() {
    echo -e "\n=== Migration Summary ==="
    
    echo "Target cluster status:"
    $KUBECTL_TARGET get nodes
    echo
    
    echo "Workloads in target cluster:"
    $KUBECTL_TARGET get deployments --all-namespaces | grep -v "kube-system"
    echo
    
    echo "Services in target cluster:"
    $KUBECTL_TARGET get services --all-namespaces | grep -v "kube-system"
    echo
    
    echo "Persistent volumes in target cluster:"
    $KUBECTL_TARGET get pv
    echo
    
    echo "Pod status in target cluster:"
    $KUBECTL_TARGET get pods --all-namespaces | grep -v -E "(kube-system|Completed)"
}

# Function to generate migration report
generate_report() {
    local report_file="/tmp/migration-report-$(date +%Y%m%d-%H%M%S).txt"
    
    echo "Generating migration report..."
    
    cat > $report_file << EOF
=== Cluster Migration Report ===
Date: $(date)
Source Cluster: $SOURCE_CLUSTER
Target Cluster: $TARGET_CLUSTER
Migration S3 Bucket: $MIGRATION_S3_BUCKET
AWS Region: $AWS_REGION

=== Target Cluster Resources ===
Nodes:
$($KUBECTL_TARGET get nodes)

Namespaces:
$($KUBECTL_TARGET get namespaces)

Deployments:
$($KUBECTL_TARGET get deployments --all-namespaces)

Services:
$($KUBECTL_TARGET get services --all-namespaces)

Persistent Volumes:
$($KUBECTL_TARGET get pv)

Pod Status:
$($KUBECTL_TARGET get pods --all-namespaces)

=== Migration Validation ===
All critical workloads should be validated manually:
1. Check application functionality
2. Verify data integrity
3. Test service connectivity
4. Validate persistent storage
5. Check monitoring and logging

=== Recommendations ===
1. Monitor target cluster performance
2. Update DNS records if applicable
3. Update CI/CD pipelines to point to new cluster
4. Verify backup schedules are configured
5. Update monitoring and alerting configurations

Report generated: $(date)
EOF

    echo "Migration report saved to: $report_file"
    
    if confirm "Do you want to upload the report to S3?"; then
        aws s3 cp $report_file s3://$MIGRATION_S3_BUCKET/reports/
        echo "✓ Report uploaded to S3"
    fi
}

# Main cleanup process
main() {
    echo "Starting post-migration cleanup..."
    
    # Display migration summary
    migration_summary
    
    # Cleanup operations
    cleanup_source_cluster
    cleanup_migration_tools
    cleanup_backups
    
    # Generate migration report
    generate_report
    
    echo -e "\n=== Post-Migration Cleanup Complete ==="
    echo "Please ensure all applications are functioning correctly in the target cluster"
    echo "before decommissioning the source cluster infrastructure."
    
    if confirm "Do you want to see the final cleanup checklist?"; then
        cat << 'EOF'
=== Final Cleanup Checklist ===
□ All applications tested and validated in target cluster
□ Data integrity verified
□ DNS records updated
□ Load balancer configurations updated
□ CI/CD pipelines updated
□ Monitoring and alerting configured
□ Backup schedules verified
□ Security groups and network policies reviewed
□ Documentation updated
□ Team notified of migration completion

Only after completing all items above:
□ Decommission source cluster
□ Remove unused networking resources
□ Clean up IAM roles and policies
□ Remove temporary migration resources
EOF
    fi
}

# Run main function
main "$@"