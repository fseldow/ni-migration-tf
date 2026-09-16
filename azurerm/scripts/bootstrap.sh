#!/usr/bin/env bash
#
# Step 0: generate a real cluster.tf from the live cluster.
#
# Run from the azurerm/ directory:
#   ./scripts/bootstrap.sh
#
# Produces generated.tf, verified to plan clean against the live cluster.
# Nothing is applied and the current directory's state is never touched.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

[[ -f terraform.tfvars ]] || {
  echo "error: terraform.tfvars not found (cp terraform.tfvars.example terraform.tfvars)" >&2
  exit 1
}

tfvar() {
  sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" terraform.tfvars | head -1
}

SUB="$(tfvar subscription_id)"
RG="$(tfvar resource_group_name)"
CL="$(tfvar resource_name)"
[[ -n "$SUB" && -n "$RG" && -n "$CL" ]] || {
  echo "error: subscription_id / resource_group_name / resource_name must be set in terraform.tfvars" >&2
  exit 1
}
ID="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.ContainerService/managedClusters/$CL"

# Generation happens in a scratch dir, not here: it requires the target
# resource to be undeclared, but outputs.tf and reimage.tf both reference
# azurerm_kubernetes_cluster.this. Moving cluster.tf aside would only produce
# "Reference to undeclared resource" and generate nothing.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp provider.tf "$WORK/"
[[ -f .terraform.lock.hcl ]] && cp .terraform.lock.hcl "$WORK/"
echo 'variable "subscription_id" { type = string }' > "$WORK/vars.tf"
cat > "$WORK/import.tf" <<EOF
import {
  to = azurerm_kubernetes_cluster.this
  id = "$ID"
}
EOF
echo "subscription_id = \"$SUB\"" > "$WORK/terraform.tfvars"

echo "==> generating config for $CL (rg $RG)"
(cd "$WORK" && terraform init -input=false) >/dev/null

# Expected to fail: the generator emits a config azurerm rejects. Repaired below.
(cd "$WORK" && terraform plan -input=false -generate-config-out=generated.tf) >/dev/null 2>&1 || true
[[ -s "$WORK/generated.tf" ]] || {
  echo "error: generation produced nothing. Raw error:" >&2
  (cd "$WORK" && terraform plan -input=false -generate-config-out=generated.tf 2>&1 | tail -20) >&2
  exit 1
}

# --- repair what Terraform's generator gets wrong -----------------------------
# 1. ConflictsWith: these empty lists cannot coexist with managed_outbound_ip_count.
sed -i -E '/^[[:space:]]*outbound_ip_(address|prefix)_ids[[:space:]]*=[[:space:]]*\[\][[:space:]]*$/d' \
  "$WORK/generated.tf"

# 2. Optional numerics emitted as 0, below their validation floors
#    (min/max_count >= 1, idle_timeout_in_minutes >= 4, managed_outbound_ipv6_count >= 1).
sed -i -E \
  -e 's/^([[:space:]]*(min_count|max_count|idle_timeout_in_minutes|managed_outbound_ipv6_count)[[:space:]]*)=[[:space:]]*0[[:space:]]*$/\1= null/' \
  "$WORK/generated.tf"

# 3. Residual cosmetic diffs, plus a guard against ForceNew mistakes.
awk '
  /^resource "azurerm_kubernetes_cluster" "this"/ && !done {
    print
    print "  lifecycle {"
    print "    # Turns an accidental ForceNew into a plan-time error instead of a"
    print "    # deleted production cluster. Do not remove."
    print "    prevent_destroy = true"
    print ""
    print "    ignore_changes = ["
    print "      # Provider defaults that differ from what ARM actually returns."
    print "      network_profile[0].load_balancer_profile[0].idle_timeout_in_minutes,"
    print "      node_provisioning_profile[0].default_node_pools,"
    print "      # Owned by AKS auto-upgrade / the cluster autoscaler, not by us."
    print "      kubernetes_version,"
    print "      default_node_pool[0].node_count,"
    print "    ]"
    print "  }"
    print ""
    done = 1
    next
  }
  { print }
' "$WORK/generated.tf" > "$WORK/g2" && mv "$WORK/g2" "$WORK/generated.tf"

echo "==> verifying it plans clean"
out="$(cd "$WORK" && terraform plan -no-color -input=false 2>&1)" || true
if ! grep -qE 'Plan: [0-9]+ to import, 0 to add, 0 to change, 0 to destroy' <<<"$out"; then
  cp "$WORK/generated.tf" ./generated.tf
  echo "$out" | tail -30 >&2
  echo "error: does not plan clean. Partial result saved to generated.tf" >&2
  exit 1
fi

cp "$WORK/generated.tf" ./generated.tf

cat <<'EOF'

==> generated.tf is ready and verified. Nothing was applied.

Now move its resource body into cluster.tf, changing two lines to:

    artifact_source = local.artifact_source
    outbound_type   = local.outbound_type

Keep the generated lifecycle block. Then:

    rm generated.tf
    terraform apply -var migration_stage=0
EOF
