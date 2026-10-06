<#
.SYNOPSIS
  Synthetic tests of the S3a-INF-1 runner (no EEG data). Uses a TestMode configuration with
  shortened times, a fake HWiNFO log, and stage3_testjob / stage3_burnin as job functions.
  Writes test_report.txt in -WorkDir.
#>
param([Parameter(Mandatory = $true)][string]$WorkDir, [string[]]$Only)
$ErrorActionPreference = 'Stop'
$infra = Split-Path $PSScriptRoot
Import-Module (Join-Path $infra 'Stage3Runner.psm1') -Force
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir | Out-Null }
$eeg = Join-Path $WorkDir 'eegout'; $outR = Join-Path $WorkDir 'outroot'
foreach ($d in @($eeg, $outR)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }
$csv = Join-Path $WorkDir 'hwinfo.csv'; $ctl = Join-Path $WorkDir 'hwinfo_control.json'
$report = Join-Path $WorkDir 'test_report.txt'
$cfgFile = Join-Path $WorkDir 'test_config.psd1'
$real = Import-PowerShellDataFile (Join-Path $infra 'runner_config.psd1')
@"
# TEST configuration (synthetic tests only). Thermal and timing values are SHORTENED for speed;
# the real values are in revision\infra\runner_config.psd1.
@{
    MatlabExe = '$($real.MatlabExe)'
    EegOutRoot = '$eeg'
    OutRoot = '$outR'
    RawRoot = '$(Join-Path $WorkDir 'raw')'
    VerifiedManifest = '$(Join-Path $WorkDir 'manifest.tsv')'
    BlockTable = '$(Join-Path $WorkDir 'blocks.csv')'
    HwinfoCsv = '$csv'
    ExtraMatlabPaths = @('$PSScriptRoot')
    Threads = 2; MklCbwr = 'AUTO'; SeedGlobal = 1
    InternalSeeds = @{}; StepSeeds = @{}
    CooldownS = 1; GateC = 70; GateMaxWaitS = 15; AbortC = 95; AbortWindowS = 6; AbortMinCoverS = 5; StaleS = 8; PollS = 1
    HwinfoTempNameTemplate = 'CPU Package [{0}C]'; HwinfoTempNameCount = 2
    ProcessorStateMaxPct = 85; HardwareChangeNotBefore = '2026-10-06T19:40:46'
    MaxRetries = 2; AcceptanceTimeoutS = 900; CompareTimeoutS = 600; MaxMismatchRecordings = 2
    DiskMinFreeGB_EegOut = 1; DiskOutputFactor = 3; DiskMinFreeGB_OutRoot = 1
    TestMode = `$true
    TestTimeoutS = @{ test = 300 }
}
"@ | Set-Content -LiteralPath $cfgFile -Encoding ASCII

$results = New-Object System.Collections.Generic.List[string]
function Check([string]$Test, [bool]$Cond, [string]$What) {
    $line = ('{0,-4} {1,-22} {2}' -f $(if ($Cond) { 'PASS' } else { 'FAIL' }), $Test, $What)
    $results.Add($line); Write-Host $line
}
function Set-Ctl([hashtable]$H) {
    $cur = @{ write = $true; temp = 60; extraField = $false; header = 'normal'; restart = 0; quit = $false }
    if (Test-Path $ctl) { $o = Get-Content -LiteralPath $ctl -Raw | ConvertFrom-Json; foreach ($p in $o.PSObject.Properties) { $cur[$p.Name] = $p.Value } }
    foreach ($k in $H.Keys) { $cur[$k] = $H[$k] }
    Write-TextAtomic $ctl ($cur | ConvertTo-Json)
}
function Join-Args([string[]]$A) { ($A | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ' }   # PS 5.1 does not quote
function Start-Writer {
    Set-Ctl @{ write = $true; temp = 60; extraField = $false; header = 'normal'; quit = $false }
    $script:writer = Start-Process powershell -ArgumentList (Join-Args @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Start-FakeHwinfo.ps1'), '-Csv', $csv, '-Control', $ctl)) -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 3
}
function Stop-Writer { Set-Ctl @{ quit = $true }; Start-Sleep -Seconds 2; if ($script:writer -and -not $script:writer.HasExited) { Stop-Process -Id $script:writer.Id -Force } }
function Write-Jobs([string]$Name, $Jobs) { $f = Join-Path $WorkDir "$Name.json"; Write-TextAtomic $f (ConvertTo-Json -InputObject @($Jobs) -Depth 10); $f }
function Start-Runner([string[]]$RunnerArgs, [string]$Tag) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $infra 'Invoke-Stage3Batch.ps1'), '-Config', $cfgFile) + $RunnerArgs
    $p = Start-Process powershell -ArgumentList (Join-Args $a) -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $WorkDir "runner_$Tag.out") -RedirectStandardError (Join-Path $WorkDir "runner_$Tag.err")
    $null = $p.Handle                                      # PS 5.1: keeps ExitCode available after exit
    $p
}
function Invoke-Runner([string[]]$RunnerArgs, [string]$Tag) { $p = Start-Runner $RunnerArgs $Tag; $p.WaitForExit(); $p.ExitCode }
function Get-St([string]$Batch, [string]$Id) { Read-Json (Join-Path $eeg "stage3_runs\$Batch\state\$Id.json") }
function Get-Bt([string]$Batch) { Read-Json (Join-Path $eeg "stage3_runs\$Batch\batch.json") }
function Get-Jn([string]$Batch) { @(Read-Journal (Join-Path $eeg "stage3_runs\$Batch")) }
function Wait-For([scriptblock]$Cond, [int]$TimeoutS, [string]$What) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $TimeoutS) { try { if (& $Cond) { return $true } } catch {}; Start-Sleep -Milliseconds 500 }
    Write-Host "timeout waiting for: $What"; $false
}
function Run-Test([string]$Name) { (-not $Only) -or ($Only -contains $Name) }
function Job([string]$Id, $Params) { [ordered]@{ id = $Id; func = 'stage3_testjob'; params = $Params; recType = 'test'; compareKind = 'all' } }

Start-Writer
$sk = '-SkipPrechecksForTest'
try {
# ---------------------------------------------------------------- T1 injected worker error
if (Run-Test 'T1') {
    $jl = Write-Jobs 't1' @((Job 'err' ([ordered]@{ mode = 'error' })))
    $code = Invoke-Runner @('-Mode', 'Batch', '-BatchId', 't1', '-JobList', $jl, $sk) 't1'
    $st = Get-St 't1' 'err'
    Check 'T1 worker error' ($code -eq 0 -and $st.status -eq 'failed' -and $st.attempts.A -eq 3 -and @($st.history | Where-Object { $_.outcome -eq 'crash' }).Count -eq 3) "status $($st.status); attempts A $($st.attempts.A); outcomes $((@($st.history) | ForEach-Object outcome) -join ',')"
}
# ---------------------------------------------------------------- T2 process killed mid-save
if (Run-Test 'T2') {
    $jl = Write-Jobs 't2' @((Job 'killsave' ([ordered]@{ mode = 'slow_save'; sleepS = 60; slowOnAttempt = 1 })))
    $p = Start-Runner @('-Mode', 'Batch', '-BatchId', 't2', '-JobList', $jl, $sk) 't2'
    $d1 = Join-Path $eeg 'stage3_runs\t2\jobs\killsave\A\attempt1'
    $okWait = Wait-For { (Test-Path (Join-Path $d1 'out.partial.mat')) -and (Select-String -LiteralPath (Join-Path $d1 'job.log') -SimpleMatch 'PARTIAL_SAVED' -Quiet) } 240 'partial file'
    $pidKilled = (Get-St 't2' 'killsave').running.pid
    & taskkill /PID $pidKilled /T /F | Out-Null
    $p.WaitForExit()
    $st = Get-St 't2' 'killsave'
    $h1 = @($st.history | Where-Object { $_.replica -eq 'A' -and $_.attempt -eq 1 })[0]
    $left = @(Get-ChildItem -LiteralPath $d1 -Filter 'out*.mat' -ErrorAction SilentlyContinue).Count
    Check 'T2 killed mid-save' ($okWait -and $st.status -eq 'verified' -and $h1.outcome -eq 'crash' -and $left -eq 0 -and $st.attempts.A -eq 2) "partial seen $okWait; killed pid $pidKilled; attempt 1 $($h1.outcome); files left in attempt1 $left; attempts A $($st.attempts.A); status $($st.status)"
}
# ---------------------------------------------------------------- T3 runner killed mid-batch, resumed
if (Run-Test 'T3') {
    $jl = Write-Jobs 't3' @((Job 'r1' ([ordered]@{ mode = 'ok'; sleepS = 40 })), (Job 'r2' ([ordered]@{ mode = 'ok'; sleepS = 5 })))
    $p = Start-Runner @('-Mode', 'Batch', '-BatchId', 't3', '-JobList', $jl, $sk) 't3a'
    $okWait = Wait-For { $s = Get-St 't3' 'r1'; $s.status -eq 'running' -and $s.running.pid } 240 'r1 running'
    Start-Sleep -Seconds 5
    $orphan = [int](Get-St 't3' 'r1').running.pid
    Stop-Process -Id $p.Id -Force
    Start-Sleep -Seconds 2
    $orphanAlive = Test-MatlabPid $orphan
    $code = Invoke-Runner @('-Mode', 'Batch', '-BatchId', 't3', '-JobList', $jl, $sk) 't3b'
    $j = Get-Jn 't3'
    $s1 = Get-St 't3' 'r1'; $s2 = Get-St 't3' 'r2'
    Check 'T3 runner killed+resume' ($okWait -and $orphanAlive -and -not (Test-MatlabPid $orphan) -and @($j | Where-Object event -eq 'orphan_killed').Count -eq 1 -and @($s1.history | Where-Object outcome -eq 'interrupted').Count -eq 1 -and $s1.status -eq 'verified' -and $s2.status -eq 'verified' -and $code -eq 0) "orphan $orphan alive after runner kill: $orphanAlive; killed on resume: $(@($j | Where-Object event -eq 'orphan_killed').Count); r1 $($s1.status) (attempts A $($s1.attempts.A)); r2 $($s2.status)"
}
# ---------------------------------------------------------------- T4a stale HWiNFO log
if (Run-Test 'T4a') {
    $jl = Write-Jobs 't4a' @((Job 's1' ([ordered]@{ mode = 'ok' })))
    Set-Ctl @{ write = $false }
    Start-Sleep -Seconds 10
    $p = Start-Runner @('-Mode', 'Batch', '-BatchId', 't4a', '-JobList', $jl, $sk) 't4a'
    $okPause = Wait-For { @(Get-Jn 't4a' | Where-Object event -eq 'stale_pause').Count -ge 1 } 120 'stale_pause'
    Start-Sleep -Seconds 10
    $startedWhileStale = @(Get-Jn 't4a' | Where-Object event -eq 'job_start').Count
    Set-Ctl @{ write = $true }
    $p.WaitForExit()
    $j = Get-Jn 't4a'
    $iRes = [array]::IndexOf(@($j.event), 'stale_resolved'); $iStart = [array]::IndexOf(@($j.event), 'job_start')
    Check 'T4a stale log' ($okPause -and $startedWhileStale -eq 0 -and $iRes -ge 0 -and $iStart -gt $iRes -and (Get-St 't4a' 's1').status -eq 'verified') "stale_pause seen $okPause; jobs started while stale $startedWhileStale; job_start after stale_resolved $($iStart -gt $iRes); status $((Get-St 't4a' 's1').status)"
}
# ---------------------------------------------------------------- T4b hot HWiNFO log
if (Run-Test 'T4b') {
    $jl = Write-Jobs 't4b' @((Job 'h1' ([ordered]@{ mode = 'ok'; sleepS = 40 })))
    $p = Start-Runner @('-Mode', 'Batch', '-BatchId', 't4b', '-JobList', $jl, $sk) 't4b'
    $okRun = Wait-For { (Get-St 't4b' 'h1').status -eq 'running' } 240 'h1 running'
    Start-Sleep -Seconds 15
    Set-Ctl @{ temp = 97 }
    $okAbort = Wait-For { @(Get-Jn 't4b' | Where-Object { $_.event -eq 'job_end' -and $_.detail -like 'thermal_abort*' }).Count -ge 1 } 120 'thermal_abort'
    Set-Ctl @{ temp = 60 }
    $p.WaitForExit()
    $st = Get-St 't4b' 'h1'
    $a1 = @($st.history | Where-Object { $_.replica -eq 'A' -and $_.attempt -eq 1 })[0]
    Check 'T4b hot log' ($okAbort -and $a1.outcome -eq 'thermal_abort' -and $st.status -eq 'verified') "attempt A1 $($a1.outcome) (max $($a1.maxTempC) C); final $($st.status); attempts A $($st.attempts.A)"
}
# ---------------------------------------------------------------- T4c HWiNFO header changed
if (Run-Test 'T4c') {
    Set-Ctl @{ restart = 1; temp = 60 }; Start-Sleep -Seconds 3
    $jl = Write-Jobs 't4c' @((Job 'c1' ([ordered]@{ mode = 'ok'; sleepS = 20 })), (Job 'c2' ([ordered]@{ mode = 'ok' })))
    $p = Start-Runner @('-Mode', 'Batch', '-BatchId', 't4c', '-JobList', $jl, $sk) 't4c'
    $okRun = Wait-For { (Get-St 't4c' 'c1').status -eq 'running' } 240 'c1 running'
    Set-Ctl @{ header = 'changed' }
    $p.WaitForExit()
    $b = Get-Bt 't4c'
    Check 'T4c header changed' ($b.status -eq 'STOPPED_HWINFO_HEADER' -and -not (Test-Path (Join-Path $eeg 'stage3_runs\t4c\state\c2.json'))) "batch $($b.status): $($b.stopReason); c2 not started: $(-not (Test-Path (Join-Path $eeg 'stage3_runs\t4c\state\c2.json')))"
    Set-Ctl @{ restart = 2; header = 'normal' }; Start-Sleep -Seconds 3
}
# ---------------------------------------------------------------- T4d extra field mid-log
if (Run-Test 'T4d') {
    $jl = Write-Jobs 't4d' @((Job 'e1' ([ordered]@{ mode = 'ok' })))
    Set-Ctl @{ extraField = $true }                                     # header unchanged, rows longer
    Start-Sleep -Seconds 3
    $p = Start-Runner @('-Mode', 'Batch', '-BatchId', 't4d', '-JobList', $jl, $sk) 't4d'
    $okPause = Wait-For { @(Get-Jn 't4d' | Where-Object { $_.event -eq 'stale_pause' -and $_.detail -like 'field count*' }).Count -ge 1 } 120 'stale_pause (field count)'
    Start-Sleep -Seconds 5
    $startedWhile = @(Get-Jn 't4d' | Where-Object event -eq 'job_start').Count
    Set-Ctl @{ extraField = $false; restart = 3 }                      # HWiNFO logging restarted
    $p.WaitForExit()
    $st = Get-St 't4d' 'e1'
    Check 'T4d extra field' ($okPause -and $startedWhile -eq 0 -and $st.status -eq 'verified') "stale_pause on field count $okPause; jobs started meanwhile $startedWhile; after log restart: $($st.status)"
}
# ---------------------------------------------------------------- T5 A != B -> C, and the stop rule
if (Run-Test 'T5') {
    $jl = Write-Jobs 't5' @((Job 'd1' ([ordered]@{ mode = 'replica_diff'; diffReplicas = @('B') })), (Job 'd2' ([ordered]@{ mode = 'replica_diff'; diffReplicas = @('B') })))
    $code = Invoke-Runner @('-Mode', 'Batch', '-BatchId', 't5', '-JobList', $jl, $sk) 't5'
    $s1 = Get-St 't5' 'd1'; $b = Get-Bt 't5'
    $ab = @($s1.compares | Where-Object label -eq 'AB')[0]
    $nAbProc = @(Get-Jn 't5' | Where-Object { $_.event -eq 'compare' -and $_.job -eq 'd1' -and $_.replica -eq 'AB' }).Count
    Check 'T5 A!=B -> C' ($s1.status -eq 'flagged' -and $s1.canonical.replica -eq 'A' -and -not $ab.equal -and $nAbProc -eq 2 -and -not (Test-Path (Join-Path $eeg 'stage3_runs\t5\jobs\d1\B\attempt1\out.mat'))) "d1 $($s1.status), canonical $($s1.canonical.replica) ($($s1.canonical.pair)); AB compare processes $nAbProc; B deleted $(-not (Test-Path (Join-Path $eeg 'stage3_runs\t5\jobs\d1\B\attempt1\out.mat')))"
    Check 'T5 stop at 2 mismatches' ($b.status -eq 'STOPPED_MISMATCH' -and $b.mismatchCount -eq 2) "batch $($b.status) ($($b.stopReason)); mismatchCount $($b.mismatchCount)"
}
# ---------------------------------------------------------------- T6 burn-in, two processes
if (Run-Test 'T6') {
    $c1 = Invoke-Runner @('-Mode', 'BurnIn', '-BatchId', 't6cal', '-Calibrate', '-Iterations', '2') 't6cal'
    $cal = Read-Json (Join-Path $eeg 'stage3_runs\t6cal\acceptance.json')
    $c2 = Invoke-Runner @('-Mode', 'BurnIn', '-BatchId', 't6', '-CalibrationBatch', 't6cal', '-Iterations', '3') 't6'
    $acc = Read-Json (Join-Path $eeg 'stage3_runs\t6\acceptance.json')
    $b = $acc.burnin
    Check 'T6 burn-in calibration' ($cal.verdict -eq 'CALIBRATED' -and $cal.meanIterationSeconds -gt 0) ("mean D5 {0:N2} s, GEMM {1:N2} s, iteration {2:N2} s, suggested 60-min count {3}" -f $cal.meanD5Seconds, $cal.meanGemmSeconds, $cal.meanIterationSeconds, $cal.suggestedIterationsFor60Min)
    Check 'T6 burn-in A=B bitwise' ($acc.verdict -eq 'PASS' -and $b.finalEqual -and [int]$b.iterationsDiffering.d5 -eq 0 -and [int]$b.iterationsDiffering.gemm -eq 0 -and [int]$b.withinMismatch.A.d5 + [int]$b.withinMismatch.A.gemm + [int]$b.withinMismatch.B.d5 + [int]$b.withinMismatch.B.gemm -eq 0) "verdict $($acc.verdict); within A D5 $($b.withinMismatch.A.d5) GEMM $($b.withinMismatch.A.gemm); within B D5 $($b.withinMismatch.B.d5) GEMM $($b.withinMismatch.B.gemm); iterations differing D5 $($b.iterationsDiffering.d5) GEMM $($b.iterationsDiffering.gemm); final equal $($b.finalEqual) $(($acc.failReasons) -join '; ')"
}
# ---------------------------------------------------------------- T7 acceptance mode, Timeouts guard, pre-checks
if (Run-Test 'T7') {
    $jl = Write-Jobs 't7' @((Job 'acc' ([ordered]@{ mode = 'ok' })))
    [void](Invoke-Runner @('-Mode', 'Acceptance', '-BatchId', 't7', '-JobList', $jl, '-Replicas', '3') 't7')
    $acc = Read-Json (Join-Path $eeg 'stage3_runs\t7\acceptance.json')
    Check 'T7 acceptance x3' ($acc.verdict -eq 'PASS' -and $acc.replicasOk -eq 3 -and @($acc.compares).Count -eq 2) "verdict $($acc.verdict); replicas ok $($acc.replicasOk); compares vs R01 $(@($acc.compares | ForEach-Object { $_.equal }) -join ','); median wall $($acc.medianWallSeconds) s"
    $code = Invoke-Runner @('-Mode', 'Timeouts', '-BatchId', 'x', '-BurnInBatch', 't6', '-MsitBatch', 't7', '-RestBatch', 't7') 't7t'
    Check 'T7 timeouts guard' ($code -eq 3 -and -not (Test-Path (Join-Path $eeg 'stage3_runs\timeouts.json'))) "exit $code (3 = refused); $(Get-Content (Join-Path $WorkDir 'runner_t7t.out') -Raw)"
    $code = Invoke-Runner @('-Mode', 'Batch', '-BatchId', 't7b', '-JobList', $jl) 't7b'
    $b = Get-Bt 't7b'
    Check 'T7 pre-checks enforced' ($code -eq 3 -and $b.status -eq 'STOPPED_PRECHECK') "exit $code; $($b.status); checks: $((@($b.prechecks) | ForEach-Object { "$($_.check)=$($_.ok)" }) -join ' ')"
}
} finally {
    Stop-Writer
    [System.IO.File]::WriteAllLines($report, $results)
    Write-Host "report -> $report"
}
