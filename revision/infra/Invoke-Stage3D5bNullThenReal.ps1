<#
.SYNOPSIS
  S3a-D5b-rb1 chain: Invoke-Stage3D5bChunked.ps1 -Stage null, then, only if the C1 validity condition
  holds (null 95th percentile <= 2 dB in both null twins, column null_c1_valid of
  <OutRoot>\stage3\d5b\null_criterion.csv, re-checked here from null_q95_db), -Stage real -Approved.
  Otherwise it stops and writes the reason to the log and to <OutRoot>\stage3\d5b\chain_stop_reason.txt.
  Serial and resumable with the same command (each stage skips or resumes its finished steps).
  Log: <EegOutRoot>\stage3_runs\d5b_chain.log
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Invoke-Stage3D5bNullThenReal.ps1
#>
param([string]$Config)
$ErrorActionPreference = 'Stop'
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'runner_config.psd1' }
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$runs = Join-Path $cfg.EegOutRoot 'stage3_runs'
$log = Join-Path $runs 'd5b_chain.log'
$outD5b = Join-Path $cfg.OutRoot 'stage3\d5b'
function Say([string]$Msg) { $l = '{0} {1}' -f (Get-Date).ToString('s'), $Msg; [System.IO.File]::AppendAllText($log, "$l`r`n"); Write-Host $l }
function Invoke-Stage([string[]]$StageArgs) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Invoke-Stage3D5bChunked.ps1'), '-Config', $Config) + $StageArgs
    & powershell.exe @a | Out-Host
    $LASTEXITCODE
}
function Stop-Chain([string]$Reason, [int]$Code) {
    Say "STOPPED: $Reason"
    $f = Join-Path $outD5b 'chain_stop_reason.txt'
    [System.IO.File]::AppendAllText($f, ('{0} {1}' -f (Get-Date).ToString('s'), $Reason) + "`r`n")
    exit $Code
}

Say "d5b null-then-real chain (pid $PID)"
$c = Invoke-Stage @('-Stage', 'null')
if ($c -ne 0) { Stop-Chain "null stage exit $c (see d5b_chunked.log)" $c }
$nc = Join-Path $outD5b 'null_criterion.csv'
if (-not (Test-Path $nc)) { Stop-Chain "$nc missing after the null stage" 3 }
$rows = @(Import-Csv -LiteralPath $nc)
if ($rows.Count -ne 2) { Stop-Chain "$nc has $($rows.Count) rows (2 expected)" 3 }
$desc = ($rows | ForEach-Object { '{0} {1} q95 {2:N3} dB' -f $_.subject, $_.task, [double]$_.null_q95_db }) -join '; '
$flag = @($rows | ForEach-Object { $_.null_c1_valid -in @('1', 'true') })
$num = @($rows | ForEach-Object { [double]$_.null_q95_db -le 2 })
if (($flag -contains $false) -ne ($num -contains $false)) { Stop-Chain "null_c1_valid disagrees with null_q95_db ($desc)" 3 }
if ($num -contains $false) { Stop-Chain "C1 not valid: null 95th percentile > 2 dB in at least one twin ($desc); -Stage real not started (S3a-D5b-rb1)" 4 }
Say "C1 valid: null 95th percentile <= 2 dB in both twins ($desc); starting -Stage real -Approved"
$c = Invoke-Stage @('-Stage', 'real', '-Approved')
if ($c -ne 0) { Stop-Chain "real stage exit $c (see d5b_chunked.log)" $c }
Say 'chain done: null and real stages finished; criterion_real_vs_null.csv written'
exit 0
