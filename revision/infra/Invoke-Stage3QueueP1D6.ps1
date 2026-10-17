<#
.SYNOPSIS
  Serial queue (jobs never run in parallel, S3a-INF-1 sec. 1), resumable with the same command; log
  <EegOutRoot>\stage3_runs\queue_p1d6.log. Steps, each resumed or skipped by its own driver:
    1. part 1 batch s3p1_2 (S3a-P1-amend2): sub-13 and sub-41 (rest, MSIT+), sub-20 rest, sub-23 rest,
       with the s3p1 timeouts, then export (manifest_s3p1_2.tsv);
    2. D6 (Invoke-Stage3D6.ps1): chain d6 -> batch d6_1 -> d6_summary.csv. Its job list is built when the
       chain first starts, from every export manifest, so the subjects completed in step 1 are included.
  Step 2 runs even if step 1 stops (the D6 job list then contains whoever has both part-1 files).
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Invoke-Stage3QueueP1D6.ps1
#>
param([string]$Config)
$ErrorActionPreference = 'Stop'
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'runner_config.psd1' }
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$log = Join-Path (Join-Path $cfg.EegOutRoot 'stage3_runs') 'queue_p1d6.log'
function Say([string]$Msg) { $l = '{0} {1}' -f (Get-Date).ToString('s'), $Msg; [System.IO.File]::AppendAllText($log, "$l`r`n"); Write-Host $l }
function Invoke-Ps([string]$Script, [string[]]$ScriptArgs) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot $Script), '-Config', $Config) + $ScriptArgs
    & powershell.exe @a | Out-Host
    $LASTEXITCODE
}

Say "queue start (pid $PID)"
$c = Invoke-Ps 'Invoke-Stage3Part1.ps1' @('-BatchId', 's3p1_2', '-Only', 'sub-13_rest,sub-13_msit,sub-41_rest,sub-41_msit,sub-20_rest,sub-23_rest')
Say "part 1 batch s3p1_2: exit $c (see s3p1.log)"
$c = Invoke-Ps 'Invoke-Stage3D6.ps1' @()
Say "D6: exit $c (see d6.log)"
Say 'queue done'
exit 0
