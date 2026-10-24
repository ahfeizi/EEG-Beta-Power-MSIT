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
              (H with the notches, S3a-D5a-H); -NotchA required; -TestSet and the overrides as for d5bu (noise twins,
              S3a-D5a-test-amend1); recording types d5a_rest / d5a_msit
    s3p1      Stage 3 part 1 (S3a-P1): one job per recording of the D4e block table (runner_config BlockTable), in its
              order, except sub-42 (excluded, S3a-D6; sub-13/41 added: their D4e-4 pair is bad in D6); recording types s3p1_rest / s3p1_msit;
              compare kind 'set' (S3a-INF-1-setspec)
    d6        D6 bad channels (S3a-D6, S3a-D6-impl): one job per subject whose rest and MSIT+ part-1 .set files are both in
              <EegOutRoot>\stage3_part1\manifest*.tsv (one per part-1 batch), sub-42 excluded; recording type d6; compare kind 'all'
    p2        Stage 3 part 2 (S3a-P2, S3a-P2-impl): one job per subject verified in batch d6_1 and not excluded
              (<OutRoot>\stage3\d6\d6_summary.csv); part-1 files and manifests as for d6; recording type p2;
              compare kind 'all'
  -Only restricts the list (e.g. -Only sub-06_msit for acceptance or timing).
  A job = id, func (MATLAB job function), params (job-specific), recType (selects the timeout),
  compareKind (stage3_compare kind). See README.md, "Adding a job type".
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('d5_0', 'd4e4', 'd5_0_asm', 'd4e4_asm', 'd5b', 'd5bu', 'd5bmerge', 'd5a', 's3p1', 'd6', 'p2')][string]$Type,
    [Parameter(Mandatory = $true)][string]$Out,
    [string[]]$Only,
    [string]$SourceBatch = 'd5_0_1',
    [string]$TestSet,
    [string]$RawRootOverride,
    [string]$ManifestOverride,
    [int]$UnitRest = 6,
    [int]$UnitMsit = 3,
    [double]$NotchA = 0,                 # d5a: band edges f0 +/- NotchA Hz (required, S3a-D5a-width)
    [string]$Config
)
$ErrorActionPreference = 'Stop'
# PS 5.1 leaves $PSScriptRoot empty in param defaults of an advanced script run with -File
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'runner_config.psd1' }
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })   # -File passes a comma list as one string
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
    if ($NotchA -le 0) { throw 'd5a needs -NotchA (S3a-D5a-width)' }
    $bt = Join-Path $cfg.OutRoot 'stage3\d5a_d4e\d4e_block_clipping.csv'
    if (-not (Test-Path -LiteralPath $bt)) { throw "missing $bt (S3a-D5a-H)" }
    if (-not $TestSet) { $TestSet = Join-Path $cfg.OutRoot 'stage3\d5b\test_set.csv' }
    foreach ($r in @(Import-Csv -LiteralPath $TestSet)) {
        $id = "$($r.subject)_$($r.task)"
        if ($Only -and $Only -notcontains $id) { continue }
        $pr = [ordered]@{ subject = $r.subject; task = $r.task; role = $r.role; notchA = $NotchA; blockTable = $bt }
        if ($RawRootOverride) { $pr.rawRoot = $RawRootOverride }
        if ($ManifestOverride) { $pr.manifest = $ManifestOverride }
        $jobs += [ordered]@{ id = $id; func = 'stage3_d5a_compute_one'; params = $pr; recType = "d5a_$($r.task)"; compareKind = 'all' }
    }
} elseif ($Type -eq 'p2') {
    $exp = Join-Path $cfg.EegOutRoot 'stage3_part1'
    $mans = @(Get-ChildItem -LiteralPath $exp -Filter 'manifest*.tsv' | Sort-Object Name | ForEach-Object { $_.FullName })
    $sum = @(Import-Csv -LiteralPath (Join-Path $cfg.OutRoot 'stage3\d6\d6_summary.csv'))
    $d6b = Join-Path (Join-Path $cfg.EegOutRoot 'stage3_runs') 'd6_1'
    foreach ($r in $sum) {
        $s = $r.subject
        if ($r.excluded -in @('1', 'true')) { continue }
        if ($Only -and $Only -notcontains $s) { continue }
        $st = Read-Json (Join-Path $d6b "state\$s.json")
        if ($st.status -notin @('verified', 'flagged')) { throw "D6 of ${s} is $($st.status)" }
        if ($st.canonical.sha256 -ne $r.d6_sha256) { throw "D6 of ${s}: summary and state hashes differ" }
        $jobs += [ordered]@{ id = $s; func = 'stage3_p2_compute_one'; params = [ordered]@{ subject = $s; p1Rest = (Join-Path $exp "${s}_task-rest_s3p1.set"); p1Msit = (Join-Path $exp "${s}_task-msit_s3p1.set"); p1Manifest = @($mans); d6File = $st.canonical.path; d6Sha = $st.canonical.sha256 }; recType = 'p2'; compareKind = 'all' }
    }
} elseif ($Type -eq 'd6') {
    $exp = Join-Path $cfg.EegOutRoot 'stage3_part1'
    $mans = @(Get-ChildItem -LiteralPath $exp -Filter 'manifest*.tsv' | Sort-Object Name | ForEach-Object { $_.FullName })   # one per part-1 batch
    $pt = Join-Path $cfg.OutRoot 'stage3\d4e4_test_v2\predictability_by_channel.csv'
    $ptSha = (Get-FileHash -LiteralPath $pt -Algorithm SHA256).Hash.ToLower()
    $files = @($mans | ForEach-Object { Import-Csv -LiteralPath $_ -Delimiter "`t" } | ForEach-Object { $_.file })
    $subs = @($files | ForEach-Object { ($_ -split '_')[0] } | Sort-Object -Unique)
    foreach ($s in $subs) {
        if ($s -eq 'sub-42') { continue }
        $fr = "${s}_task-rest_s3p1.set"; $fm = "${s}_task-msit_s3p1.set"
        if (($files -notcontains $fr) -or ($files -notcontains $fm)) { continue }
        if ($Only -and $Only -notcontains $s) { continue }
        $jobs += [ordered]@{ id = $s; func = 'stage3_d6_compute_one'; params = [ordered]@{ subject = $s; p1Rest = (Join-Path $exp $fr); p1Msit = (Join-Path $exp $fm); p1Manifest = @($mans); predTable = $pt; predSha = $ptSha }; recType = 'd6'; compareKind = 'all' }
    }
} elseif ($Type -eq 's3p1') {
    $seen = @{}
    foreach ($r in @(Import-Csv -LiteralPath $cfg.BlockTable)) {
        $id = "$($r.subject)_$($r.task)"
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        if ($r.subject -eq 'sub-42') { continue }                     # S3a-D6 item 4 (sub-13/41 added, item 5)
        if ($Only -and $Only -notcontains $id) { continue }
        $jobs += [ordered]@{ id = $id; func = 'stage3_p1_compute_one'; params = [ordered]@{ subject = $r.subject; task = $r.task }; recType = "s3p1_$($r.task)"; compareKind = 'set' }
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
