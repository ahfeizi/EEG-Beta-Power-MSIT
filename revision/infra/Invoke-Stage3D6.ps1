<#
.SYNOPSIS
  D6 bad channels (S3a-D6, S3a-D6-impl). Serial and resumable with the same command; log
  <EegOutRoot>\stage3_runs\d6.log.
    1. chain d6 (S3a-INF-1-amend2): timing run on sub-06 (3 replicas), timeouts_d6.json, A/B batch d6_1
       (every subject whose rest and MSIT+ part-1 files are both exported; sub-42 excluded);
    2. stage3_d6_summary -> <OutRoot>\stage3\d6\d6_summary.csv.
  Refuses to start while the centring of the individual positions is undecided (S3a-D2-close): the job
  function errors then, so the timing run fails and the chain stops before the batch.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Invoke-Stage3D6.ps1
#>
param([string]$Config)
$ErrorActionPreference = 'Stop'
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'runner_config.psd1' }
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$runs = Join-Path $cfg.EegOutRoot 'stage3_runs'
$log = Join-Path $runs 'd6.log'
$stage3 = (Resolve-Path (Join-Path $PSScriptRoot '..\stage3')).Path
function Say([string]$Msg) { $l = '{0} {1}' -f (Get-Date).ToString('s'), $Msg; [System.IO.File]::AppendAllText($log, "$l`r`n"); Write-Host $l }

Say "D6 (pid $PID)"
$a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Invoke-Stage3JobTypeChain.ps1'),
       '-Type', 'd6', '-Name', 'd6', '-TimingJobs', 'sub-06', '-BatchId', 'd6_1', '-Config', $Config)
& powershell.exe @a | Out-Host
$c = $LASTEXITCODE
$bf = Join-Path $runs 'd6_1\batch.json'
if (-not (Test-Path $bf) -or (Read-Json $bf).status -eq 'RUNNING') { Say "STOPPED: chain d6 exit $c (see chain_d6.log)"; exit 3 }
Say "d6_1 ended: status $((Read-Json $bf).status) $((Read-Json $bf).stopReason)"
$od = Join-Path $cfg.OutRoot 'stage3\d6'
$out = Join-Path $od 'd6_summary.csv'
if (Test-Path $out) { Say "$out exists"; exit 0 }
if (-not (Test-Path $od)) { New-Item -ItemType Directory -Path $od | Out-Null }
$r = Invoke-MatlabSimple $cfg "addpath('$stage3'); stage3_d6_summary('$(Join-Path $runs 'd6_1')', '$out')" (Join-Path $runs 'd6_summary.log') $runs 900
if ($r.ExitCode -ne 0) { Say "STOPPED: summary exit $($r.ExitCode)"; exit 3 }
Say "summary written: $out"
exit 0
