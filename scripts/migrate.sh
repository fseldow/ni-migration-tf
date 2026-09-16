#!/usr/bin/env bash
#
# Driver for the AKS network-isolated migration.
#
# Route A (azapi/)   : one apply, three ordered azapi resources.
# Route B (azurerm/) : three applies, gated by var.migration_stage.
#
# The dangerous part of route B is stage ordering: if egress is removed
# (stage 2) before the nodes have been reimaged onto the cached image
# (stage 1), they can no longer pull images. This script enforces that
# ordering by reading the stage actually recorded in Terraform state,
# rather than trusting whatever you typed on the command line.
#
# Usage: ./scripts/migrate.sh <command> [args]
#        run with no arguments for help.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AZAPI_DIR="$REPO_ROOT/azapi"
AZURERM_DIR="$REPO_ROOT/azurerm"

# Scratch workspace used by `bootstrap`. Cleaned up on exit.
#
# Deliberately an EXIT trap rather than a RETURN trap inside the function:
# a RETURN trap set inside a function stays registered after that function
# returns and fires again on the next function return, where the variable it
# references no longer exists -> "unbound variable" under `set -u`.
WORKDIR=""
cleanup() { [[ -n "${WORKDIR:-}" ]] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# --- pretty ------------------------------------------------------------------
if [[ -t 1 ]]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[36m'; D=$'\033[2m'; N=$'\033[0m'
else
  R=''; G=''; Y=''; B=''; D=''; N=''
fi

info()  { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()    { printf '%s  ok%s %s\n' "$G" "$N" "$*"; }
warn()  { printf '%s  !!%s %s\n' "$Y" "$N" "$*"; }
die()   { printf '%serror%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
step()  { printf '\n%s%s%s\n' "$B" "$*" "$N"; }

confirm() {
  local prompt="$1" reply
  if [[ "${ASSUME_YES:-0}" == "1" ]]; then
    warn "ASSUME_YES=1, auto-confirming: $prompt"
    return 0
  fi
  printf '%s%s%s [y/N] ' "$Y" "$prompt" "$N"
  read -r reply </dev/tty
  [[ "$reply" == "y" || "$reply" == "Y" ]]
}

# --- prerequisites -----------------------------------------------------------
need_tools() {
  local missing=0
  for c in terraform az; do
    command -v "$c" >/dev/null 2>&1 || { warn "missing: $c"; missing=1; }
  done
  [[ $missing -eq 0 ]] || die "install the missing tools and retry"
}

need_login() {
  az account show >/dev/null 2>&1 \
    || die "not logged in to Azure. Run: az login"
}

tfvars_for() {
  local dir="$1"
  [[ -f "$dir/terraform.tfvars" ]] \
    || die "missing $dir/terraform.tfvars (copy terraform.tfvars.example and edit it)"
}

# Reads a variable out of terraform.tfvars. Good enough for the flat
# string values this project uses. Tolerates a missing file: under
# `set -o pipefail` a failing sed would otherwise abort the whole script.
tfvar() {
  local dir="$1" key="$2"
  [[ -f "$dir/terraform.tfvars" ]] || return 0
  sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" \
    "$dir/terraform.tfvars" 2>/dev/null | head -1 || true
}

# --- stage bookkeeping -------------------------------------------------------
# The stage recorded in state is the source of truth for what has actually
# been applied. Absent state means nothing has been applied yet.
applied_stage() {
  local out
  if ! out="$(cd "$AZURERM_DIR" && terraform output -raw migration_stage 2>/dev/null)"; then
    echo "none"
    return
  fi
  if [[ -n "$out" ]]; then echo "$out"; else echo "none"; fi
}

assert_stage_transition() {
  local target="$1" current
  current="$(applied_stage)"

  if [[ "$current" == "none" ]]; then
    [[ "$target" == "0" ]] || die \
"nothing applied yet, so you must start at STAGE=0 (you asked for $target).
       Stage 0 imports the cluster and proves your config matches reality."
    return 0
  fi

  if (( target < current )); then
    die "cannot go backwards: stage $current is already applied, you asked for $target"
  fi
  if (( target > current + 1 )); then
    die "cannot skip stages: stage $current is applied, you asked for $target.
       Nodes that have not been reimaged (stage 1) lose the ability to pull
       images the moment egress is removed (stage 2)."
  fi
  return 0
}

# Pure usage validation, checked before anything touches Azure.
validate_stage_arg() {
  local s="${1:-}"
  [[ -n "$s" ]] || die "usage: $0 $2 <0|1|2>"
  case "$s" in
    0|1|2) return 0 ;;
    *) die "stage must be 0, 1 or 2 (got '$s')" ;;
  esac
}

# --- terraform helpers -------------------------------------------------------
tf() { local d="$1"; shift; (cd "$d" && terraform "$@"); }

# Returns 0 if the plan is a pure no-op. An import-only plan counts as a no-op.
plan_is_noop() {
  local dir="$1"; shift
  local out rc
  set +e
  out="$(cd "$dir" && terraform plan -no-color -input=false -detailed-exitcode "$@" 2>&1)"
  rc=$?
  set -e
  [[ $rc -eq 0 ]] && return 0
  if [[ $rc -eq 2 ]]; then
    # exit 2 == changes present. An import-only plan still reports 2, so
    # fall back to parsing the summary line.
    if grep -qE 'Plan: [0-9]+ to import, 0 to add, 0 to change, 0 to destroy' <<<"$out"; then
      return 0
    fi
    printf '%s\n' "$out" | tail -40
    return 1
  fi
  printf '%s\n' "$out" | tail -40
  return 1
}

scaffold_still_in_place() {
  grep -q 'PLACEHOLDER SCAFFOLD' "$AZURERM_DIR/cluster.tf" 2>/dev/null
}

# generated.tf declares azurerm_kubernetes_cluster.this too, so leaving it
# next to a real cluster.tf is a "Duplicate resource configuration" error that
# blocks init. Easy to hit: bootstrap leaves the file there on purpose.
assert_no_leftover_generated() {
  [[ -f "$AZURERM_DIR/generated.tf" ]] || return 0
  die "azurerm/generated.tf is still present alongside cluster.tf.

       Both declare azurerm_kubernetes_cluster.this, which Terraform rejects
       as a duplicate resource. Once you have folded its contents into
       cluster.tf, delete it:

           rm azurerm/generated.tf"
}

# =============================================================================
# commands
# =============================================================================

cmd_check() {
  step "Prerequisites"
  need_tools
  ok "terraform $(terraform version | head -1 | awk '{print $2}')"
  ok "az $(az version --query '"azure-cli"' -o tsv 2>/dev/null)"
  need_login
  ok "azure account: $(az account show --query '[name,id]' -o tsv | tr '\n' ' ')"

  if [[ -n "${ARM_SUBSCRIPTION_ID:-}" ]]; then
    ok "ARM_SUBSCRIPTION_ID=$ARM_SUBSCRIPTION_ID"
  else
    warn "ARM_SUBSCRIPTION_ID not exported (providers read subscription_id from tfvars anyway)"
  fi

  for d in "$AZAPI_DIR" "$AZURERM_DIR"; do
    if [[ -f "$d/terraform.tfvars" ]]; then
      ok "$(basename "$d")/terraform.tfvars present"
    else
      warn "$(basename "$d")/terraform.tfvars missing (cp terraform.tfvars.example terraform.tfvars)"
    fi
  done

  if scaffold_still_in_place; then
    warn "azurerm/cluster.tf is still the PLACEHOLDER SCAFFOLD — run '$0 bootstrap'"
  fi
  if [[ -f "$AZURERM_DIR/generated.tf" ]]; then
    warn "azurerm/generated.tf still present - fold it into cluster.tf and delete it"
  fi
}

cmd_pools() {
  need_tools; need_login
  tfvars_for "$AZURERM_DIR"
  local rg cl
  rg="$(tfvar "$AZURERM_DIR" resource_group_name)"
  cl="$(tfvar "$AZURERM_DIR" resource_name)"
  [[ -n "$rg" && -n "$cl" ]] || die "could not read resource_group_name / resource_name from terraform.tfvars"

  step "Agent pools on $cl"
  az aks nodepool list -g "$rg" --cluster-name "$cl" \
    --query "[].{name:name, mode:mode, count:count, image:nodeImageVersion}" -o table

  echo
  info "agentpool_names in terraform.tfvars must list ALL of the above."
  info "Any pool you omit is never reimaged, and will not be able to pull"
  info "images once stage 2 removes egress."
}

cmd_bootstrap() {
  need_tools; need_login
  tfvars_for "$AZURERM_DIR"

  local sub rg cl id
  sub="$(tfvar "$AZURERM_DIR" subscription_id)"
  rg="$(tfvar "$AZURERM_DIR" resource_group_name)"
  cl="$(tfvar "$AZURERM_DIR" resource_name)"
  [[ -n "$sub" && -n "$rg" && -n "$cl" ]] \
    || die "subscription_id / resource_group_name / resource_name must all be set in azurerm/terraform.tfvars"
  id="/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ContainerService/managedClusters/$cl"

  # Generation happens in an isolated scratch directory containing nothing but
  # a provider block and an import block.
  #
  # It cannot be done in $AZURERM_DIR: config generation requires the target
  # resource to be undeclared, but outputs.tf and reimage.tf both reference
  # azurerm_kubernetes_cluster.this. Moving cluster.tf aside therefore turns
  # those into "Reference to undeclared resource" errors and nothing is
  # generated. Working in a scratch dir also means the real directory and its
  # state are never touched by this step.
  local work
  WORKDIR="$(mktemp -d)"
  work="$WORKDIR"

  step "Step 0a - staging an isolated generation workspace"
  cp "$AZURERM_DIR/provider.tf" "$work/"
  if [[ -f "$AZURERM_DIR/.terraform.lock.hcl" ]]; then
    cp "$AZURERM_DIR/.terraform.lock.hcl" "$work/"
  fi
  cat > "$work/vars.tf" <<EOF
variable "subscription_id" { type = string }
EOF
  cat > "$work/import.tf" <<EOF
import {
  to = azurerm_kubernetes_cluster.this
  id = "$id"
}
EOF
  cat > "$work/terraform.tfvars" <<EOF
subscription_id = "$sub"
EOF
  ok "workspace: $work"
  ok "target: $cl (rg $rg)"

  step "Step 0b - terraform init"
  (cd "$work" && terraform init -input=false) >/dev/null
  ok "initialised"

  step "Step 0c - generate config from the live cluster"
  info "This command is EXPECTED to fail. Terraform's generator emits a"
  info "config that azurerm rejects; the next step repairs it."
  (cd "$work" && terraform plan -input=false -generate-config-out=generated.tf) >/dev/null 2>&1 || true
  if [[ ! -s "$work/generated.tf" ]]; then
    warn "generation produced nothing. Raw error:"
    (cd "$work" && terraform plan -input=false -generate-config-out=generated.tf 2>&1 | tail -20) || true
    die "could not generate config for $cl"
  fi
  ok "generated $(wc -l < "$work/generated.tf") lines"

  step "Step 0d - normalise it"
  QUIET_NEXT_STEPS=1 "$AZURERM_DIR/scripts/normalize-generated.sh" "$work/generated.tf"

  step "Step 0e - verify it plans clean against the live cluster"
  if plan_is_noop "$work"; then
    ok "clean: 0 to add, 0 to change, 0 to destroy"
  else
    cp "$work/generated.tf" "$AZURERM_DIR/generated.tf"
    die "still does not plan clean (diff above).
       The partial result was saved to azurerm/generated.tf for inspection."
  fi

  cp "$work/generated.tf" "$AZURERM_DIR/generated.tf"

  cat <<EOF

${G}Bootstrap complete.${N} Verified against the live cluster, nothing was applied.

  Result: ${B}azurerm/generated.tf${N}

${Y}Manual step - this is deliberately not automated:${N}

  Replace the placeholder body of ${B}azurerm/cluster.tf${N} with the resource
  body from generated.tf, then re-add the two migration hooks (they are
  marked MIGRATION BLOCK in the current cluster.tf):

      bootstrap_profile {
        artifact_source = local.artifact_source
      }

      network_profile {
        # ...everything else from generated.tf...
        outbound_type = local.outbound_type
      }

  Keep the generated ${B}lifecycle${N} block. Then:

      rm azurerm/generated.tf
      $0 plan 0      ${D}# must be 0 to add, 0 to change, 0 to destroy${N}
EOF
  return 0
}

cmd_plan() {
  local stage="${1:-}"
  validate_stage_arg "$stage" plan
  need_tools; need_login
  tfvars_for "$AZURERM_DIR"

  if scaffold_still_in_place; then
    die "cluster.tf is still the placeholder scaffold.
       Run '$0 bootstrap' first - applying this would reset real cluster settings."
  fi
  assert_no_leftover_generated

  step "Plan stage $stage"
  tf "$AZURERM_DIR" init -input=false >/dev/null
  tf "$AZURERM_DIR" plan -input=false -var "migration_stage=$stage" -out "stage${stage}.tfplan"

  if [[ "$stage" == "0" ]]; then
    echo
    info "Stage 0 gate: the plan above MUST be '0 to add, 0 to change, 0 to destroy'"
    info "(an import line is fine). Anything else means your cluster.tf disagrees"
    info "with the live cluster, and applying it will change things you did not intend."
  fi
}

cmd_apply() {
  local stage="${1:-}"
  validate_stage_arg "$stage" apply
  need_tools; need_login
  tfvars_for "$AZURERM_DIR"

  if scaffold_still_in_place; then
    die "cluster.tf is still the placeholder scaffold. Run '$0 bootstrap' first."
  fi
  assert_no_leftover_generated

  assert_stage_transition "$stage"

  tf "$AZURERM_DIR" init -input=false >/dev/null

  # Stage 0 must be provably a no-op before we let it touch anything.
  if [[ "$stage" == "0" ]]; then
    step "Stage 0 gate - proving the config matches the live cluster"
    if plan_is_noop "$AZURERM_DIR" -var "migration_stage=0"; then
      ok "clean no-op, safe to import"
    else
      die "stage 0 is not a no-op (diff above).
       Your cluster.tf disagrees with the live cluster. Fix it before applying."
    fi
  fi

  case "$stage" in
    1) warn "stage 1 switches artifactSource to Cache and REIMAGES every pool in agentpool_names."
       warn "Run '$0 pools' first if you are not certain that list is complete." ;;
    2) warn "stage 2 REMOVES EGRESS from the cluster (outboundType=none)."
       warn "Only proceed if stage 1 reimaging completed and nodes are healthy." ;;
  esac

  confirm "Apply stage $stage?" || { info "aborted"; return 0; }

  step "Applying stage $stage"
  tf "$AZURERM_DIR" apply -input=false -auto-approve -var "migration_stage=$stage"

  echo
  ok "stage $stage applied"
  local nxt
  nxt="$(tf "$AZURERM_DIR" output -raw next_step 2>/dev/null || true)"
  [[ -n "$nxt" ]] && printf '\n%s\n' "$nxt"
  return 0
}

cmd_status() {
  need_tools
  step "Migration status"

  local cur; cur="$(applied_stage)"
  if [[ "$cur" == "none" ]]; then
    printf '  applied stage : %s(nothing applied yet)%s\n' "$D" "$N"
  else
    printf '  applied stage : %s\n' "$cur"
    (cd "$AZURERM_DIR" && terraform output 2>/dev/null | sed 's/^/  /') || true
  fi

  if command -v az >/dev/null 2>&1 && az account show >/dev/null 2>&1; then
    local rg cl
    rg="$(tfvar "$AZURERM_DIR" resource_group_name)"
    cl="$(tfvar "$AZURERM_DIR" resource_name)"
    if [[ -n "$rg" && -n "$cl" ]]; then
      step "Live cluster ($cl)"
      az aks show -g "$rg" -n "$cl" \
        --query '{artifactSource:bootstrapProfile.artifactSource, outboundType:networkProfile.outboundType, provisioning:provisioningState}' \
        -o yaml 2>/dev/null | sed 's/^/  /' || warn "could not read live cluster"
    fi
  fi
  return 0
}

cmd_verify() {
  need_tools; need_login
  tfvars_for "$AZURERM_DIR"
  local rg cl
  rg="$(tfvar "$AZURERM_DIR" resource_group_name)"
  cl="$(tfvar "$AZURERM_DIR" resource_name)"

  step "Cluster state"
  az aks show -g "$rg" -n "$cl" \
    --query '{artifactSource:bootstrapProfile.artifactSource, outboundType:networkProfile.outboundType, provisioning:provisioningState, power:powerState.code}' \
    -o yaml | sed 's/^/  /'

  step "Node pool images"
  az aks nodepool list -g "$rg" --cluster-name "$cl" \
    --query "[].{name:name, provisioning:provisioningState, image:nodeImageVersion}" -o table | sed 's/^/  /'

  step "Nodes"
  if command -v kubectl >/dev/null 2>&1; then
    kubectl get nodes -o wide 2>/dev/null | sed 's/^/  /' \
      || warn "kubectl could not reach the cluster (az aks get-credentials -g $rg -n $cl)"
  else
    warn "kubectl not installed, skipping node check"
  fi
}

cmd_azapi_plan() {
  need_tools; need_login
  tfvars_for "$AZAPI_DIR"
  step "Route A - plan (single apply, all three steps)"
  tf "$AZAPI_DIR" init -input=false >/dev/null
  tf "$AZAPI_DIR" plan -input=false -out main.tfplan
}

cmd_azapi_apply() {
  need_tools; need_login
  tfvars_for "$AZAPI_DIR"
  [[ -f "$AZAPI_DIR/main.tfplan" ]] || die "no saved plan. Run '$0 azapi-plan' first."
  warn "This performs ALL THREE steps in one apply, ending with egress removed."
  confirm "Apply route A?" || { info "aborted"; return 0; }
  tf "$AZAPI_DIR" apply -input=false main.tfplan
}

cmd_fmt() {
  need_tools
  terraform fmt -recursive "$REPO_ROOT"
  for d in "$AZAPI_DIR" "$AZURERM_DIR"; do
    tf "$d" init -backend=false -input=false >/dev/null
    printf '%-10s ' "$(basename "$d")"
    tf "$d" validate -no-color | head -1
  done
}

cmd_clean() {
  info "removing plan files and generated config (state is NOT touched)"
  rm -f "$AZURERM_DIR"/stage*.tfplan "$AZURERM_DIR"/generated.tf "$AZAPI_DIR"/main.tfplan
  ok "done"
}

usage() {
  cat <<EOF
${B}AKS network-isolated migration${N}

${Y}Route B - azurerm/ (three applies)${N}
  $0 check              verify terraform, az, login, tfvars
  $0 pools              list agent pools (check your agentpool_names)
  $0 bootstrap          Step 0: generate + normalise cluster.tf from the live cluster
  $0 plan <0|1|2>       plan one stage
  $0 apply <0|1|2>      apply one stage (enforces ordering)
  $0 status             what has been applied, and live cluster state
  $0 verify             post-apply checks (cluster, pools, nodes)

    stage 0 = import + baseline   (must be a clean no-op)
    stage 1 = artifactSource=Cache, then reimage every pool
    stage 2 = outboundType=none   (removes egress)

${Y}Route A - azapi/ (one apply)${N}
  $0 azapi-plan
  $0 azapi-apply

${Y}Misc${N}
  $0 fmt                terraform fmt + validate both directories
  $0 clean              remove .tfplan / generated.tf

${D}Set ASSUME_YES=1 to skip confirmation prompts (CI only).${N}
EOF
}

main() {
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    check)          cmd_check "$@" ;;
    pools)          cmd_pools "$@" ;;
    bootstrap)      cmd_bootstrap "$@" ;;
    plan)           cmd_plan "$@" ;;
    apply)          cmd_apply "$@" ;;
    status)         cmd_status "$@" ;;
    verify)         cmd_verify "$@" ;;
    azapi-plan)     cmd_azapi_plan "$@" ;;
    azapi-apply)    cmd_azapi_apply "$@" ;;
    fmt)            cmd_fmt "$@" ;;
    clean)          cmd_clean "$@" ;;
    help|-h|--help) usage ;;
    *) printf '%serror%s unknown command: %s\n\n' "$R" "$N" "$cmd" >&2; usage; exit 1 ;;
  esac
}

main "$@"
