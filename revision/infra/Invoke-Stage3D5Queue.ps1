<#
.SYNOPSIS
  Serial queue (jobs never run in parallel), resumable with the same command; log
  <EegOutRoot>\stage3_runs\queue_d5.log. Steps, each skipped when finished:
    1. D5-0 recompute, A/B batch d5_0_2 (S3a-D5-0-amend2; the 84-job list of d5_0_1);
    2. D5-0 assembly d5asm_2 from d5_0_2 (timeouts_d5asm.json, S3a-INF-1-amend2);
    3. export to <OutRoot>\stage3\d5_0_v2\ and the d5_0_1 vs d5_0_2 check (stage3_d5_0_compare_runs).
  The queue then STOPS. The unchunked (b) test that was step 4 is withdrawn (S3a-D5b-amend1): the chunked
  (b) test runs only after Amirhossein approves the revised R-b1 criterion.
  A step that does not succeed stops the queue.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Invoke-Stage3D5Queue.ps1
#>
param([string]$Config)
$ErrorActionPreference = 'Stop'
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'runner_config.psd1' }
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$runs = Join-Path $cfg.EegOutRoot 'stage3_runs'
$log = Join-Path $runs 'queue_d5.log'
function Say([string]$Msg) { $l = '{0} {1}' -f (Get-Date).ToString('s'), $Msg; [System.IO.File]::AppendAllText($log, "$l`r`n"); Write-Host $l }
function Invoke-Ps([string]$Script, [string[]]$ScriptArgs) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot $Script)) + $ScriptArgs
    & powershell.exe @a | Out-Host
    $LASTEXITCODE
}
function Get-Status([string]$Batch) { $f = Join-Path $runs "$Batch\batch.json"; if (Test-Path $f) { (Read-Json $f).status } else { '' } }
function Invoke-BatchStep([string]$Batch, [string[]]$RunnerArgs) {
    $s = Get-Status $Batch
    if ($s -eq 'DONE') { Say "$Batch already DONE"; return }
    if ($s -and $s -ne 'RUNNING') { Say "QUEUE STOPPED: $Batch is $s"; exit 3 }
    Say "start or resume $Batch"
    $c = Invoke-Ps 'Invoke-Stage3Batch.ps1' (@('-Config', $Config, '-Mode', 'Batch', '-BatchId', $Batch) + $RunnerArgs)
    $s = Get-Status $Batch
    Say "$Batch ended: exit $c, status $s"
    if ($s -ne 'DONE') { Say "QUEUE STOPPED: $Batch status $s"; exit 3 }
}

Say "queue start (pid $PID)"
# 1. D5-0 recompute
Invoke-BatchStep 'd5_0_2' @('-JobList', (Join-Path $runs 'jobs_d5_0.json'))
# 2. assembly from d5_0_2
$jl = Join-Path $runs 'jobs_d5asm2.json'
if (-not (Test-Path $jl)) { [void](Invoke-Ps 'New-Stage3JobList.ps1' @('-Type', 'd5_0_asm', '-SourceBatch', 'd5_0_2', '-Out', $jl, '-Config', $Config)) }
Invoke-BatchStep 'd5asm_2' @('-JobList', $jl, '-JobTimeouts', (Join-Path $runs 'timeouts_d5asm.json'))
# 3. export and check
$outDir = Join-Path $cfg.OutRoot 'stage3\d5_0_v2'
if (-not (Test-Path (Join-Path $outDir 'run_info.txt'))) {
    $c = Invoke-Ps 'Export-Stage3D50Assembly.ps1' @('-BatchId', 'd5asm_2', '-OutSubdir', 'd5_0_v2', '-Config', $Config)
    if ($c -ne 0) { Say "QUEUE STOPPED: export exit $c"; exit 3 }
    Say "d5asm_2 exported to $outDir"
}
$chk = Join-Path $outDir 'compare_d5_0_1_vs_d5_0_2.txt'
if (-not (Test-Path $chk)) {
    $stage3 = (Resolve-Path (Join-Path $PSScriptRoot '..\stage3')).Path
    $r = Invoke-MatlabSimple $cfg "addpath('$stage3'); stage3_d5_0_compare_runs('$(Join-Path $runs 'd5_0_1')', '$(Join-Path $runs 'd5_0_2')', '$chk')" (Join-Path $runs 'd5_0_2\compare_runs.log') (Join-Path $runs 'd5_0_2') 3600
    Say "d5_0_1 vs d5_0_2 check: exit $($r.ExitCode); $((Get-Content -LiteralPath $chk -ErrorAction SilentlyContinue | Select-Object -Last 1))"
    if ($r.ExitCode -ne 0) { Say 'QUEUE STOPPED: check failed to run'; exit 3 }
}
Say 'queue done: d5_0_2, d5asm_2, export and check finished; the chunked (b) test is not part of this queue (S3a-D5b-amend1)'
exit 0
