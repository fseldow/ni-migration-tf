# ni-migration-tf (azapi implementation)

Migrates an existing AKS cluster to network isolated using only the `azapi`
provider. This is the original implementation. See the
[repo root README](../README.md) for how it compares to [`../azurerm`](../azurerm).

## Prerequest
1. already created one cluster to meet the network isolated cluster limitation
1. modify the variable related to the cluster

## Steps:
1. export ARM_SUBSCRIPTION_ID="your-subscription-id"
1. terraform init -upgrade
1. terraform plan -out main.tfplan
1. terraform apply main.tfplan

## What it does

All three steps happen in a single apply, ordered by `depends_on`:

1. `azapi_update_resource.update_artifact_source` -- `bootstrapProfile.artifactSource` to `Cache`
2. `azapi_resource_action.reimage_nodepool` -- `upgradeNodeImageVersion` on every pool in `var.agentpool_names`
3. `azapi_update_resource.update_outbound_type` -- `networkProfile.outboundType` to `none`

> [!WARNING]
> The order is not optional. Nodes that have not been reimaged onto the cached
> image lose the ability to pull images the moment egress is removed in step 3.

### Why step 3 repeats `artifactSource = "Cache"`

`azapi_update_resource` does a GET, merges the body you gave it into the live
payload, and PUTs the result. Repeating `artifactSource` is harmless and keeps
each resource's intent self-contained.

### Why not `azapi_resource_action` with `PATCH`

It looks like the obvious way to avoid `azapi_update_resource`, but it does not
work here. On `Microsoft.ContainerService/managedClusters` the `PATCH` operation
is `ManagedClusters_UpdateTags` and its body schema is `TagsObject` -- **AKS only
supports patching tags**. A `PATCH` carrying `properties` is ignored. The
GET-merge-PUT that `azapi_update_resource` performs internally is precisely why
it works.

## Notes

- **The `azapi` provider must be v2.x.** The `body` arguments in `main.tf` are HCL
  objects, which is v2 syntax; in azapi v1.x `body` was a JSON *string*. This was
  previously pinned to `~>1.5`, under which the config could not `init`.
- The unused `azurerm` provider requirement was dropped -- no `azurerm` resources
  are declared here.
- With `artifactSource = Cache` and an explicit `outboundType`, the managed ACR,
  its private endpoint, and its private DNS zone are **not** deleted when the
  cluster is destroyed. Clean them up manually.
