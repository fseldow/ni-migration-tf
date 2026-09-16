# ni-migration-tf

Terraform for migrating an **existing** AKS cluster to
[network isolated](https://learn.microsoft.com/azure/aks/concepts-network-isolated).

Two implementations of the same migration. Pick one.

| | [`azapi/`](./azapi) | [`azurerm/`](./azurerm) |
|---|---|---|
| Describes the cluster? | No — patches 2 fields | **Yes — the whole thing** |
| Requires `import`? | No | Yes |
| Applies needed | 1 | 3 |
| Drift detection | No | Yes |
| Best for | **One-shot migration** | Cluster is a long-term Terraform resource |

## The migration

Three ordered steps, in both implementations:

1. `bootstrapProfile.artifactSource` → `Cache`
2. `upgradeNodeImageVersion` on every agent pool
3. `networkProfile.outboundType` → `none`

> [!WARNING]
> The order is not optional. Nodes that have not been reimaged lose the ability
> to pull images the moment egress is removed in step 3.

## Route A — `azapi/`, one apply

```bash
cd azapi
cp terraform.tfvars.example terraform.tfvars   # then edit
terraform init
terraform apply
```

## Route B — `azurerm/`, three applies

```bash
cd azurerm
cp terraform.tfvars.example terraform.tfvars   # then edit

./scripts/bootstrap.sh    # generate a real cluster.tf from the live cluster
# fold generated.tf into cluster.tf, see azurerm/README.md
rm generated.tf

terraform init
terraform apply -var migration_stage=0   # must be 0 changes
terraform apply -var migration_stage=1
terraform apply -var migration_stage=2
```

## Which should I use?

**`azapi/`**, unless you have a specific reason not to.

`azapi_update_resource` does a GET, merges only the fields you named, and PUTs
the result. It never needs to know anything about the rest of your cluster.

**`azurerm/`** only if this config will be the long-term source of truth for the
cluster. You get drift detection, but `azurerm_kubernetes_cluster` always sends a
**full PUT built from your HCL**, so you must first import and faithfully
describe the entire existing cluster. A wrong field silently resets a setting; a
wrong **ForceNew** field makes Terraform propose deleting the cluster.
`bootstrap.sh` automates most of that.

## You cannot get to zero azapi

Step 2 has no `azurerm` equivalent. `node_image_version` is read-only computed
and there is no on-demand reimage resource; `node_os_upgrade_channel` only
schedules an *eventual* upgrade, which is not deterministic enough when step 3
removes egress. So `azurerm/reimage.tf` keeps one `azapi_resource_action`. It is
a `POST`, not a `PUT`, so it carries none of the full-body risk.

## Not migrating? Don't use either

If the cluster does **not** exist yet, skip all of this. Declare both settings at
creation time and AKS builds a network-isolated cluster in one shot — no
ordering constraint, no reimage step:

```hcl
resource "azurerm_kubernetes_cluster" "ni" {
  # ...
  bootstrap_profile {
    artifact_source = "Cache"
  }
  network_profile {
    # ...
    outbound_type = "none"
  }
}
```

## Prerequisites

- An existing cluster meeting the
  [network isolated limitations](https://learn.microsoft.com/azure/aks/concepts-network-isolated).
- `terraform` >= 1.9, `az`, and `az login`.

On Windows, run `bootstrap.sh` from WSL or Git Bash.

## Gotcha for both

With `artifactSource = Cache` and an explicit `outboundType`, the managed ACR,
its private endpoint, and its private DNS zone are **not** deleted when the
cluster is destroyed. Clean them up manually.

## Verified against

Terraform v1.16.2 · azurerm v5.5.0 · azapi v2.12.0 · AKS API `2025-05-01`.
Both directories pass `terraform validate` and were plan-verified against a live
AKS cluster. Nothing was applied.
