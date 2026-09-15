locals {
  cluster_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ContainerService/managedClusters/${var.resource_name}"

  # Stage 1 flips artifacts to the managed ACR cache.
  artifact_source = var.migration_stage >= 1 ? "Cache" : "Direct"

  # Stage 2 removes egress. Until then keep whatever the cluster has today,
  # otherwise the stage 0 plan will not be a no-op.
  outbound_type = var.migration_stage >= 2 ? var.target_outbound_type : var.pre_migration_outbound_type

  # Reimage only exists from stage 1 onward. Once created it is never re-run,
  # so the stage 2 apply will not churn the node pools again.
  pools_to_reimage = var.migration_stage >= 1 ? toset(var.agentpool_names) : toset([])
}
