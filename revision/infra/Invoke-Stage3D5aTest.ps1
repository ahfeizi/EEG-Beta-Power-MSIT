<#
.SYNOPSIS
  Residual test of D5 fallback (a) (S3a-D5a-test): job-type chain d5a (timing runs on sub-15 MSIT+ and
  sub-14 rest, the longest test recording per task; timeouts_d5a.json; A/B batch d5a_1), then the
  decision table stage3_d5a_criterion -> <OutRoot>\stage3\d5a\criterion_a.csv and
  criterion_a_decision.txt. Serial and resumable with the same command; log
  <EegOutRoot>\stage3_runs\d5a_test.log. No step after the decision table runs automatically.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Invoke-Stage3D5aTest.ps1
#>
param([string]$Config)
$ErrorActionPreference = 'Stop'
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'runner_config.psd1' }
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$runs = Join-Path $cfg.EegOutRoot 'stage3_runs'
$log = Join-Path $runs 'd5a_test.log'
$stage3 = (Resolve-Path (Join-Path $PSScriptRoot '..\stage3')).Path
$outDir = Join-Path $cfg.OutRoot 'stage3\d5a'
function Say([string]$Msg) { $l = '{0} {1}' -f (Get-Date).ToString('s'), $Msg; [System.IO.File]::AppendAllText($log, "$l`r`n"); Write-Host $l }
function Get-Canonical([string]$Batch) {
    $b = Read-Json (Join-Path $runs "$Batch\batch.json")
    if ($b.status -ne 'DONE') { throw "$Batch is $($b.status)" }
    (Read-Json (Join-Path $runs "$Batch\state\$(@($b.jobs)[0].id).json")).canonical.path
}

Say "d5a residual test (pid $PID)"
$a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Invoke-Stage3JobTypeChain.ps1'),
       '-Type', 'd5a', '-Name', 'd5a', '-TimingJobs', 'sub-15_msit,sub-14_rest', '-BatchId', 'd5a_1', '-Config', $Config)
& powershell.exe @a | Out-Host
$c = $LASTEXITCODE
$bf = Join-Path $runs 'd5a_1\batch.json'
if ($c -ne 0 -or -not (Test-Path $bf) -or (Read-Json $bf).status -ne 'DONE') { Say "STOPPED: chain d5a exit $c (see chain_d5a.log)"; exit 3 }
$out = Join-Path $outDir 'criterion_a.csv'
if (Test-Path $out) { Say "$out exists"; exit 0 }
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$cmd = "addpath('$stage3'); stage3_d5a_criterion('$(Join-Path $runs 'd5a_1')', '$(Get-Canonical 'd5bm_1')', '$out')"
$r = Invoke-MatlabSimple $cfg $cmd (Join-Path $runs 'd5a_criterion.log') $runs 900
if ($r.ExitCode -ne 0) { Say "STOPPED: criterion exit $($r.ExitCode)"; exit 3 }
$dec = Get-Content -LiteralPath (Join-Path $outDir 'criterion_a_decision.txt') | Where-Object { $_ -like 'DECISION*' }
Say "decision table written: $out; $dec"
exit 0
