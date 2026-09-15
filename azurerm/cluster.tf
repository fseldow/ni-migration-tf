# =============================================================================
# THE EXISTING CLUSTER
# =============================================================================
#
# !!! READ THIS BEFORE YOU APPLY ANYTHING !!!
#
# azurerm_kubernetes_cluster always sends a FULL PUT built from this HCL.
# Anything you fail to declare here gets reset to the provider default on the
# first apply. Anything you declare WRONG on a ForceNew field makes Terraform
# propose destroying and recreating your cluster.
#
# So do NOT hand-write this block. Generate it:
#
#   1. mv cluster.tf cluster.tf.scaffold
#   2. terraform init
#   3. terraform plan "-generate-config-out=generated.tf"      (this WILL error)
#   4. .\scripts\normalize-generated.ps1 -Path generated.tf    (fixes the errors)
#   5. Move the generated resource body back into this file, then re-add the
#      three marked MIGRATION blocks below (bootstrap_profile, outbound_type,
#      lifecycle).
#   6. Re-run `terraform plan -var migration_stage=0` until it reports
#      "0 to add, 0 to change, 0 to destroy". Do not proceed until it does.
#
# What is below is a PLACEHOLDER SCAFFOLD so the module parses and validates.
# It is almost certainly not your cluster.
# =============================================================================

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.resource_name
  resource_group_name = var.resource_group_name
  location            = var.resource_group_location
  dns_prefix          = var.resource_name

  # ---------------------------------------------------------------------------
  # MIGRATION BLOCK 1 of 3 - stage 1 flips this to "Cache"
  # ---------------------------------------------------------------------------
  bootstrap_profile {
    artifact_source = local.artifact_source
  }

  default_node_pool {
    name           = var.agentpool_names[0]
    vm_size        = "Standard_D4s_v5"
    node_count     = 2
    os_sku         = "AzureLinux"
    vnet_subnet_id = null

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # Required block in azurerm v5. "Manual" == classic, non-NAP node pools.
  node_provisioning_profile {
    mode               = "Manual"
    default_node_pools = "Auto"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"

    # -------------------------------------------------------------------------
    # MIGRATION BLOCK 2 of 3 - stage 2 flips this to "none"
    # -------------------------------------------------------------------------
    outbound_type = local.outbound_type
  }

  # ---------------------------------------------------------------------------
  # MIGRATION BLOCK 3 of 3 - keep this, it is the safety net
  # ---------------------------------------------------------------------------
  lifecycle {
    # If your generated config is wrong on a ForceNew field, this turns a
    # cluster deletion into a plan-time error. Do not remove it.
    prevent_destroy = true

    ignore_changes = [
      # Managed by AKS auto-upgrade, not by this migration.
      kubernetes_version,
      # Managed by the cluster autoscaler.
      default_node_pool[0].node_count,
    ]
  }
}
