variable "resource_group_location" {
  type        = string
  default     = "westcentralus"
  description = "Location of the resource group."
}

variable "subscription_id" {
  type        = string
  description = "The Subscription ID where the resources will be created."
  default     = "12015272-f077-4945-81de-a5f607d067e1"
}

variable "agentpool_names" {
  type    = list(string)
  default = ["agentpool"] # example default
}

variable "resource_group_name" {
  type        = string
  default     = "ni-test-rg"
  description = "Prefix of the resource group name that's combined with a random ID so name is unique in your Azure subscription."
}

variable "resource_name" {
  type        = string
  description = "The name of the AKS cluster."
  default     = "myPrivateAKSCluster"
}

variable "node_count" {
  type        = number
  description = "The initial quantity of nodes for the node pool."
  default     = 2
}

variable "msi_id" {
  type        = string
  description = "The Managed Service Identity ID. Set this value if you're running this example using Managed Identity as the authentication method."
  default     = null
}

variable "username" {
  type        = string
  description = "The admin username for the new cluster."
  default     = "azureadmin"
}