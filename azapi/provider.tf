terraform {
  required_version = ">= 1.0"

  required_providers {
    # NOTE: must be v2.x. The `body` argument is an HCL object in main.tf, which
    # is v2 syntax -- in azapi v1.x `body` was a JSON *string*. This was
    # previously pinned to "~>1.5", under which this config could not init.
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.12"
    }
  }
}

provider "azapi" {}
