<#
.SYNOPSIS
  Residual test of D5 fallback (a) (S3a-D5a-test, -amend1, S3a-D5a-width). Serial and resumable with the
  same command; log <EegOutRoot>\stage3_runs\d5a_test.log. Steps, each skipped or resumed when done:
    1. job lists (written once; -NotchA is checked against them on every resume):
       jobs_d5a<a>null.json  the two noise twins (<OutRoot>\stage3\d5b\null_set.csv, <EegOutRoot>\d5b_null)
       jobs_d5a<a>.json      the 9 test-set recordings
       both with blocks from <OutRoot>\stage3\d5a_d4e\d4e_block_clipping.csv (H = 6.637 s);
    2. null chain d5a<a>null (timing on both twins; A/B batch d5a<a>null_1);
    3. real chain d5a<a> (timing on sub-15 MSIT+ and sub-14 rest; A/B batch d5a<a>_1);
    4. stage3_d5a_criterion -> <OutRoot>\stage3\d5a_a<a>\criterion_a.csv and criterion_a_decision.txt.
  Nothing runs after step 4. The final D5 decision is logged by hand (S3a-D5a-width).
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Invoke-Stage3D5aTest.ps1 -NotchA 3
#>
param([Parameter(Mandatory = $true)][double]$NotchA, [string]$Config)
$ErrorActionPreference = 'Stop'
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'runner_config.psd1' }
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$runs = Join-Path $cfg.EegOutRoot 'stage3_runs'
$log = Join-Path $runs 'd5a_test.log'
$stage3 = (Resolve-Path (Join-Path $PSScriptRoot '..\stage3')).Path
$tag = 'd5a{0:g}' -f $NotchA
$outDir = Join-Path $cfg.OutRoot ('stage3\d5a_a{0:g}' -f $NotchA)
function Say([string]$Msg) { $l = '{0} {1}' -f (Get-Date).ToString('s'), $Msg; [System.IO.File]::AppendAllText($log, "$l`r`n"); Write-Host $l }
function Invoke-Ps([string]$Script, [string[]]$ScriptArgs) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot $Script)) + $ScriptArgs
    & powershell.exe @a | Out-Host
    $LASTEXITCODE
}
function Get-JobList([string]$Name, [string[]]$JobListArgs) {
    $jl = Join-Path $runs "jobs_$Name.json"
    if (-not (Test-Path $jl)) {
        $c = Invoke-Ps 'New-Stage3JobList.ps1' (@('-Type', 'd5a', '-Out', $jl, '-NotchA', "$NotchA", '-Config', $Config) + $JobListArgs)
        if ($c -ne 0 -or -not (Test-Path $jl)) { Say "STOPPED: job list $Name exit $c"; exit 3 }
    }
    $all = Read-JsonArray $jl
    $bad = @($all | Where-Object { [double]$_.params.notchA -ne $NotchA })
    if ($bad.Count) { Say "STOPPED: $jl has notchA $($bad[0].params.notchA), not $NotchA"; exit 3 }
    Say "job list $Name`: $($all.Count) jobs, notchA $NotchA"
}
function Invoke-Chain([string]$Name, [string]$Timing) {
    $c = Invoke-Ps 'Invoke-Stage3JobTypeChain.ps1' @('-Type', 'd5a', '-Name', $Name, '-TimingJobs', $Timing, '-BatchId', "${Name}_1", '-Config', $Config)
    $bf = Join-Path $runs "${Name}_1\batch.json"
    if ($c -ne 0 -or -not (Test-Path $bf) -or (Read-Json $bf).status -ne 'DONE') { Say "STOPPED: chain $Name exit $c (see chain_$Name.log)"; exit 3 }
    Say "${Name}_1 DONE"
}
function Get-Canonical([string]$Batch) {
    $b = Read-Json (Join-Path $runs "$Batch\batch.json")
    if ($b.status -ne 'DONE') { throw "$Batch is $($b.status)" }
    (Read-Json (Join-Path $runs "$Batch\state\$(@($b.jobs)[0].id).json")).canonical.path
}

Say "d5a residual test, notchA $NotchA (pid $PID)"
$nd = Join-Path $cfg.EegOutRoot 'd5b_null'
Get-JobList "${tag}null" @('-TestSet', (Join-Path $cfg.OutRoot 'stage3\d5b\null_set.csv'), '-RawRootOverride', (Join-Path $nd 'raw'), '-ManifestOverride', (Join-Path $nd 'manifest.tsv'))
Get-JobList $tag @()
Invoke-Chain "${tag}null" 'sub-25_rest,sub-15_msit'
Invoke-Chain $tag 'sub-15_msit,sub-14_rest'
$out = Join-Path $outDir 'criterion_a.csv'
if (Test-Path $out) { Say "$out exists"; exit 0 }
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$cmd = "addpath('$stage3'); stage3_d5a_criterion('$(Join-Path $runs "${tag}_1")', '$(Join-Path $runs "${tag}null_1")', '$(Get-Canonical 'd5bm_1')', '$out')"
$r = Invoke-MatlabSimple $cfg $cmd (Join-Path $runs 'd5a_criterion.log') $runs 900
if ($r.ExitCode -ne 0) { Say "STOPPED: criterion exit $($r.ExitCode)"; exit 3 }
$dec = Get-Content -LiteralPath (Join-Path $outDir 'criterion_a_decision.txt') | Where-Object { $_ -like 'DECISION*' }
Say "decision table written: $out; $dec"
exit 0
