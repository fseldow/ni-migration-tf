# ni-migration-tf (azurerm implementation)

Migrates an **existing** AKS cluster to network isolated using
`azurerm_kubernetes_cluster` instead of `azapi_update_resource`.

See the [repo root README](../README.md) for how this compares to
[`../azapi`](../azapi), and read that comparison before committing to this
route — it is substantially more work.

All commands below are run from the **repo root**.

## Why three applies

A single `azurerm_kubernetes_cluster` resource is PUT at most once per apply,
so "change A → reimage → change B" cannot be expressed in one graph. A
`migration_stage` variable splits it:

| stage | cluster PUT | reimage | meaning |
|---|---|---|---|
| `0` | no-op | — | import + baseline. **Plan must be a clean no-op.** |
| `1` | `artifactSource = Cache` | ✅ runs | nodes move onto the cached image |
| `2` | `outboundType = none` | (already done) | egress removed |

> [!WARNING]
> Never skip straight to stage 2. Nodes that have not been reimaged lose the
> ability to pull images the moment egress disappears. `migrate.sh apply`
> enforces this by reading the stage recorded in Terraform state, but do not
> rely on that alone — understand the ordering.

## Step 0 — generate the cluster config

`cluster.tf` ships a **placeholder scaffold** so the module parses. It is
almost certainly not your cluster, and applying it would reset real settings.

```bash
cp azurerm/terraform.tfvars.example azurerm/terraform.tfvars   # then edit
./scripts/migrate.sh pools        # confirm agentpool_names lists every pool
./scripts/migrate.sh bootstrap
```

`bootstrap` does the whole generation dance for you:

1. Stages an **isolated scratch workspace** containing only a provider block
   and an `import` block. This cannot be done in `azurerm/` itself: config
   generation requires the target resource to be *undeclared*, but `outputs.tf`
   and `reimage.tf` both reference `azurerm_kubernetes_cluster.this`. It also
   means your real directory and its state are never touched by this step.
2. Runs `terraform plan -generate-config-out=generated.tf`.
3. Repairs the result with
   [`scripts/normalize-generated.sh`](./scripts/normalize-generated.sh) — see
   below for why that is necessary.
4. **Verifies** the repaired config plans clean against the live cluster before
   handing it to you.
5. Copies it out to `azurerm/generated.tf`.

### Why the generated config has to be repaired

Terraform's config generator emits a config that azurerm rejects. All three of
these were reproduced against a real cluster on azurerm v5.5.0 / Terraform
v1.16.2:

1. `outbound_ip_address_ids = []` and `outbound_ip_prefix_ids = []` are emitted
   next to `managed_outbound_ip_count`, which they `ConflictsWith`. They must be
   **deleted**, not set to `null`.
2. Optional numerics are emitted as literal `0`, below their validation floors:
   `min_count`/`max_count` ≥ 1, `idle_timeout_in_minutes` ≥ 4,
   `managed_outbound_ipv6_count` ≥ 1.
3. Two residual cosmetic diffs remain afterwards
   (`idle_timeout_in_minutes 0 → 30`, `default_node_pools null → "Auto"`).

`normalize-generated.sh` fixes 1 and 2, and handles 3 by injecting a
`lifecycle` block. You can also run it standalone:

```bash
cd azurerm
terraform plan -generate-config-out=generated.tf
./scripts/normalize-generated.sh generated.tf
```

### The manual part

This is deliberately not automated. Replace the placeholder body of
`azurerm/cluster.tf` with the resource body from `azurerm/generated.tf`, then
re-add the two migration hooks — they are marked `MIGRATION BLOCK` in the
scaffold:

```hcl
bootstrap_profile {
  artifact_source = local.artifact_source     # <- stage 1 hook
}

network_profile {
  # ...everything else from generated.tf...
  outbound_type = local.outbound_type         # <- stage 2 hook
}
```

Keep the generated `lifecycle` block. Then delete `generated.tf` — it declares
`azurerm_kubernetes_cluster.this` as well, so leaving it in place is a
duplicate-resource error:

```bash
rm azurerm/generated.tf
```

## Gate

```bash
./scripts/migrate.sh plan 0
```

**Do not proceed until this reports `0 to add, 0 to change, 0 to destroy`**
(an import line is fine). A non-empty diff means your config disagrees with the
live cluster, and applying it will change things you did not intend.

`apply 0` re-checks this itself and refuses to run if it is not a no-op.

## Steps 1–3

```bash
./scripts/migrate.sh apply 0      # import + baseline
./scripts/migrate.sh apply 1      # artifactSource=Cache, then reimage every pool
./scripts/migrate.sh verify       # confirm nodes are healthy on the new image
./scripts/migrate.sh apply 2      # outboundType=none
```

`./scripts/migrate.sh status` shows the applied stage and the live cluster's
current `artifactSource` / `outboundType` at any point.

## Gotchas

- **`prevent_destroy = true` is load-bearing.** It converts a misconfigured
  ForceNew field from "cluster deleted" into a plan-time error. Do not remove it.
- **The managed ACR is not garbage collected.** With `artifact_source = "Cache"`
  and an explicit `outbound_type`, `terraform destroy` leaves the managed ACR,
  its private endpoint, and private DNS zone behind. Clean them up manually.
- **Pin `migration_stage` in `terraform.tfvars`** so a bare `terraform apply`
  outside the script cannot silently revert a stage.
- **`azapi_resource_action` has no drift detection.** Its read is a no-op; it
  fires once at create and never re-runs. That is intentional — you do not want
  a node pool reimage on every apply.
- Provider floors: `bootstrap_profile` needs azurerm **≥ 4.44.0**; this config
  targets the **v5** line, which additionally requires the
  `node_provisioning_profile` block.

## Layout

```
provider.tf     azurerm ~> 5.5, azapi ~> 2.12
variables.tf    inputs + migration_stage validation
locals.tf       stage -> artifact_source / outbound_type / reimage set
import.tf       import block for the existing cluster
cluster.tf      THE CLUSTER (replace the scaffold, see Step 0)
reimage.tf      the one remaining azapi resource
outputs.tf      includes a next_step hint
scripts/        normalize-generated.sh
```

## Verified against

Terraform v1.16.2 · azurerm v5.5.0 · azapi v2.12.0 · AKS API `2025-05-01`.

`terraform validate` passes. `bootstrap` was run end-to-end against a live AKS
cluster and reached `0 to add, 0 to change, 0 to destroy`; stage 1 and stage 2
plans were confirmed to produce exactly the intended `artifact_source` and
`outbound_type` diffs plus the reimage action. Nothing was applied.
