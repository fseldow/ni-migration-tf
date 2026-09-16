output "cluster_id" {
  description = "Resource ID of the managed cluster."
  value       = azurerm_kubernetes_cluster.this.id
}

output "migration_stage" {
  description = "Stage currently materialised in state."
  value       = var.migration_stage
}

output "effective_artifact_source" {
  description = "bootstrapProfile.artifactSource as of the last apply."
  value       = local.artifact_source
}

output "effective_outbound_type" {
  description = "networkProfile.outboundType as of the last apply."
  value       = local.outbound_type
}

output "reimaged_pools" {
  description = "Agent pools an upgradeNodeImageVersion action has been issued for."
  value       = sort([for k in keys(azapi_resource_action.reimage_nodepool) : k])
}

output "next_step" {
  description = "What to run next."
  value = (
    var.migration_stage == 0 ? "Baseline imported. Confirm 'terraform plan -var migration_stage=0' is a clean no-op, then apply with -var migration_stage=1." :
    var.migration_stage == 1 ? "artifactSource=Cache applied and pools reimaged. Verify nodes are healthy and pulling from the managed ACR, then apply with -var migration_stage=2." :
    "Migration complete. Cluster is network isolated. Remember: the managed ACR and its private endpoint are NOT auto-deleted on destroy."
  )
}
