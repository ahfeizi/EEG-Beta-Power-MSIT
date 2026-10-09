<#
.SYNOPSIS
  Synthetic tests of the S3a-INF-1 runner (no EEG data). Uses a TestMode configuration with
  shortened times and stage3_testjob / stage3_burnin as job functions (HWiNFO tests removed by S3a-INF-1-amend1).
  Writes test_report.txt in -WorkDir.
#>
param([Parameter(Mandatory = $true)][string]$WorkDir, [string[]]$Only)
$ErrorActionPreference = 'Stop'
$infra = Split-Path $PSScriptRoot
Import-Module (Join-Path $infra 'Stage3Runner.psm1') -Force
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir | Out-Null }
$eeg = Join-Path $WorkDir 'eegout'; $outR = Join-Path $WorkDir 'outroot'
foreach ($d in @($eeg, $outR)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }
$report = Join-Path $WorkDir 'test_report.txt'
$cfgFile = Join-Path $WorkDir 'test_config.psd1'
$real = Import-PowerShellDataFile (Join-Path $infra 'runner_config.psd1')
@"
# TEST configuration (synthetic tests only). Timing values are SHORTENED for speed;
# the real values are in revision\infra\runner_config.psd1.
@{
    MatlabExe = '$($real.MatlabExe)'
    EegOutRoot = '$eeg'
    OutRoot = '$outR'
    RawRoot = '$(Join-Path $WorkDir 'raw')'
    VerifiedManifest = '$(Join-Path $WorkDir 'manifest.tsv')'
    BlockTable = '$(Join-Path $WorkDir 'blocks.csv')'
    ExtraMatlabPaths = @('$PSScriptRoot')
    Threads = 2; MklCbwr = 'AUTO'; SeedGlobal = 1
    InternalSeeds = @{}; StepSeeds = @{}
    CooldownS = 1; PollS = 1
    ProcessorStateMaxPct = 85; HardwareChangeNotBefore = '2026-10-06T19:40:46'
    MaxAttemptsPerReplica = 5; AcceptanceMinCompleted = 3; MaxQuarantinedRecordings = 3; AcceptanceTimeoutS = 900; CompareTimeoutS = 600
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
function Join-Args([string[]]$A) { ($A | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ' }   # PS 5.1 does not quote
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

$sk = '-SkipPrechecksForTest'
try {
# ---------------------------------------------------------------- T1 injected worker error
if (Run-Test 'T1') {
    $jl = Write-Jobs 't1' @((Job 'err' ([ordered]@{ mode = 'error' })))
    $code = Invoke-Runner @('-Mode', 'Batch', '-BatchId', 't1', '-JobList', $jl, $sk) 't1'
    $st = Get-St 't1' 'err'
    Check 'T1 worker error' ($code -eq 0 -and $st.status -eq 'failed' -and $st.attempts.A -eq 5 -and @($st.history | Where-Object { $_.outcome -eq 'crash' }).Count -eq 5) "status $($st.status); attempts A $($st.attempts.A); outcomes $((@($st.history) | ForEach-Object outcome) -join ',')"
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
# ---------------------------------------------------------------- T5 A != B -> C (no stop), quarantine stop rule (amend1)
if (Run-Test 'T5') {
    $jl = Write-Jobs 't5' @((Job 'd1' ([ordered]@{ mode = 'replica_diff'; diffReplicas = @('B') })), (Job 'q1' ([ordered]@{ mode = 'replica_diff'; diffReplicas = @('B', 'C') })), (Job 'q2' ([ordered]@{ mode = 'replica_diff'; diffReplicas = @('B', 'C') })), (Job 'q3' ([ordered]@{ mode = 'replica_diff'; diffReplicas = @('B', 'C') })), (Job 'q4' ([ordered]@{ mode = 'ok' })))
    $code = Invoke-Runner @('-Mode', 'Batch', '-BatchId', 't5', '-JobList', $jl, $sk) 't5'
    $s1 = Get-St 't5' 'd1'; $b = Get-Bt 't5'
    $ab = @($s1.compares | Where-Object label -eq 'AB')[0]
    $nAbProc = @(Get-Jn 't5' | Where-Object { $_.event -eq 'compare' -and $_.job -eq 'd1' -and $_.replica -eq 'AB' }).Count
    Check 'T5 A!=B -> C' ($s1.status -eq 'flagged' -and $s1.canonical.replica -eq 'A' -and -not $ab.equal -and $nAbProc -eq 2 -and -not (Test-Path (Join-Path $eeg 'stage3_runs\t5\jobs\d1\B\attempt1\out.mat'))) "d1 $($s1.status), canonical $($s1.canonical.replica) ($($s1.canonical.pair)); AB compare processes $nAbProc; B deleted $(-not (Test-Path (Join-Path $eeg 'stage3_runs\t5\jobs\d1\B\attempt1\out.mat')))"
    $q = @('q1', 'q2', 'q3' | ForEach-Object { (Get-St 't5' $_).status })
    $q4 = Test-Path (Join-Path $eeg 'stage3_runs\t5\state\q4.json')
    Check 'T5 stop at 3 quarantined' ($b.status -eq 'STOPPED_QUARANTINE' -and ($q -join ',') -eq 'quarantined,quarantined,quarantined' -and -not $q4 -and $b.mismatchCount -eq 4) "batch $($b.status) ($($b.stopReason)); q1-q3 $($q -join ','); q4 started $q4; mismatchCount $($b.mismatchCount) (no stop at 2)"
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
# ---------------------------------------------------------------- T7 acceptance (crashes tolerated), Timeouts guard, pre-checks
if (Run-Test 'T7') {
    $jl = Write-Jobs 't7' @((Job 'acc' ([ordered]@{ mode = 'error_on_attempt'; errorReplicas = @('R02'); errorAttempt = 1 })))
    [void](Invoke-Runner @('-Mode', 'Acceptance', '-BatchId', 't7', '-JobList', $jl, '-Replicas', '3') 't7')
    $acc = Read-Json (Join-Path $eeg 'stage3_runs\t7\acceptance.json')
    Check 'T7 acceptance, 1 crash' ($acc.verdict -eq 'PASS' -and $acc.replicasOk -eq 3 -and @($acc.compares).Count -eq 2 -and $acc.crashes -eq 1 -and $acc.attempts -eq 4 -and $acc.crashesPerJobHour -gt 0) "verdict $($acc.verdict); replicas ok $($acc.replicasOk); attempts $($acc.attempts); crashes $($acc.crashes); per job-hour $($acc.crashesPerJobHour); compares vs $($acc.referenceReplica) $(@($acc.compares | ForEach-Object { $_.equal }) -join ',')"
    $jl = Write-Jobs 't7d' @((Job 'accd' ([ordered]@{ mode = 'replica_diff'; diffReplicas = @('R03') })))
    $code = Invoke-Runner @('-Mode', 'Acceptance', '-BatchId', 't7d', '-JobList', $jl, '-Replicas', '3') 't7d'
    $acc = Read-Json (Join-Path $eeg 'stage3_runs\t7d\acceptance.json')
    Check 'T7 acceptance, R03 differs' ($code -eq 4 -and $acc.verdict -eq 'FAIL' -and $acc.replicasOk -eq 3) "exit $code; verdict $($acc.verdict): $(($acc.failReasons) -join '; ')"
    $jl = Write-Jobs 't7e' @((Job 'acce' ([ordered]@{ mode = 'error_on_attempt'; errorReplicas = @('R01'); errorAttempt = @(1, 2, 3, 4, 5) })))
    $code = Invoke-Runner @('-Mode', 'Acceptance', '-BatchId', 't7e', '-JobList', $jl, '-Replicas', '3') 't7e'
    $acc = Read-Json (Join-Path $eeg 'stage3_runs\t7e\acceptance.json')
    Check 'T7 acceptance, min completed' ($code -eq 4 -and $acc.verdict -eq 'FAIL' -and $acc.replicasOk -eq 2 -and $acc.crashes -eq 5 -and $acc.referenceReplica -eq 'R02' -and @($acc.compares).Count -eq 1 -and $acc.compares[0].equal) "exit $code; verdict $($acc.verdict): $(($acc.failReasons) -join '; '); crashes $($acc.crashes); reference $($acc.referenceReplica); R02 vs R03 equal $(@($acc.compares)[0].equal)"
    $code = Invoke-Runner @('-Mode', 'Timeouts', '-BatchId', 'x', '-MsitBatch', 't7', '-RestBatch', 't7') 't7t'
    Check 'T7 timeouts guard' ($code -eq 3 -and -not (Test-Path (Join-Path $eeg 'stage3_runs\timeouts.json'))) "exit $code (3 = refused); $(Get-Content (Join-Path $WorkDir 'runner_t7t.out') -Raw)"
    $code = Invoke-Runner @('-Mode', 'Batch', '-BatchId', 't7b', '-JobList', $jl) 't7b'
    $b = Get-Bt 't7b'
    Check 'T7 pre-checks enforced' ($code -eq 3 -and $b.status -eq 'STOPPED_PRECHECK') "exit $code; $($b.status); checks: $((@($b.prechecks) | ForEach-Object { "$($_.check)=$($_.ok)" }) -join ' ')"
}
# ---------------------------------------------------------------- T8 kernel crash: resume, re-verify, reset (amend1)
if (Run-Test 'T8') {
    $jl = Write-Jobs 't8' @((Job 'k0' ([ordered]@{ mode = 'ok' })), (Job 'k1' ([ordered]@{ mode = 'ok' })), (Job 'k3' ([ordered]@{ mode = 'ok' })), (Job 'k2' ([ordered]@{ mode = 'ok'; sleepS = 40 })))
    $p = Start-Runner @('-Mode', 'Batch', '-BatchId', 't8', '-JobList', $jl, $sk) 't8a'
    $okWait = Wait-For { $s = Get-St 't8' 'k2'; $s.status -eq 'running' -and $s.running.replica -eq 'B' } 600 'k2 replica B running'
    Start-Sleep -Seconds 3
    $orphan = [int](Get-St 't8' 'k2').running.pid
    Stop-Process -Id $p.Id -Force                                                    # the runner dies, as in a kernel crash
    Start-Sleep -Seconds 2
    $s0 = Get-St 't8' 'k0'; $s1 = Get-St 't8' 'k1'
    [System.IO.File]::AppendAllText($s1.canonical.path, 'x')                           # k1: verified output no longer matches its SHA-256
    [System.IO.File]::WriteAllText((Join-Path $eeg 'stage3_runs\t8\state\k3.json'), '')  # k3: state file lost (empty)
    [System.IO.File]::WriteAllText((Join-Path $eeg 'stage3_runs\t8\test_kernel_events.txt'), '1')
    $code = Invoke-Runner @('-Mode', 'Batch', '-BatchId', 't8', '-JobList', $jl, $sk) 't8b'
    $j = Get-Jn 't8'; $b = Get-Bt 't8'
    $n0 = Get-St 't8' 'k0'; $n1 = Get-St 't8' 'k1'; $n2 = Get-St 't8' 'k2'; $n3 = Get-St 't8' 'k3'
    $c1 = $okWait -and $code -eq 0 -and $b.status -eq 'DONE' -and $b.kernelRecoveries -eq 1 -and @($j | Where-Object event -eq 'kernel_crash_detected').Count -eq 1
    Check 'T8 resume after kernel crash' $c1 "k2 B running seen $okWait; exit $code; batch $($b.status); recoveries $($b.kernelRecoveries); orphan $orphan killed $(@($j | Where-Object event -eq 'orphan_killed').Count)"
    Check 'T8 verified output kept' ($n0.status -eq 'verified' -and $n0.canonical.sha256 -eq $s0.canonical.sha256 -and $n0.attempts.A -eq 1 -and @($j | Where-Object { $_.event -eq 'kernel_reverified' -and $_.job -eq 'k0' }).Count -eq 1) "k0 $($n0.status); SHA-256 unchanged $($n0.canonical.sha256 -eq $s0.canonical.sha256); attempts A $($n0.attempts.A)"
    Check 'T8 changed output reset' ($n1.status -eq 'verified' -and $n1.attempts.A -eq 2 -and @($n1.flags) -contains 'reset_after_kernel_crash' -and $n1.canonical.path -ne $s1.canonical.path) "k1 $($n1.status); attempts A $($n1.attempts.A); flags $(@($n1.flags) -join ';'); canonical $($n1.canonical.path)"
    Check 'T8 unverified reset' ($n2.status -eq 'verified' -and @($n2.flags) -contains 'reset_after_kernel_crash' -and @($n2.history | Where-Object outcome -eq 'interrupted').Count -eq 1 -and $n2.attempts.A -eq 2) "k2 $($n2.status); attempts A $($n2.attempts.A) B $($n2.attempts.B); flags $(@($n2.flags) -join ';')"
    Check 'T8 unreadable state' ($n3.status -eq 'verified' -and @($j | Where-Object { $_.event -eq 'state_unreadable' -and $_.job -eq 'k3' }).Count -eq 1) "k3 $($n3.status); state_unreadable events $(@($j | Where-Object { $_.event -eq 'state_unreadable' }).Count)"
}} finally {
    [System.IO.File]::WriteAllLines($report, $results)
    Write-Host "report -> $report"
}
