<#
.SYNOPSIS
  Chunked D5 option (b) residual test (S3a-D5b-amend1) and its R-b1 null calibration (S3a-D5b-null).
  Serial and resumable with the same command; log <EegOutRoot>\stage3_runs\d5b_chunked.log.
    -Stage null : noise-only twins of the 9 test recordings (<EegOutRoot>\d5b_null, stage3_d5b_null_make,
                  seed base 5000) -> unit batch d5bnullu_1 (timing runs first, S3a-INF-1-amend2) -> merge
                  batch d5bnullm_1 -> <OutRoot>\stage3\d5b\null_criterion.csv
    -Stage real : unit batch d5bu_1 -> merge batch d5bm_1 -> <OutRoot>\stage3\d5b\criterion_real_vs_null.csv
                  (runs only after Amirhossein has decided the R-b1 criterion; refuses without -Approved)
  Units: one test-set recording x a channel range (6 channels rest, 3 MSIT+; ~5 min each).
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Invoke-Stage3D5bChunked.ps1 -Stage null
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('null', 'real')][string]$Stage,
    [switch]$Approved,
    [string]$Config
)
$ErrorActionPreference = 'Stop'
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'runner_config.psd1' }
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$runs = Join-Path $cfg.EegOutRoot 'stage3_runs'
$log = Join-Path $runs 'd5b_chunked.log'
$stage3 = (Resolve-Path (Join-Path $PSScriptRoot '..\stage3')).Path
$testSet = Join-Path $cfg.OutRoot 'stage3\d5b\test_set.csv'
$outD5b = Join-Path $cfg.OutRoot 'stage3\d5b'
function Say([string]$Msg) { $l = '{0} {1}' -f (Get-Date).ToString('s'), $Msg; [System.IO.File]::AppendAllText($log, "$l`r`n"); Write-Host $l }
function Invoke-Ps([string]$Script, [string[]]$ScriptArgs) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot $Script)) + $ScriptArgs
    & powershell.exe @a | Out-Host
    $LASTEXITCODE
}
function Get-Canonical([string]$Batch) {
    $b = Read-Json (Join-Path $runs "$Batch\batch.json")
    if ($b.status -ne 'DONE') { throw "$Batch is $($b.status)" }
    (Read-Json (Join-Path $runs "$Batch\state\$(@($b.jobs)[0].id).json")).canonical.path
}
function Invoke-Units([string]$Name, [string]$BatchId, [string[]]$JobListArgs) {
    $jl = Join-Path $runs "jobs_$Name.json"
    if (-not (Test-Path $jl)) { [void](Invoke-Ps 'New-Stage3JobList.ps1' (@('-Type', 'd5bu', '-Out', $jl, '-Config', $Config) + $JobListArgs)) }
    $all = Read-JsonArray $jl
    $tj = @(($all | Where-Object { $_.recType -eq 'd5bu_rest' } | Select-Object -First 1).id, ($all | Where-Object { $_.recType -eq 'd5bu_msit' } | Select-Object -First 1).id)
    Say "units $BatchId ($($all.Count) units; timing on $($tj -join ', '))"
    $c = Invoke-Ps 'Invoke-Stage3JobTypeChain.ps1' @('-Type', 'd5bu', '-Name', $Name, '-TimingJobs', ($tj -join ','), '-BatchId', $BatchId, '-Config', $Config)
    if ($c -ne 0) { Say "STOPPED: unit chain $Name exit $c"; exit $c }
}
function Invoke-Merge([string]$Name, [string]$BatchId, [string]$Source) {
    $c = Invoke-Ps 'Invoke-Stage3JobTypeChain.ps1' @('-Type', 'd5bmerge', '-Name', $Name, '-TimingJobs', "d5bmerge_$Source", '-BatchId', $BatchId, '-SourceBatch', $Source, '-Config', $Config)
    if ($c -ne 0) { Say "STOPPED: merge chain $Name exit $c"; exit $c }
}
function Invoke-Criterion([string]$Out, [string]$NullMat, [string]$RealMat) {
    if (Test-Path $Out) { Say "$Out exists"; return }
    $cmd = "addpath('$stage3'); stage3_d5b_criterion('$NullMat', '$Out'"
    if ($RealMat) { $cmd += ", '$RealMat'" }
    $cmd += ')'
    $r = Invoke-MatlabSimple $cfg $cmd (Join-Path $runs 'd5b_criterion.log') $runs 900
    if ($r.ExitCode -ne 0) { Say "STOPPED: criterion table exit $($r.ExitCode)"; exit 3 }
    Say "criterion table written: $Out"
}

Say "d5b chunked, stage $Stage (pid $PID)"
if ($Stage -eq 'null') {
    $nd = Join-Path $cfg.EegOutRoot 'd5b_null'
    if (-not (Test-Path (Join-Path $nd 'manifest.tsv'))) {
        if (Test-Path (Join-Path $nd 'raw')) { Say "STOPPED: $nd\raw exists without manifest (interrupted generation; inspect and remove by hand)"; exit 3 }
        $r = Invoke-MatlabSimple $cfg "addpath('$stage3'); stage3_d5b_null_make('$($cfg.RawRoot)', '$testSet', '$nd', 5000)" (Join-Path $runs 'd5b_null_make.log') $runs 7200
        if ($r.ExitCode -ne 0) { Say "STOPPED: null generation exit $($r.ExitCode)"; exit 3 }
        Say "noise twins written to $nd"
    }
    Invoke-Units 'd5bnullu' 'd5bnullu_1' @('-RawRootOverride', (Join-Path $nd 'raw'), '-ManifestOverride', (Join-Path $nd 'manifest.tsv'))
    Invoke-Merge 'd5bnullm' 'd5bnullm_1' 'd5bnullu_1'
    Invoke-Criterion (Join-Path $outD5b 'null_criterion.csv') (Get-Canonical 'd5bnullm_1') ''
} else {
    if (-not $Approved) { Say 'STOPPED: the real (b) test needs -Approved (R-b1 criterion decided by Amirhossein, S3a-D5b-null)'; exit 3 }
    Invoke-Units 'd5bu' 'd5bu_1' @()
    Invoke-Merge 'd5bm' 'd5bm_1' 'd5bu_1'
    Invoke-Criterion (Join-Path $outD5b 'criterion_real_vs_null.csv') (Get-Canonical 'd5bnullm_1') (Get-Canonical 'd5bm_1')
}
Say "stage $Stage done"
exit 0
