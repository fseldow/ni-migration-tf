variable "subscription_id" {
  type        = string
  description = "Subscription that holds the existing AKS cluster."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group of the existing AKS cluster."
}

variable "resource_group_location" {
  type        = string
  description = "Region of the existing AKS cluster. Must match reality or stage 0 will try to recreate the cluster."
}

variable "resource_name" {
  type        = string
  description = "Name of the existing AKS cluster."
}

variable "agentpool_names" {
  type        = list(string)
  description = "Agent pools to reimage after switching artifactSource to Cache."
  default     = ["agentpool"]

  validation {
    condition     = length(var.agentpool_names) > 0
    error_message = "At least one agent pool must be listed, otherwise stage 1 would leave nodes on the old image."
  }
}

variable "migration_stage" {
  type        = number
  description = <<-EOT
    Drives the network-isolated migration, one stage per apply.

      0 = import + baseline. No functional change. Plan MUST be a clean no-op.
      1 = bootstrapProfile.artifactSource -> Cache, then reimage every agent pool.
      2 = networkProfile.outboundType     -> none.

    Stages must be applied in order 0 -> 1 -> 2. Never skip straight to 2:
    nodes that have not been reimaged onto the Cache-based image will lose
    their ability to pull images the moment egress is removed.
  EOT
  default     = 0

  validation {
    condition     = contains([0, 1, 2], var.migration_stage)
    error_message = "migration_stage must be one of 0, 1 or 2."
  }
}

variable "pre_migration_outbound_type" {
  type        = string
  description = "The cluster's current outboundType, used for stages 0 and 1. Must match reality or stage 0 will not be a no-op."
  default     = "loadBalancer"

  validation {
    condition     = contains(["loadBalancer", "userDefinedRouting", "managedNATGateway", "userAssignedNATGateway"], var.pre_migration_outbound_type)
    error_message = "pre_migration_outbound_type must be a valid pre-migration outbound type (not 'none')."
  }
}

variable "target_outbound_type" {
  type        = string
  description = "Outbound type to land on at stage 2. 'none' or 'block'."
  default     = "none"

  validation {
    condition     = contains(["none", "block"], var.target_outbound_type)
    error_message = "target_outbound_type must be 'none' or 'block'."
  }
}
