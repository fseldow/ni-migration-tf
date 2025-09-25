resource "azapi_update_resource" "update_artifact_source" {
  type      = "Microsoft.ContainerService/managedClusters@2025-05-01"
  parent_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  name      = var.resource_name
  body = {
    properties = {
      bootstrapProfile = {
        artifactSource = "Cache"
      }
    }
  }
}

resource "azapi_resource_action" "reimage_nodepool" {
  for_each = toset(var.agentpool_names)
  type        = "Microsoft.ContainerService/managedClusters/agentPools@2025-05-01"
  resource_id = "${azapi_update_resource.update_artifact_source.id}/agentPools/${each.key}"
  action      = "upgradeNodeImageVersion"
  method      = "POST"
  body        = "{}"
  depends_on = [azapi_update_resource.update_artifact_source]
}

resource "azapi_update_resource" "update_outbound_type" {
  type      = "Microsoft.ContainerService/managedClusters@2025-05-01"
  parent_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  name      = var.resource_name
  body = {
    properties = {
      bootstrapProfile = {
        artifactSource = "Cache"
      }
      networkProfile = {
        outboundType    = "none"
      }
    }
  }
  depends_on = [azapi_resource_action.reimage_nodepool]
}
