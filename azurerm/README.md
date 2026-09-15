# ni-migration-azurerm

Migrates an **existing** AKS cluster to [network isolated](https://learn.microsoft.com/azure/aks/concepts-network-isolated)
using `azurerm_kubernetes_cluster` instead of `azapi_update_resource`.

This is the azurerm rewrite of [`fseldow/ni-migration-tf`](https://github.com/fseldow/ni-migration-tf).

## Why this exists, and why it is not obviously better

The original repo drives the migration with three `azapi` resources. That works,
and it is *surgical*: `azapi_update_resource` does a GET, merges only the fields
you named, and PUTs the result. You never have to describe the rest of the cluster.

`azurerm_kubernetes_cluster` always sends a **full PUT built from your HCL**.
That buys you real drift detection, but it means you must first describe the
entire existing cluster accurately. Get a field wrong and you silently reset it;
get a **ForceNew** field wrong and Terraform proposes deleting your cluster.

> **Pick azurerm if** this config will be the long-term source of truth for the cluster.
> **Stay on azapi if** this is a one-shot migration tool. You are not being rewarded
> for the import work.

## What azurerm still cannot do

| Migration step | Mechanism here |
|---|---|
| 1. `bootstrapProfile.artifactSource = Cache` | ✅ `azurerm` — `bootstrap_profile.artifact_source` |
| 2. `upgradeNodeImageVersion` on each pool | ❌ **`azapi_resource_action`** — see below |
| 3. `networkProfile.outboundType = none` | ✅ `azurerm` — `network_profile.outbound_type` |

`node_image_version` is a **read-only computed** attribute in azurerm and there is
no on-demand reimage resource. `node_os_upgrade_channel = "NodeImage"` only schedules
an *eventual* upgrade, which is not deterministic enough when step 3 removes egress.

So one `azapi_resource_action` survives in `reimage.tf`. It is a `POST` action, not
a `PUT`, so it carries none of the full-body risk.

**You cannot get to zero azapi resources for this scenario.**

## Why three applies

A single `azurerm_kubernetes_cluster` resource is PUT at most once per apply, so
"change A → reimage → change B" cannot be expressed in one graph. A `migration_stage`
variable splits it:

| stage | cluster PUT | reimage | meaning |
|---|---|---|---|
| `0` | no-op | — | import + baseline. **Plan must be a clean no-op.** |
| `1` | `artifactSource = Cache` | ✅ runs | nodes move onto the cached image |
| `2` | `outboundType = none` | (already done) | egress removed |

> ⚠️ **Never skip straight to stage 2.** Nodes that have not been reimaged lose
> the ability to pull images the moment egress disappears.

## Setup

### Step 0 — generate the cluster config (do not hand-write it)

`cluster.tf` ships a **placeholder scaffold** so the module parses. It is almost
certainly not your cluster. Replace it:

```powershell
cp terraform.tfvars.example terraform.tfvars   # then edit it
mv cluster.tf cluster.tf.scaffold              # get it out of the way

terraform init
terraform plan "-generate-config-out=generated.tf"
```

That plan **will fail**. Terraform's config generator emits a config azurerm
rejects. Reproduced against a real cluster on azurerm v5.5.0 / Terraform v1.16.2:

1. `outbound_ip_address_ids = []` and `outbound_ip_prefix_ids = []` are emitted
   next to `managed_outbound_ip_count`, which they `ConflictsWith`.
2. Optional numerics are emitted as literal `0`, below their validation floors
   (`min_count`/`max_count` ≥ 1, `idle_timeout_in_minutes` ≥ 4, `managed_outbound_ipv6_count` ≥ 1).
3. Two residual cosmetic diffs (`idle_timeout_in_minutes 0 → 30`,
   `node_provisioning_profile.default_node_pools null → "Auto"`).

All three are fixed for you:

```powershell
.\scripts\normalize-generated.ps1 -Path generated.tf
terraform plan     # -> Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.
```

Now fold the normalised resource body back into `cluster.tf`, re-adding the two
migration hooks (they are marked `MIGRATION BLOCK` in the scaffold):

```hcl
bootstrap_profile {
  artifact_source = local.artifact_source     # <- stage 1 hook
}

network_profile {
  # ...everything else from generated.tf...
  outbound_type = local.outbound_type         # <- stage 2 hook
}
```

Delete `generated.tf` and `cluster.tf.scaffold`.

### Gate

```bash
terraform plan -var migration_stage=0
```

**Do not proceed until this reports `0 to add, 0 to change, 0 to destroy`.**
A non-empty diff here means your config disagrees with the live cluster, and
applying it will change things you did not intend.

### Step 1 — baseline

```bash
terraform apply -var migration_stage=0
```

### Step 2 — Cache + reimage

```bash
terraform apply -var migration_stage=1
```

Then verify nodes are healthy and pulling from the managed ACR before continuing.

### Step 3 — remove egress

```bash
terraform apply -var migration_stage=2
```

## Gotchas

- **`prevent_destroy = true` is load-bearing.** It converts a misconfigured
  ForceNew field from "cluster deleted" into "plan-time error". Do not remove it.
- **The managed ACR is not garbage collected.** With `artifact_source = "Cache"`
  and an explicit `outbound_type`, `terraform destroy` leaves the managed ACR,
  its private endpoint, and private DNS zone behind. Clean them up manually.
- **Pin `migration_stage` in `terraform.tfvars`** so nobody forgets `-var` and
  silently reverts a stage.
- **`azapi_resource_action` has no drift detection.** Its read is a no-op; it
  fires once at create and never re-runs. That is intentional here — you do not
  want a node pool reimage on every apply.
- Provider floors: `bootstrap_profile` needs azurerm **≥ 4.44.0**; this config
  targets the **v5** line and requires `node_provisioning_profile`, which is a
  required block in v5.

## Layout

```
provider.tf     azurerm ~> 5.5, azapi ~> 2.12
variables.tf    inputs + migration_stage validation
locals.tf       stage -> artifact_source / outbound_type / reimage set
import.tf       import block for the existing cluster
cluster.tf      THE CLUSTER (replace the scaffold, see Step 0)
reimage.tf      the one remaining azapi resource
outputs.tf      includes a next_step hint
scripts/        normalize-generated.ps1
```

## Verified against

Terraform v1.16.2 · azurerm v5.5.0 · azapi v2.12.0 · AKS API `2025-05-01`.
`terraform validate` passes; the import + normalize flow was confirmed to reach
`0 to add, 0 to change, 0 to destroy` against a live AKS cluster.
