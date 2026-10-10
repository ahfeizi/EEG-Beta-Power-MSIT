<#
.SYNOPSIS
  Writes a job list (JSON) for Invoke-Stage3Batch.ps1. Type d5_0: one job per recording of the D4e
  block table (<outRoot>\stage3\d4e_block_clipping.csv), in its order; -Only restricts the list
  (e.g. -Only sub-06_msit for acceptance).
  A job = id, func (MATLAB job function), params (job-specific), recType (selects the timeout),
  compareKind (stage3_compare kind). See README.md, "Adding a job type".
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('d5_0')][string]$Type,
    [Parameter(Mandatory = $true)][string]$Out,
    [string[]]$Only,
    [string]$Config
)
$ErrorActionPreference = 'Stop'
# PS 5.1 leaves $PSScriptRoot empty in param defaults of an advanced script run with -File
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'runner_config.psd1' }
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$rows = Import-Csv -LiteralPath $cfg.BlockTable
$seen = @{}; $jobs = @()
foreach ($r in $rows) {
    $id = "$($r.subject)_$($r.task)"
    if ($seen.ContainsKey($id)) { continue }
    $seen[$id] = $true
    if ($Only -and $Only -notcontains $id) { continue }
    $jobs += [ordered]@{ id = $id; func = 'stage3_d5_0_compute_one'; params = [ordered]@{ subject = $r.subject; task = $r.task }; recType = $r.task; compareKind = 'd5_0' }
}
Write-TextAtomic $Out (ConvertTo-Json -InputObject @($jobs) -Depth 10)
Write-Host "$($jobs.Count) jobs -> $Out"
