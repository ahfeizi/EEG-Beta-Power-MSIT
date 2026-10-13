<#
.SYNOPSIS
  Writes a job list (JSON) for Invoke-Stage3Batch.ps1.
    d5_0      one job per recording of the D4e block table (<outRoot>\stage3\d4e_block_clipping.csv), in its order
    d4e4      S3a-D4e-4-test (S3a-D4e-4-test-approval): one job per recording, same order; testN for
              sub-13/41/42; recording types d4e4_rest / d4e4_msit (S3a-INF-1-amend2)
    d5_0_asm  the single D5-0 assembly job (S3a-D5-0-asm) over the canonical outputs of -SourceBatch
              (default d5_0_1); recording type d5_0_asm
    d4e4_asm  the single D4e-4 assembly job (S3a-D4e-4-asm) over -SourceBatch (use d4e4_1); type d4e4_asm
    d5b       the D5 option (b) residual test (S3a-D5b): one job per row of <outRoot>\stage3\d5b\test_set.csv;
              recording types d5b_rest / d5b_msit (unchunked; withdrawn from use by S3a-D5b-amend1)
    d5bu      chunked (b) test (S3a-D5b-amend1): one job per test-set recording x channel range
              (-UnitRest channels per rest unit, -UnitMsit per MSIT+ unit, ~5 min each); recording types
              d5bu_rest / d5bu_msit; -TestSet, -RawRootOverride and -ManifestOverride (noise twins, S3a-D5b-null)
    d5bmerge  the single merge job (stage3_d5b_merge) over -SourceBatch; recording type d5bmerge
    d5a       residual test of fallback (a) (S3a-D5a-test): one job per row of <outRoot>\stage3\d5b\test_set.csv
              (whole recording, 16-channel groups), blocks from <outRoot>\stage3\d5a_d4e\d4e_block_clipping.csv
              (H with the notches, S3a-D5a-H); recording types d5a_rest / d5a_msit
  -Only restricts the list (e.g. -Only sub-06_msit for acceptance or timing).
  A job = id, func (MATLAB job function), params (job-specific), recType (selects the timeout),
  compareKind (stage3_compare kind). See README.md, "Adding a job type".
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('d5_0', 'd4e4', 'd5_0_asm', 'd4e4_asm', 'd5b', 'd5bu', 'd5bmerge', 'd5a')][string]$Type,
    [Parameter(Mandatory = $true)][string]$Out,
    [string[]]$Only,
    [string]$SourceBatch = 'd5_0_1',
    [string]$TestSet,
    [string]$RawRootOverride,
    [string]$ManifestOverride,
    [int]$UnitRest = 6,
    [int]$UnitMsit = 3,
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
} elseif ($Type -eq 'd4e4_asm') {
    $src = Join-Path (Join-Path $cfg.EegOutRoot 'stage3_runs') $SourceBatch
    $jobs += [ordered]@{ id = "d4e4_asm_$SourceBatch"; func = 'stage3_d4e4_assemble'; params = [ordered]@{ sourceBatchDir = $src }; recType = 'd4e4_asm'; compareKind = 'all' }
} elseif ($Type -eq 'd5bmerge') {
    $src = Join-Path (Join-Path $cfg.EegOutRoot 'stage3_runs') $SourceBatch
    $jobs += [ordered]@{ id = "d5bmerge_$SourceBatch"; func = 'stage3_d5b_merge'; params = [ordered]@{ sourceBatchDir = $src }; recType = 'd5bmerge'; compareKind = 'all' }
} elseif ($Type -eq 'd5bu') {
    if (-not $TestSet) { $TestSet = Join-Path $cfg.OutRoot 'stage3\d5b\test_set.csv' }
    $root = if ($RawRootOverride) { $RawRootOverride } else { $cfg.RawRoot }
    foreach ($r in @(Import-Csv -LiteralPath $TestSet)) {
        $vh = Get-Content -LiteralPath (Join-Path $root "$($r.subject)\eeg\$($r.subject)_task-$($r.task)_eeg.vhdr") -Raw
        if ($vh -notmatch 'NumberOfChannels=(\d+)') { throw "no NumberOfChannels for $($r.subject) $($r.task)" }
        $nCh = [int]$Matches[1]
        $size = if ($r.task -eq 'msit') { $UnitMsit } else { $UnitRest }
        for ($a = 1; $a -le $nCh; $a += $size) {
            $b = [math]::Min($a + $size - 1, $nCh)
            $id = '{0}_{1}_c{2:D3}-{3:D3}' -f $r.subject, $r.task, $a, $b
            if ($Only -and $Only -notcontains $id) { continue }
            $pr = [ordered]@{ subject = $r.subject; task = $r.task; role = $r.role; chans = @($a, $b) }
            if ($RawRootOverride) { $pr.rawRoot = $RawRootOverride }
            if ($ManifestOverride) { $pr.manifest = $ManifestOverride }
            $jobs += [ordered]@{ id = $id; func = 'stage3_d5b_compute_one'; params = $pr; recType = "d5bu_$($r.task)"; compareKind = 'all' }
        }
    }
} elseif ($Type -eq 'd5a') {
    $bt = Join-Path $cfg.OutRoot 'stage3\d5a_d4e\d4e_block_clipping.csv'
    if (-not (Test-Path -LiteralPath $bt)) { throw "missing $bt (S3a-D5a-H)" }
    foreach ($r in @(Import-Csv -LiteralPath (Join-Path $cfg.OutRoot 'stage3\d5b\test_set.csv'))) {
        $id = "$($r.subject)_$($r.task)"
        if ($Only -and $Only -notcontains $id) { continue }
        $jobs += [ordered]@{ id = $id; func = 'stage3_d5a_compute_one'; params = [ordered]@{ subject = $r.subject; task = $r.task; role = $r.role; blockTable = $bt }; recType = "d5a_$($r.task)"; compareKind = 'all' }
    }
} elseif ($Type -eq 'd5b') {
    foreach ($r in @(Import-Csv -LiteralPath (Join-Path $cfg.OutRoot 'stage3\d5b\test_set.csv'))) {
        $id = "$($r.subject)_$($r.task)"
        if ($Only -and $Only -notcontains $id) { continue }
        $jobs += [ordered]@{ id = $id; func = 'stage3_d5b_compute_one'; params = [ordered]@{ subject = $r.subject; task = $r.task; role = $r.role }; recType = "d5b_$($r.task)"; compareKind = 'all' }
    }
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
