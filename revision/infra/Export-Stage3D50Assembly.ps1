<#
.SYNOPSIS
  S3a-D5-0-asm export: writes line_noise_by_channel.csv, line_noise_by_recording.csv,
  line_noise_rules_by_recording.csv and run_info.txt into <OutRoot>\stage3\d5_0\ from the verified
  canonical output of a finished D5-0 assembly batch (stage3_d5_0_export.m; never overwrites).
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Export-Stage3D50Assembly.ps1 -BatchId d5asm_1
#>
param(
    [Parameter(Mandatory = $true)][string]$BatchId,
    [string]$Config
)
$ErrorActionPreference = 'Stop'
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'runner_config.psd1' }
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$bd = Join-Path (Join-Path $cfg.EegOutRoot 'stage3_runs') $BatchId
$b = Read-Json (Join-Path $bd 'batch.json')
if ($b.mode -ne 'Batch' -or $b.status -ne 'DONE') { throw "$BatchId is not a finished Batch-mode run ($($b.mode) $($b.status))" }
$jobs = @($b.jobs)
if ($jobs.Count -ne 1 -or $jobs[0].func -ne 'stage3_d5_0_assemble') { throw "$BatchId is not a D5-0 assembly batch" }
$st = Read-Json (Join-Path $bd "state\$($jobs[0].id).json")
if ($st.status -ne 'verified') { throw "$BatchId $($jobs[0].id): status $($st.status) (export needs verified)" }
$outDir = Join-Path $cfg.OutRoot 'stage3\d5_0'
$stage3 = (Resolve-Path (Join-Path $PSScriptRoot '..\stage3')).Path
$log = Join-Path $bd 'export.log'
$cmd = "addpath('$stage3'); stage3_d5_0_export('$($st.canonical.path)', '$($st.canonical.sha256)', '$outDir', '$BatchId')"
$r = Invoke-MatlabSimple $cfg $cmd $log $bd 900
Get-Content -LiteralPath $log | Out-Host
if ($r.ExitCode -ne 0) { throw "export failed: exit $($r.ExitCode) (log $log)" }
