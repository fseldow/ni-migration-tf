# =============================================================================
# STAGE 1, PART 2 - reimage the agent pools
# =============================================================================
#
# This is the one step azurerm cannot do. `node_image_version` on
# azurerm_kubernetes_cluster_node_pool is a read-only computed attribute, and
# there is no on-demand reimage resource. node_os_upgrade_channel = "NodeImage"
# only schedules an eventual upgrade, which is not deterministic enough for a
# migration where step 3 removes egress.
#
# So we keep exactly one azapi resource. It is a POST action, not a PUT, so it
# carries none of the full-body risk that azapi_update_resource / azurerm do.
#
# azapi_resource_action runs once at create and is never re-run unless its own
# arguments change, so the stage 2 apply will not churn the node pools again.
# =============================================================================

resource "azapi_resource_action" "reimage_nodepool" {
  for_each = local.pools_to_reimage

  type        = "Microsoft.ContainerService/managedClusters/agentPools@2025-05-01"
  resource_id = "${local.cluster_id}/agentPools/${each.key}"
  action      = "upgradeNodeImageVersion"
  method      = "POST"
  body        = {}

  # Guarantees artifactSource=Cache lands before we reimage.
  depends_on = [azurerm_kubernetes_cluster.this]

  timeouts {
    create = "60m"
  }
}
