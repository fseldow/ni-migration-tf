# ni-migration-tf

Terraform for migrating an **existing** AKS cluster to
[network isolated](https://learn.microsoft.com/azure/aks/concepts-network-isolated).

Two independent implementations of the same migration live here. Pick one.

| | [`azapi/`](./azapi) | [`azurerm/`](./azurerm) |
|---|---|---|
| Provider | `azapi` only | `azurerm` + one `azapi` resource |
| Describes the cluster? | No — patches 2 fields | **Yes — the whole thing** |
| Requires `import`? | No | Yes |
| Applies needed | 1 | 3 |
| Drift detection | No | Yes |
| Risk of clobbering unrelated settings | Low | Real, if the import config is wrong |
| Best for | **One-shot migration** | Cluster is a long-term Terraform resource |

## The migration itself

Three ordered steps, in both implementations:

1. `bootstrapProfile.artifactSource` → `Cache`
2. `upgradeNodeImageVersion` on every agent pool
3. `networkProfile.outboundType` → `none`

> [!WARNING]
> The order is not optional. Nodes that have not been reimaged onto the cached
> image lose the ability to pull images the moment egress is removed in step 3.

## Quick start

Everything is driven by [`scripts/migrate.sh`](./scripts/migrate.sh). A
[`Makefile`](./Makefile) wraps it if you prefer `make`; both are equivalent.

```bash
az login
cp azurerm/terraform.tfvars.example azurerm/terraform.tfvars   # then edit
./scripts/migrate.sh check
```

### Route A — `azapi/`, one apply

```bash
cp azapi/terraform.tfvars.example azapi/terraform.tfvars       # then edit
./scripts/migrate.sh azapi-plan
./scripts/migrate.sh azapi-apply
```

### Route B — `azurerm/`, three applies

```bash
./scripts/migrate.sh pools        # confirm agentpool_names lists every pool
./scripts/migrate.sh bootstrap    # generate + verify cluster.tf from the live cluster
# ... fold generated.tf into cluster.tf, see azurerm/README.md ...
./scripts/migrate.sh apply 0      # import + baseline (must be a clean no-op)
./scripts/migrate.sh apply 1      # artifactSource=Cache, then reimage
./scripts/migrate.sh verify       # check nodes before removing egress
./scripts/migrate.sh apply 2      # outboundType=none
```

Or with make:

```bash
make pools
make bootstrap
make apply STAGE=0     # or: make stage0
make apply STAGE=1
make verify
make apply STAGE=2
```

### All commands

```
check          verify terraform, az, login, tfvars
pools          list agent pools (verify your agentpool_names)
bootstrap      Step 0: generate + normalise cluster.tf from the live cluster
plan <0|1|2>   plan one stage
apply <0|1|2>  apply one stage (enforces ordering)
status         what has been applied, and live cluster state
verify         post-apply checks (cluster, pools, nodes)
azapi-plan     route A: plan the single-apply migration
azapi-apply    route A: apply it
fmt            terraform fmt + validate both directories
clean          remove .tfplan / generated.tf (state untouched)
```

`apply` refuses to skip or repeat stages. It reads the stage recorded in
Terraform state rather than trusting the number you typed, so `apply 2` on a
fresh checkout is rejected rather than silently cutting egress to un-reimaged
nodes.

## Which should I use?

**Use `azapi/`** unless you have a specific reason not to.

`azapi_update_resource` does a GET, merges only the fields you named, and PUTs
the result. It never needs to know anything about the rest of your cluster,
which makes it the right shape for a one-shot migration tool.

**Use `azurerm/`** only if this config is going to be the long-term source of
truth for the cluster — i.e. all future changes will go through Terraform too.
You get real drift detection, but you pay for it up front:
`azurerm_kubernetes_cluster` always sends a **full PUT built from your HCL**, so
you must first import and faithfully describe the entire existing cluster. A
wrong field silently resets a setting; a wrong **ForceNew** field makes
Terraform propose deleting the cluster. `bootstrap` automates most of that
pain, and [`azurerm/README.md`](./azurerm/README.md) documents the rest.

## Note: you cannot get to zero azapi

Step 2 has no `azurerm` equivalent. `node_image_version` is a read-only computed
attribute and there is no on-demand reimage resource; `node_os_upgrade_channel`
only schedules an *eventual* upgrade, which is not deterministic enough when
step 3 removes egress. So `azurerm/reimage.tf` keeps a single
`azapi_resource_action`. It is a `POST` action, not a `PUT`, so it carries none
of the full-body risk.

## Not migrating? Don't use either

If the cluster does **not** exist yet, skip all of this. Declare
`bootstrap_profile` and `outbound_type` at creation time and AKS builds a
network-isolated cluster in one shot — no ordering constraint, no reimage step:

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

- An existing cluster that already meets the
  [network isolated cluster limitations](https://learn.microsoft.com/azure/aks/concepts-network-isolated).
- `terraform` >= 1.9 and `az`, both on `PATH`.
- `az login`, and the subscription set in `terraform.tfvars`.

`./scripts/migrate.sh check` verifies all of the above.

On Windows, run the scripts from WSL or Git Bash. `.gitattributes` forces LF on
`*.sh`; a CRLF checkout would fail with `bad interpreter: /usr/bin/env bash^M`.

## Gotcha that applies to both

With `artifactSource = Cache` and an explicit `outboundType`, the managed ACR,
its private endpoint, and its private DNS zone are **not** deleted when the
cluster is destroyed. Clean them up manually.

## Verified against

Terraform v1.16.2 · azurerm v5.5.0 · azapi v2.12.0 · GNU Make 4.4.1 ·
AKS API `2025-05-01`.

Both directories pass `terraform validate`. `bootstrap` and all three stage
plans were exercised against a live AKS cluster and produce the expected diffs;
nothing was applied during that verification.
