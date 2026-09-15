# Brings the pre-existing cluster under Terraform management on the first apply.
# Safe to leave in place permanently: once the resource is in state, Terraform
# treats the import block as a no-op.
import {
  to = azurerm_kubernetes_cluster.this
  id = local.cluster_id
}
