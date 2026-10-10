<#
.SYNOPSIS
  Writes a job list (JSON) for Invoke-Stage3Batch.ps1.
    d5_0      one job per recording of the D4e block table (<outRoot>\stage3\d4e_block_clipping.csv), in its order
    d4e4      S3a-D4e-4-test (S3a-D4e-4-test-approval): one job per recording, same order; testN for
              sub-13/41/42; recording types d4e4_rest / d4e4_msit (S3a-INF-1-amend2)
    d5_0_asm  the single D5-0 assembly job (S3a-D5-0-asm) over the canonical outputs of -SourceBatch
              (default d5_0_1); recording type d5_0_asm
  -Only restricts the list (e.g. -Only sub-06_msit for acceptance or timing).
  A job = id, func (MATLAB job function), params (job-specific), recType (selects the timeout),
  compareKind (stage3_compare kind). See README.md, "Adding a job type".
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('d5_0', 'd4e4', 'd5_0_asm')][string]$Type,
    [Parameter(Mandatory = $true)][string]$Out,
    [string[]]$Only,
    [string]$SourceBatch = 'd5_0_1',
    [string]$Config
)
$ErrorActionPreference = 'Stop'
# PS 5.1 leaves $PSScriptRoot empty in param defaults of an advanced script run with -File
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'runner_config.psd1' }
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$jobs = @()
if ($Type -eq 'd5_0_asm') {
    $src = Join-Path (Join-Path $cfg.EegOutRoot 'stage3_runs') $SourceBatch
    $jobs += [ordered]@{ id = "d5_0_asm_$SourceBatch"; func = 'stage3_d5_0_assemble'; params = [ordered]@{ sourceBatchDir = $src }; recType = 'd5_0_asm'; compareKind = 'all' }
} else {
    $rows = Import-Csv -LiteralPath $cfg.BlockTable
    $seen = @{}
    foreach ($r in $rows) {
        $id = "$($r.subject)_$($r.task)"
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        if ($Only -and $Only -notcontains $id) { continue }
        if ($Type -eq 'd5_0') {
            $jobs += [ordered]@{ id = $id; func = 'stage3_d5_0_compute_one'; params = [ordered]@{ subject = $r.subject; task = $r.task }; recType = $r.task; compareKind = 'd5_0' }
        } else {
            $testN = @('sub-13', 'sub-41', 'sub-42') -contains $r.subject
            $jobs += [ordered]@{ id = $id; func = 'stage3_d4e4_compute_one'; params = [ordered]@{ subject = $r.subject; task = $r.task; testN = $testN }; recType = "d4e4_$($r.task)"; compareKind = 'all' }
        }
    }
}
Write-TextAtomic $Out (ConvertTo-Json -InputObject @($jobs) -Depth 10)
Write-Host "$($jobs.Count) jobs -> $Out"
