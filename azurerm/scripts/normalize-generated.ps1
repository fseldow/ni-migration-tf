<#
.SYNOPSIS
  Normalises a `terraform plan -generate-config-out=` file for
  azurerm_kubernetes_cluster so that it actually parses and plans clean.

.DESCRIPTION
  Terraform's config generator emits a config that azurerm rejects. Every one
  of the fixes below was reproduced against a real AKS cluster with
  azurerm v5.5.0 / Terraform v1.16.2:

    1. `outbound_ip_address_ids = []` and `outbound_ip_prefix_ids = []` are
       emitted alongside `managed_outbound_ip_count`, which they ConflictWith.
       -> must be deleted outright, not set to null.

    2. Optional numeric fields are emitted as literal 0, but their ValidateFunc
       ranges start at 1 or 4:
         default_node_pool.min_count                          (1-1000)
         default_node_pool.max_count                          (1-1000)
         load_balancer_profile.idle_timeout_in_minutes        (4-100)
         load_balancer_profile.managed_outbound_ipv6_count    (1-100)
       -> must become null.

    3. After that it parses, but still plans two cosmetic changes:
         idle_timeout_in_minutes 0 -> 30
         node_provisioning_profile.default_node_pools null -> "Auto"
       -> handled by the injected lifecycle.ignore_changes.

  After running this you should get:
    Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.

.EXAMPLE
  terraform plan "-generate-config-out=generated.tf"
  .\scripts\normalize-generated.ps1 -Path generated.tf
  terraform plan
#>
[CmdletBinding()]
param(
    [string]$Path = "generated.tf",
    [string]$ResourceAddress = 'resource "azurerm_kubernetes_cluster" "this"'
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Path)) {
    throw "Not found: $Path. Run terraform plan with -generate-config-out first."
}

Write-Host "==> Normalising $Path" -ForegroundColor Cyan

# --- Fix 1: drop ConflictsWith empty lists -----------------------------------
$before = (Get-Content $Path).Count
$lines = Get-Content $Path | Where-Object {
    $_ -notmatch 'outbound_ip_address_ids\s*=\s*\[\]' -and
    $_ -notmatch 'outbound_ip_prefix_ids\s*=\s*\[\]'
}
Write-Host ("    dropped {0} conflicting empty-list arg(s)" -f ($before - $lines.Count))

# --- Fix 2: zero -> null for range-validated optionals -----------------------
$zeroFields = @(
    'min_count'
    'max_count'
    'idle_timeout_in_minutes'
    'managed_outbound_ipv6_count'
)
foreach ($f in $zeroFields) {
    $lines = $lines -replace "(?<=^\s{0,80}$f)(\s*)=\s*0\s*$", '$1= null'
}
Write-Host "    rewrote out-of-range 0 values to null"

# --- Fix 3: inject lifecycle guard ------------------------------------------
if ($lines -match '^\s*lifecycle\s*\{') {
    Write-Host "    lifecycle block already present, skipping injection" -ForegroundColor Yellow
}
else {
    $idx = ($lines | Select-String -Pattern ([regex]::Escape($ResourceAddress)) | Select-Object -First 1).LineNumber
    if (-not $idx) { throw "Could not locate '$ResourceAddress' in $Path" }

    $inject = @(
        '  lifecycle {'
        '    # Turns an accidental ForceNew into a plan-time error instead of a'
        '    # deleted production cluster. Do not remove.'
        '    prevent_destroy = true'
        ''
        '    ignore_changes = ['
        '      # Provider defaults that differ from what ARM actually returns.'
        '      network_profile[0].load_balancer_profile[0].idle_timeout_in_minutes,'
        '      node_provisioning_profile[0].default_node_pools,'
        '      # Owned by AKS auto-upgrade / the cluster autoscaler, not by us.'
        '      kubernetes_version,'
        '      default_node_pool[0].node_count,'
        '    ]'
        '  }'
        ''
    )
    $lines = $lines[0..($idx - 1)] + $inject + $lines[$idx..($lines.Count - 1)]
    Write-Host "    injected lifecycle { prevent_destroy + ignore_changes }"
}

Set-Content -Path $Path -Value $lines -Encoding utf8

Write-Host ""
Write-Host "==> Done. Now:" -ForegroundColor Green
Write-Host "      1. Move the resource body from $Path into cluster.tf,"
Write-Host "         re-adding the two MIGRATION hooks:"
Write-Host "           bootstrap_profile.artifact_source = local.artifact_source"
Write-Host "           network_profile.0.outbound_type   = local.outbound_type"
Write-Host "      2. Delete $Path"
Write-Host "      3. terraform plan -var migration_stage=0"
Write-Host "         -> must say '0 to add, 0 to change, 0 to destroy'"
