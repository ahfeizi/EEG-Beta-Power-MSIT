<#
.SYNOPSIS
  Writes the CSVs and run_info.txt of a finished assembly batch from its verified canonical output
  into <OutRoot>\stage3\<OutSubdir>\ (never overwrites). Assembly job function -> export function:
    stage3_d5_0_assemble -> stage3_d5_0_export (S3a-D5-0-asm)
    stage3_d4e4_assemble -> stage3_d4e4_export (S3a-D4e-4-asm)
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Export-Stage3Assembly.ps1 -BatchId d4e4asm_1 -OutSubdir d4e4_test
#>
param(
    [Parameter(Mandatory = $true)][string]$BatchId,
    [Parameter(Mandatory = $true)][string]$OutSubdir,
    [string]$Config
)
$ErrorActionPreference = 'Stop'
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'runner_config.psd1' }
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$exportOf = @{ stage3_d5_0_assemble = 'stage3_d5_0_export'; stage3_d4e4_assemble = 'stage3_d4e4_export' }
$bd = Join-Path (Join-Path $cfg.EegOutRoot 'stage3_runs') $BatchId
$b = Read-Json (Join-Path $bd 'batch.json')
if ($b.mode -ne 'Batch' -or $b.status -ne 'DONE') { throw "$BatchId is not a finished Batch-mode run ($($b.mode) $($b.status))" }
$jobs = @($b.jobs)
if ($jobs.Count -ne 1 -or -not $exportOf.ContainsKey($jobs[0].func)) { throw "$BatchId is not an assembly batch with a known export" }
$st = Read-Json (Join-Path $bd "state\$($jobs[0].id).json")
if ($st.status -ne 'verified') { throw "$BatchId $($jobs[0].id): status $($st.status) (export needs verified)" }
$outDir = Join-Path (Join-Path $cfg.OutRoot 'stage3') $OutSubdir
$stage3 = (Resolve-Path (Join-Path $PSScriptRoot '..\stage3')).Path
$log = Join-Path $bd 'export.log'
$cmd = "addpath('$stage3'); $($exportOf[$jobs[0].func])('$($st.canonical.path)', '$($st.canonical.sha256)', '$outDir', '$BatchId')"
$r = Invoke-MatlabSimple $cfg $cmd $log $bd 900
Get-Content -LiteralPath $log | Select-Object -Last 3 | Out-Host
if ($r.ExitCode -ne 0) { throw "export failed: exit $($r.ExitCode) (log $log)" }
