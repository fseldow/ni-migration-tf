terraform {
  required_version = ">= 1.9"

  required_providers {
    # bootstrap_profile requires >= 4.44.0. v5 is the current major line.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.5"
    }
    # Only still needed for the node-image reimage step, which azurerm
    # cannot express (node_image_version is a read-only computed attribute).
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azapi" {
  subscription_id = var.subscription_id
}
