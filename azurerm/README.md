# ni-migration-tf (azurerm implementation)

Migrates an **existing** AKS cluster to network isolated using
`azurerm_kubernetes_cluster`. See the [root README](../README.md) for how this
compares to [`../azapi`](../azapi) — that one is simpler and usually the right
choice.

## Usage

```bash
cd azurerm
cp terraform.tfvars.example terraform.tfvars   # fill in sub / rg / cluster / pools

# Step 0: generate a real cluster.tf from the live cluster
./scripts/bootstrap.sh
# move generated.tf's resource body into cluster.tf, changing two lines to:
#   artifact_source = local.artifact_source
#   outbound_type   = local.outbound_type
rm generated.tf

terraform init
terraform apply -var migration_stage=0   # import + baseline, must be 0 changes
terraform apply -var migration_stage=1   # artifactSource=Cache, then reimage
terraform apply -var migration_stage=2   # outboundType=none
```

> [!WARNING]
> Apply the stages in order. Nodes that have not been reimaged in stage 1 lose
> the ability to pull images the moment stage 2 removes egress.

## Why three applies

A single `azurerm_kubernetes_cluster` resource is PUT at most once per apply, so
"change A → reimage → change B" cannot be one graph. `migration_stage` splits it:

| stage | cluster PUT | reimage |
|---|---|---|
| `0` | no-op | — |
| `1` | `artifactSource = Cache` | runs |
| `2` | `outboundType = none` | already done |

Stage 0 exists so you can prove the imported config matches reality before it is
allowed to change anything. **It must plan `0 to add, 0 to change, 0 to destroy`**
(an import line is fine). Anything else means your `cluster.tf` disagrees with the
live cluster and applying it will change things you did not intend.

## Why Step 0 needs a script

`cluster.tf` ships a **placeholder scaffold** so the module parses — it is not
your cluster. `azurerm_kubernetes_cluster` always sends a **full PUT built from
your HCL**, so the entire existing cluster must be described accurately first.

`terraform plan -generate-config-out` is supposed to do that, but its output is
rejected by azurerm. Reproduced against a live cluster on azurerm v5.5.0 /
Terraform v1.16.2:

1. `outbound_ip_address_ids = []` and `outbound_ip_prefix_ids = []` are emitted
   next to `managed_outbound_ip_count`, which they `ConflictsWith` — must be
   deleted, not nulled.
2. Optional numerics are emitted as literal `0`, below their validation floors
   (`min_count`/`max_count` ≥ 1, `idle_timeout_in_minutes` ≥ 4,
   `managed_outbound_ipv6_count` ≥ 1).
3. Two residual cosmetic diffs afterwards (`idle_timeout_in_minutes 0 → 30`,
   `default_node_pools null → "Auto"`).

`scripts/bootstrap.sh` fixes all three, injects a `lifecycle` block, and verifies
the result plans clean before handing it to you. It generates in a scratch
directory — config generation requires the target resource to be *undeclared*,
but `outputs.tf` and `reimage.tf` both reference
`azurerm_kubernetes_cluster.this`, so moving `cluster.tf` aside would only
produce "Reference to undeclared resource". Your directory and its state are
never touched.

## Gotchas

- **`prevent_destroy = true` is load-bearing.** It converts a misconfigured
  ForceNew field from "cluster deleted" into a plan-time error. Do not remove it.
- **Delete `generated.tf` after folding it in.** It declares
  `azurerm_kubernetes_cluster.this` too, so leaving it there is a duplicate
  resource error.
- **The managed ACR is not garbage collected.** With `artifact_source = "Cache"`
  and an explicit `outbound_type`, `terraform destroy` leaves the managed ACR,
  its private endpoint, and private DNS zone behind.
- **`reimage.tf` keeps one `azapi_resource_action`.** azurerm has no equivalent:
  `node_image_version` is read-only computed, and `node_os_upgrade_channel` only
  schedules an *eventual* upgrade. It fires once at create and never re-runs, so
  stage 2 does not reimage again.
- Provider floors: `bootstrap_profile` needs azurerm ≥ 4.44.0; this targets v5,
  which additionally requires the `node_provisioning_profile` block.

## Layout

```
provider.tf     azurerm ~> 5.5, azapi ~> 2.12
variables.tf    inputs + migration_stage validation
locals.tf       stage -> artifact_source / outbound_type / reimage set
import.tf       import block for the existing cluster
cluster.tf      THE CLUSTER (replace the scaffold via bootstrap.sh)
reimage.tf      the one remaining azapi resource
outputs.tf      includes a next_step hint
scripts/        bootstrap.sh
```

## Verified against

Terraform v1.16.2 · azurerm v5.5.0 · azapi v2.12.0 · AKS API `2025-05-01`.

`bootstrap.sh` was run end-to-end against a live AKS cluster; stage 0 plans
`1 to import, 0 to add, 0 to change, 0 to destroy`, stage 1 adds the reimage
action and flips `artifact_source` to `Cache`, stage 2 flips `outbound_type` to
`none`. Nothing was applied.
