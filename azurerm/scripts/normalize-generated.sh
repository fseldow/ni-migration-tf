#!/usr/bin/env bash
#
# Normalises a `terraform plan -generate-config-out=` file for
# azurerm_kubernetes_cluster so that it actually parses and plans clean.
#
# Terraform's config generator emits a config that azurerm rejects. Every fix
# below was reproduced against a real AKS cluster on
# azurerm v5.5.0 / Terraform v1.16.2:
#
#   1. `outbound_ip_address_ids = []` and `outbound_ip_prefix_ids = []` are
#      emitted alongside `managed_outbound_ip_count`, which they ConflictWith.
#      -> must be deleted outright, not set to null.
#
#   2. Optional numeric fields are emitted as literal 0, but their ValidateFunc
#      ranges start at 1 or 4:
#        default_node_pool.min_count                       (1-1000)
#        default_node_pool.max_count                       (1-1000)
#        load_balancer_profile.idle_timeout_in_minutes     (4-100)
#        load_balancer_profile.managed_outbound_ipv6_count (1-100)
#      -> must become null.
#
#   3. After that it parses, but still plans two cosmetic changes:
#        idle_timeout_in_minutes 0 -> 30
#        node_provisioning_profile.default_node_pools null -> "Auto"
#      -> handled by the injected lifecycle.ignore_changes.
#
# After running this you should get:
#   Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.
#
# Usage:
#   terraform plan -generate-config-out=generated.tf
#   ./scripts/normalize-generated.sh generated.tf
#   terraform plan

set -euo pipefail

FILE="${1:-generated.tf}"
RESOURCE_ADDRESS='resource "azurerm_kubernetes_cluster" "this"'

if [[ ! -f "$FILE" ]]; then
  echo "error: $FILE not found." >&2
  echo "       Run 'terraform plan -generate-config-out=$FILE' first." >&2
  exit 1
fi

echo "==> Normalising $FILE"

before=$(wc -l < "$FILE")

# --- Fix 1: drop ConflictsWith empty lists -----------------------------------
# Deleted, not nulled: the provider rejects these being set at all next to
# managed_outbound_ip_count.
sed -i -E '/^[[:space:]]*outbound_ip_(address|prefix)_ids[[:space:]]*=[[:space:]]*\[\][[:space:]]*$/d' "$FILE"

after=$(wc -l < "$FILE")
echo "    dropped $((before - after)) conflicting empty-list arg(s)"

# --- Fix 2: zero -> null for range-validated optionals -----------------------
sed -i -E \
  -e 's/^([[:space:]]*min_count[[:space:]]*)=[[:space:]]*0[[:space:]]*$/\1= null/' \
  -e 's/^([[:space:]]*max_count[[:space:]]*)=[[:space:]]*0[[:space:]]*$/\1= null/' \
  -e 's/^([[:space:]]*idle_timeout_in_minutes[[:space:]]*)=[[:space:]]*0[[:space:]]*$/\1= null/' \
  -e 's/^([[:space:]]*managed_outbound_ipv6_count[[:space:]]*)=[[:space:]]*0[[:space:]]*$/\1= null/' \
  "$FILE"
echo "    rewrote out-of-range 0 values to null"

# --- Fix 3: inject lifecycle guard ------------------------------------------
if grep -qE '^[[:space:]]*lifecycle[[:space:]]*\{' "$FILE"; then
  echo "    lifecycle block already present, skipping injection"
else
  if ! grep -qF "$RESOURCE_ADDRESS" "$FILE"; then
    echo "error: could not locate '$RESOURCE_ADDRESS' in $FILE" >&2
    exit 1
  fi

  tmp="$(mktemp)"
  # Append the lifecycle block immediately after the resource header line.
  awk -v addr="$RESOURCE_ADDRESS" '
    index($0, addr) && !done {
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
  ' "$FILE" > "$tmp"
  mv "$tmp" "$FILE"
  echo "    injected lifecycle { prevent_destroy + ignore_changes }"
fi

# The trailing guidance is noise when this runs as part of `migrate.sh
# bootstrap`, which prints its own instructions against the real paths.
if [[ "${QUIET_NEXT_STEPS:-0}" == "1" ]]; then
  exit 0
fi

cat <<EOF

==> Done. Now:
      1. Move the resource body from $FILE into cluster.tf,
         re-adding the two MIGRATION hooks:
           bootstrap_profile.artifact_source = local.artifact_source
           network_profile.0.outbound_type   = local.outbound_type
      2. rm $FILE
      3. ./scripts/migrate.sh plan 0
         -> must say '0 to add, 0 to change, 0 to destroy'
EOF
