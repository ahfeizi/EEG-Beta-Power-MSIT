<#
.SYNOPSIS
  S3a-INF-1-amend2 chain for a job type other than D5-0: timing run(s) (Acceptance -TimingOnly,
  3 replicas, one per -TimingJobs id) -> JobTimeouts (timeouts_<Name>.json) -> Batch -BatchId.
  Every step is skipped if already finished and resumed otherwise, under fixed BatchIds, so the
  same command resumes the chain after any crash. A step that does not succeed stops the chain.
  Log: <EegOutRoot>\stage3_runs\chain_<Name>.log
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Invoke-Stage3JobTypeChain.ps1 -Type d4e4 -Name d4e4 -TimingJobs sub-06_msit,sub-06_rest -BatchId d4e4_1
  powershell -NoProfile -ExecutionPolicy Bypass -File Invoke-Stage3JobTypeChain.ps1 -Type d5_0_asm -Name d5asm -TimingJobs d5_0_asm_d5_0_1 -BatchId d5asm_1
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('d4e4', 'd5_0_asm', 'd4e4_asm', 'd5b', 'd5bu', 'd5bmerge')][string]$Type,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$TimingJobs,      # comma-separated job ids of the full list
    [Parameter(Mandatory = $true)][string]$BatchId,
    [string]$SourceBatch,
    [int]$TimingTimeoutS = 0,                              # S3a-INF-1-amend3: per-replica timeout of the timing runs (0 = AcceptanceTimeoutS)                                  # assembly types: the batch to assemble (default of New-Stage3JobList)
    [string]$Config,
    [switch]$SkipPrechecksForTest                          # synthetic tests only (the runner refuses it without TestMode)
)
$ErrorActionPreference = 'Stop'
# PS 5.1 leaves $PSScriptRoot empty in param defaults of an advanced script run with -File
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'runner_config.psd1' }
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$runs = Join-Path $cfg.EegOutRoot 'stage3_runs'
if (-not (Test-Path $runs)) { New-Item -ItemType Directory -Path $runs | Out-Null }
$log = Join-Path $runs "chain_$Name.log"

function Say([string]$Msg) {
    $l = '{0} {1}' -f (Get-Date).ToString('s'), $Msg
    [System.IO.File]::AppendAllText($log, "$l`r`n")
    Write-Host $l
}
function Invoke-Runner([string[]]$RunnerArgs) {
    # child process (the runner ends with `exit`); its stdout goes to the host, so only the exit code is returned
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Invoke-Stage3Batch.ps1'), '-Config', $Config) + $RunnerArgs
    & powershell.exe @a | Out-Host
    $LASTEXITCODE
}

Say "chain $Name start (pid $PID): type $Type, timing $TimingJobs, batch $BatchId"

# 1. full job list
$jl = Join-Path $runs "jobs_$Name.json"
if (-not (Test-Path $jl)) {
    $jla = @{ Type = $Type; Out = $jl; Config = $Config }
    if ($SourceBatch) { $jla.SourceBatch = $SourceBatch }
    & (Join-Path $PSScriptRoot 'New-Stage3JobList.ps1') @jla | Out-Host
    Say "job list written: $jl ($((Read-JsonArray $jl).Count) jobs)"
}
$all = Read-JsonArray $jl                                   # already an array (do not wrap in @())

# 2. timing runs, one per timing job (S3a-INF-1-amend2)
$tb = @()
foreach ($id in @($TimingJobs -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    $job = @($all | Where-Object { $_.id -eq $id })
    if ($job.Count -ne 1) { Say "CHAIN STOPPED: timing job $id is not in $jl"; exit 3 }
    $b = "${Name}_t_$id"; $tb += $b
    $f = Join-Path $runs "jobs_$b.json"
    if (-not (Test-Path $f)) { Write-TextAtomic $f (ConvertTo-Json -InputObject @($job) -Depth 10) }
    $af = Join-Path $runs "$b\acceptance.json"
    if (-not (Test-Path $af)) {
        Say "start or resume timing run $b"
        $ta = @('-Mode', 'Acceptance', '-BatchId', $b, '-JobList', $f, '-Replicas', '3', '-TimingOnly')
        if ($TimingTimeoutS -gt 0) { $ta += @('-ReplicaTimeoutS', "$TimingTimeoutS") }
        $c = Invoke-Runner $ta
        Say "$b ended: exit $c"
    }
    $v = if (Test-Path $af) { (Read-Json $af).verdict } else { '' }
    if ($v -ne 'TIMING_ONLY') { Say "CHAIN STOPPED: $b verdict '$v'"; exit 4 }
    if ([int](Read-Json $af).replicasOk -lt 1) { Say "CHAIN STOPPED: $b has no successful replica (see its summary)"; exit 4 }
    Say "$b finished: median $((Read-Json $af).medianWallSeconds) s"
}

# 3. job-type timeouts
$tf = Join-Path $runs "timeouts_$Name.json"
if (Test-Path $tf) {
    $src = @((Read-Json $tf).sources | ForEach-Object { $_.batch } | Sort-Object -Unique)
    if (($src -join ',') -ne (($tb | Sort-Object) -join ',')) { Say "CHAIN STOPPED: $tf exists but comes from $($src -join ', ')"; exit 3 }
    Say "timeouts_$Name.json already written"
} else {
    $c = Invoke-Runner @('-Mode', 'JobTimeouts', '-BatchId', $Name, '-TimingBatches', ($tb -join ','))
    if ($c -ne 0) { Say "CHAIN STOPPED: JobTimeouts mode exit $c"; exit $c }
    Say "timeouts_$Name.json written: $(((Read-Json $tf).timeoutS | ConvertTo-Json -Compress))"
}

# 4. the batch
$bf = Join-Path $runs "$BatchId\batch.json"
if ((Test-Path $bf) -and ((Read-Json $bf).status -ne 'RUNNING')) { Say "$BatchId already ended: $((Read-Json $bf).status) $((Read-Json $bf).stopReason)"; exit 0 }
Say "start or resume $BatchId"
$ba = @('-Mode', 'Batch', '-BatchId', $BatchId, '-JobList', $jl, '-JobTimeouts', $tf)
if ($SkipPrechecksForTest) { $ba += '-SkipPrechecksForTest' }
$c = Invoke-Runner $ba
$b = Read-Json $bf
Say "$BatchId ended: exit $c, status $($b.status) $($b.stopReason)"
exit $c
