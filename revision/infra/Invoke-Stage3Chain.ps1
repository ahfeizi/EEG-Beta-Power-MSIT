<#
.SYNOPSIS
  S3a-INF-1-amend1 chain: acceptance sub-06 MSIT+ x 11 -> sub-06 rest x 3 (timing) -> Timeouts ->
  d5_0 job list -> D5-0 batch. Every step is skipped if already finished and resumed otherwise, under
  fixed BatchIds, so the same command resumes the chain after any crash (kernel crashes included).
  A step that does not succeed stops the chain (exit code of the failing step). Log: <EegOutRoot>\stage3_runs\chain.log
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Invoke-Stage3Chain.ps1
#>
param(
    [string]$MsitBatch = 'acc_msit_1',
    [string]$RestBatch = 'acc_rest_1',
    [string]$D50Batch = 'd5_0_1',
    [string]$Config = (Join-Path $PSScriptRoot 'runner_config.psd1')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$runs = Join-Path $cfg.EegOutRoot 'stage3_runs'
if (-not (Test-Path $runs)) { New-Item -ItemType Directory -Path $runs | Out-Null }
$log = Join-Path $runs 'chain.log'

function Say([string]$Msg) {
    $l = '{0} {1}' -f (Get-Date).ToString('s'), $Msg
    [System.IO.File]::AppendAllText($log, "$l`r`n")
    Write-Host $l
}
function Invoke-Runner([string[]]$RunnerArgs) {
    # child process: the runner ends with `exit`, which would otherwise end this chain.
    # Its stdout goes to the host, so the function returns the exit code alone (not stdout + code).
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Invoke-Stage3Batch.ps1'), '-Config', $Config) + $RunnerArgs
    & powershell.exe @a | Out-Host
    $LASTEXITCODE
}
function Get-Verdict([string]$Batch) {
    $f = Join-Path $runs "$Batch\acceptance.json"
    if (Test-Path $f) { (Read-Json $f).verdict } else { '' }
}
function Get-JobList([string]$Name, [string[]]$Only) {
    $f = Join-Path $runs $Name
    if (-not (Test-Path $f)) {
        if ($Only) { & (Join-Path $PSScriptRoot 'New-Stage3JobList.ps1') -Type d5_0 -Out $f -Only $Only -Config $Config }
        else { & (Join-Path $PSScriptRoot 'New-Stage3JobList.ps1') -Type d5_0 -Out $f -Config $Config }
        Say "job list written: $f ($(@(Read-JsonArray $f).Count) jobs)"
    }
    $f
}
function Invoke-AcceptanceStep([string]$Batch, [string]$JobListFile, [string[]]$Extra, [string]$Expected) {
    $v = Get-Verdict $Batch
    if (-not $v) {
        Say "start or resume $Batch"
        $c = Invoke-Runner (@('-Mode', 'Acceptance', '-BatchId', $Batch, '-JobList', $JobListFile) + $Extra)
        $v = Get-Verdict $Batch
        Say "$Batch ended: exit $c, verdict '$v'"
    } else { Say "$Batch already finished: verdict '$v'" }
    if ($v -ne $Expected) { Say "CHAIN STOPPED: $Batch verdict '$v' (needed '$Expected')"; exit 4 }
}

Say "chain start (runner pid $PID)"

# 1-2. acceptance sub-06 MSIT+ x 11 (PASS rule of S3a-INF-1-amend1), then sub-06 rest x 3 (timing only)
Invoke-AcceptanceStep $MsitBatch (Get-JobList 'jobs_acc_msit.json' @('sub-06_msit')) @('-Replicas', '11') 'PASS'
Invoke-AcceptanceStep $RestBatch (Get-JobList 'jobs_acc_rest.json' @('sub-06_rest')) @('-Replicas', '3', '-TimingOnly') 'TIMING_ONLY'

# 3. timeouts.json from these two runs
$tf = Join-Path $runs 'timeouts.json'
if (Test-Path $tf) {
    $src = @((Read-Json $tf).sources | ForEach-Object { $_.batch } | Sort-Object -Unique)
    if (($src -join ',') -ne ((@($MsitBatch, $RestBatch) | Sort-Object) -join ',')) { Say "CHAIN STOPPED: $tf exists but comes from $($src -join ', ')"; exit 3 }
    Say "timeouts.json already written from $($src -join ', ')"
} else {
    $c = Invoke-Runner @('-Mode', 'Timeouts', '-BatchId', 'timeouts', '-MsitBatch', $MsitBatch, '-RestBatch', $RestBatch)
    if ($c -ne 0) { Say "CHAIN STOPPED: Timeouts mode exit $c"; exit $c }
    Say 'timeouts.json written'
}

# 4-5. D5-0 job list (84 recordings) and the D5-0 batch
$jl = Get-JobList 'jobs_d5_0.json' @()
$bf = Join-Path $runs "$D50Batch\batch.json"
if ((Test-Path $bf) -and ((Read-Json $bf).status -ne 'RUNNING')) { Say "$D50Batch already ended: $((Read-Json $bf).status) $((Read-Json $bf).stopReason)"; exit 0 }
Say "start or resume $D50Batch"
$c = Invoke-Runner @('-Mode', 'Batch', '-BatchId', $D50Batch, '-JobList', $jl)
$b = Read-Json $bf
Say "$D50Batch ended: exit $c, status $($b.status) $($b.stopReason)"
exit $c
