<#
.SYNOPSIS
  S3a-INF-1 runner: crash-tolerant A/B execution of heavy Stage 3 MATLAB jobs (Windows PowerShell 5.1).
.DESCRIPTION
  Decision log: S3a-INF-1 (df80384) and S3a-INF-1-clar1. One command starts or resumes a batch.
  Modes:
    Batch       every job of -JobList: replica A, then B; A = B -> verified (B deleted); A != B -> C
                (C = A or B -> verified, flagged; else quarantined). Up to MaxRetries retries per replica.
                Pre-checks (S3a-INF-1-clar1) must pass before the first job.
    Acceptance  one job of -JobList run -Replicas times (R01, R02, ...), no retries; all outputs
                compared with R01. -TimingOnly: timing calibration only (sub-06 rest x 3), no verdict.
    BurnIn      stage3_burnin as replicas A then B (no retries), -Iterations each; -Calibrate runs
                replica A only and reports the time per iteration.
    Timeouts    writes timeouts.json from a PASS burn-in, a PASS MSIT+ acceptance and the rest
                timing run (3 x median wall time per recording type).
  Every job is one fresh `MATLAB.exe -batch` process; jobs never run in parallel. Thermal, disk and
  HWiNFO-header gates run before every job; thermal and header monitoring run during it.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Invoke-Stage3Batch.ps1 -Mode Batch -BatchId d5_0_ab_1 -JobList jobs_d5_0.json
  (the pre-checks find the acceptance through <EegOutRoot>\stage3_runs\timeouts.json)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('Batch', 'Acceptance', 'BurnIn', 'Timeouts')][string]$Mode,
    [Parameter(Mandatory = $true)][string]$BatchId,
    [string]$JobList,
    [int]$Replicas = 11,
    [switch]$TimingOnly,
    [int]$Iterations = 0,
    [switch]$Calibrate,
    [string]$CalibrationBatch,
    [string]$BurnInBatch,
    [string]$MsitBatch,
    [string]$RestBatch,
    [string]$CarryOverFrom,
    [string]$Config = (Join-Path $PSScriptRoot 'runner_config.psd1'),
    [switch]$SkipPrechecksForTest
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$infra = $PSScriptRoot
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$stage3 = Join-Path $repo 'revision\stage3'
$logFile = Join-Path $repo 'docs\decision_log.md'
$runsRoot = Join-Path $cfg.EegOutRoot 'stage3_runs'
$batchDir = Join-Path $runsRoot $BatchId
if ($SkipPrechecksForTest -and -not $cfg.TestMode) { throw '-SkipPrechecksForTest is allowed only with a TestMode configuration' }

# ============================================================== Timeouts mode (no jobs)
if ($Mode -eq 'Timeouts') {
    $src = @{}
    foreach ($pair in @(@('burnin', $BurnInBatch), @('msit', $MsitBatch), @('rest', $RestBatch))) {
        if (-not $pair[1]) { throw "Timeouts mode needs -BurnInBatch, -MsitBatch and -RestBatch" }
        $d = Join-Path $runsRoot $pair[1]
        $a = Read-Json (Join-Path $d 'acceptance.json')
        $src[$pair[0]] = [pscustomobject]@{ batch = $pair[1]; acceptance = $a; dir = $d }
    }
    $problems = @()
    if ($src.burnin.acceptance.kind -ne 'burnin' -or $src.burnin.acceptance.verdict -ne 'PASS') { $problems += 'burn-in verdict is not PASS' }
    if ($src.msit.acceptance.kind -ne 'acceptance' -or $src.msit.acceptance.verdict -ne 'PASS') { $problems += 'MSIT+ acceptance verdict is not PASS' }
    if ($src.msit.acceptance.recType -ne 'msit' -or $src.msit.acceptance.replicasRequested -ne 11) { $problems += 'MSIT+ acceptance is not an 11-replica msit run' }
    if ($src.rest.acceptance.kind -ne 'timing' -or $src.rest.acceptance.recType -ne 'rest' -or $src.rest.acceptance.replicasRequested -ne 3) { $problems += 'rest run is not a 3-replica timing run' }
    if (@($src.rest.acceptance.wallSecondsSuccessful).Count -lt 1) { $problems += 'rest run has no successful replica' }
    $hwBound = [datetime]::Parse($cfg.HardwareChangeNotBefore, [System.Globalization.CultureInfo]::InvariantCulture)
    foreach ($k in $src.Keys) { if ([datetime]::Parse($src[$k].acceptance.startTime) -le $hwBound) { $problems += "$k run started before the S3a-HW-1 bound $($cfg.HardwareChangeNotBefore)" } }
    if ($problems.Count -gt 0) { Write-Host ('TIMEOUTS NOT WRITTEN: ' + ($problems -join '; ')); exit 3 }
    $sources = @()
    foreach ($k in @('burnin', 'msit', 'rest')) {
        foreach ($f in @('acceptance.json', 'summary.txt', 'summary.csv')) {
            $p = Join-Path $src[$k].dir $f
            $sources += [pscustomobject]@{ role = $k; batch = $src[$k].batch; file = $p; sha256 = (Get-Sha256File $p) }
        }
    }
    $t = [ordered]@{
        written = (Get-Date).ToString('s')
        rule = 'timeout = 3 x median wall time of the successful replicas (S3a-INF-1 sec. 6; S3a-INF-1-clar1)'
        timeoutS = [ordered]@{ msit = [int][math]::Ceiling(3 * $src.msit.acceptance.medianWallSeconds); rest = [int][math]::Ceiling(3 * $src.rest.acceptance.medianWallSeconds) }
        medianWallSeconds = [ordered]@{ msit = $src.msit.acceptance.medianWallSeconds; rest = $src.rest.acceptance.medianWallSeconds }
        acceptanceFingerprint = $src.msit.acceptance.fingerprint
        acceptanceConfig = $src.msit.acceptance.configSnapshot
        acceptanceStart = [ordered]@{ burnin = $src.burnin.acceptance.startTime; msit = $src.msit.acceptance.startTime; rest = $src.rest.acceptance.startTime }
        sources = $sources
    }
    $tf = Join-Path $runsRoot 'timeouts.json'
    Write-JsonAtomic $tf $t
    $runsCopy = Join-Path $cfg.OutRoot 'stage3\runs'
    if (-not (Test-Path $runsCopy)) { New-Item -ItemType Directory -Path $runsCopy | Out-Null }
    Copy-Item -LiteralPath $tf -Destination (Join-Path $runsCopy 'timeouts.json') -Force
    Write-Host "timeouts.json written: msit $($t.timeoutS.msit) s, rest $($t.timeoutS.rest) s -> $tf"
    exit 0
}

# ============================================================== batch directory, lock, batch.json
if (-not (Test-Path $batchDir)) { New-Item -ItemType Directory -Path $batchDir | Out-Null }
foreach ($sub in @('state', 'jobs', 'compare')) { $p = Join-Path $batchDir $sub; if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null } }
$lockFile = Join-Path $batchDir 'batch.lock'
if (Test-Path $lockFile) {
    $other = [int](Get-Content -LiteralPath $lockFile -Raw).Trim()
    $op = Get-Process -Id $other -ErrorAction SilentlyContinue
    if ($op -and $op.ProcessName -match 'powershell' -and $other -ne $PID) { throw "batch $BatchId is locked by running process $other" }
}
[System.IO.File]::WriteAllText($lockFile, "$PID")

$batchFile = Join-Path $batchDir 'batch.json'
$resume = Test-Path $batchFile
if ($resume) {
    $batch = Read-Json $batchFile
    if ($batch.mode -ne $Mode) { throw "batch $BatchId was started in mode $($batch.mode), not $Mode" }
    if ($batch.status -like 'STOPPED*' -or $batch.status -eq 'DONE') {
        Write-Host "batch $BatchId is $($batch.status); nothing to resume. Start a new batch (see S3a-INF-1 sec. 7)."
        Remove-Item -LiteralPath $lockFile; exit 2
    }
    Add-Journal $batchDir 'resume' -Detail "runner pid $PID"
} else {
    $jobs = @()
    if ($Mode -eq 'BurnIn') {
        if ($Iterations -lt 1 -and -not $Calibrate) { $Iterations = [int]$cfg.BurnInIterations }       # fixed N (S3a-INF-1-clar1)
        if ($Iterations -lt 1) { throw 'BurnIn mode needs -Iterations or BurnInIterations in the configuration' }
        $jobs = @([pscustomobject]@{ id = 'burnin'; func = 'stage3_burnin'; params = [pscustomobject]@{ nIter = $Iterations }; recType = 'burnin'; compareKind = 'burnin' })
    } else {
        if (-not $JobList) { throw "$Mode mode needs -JobList" }
        $jobs = Read-JsonArray $JobList
        if ($Mode -eq 'Acceptance' -and $jobs.Count -ne 1) { throw 'Acceptance mode needs a job list with exactly one job' }
    }
    foreach ($j in $jobs) {
        if ($j.compareKind -eq 'set') { Remove-Item -LiteralPath $lockFile; throw "job $($j.id): compare kind 'set' is refused until its specification is logged (S3a-INF-1-clar1)" }
        if ($j.PSObject.Properties.Name -contains 'randomSteps') {
            foreach ($rs in @($j.randomSteps)) { if (-not $cfg.StepSeeds.ContainsKey($rs)) { Remove-Item -LiteralPath $lockFile; throw "job $($j.id): random step '$rs' has no seed in StepSeeds (S3a-INF-1-clar1)" } }
        }
    }
    $snap = Get-HwinfoSnapshot $cfg.HwinfoCsv
    $hdr = Test-HwinfoHeader $snap '' $cfg._TempName $cfg.HwinfoTempNameCount
    if (-not $hdr.Ok) { Remove-Item -LiteralPath $lockFile; throw "HWiNFO log not usable at batch start: $($hdr.Reason)" }
    $batch = [pscustomobject]@{
        batchId = $BatchId; mode = $Mode; status = 'RUNNING'; stopReason = ''
        startTime = (Get-Date).ToString('s'); endTime = ''
        timingOnly = [bool]$TimingOnly; calibrate = [bool]$Calibrate; replicasRequested = $Replicas; iterations = $Iterations
        calibrationBatch = $CalibrationBatch; carryOverFrom = $CarryOverFrom
        jobs = $jobs
        configPath = $cfg._Path; configSha256 = $cfg._Sha256
        hwinfoCsv = $cfg.HwinfoCsv; hwinfoHeaderSha256 = $snap.HeaderSha; hwinfoTempIndex = $hdr.TempIndex
        entryHashes = [pscustomobject]@{ 'S3a-INF-1' = (Get-LogEntryHash $logFile 'S3a-INF-1'); 'S3a-INF-1-clar1' = (Get-LogEntryHash $logFile 'S3a-INF-1-clar1') }
        prechecks = @(); timeoutsFile = ''; timeoutsSha256 = ''; timeoutS = $null
        mismatchCount = 0
    }
    Write-JsonAtomic $batchFile $batch
    Add-Journal $batchDir 'batch_start' -Detail "mode $Mode; runner pid $PID; config $($cfg._Sha256)"
}

function Save-Batch { Write-JsonAtomic $batchFile $batch }

function Stop-Batch([string]$Status, [string]$Reason, [int]$Code = 2) {
    $batch.status = $Status; $batch.stopReason = $Reason; $batch.endTime = (Get-Date).ToString('s')
    Save-Batch
    Add-Journal $batchDir 'batch_stop' -Detail "$Status $Reason"
    & (Join-Path $infra 'Write-Stage3Summary.ps1') -BatchDir $batchDir -Config $Config
    Remove-Item -LiteralPath $lockFile -ErrorAction SilentlyContinue
    exit $Code
}

# kernel crash since batch start -> STOPPED_KERNEL (S3a-INF-1 sec. 7)
if ($resume) {
    $ev = Get-Stage3SystemEventCounts ([datetime]::Parse($batch.startTime))
    if ($ev.KernelPower41 -gt 0 -or $ev.BugCheck1001 -gt 0) {
        Stop-Batch 'STOPPED_KERNEL' "Kernel-Power 41: $($ev.KernelPower41), BugCheck 1001: $($ev.BugCheck1001) since batch start"
    }
}

# ============================================================== state helpers
function Get-StatePath([string]$Id) { Join-Path $batchDir "state\$Id.json" }
function Get-JobState($Job) {
    $p = Get-StatePath $Job.id
    if (Test-Path $p) { return Read-Json $p }
    [pscustomobject]@{
        id = $Job.id; status = 'pending'; prevStatus = ''; running = $null
        attempts = [pscustomobject]@{ A = 0; B = 0; C = 0 }
        outputs = [pscustomobject]@{ A = ''; B = ''; C = '' }
        fingerprintRef = ''; history = @(); flags = @(); compares = @(); mismatch = $false
        canonical = $null; failureReason = ''
    }
}
function Save-JobState($St) { Write-JsonAtomic (Get-StatePath $St.id) $St }
function Add-Flag($St, [string]$Flag) { if (@($St.flags) -notcontains $Flag) { $St.flags = @($St.flags) + $Flag } }
function Set-Attempts($St, [string]$Replica, [int]$N) {
    if ($St.attempts.PSObject.Properties.Name -contains $Replica) { $St.attempts.$Replica = $N }
    else { $St.attempts | Add-Member -NotePropertyName $Replica -NotePropertyValue $N }
}
function Get-Attempts($St, [string]$Replica) {
    if ($St.attempts.PSObject.Properties.Name -contains $Replica) { return [int]$St.attempts.$Replica }
    0
}
function Set-Output($St, [string]$Replica, [string]$Path) {
    if ($St.outputs.PSObject.Properties.Name -contains $Replica) { $St.outputs.$Replica = $Path }
    else { $St.outputs | Add-Member -NotePropertyName $Replica -NotePropertyValue $Path }
}
function Remove-AttemptOutputs([string]$Dir) {
    foreach ($f in @('out.mat', 'out.partial.mat')) { $p = Join-Path $Dir $f; if (Test-Path $p) { Remove-Item -LiteralPath $p -Force } }
}

# resume: every 'running' entry is reset; its process tree is killed if still alive (S3a-INF-1 sec. 5)
foreach ($sf in @(Get-ChildItem -LiteralPath (Join-Path $batchDir 'state') -Filter '*.json' -ErrorAction SilentlyContinue)) {
    $st = Read-Json $sf.FullName
    if ($st.status -eq 'running' -and $st.running) {
        $r = $st.running
        if ($r.pid -and (Test-MatlabPid ([int]$r.pid))) { Stop-ProcessTree ([int]$r.pid); Add-Journal $batchDir 'orphan_killed' $st.id $r.replica $r.attempt $r.pid }
        Remove-AttemptOutputs $r.dir
        $st.history = @($st.history) + [pscustomobject]@{ replica = $r.replica; attempt = $r.attempt; pid = $r.pid; start = $r.start; end = (Get-Date).ToString('s'); exitCode = $null; outcome = 'interrupted'; reason = 'runner interrupted (resume)'; wallSeconds = $null; maxTempC = $null; appErrors1000 = $null }
        $st.status = $st.prevStatus; $st.running = $null
        Save-JobState $st
        Add-Journal $batchDir 'attempt_interrupted' $st.id $r.replica $r.attempt $r.pid -Detail 'reset on resume; counted as a failed attempt'
    }
}

# ============================================================== gates and one replica attempt
function Wait-Gates {
    # disk gate, HWiNFO header and staleness, cool-down, temperature gate (S3a-INF-1 sec. 6)
    $largest = 0
    foreach ($o in @(Get-ChildItem -LiteralPath (Join-Path $batchDir 'jobs') -Recurse -Filter 'out.mat' -ErrorAction SilentlyContinue)) { if ($o.Length -gt $largest) { $largest = $o.Length } }
    $paused = $false
    while ($true) {
        $needD = $cfg.DiskMinFreeGB_EegOut + $cfg.DiskOutputFactor * $largest / 1GB
        $fD = Get-FreeGB $cfg.EegOutRoot; $fC = Get-FreeGB $cfg.OutRoot
        if ($fD -ge $needD -and $fC -ge $cfg.DiskMinFreeGB_OutRoot) { break }
        if (-not $paused) { Add-Journal $batchDir 'disk_pause' -Detail ("eegOut free {0} GB (need {1:N2}); outRoot free {2} GB (need {3})" -f $fD, $needD, $fC, $cfg.DiskMinFreeGB_OutRoot); $paused = $true }
        Start-Sleep -Seconds 60
    }
    Start-Sleep -Seconds $cfg.CooldownS
    $gateStart = $null; $stalePaused = $false
    while ($true) {
        $snap = Get-HwinfoSnapshot $cfg.HwinfoCsv
        $h = Test-HwinfoHeader $snap $batch.hwinfoHeaderSha256 $cfg._TempName $cfg.HwinfoTempNameCount
        if (-not $h.Ok -and $h.Fatal) { Stop-Batch 'STOPPED_HWINFO_HEADER' $h.Reason }
        $th = $null
        if ($h.Ok) { $th = Get-HwinfoThermal $snap $h.TempIndex $cfg (Get-Date) }
        if (-not $h.Ok -or $th.Stale) {
            $why = if (-not $h.Ok) { $h.Reason } else { $th.Reason }
            if (-not $stalePaused) { Add-Journal $batchDir 'stale_pause' -Detail $why; $stalePaused = $true }
            $gateStart = $null
            Start-Sleep -Seconds $cfg.PollS
            continue
        }
        if ($stalePaused) { Add-Journal $batchDir 'stale_resolved' -Detail ("last row {0:s}" -f $th.LastTime); $stalePaused = $false }
        if ($null -eq $gateStart) { $gateStart = Get-Date }
        if ($th.LastTemp -le $cfg.GateC) { Add-Journal $batchDir 'gate_ok' -Detail ("CPU package {0} C" -f $th.LastTemp); return }
        if (((Get-Date) - $gateStart).TotalSeconds -ge $cfg.GateMaxWaitS) { Add-Journal $batchDir 'gate_timeout' -Detail ("CPU package {0} C after {1} s" -f $th.LastTemp, $cfg.GateMaxWaitS); return }
        Start-Sleep -Seconds $cfg.PollS
    }
}

function Invoke-Attempt($Job, $St, [string]$Replica, [int]$TimeoutS) {
    $attempt = (Get-Attempts $St $Replica) + 1
    $dir = Join-Path $batchDir ("jobs\{0}\{1}\attempt{2}" -f $Job.id, $Replica, $attempt)
    if (Test-Path $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    New-Item -ItemType Directory -Path $dir | Out-Null
    $out = Join-Path $dir 'out.mat'
    $fpFile = Join-Path $dir 'fingerprint.json'
    $jobLog = Join-Path $dir 'job.log'
    $paths = @($infra, $stage3) + @($cfg.ExtraMatlabPaths)
    $spec = [ordered]@{
        jobId = $Job.id; replica = $Replica; attempt = $attempt; func = $Job.func; params = $Job.params
        common = [ordered]@{ rawRoot = $cfg.RawRoot; manifest = $cfg.VerifiedManifest; blockTable = $cfg.BlockTable; seedGlobal = $cfg.SeedGlobal }
        paths = $paths; threads = $cfg.Threads; seedGlobal = $cfg.SeedGlobal; configSha256 = $cfg._Sha256
        testMode = [bool]$cfg.TestMode; outFile = $out; fingerprintFile = $fpFile
    }
    $specFile = Join-Path $dir 'spec.json'
    Write-JsonAtomic $specFile $spec
    Wait-Gates
    Set-Attempts $St $Replica $attempt
    $St.prevStatus = $St.status; $St.status = 'running'
    $t0 = Get-Date
    $cmd = "addpath('$infra'); stage3_job('$specFile')"
    $p = Start-MatlabProcess $cfg $cmd $jobLog $dir
    $St.running = [pscustomobject]@{ replica = $Replica; attempt = $attempt; pid = $p.Id; start = $t0.ToString('s'); dir = $dir }
    Save-JobState $St
    Add-Journal $batchDir 'job_start' $Job.id $Replica $attempt $p.Id -Detail "timeout $TimeoutS s"
    $outcome = ''; $maxT = $null; $flags = @()
    while (-not $p.WaitForExit($cfg.PollS * 1000)) {
        if (((Get-Date) - $t0).TotalSeconds -gt $TimeoutS) { Stop-ProcessTree $p.Id; $outcome = 'timeout'; break }
        $snap = Get-HwinfoSnapshot $cfg.HwinfoCsv
        $h = Test-HwinfoHeader $snap $batch.hwinfoHeaderSha256 $cfg._TempName $cfg.HwinfoTempNameCount
        if (-not $h.Ok) {
            if ($flags -notcontains 'thermal_unmonitored') { $flags += 'thermal_unmonitored'; Add-Journal $batchDir 'thermal_unmonitored' $Job.id $Replica $attempt $p.Id -Detail $h.Reason }
            if ($h.Fatal -and $flags -notcontains 'hwinfo_header_changed') { $flags += 'hwinfo_header_changed' }
            continue
        }
        $th = Get-HwinfoThermal $snap $h.TempIndex $cfg (Get-Date)
        if ($th.Stale) {
            if ($flags -notcontains 'thermal_unmonitored') { $flags += 'thermal_unmonitored'; Add-Journal $batchDir 'thermal_unmonitored' $Job.id $Replica $attempt $p.Id -Detail $th.Reason }
            continue
        }
        foreach ($v in @($th.WindowTemps) + $th.LastTemp) { if ($null -eq $maxT -or $v -gt $maxT) { $maxT = $v } }
        if ($th.Hot) { Stop-ProcessTree $p.Id; $outcome = 'thermal_abort'; break }
    }
    $p.WaitForExit()
    $t1 = Get-Date
    $exit = $null; try { $exit = $p.ExitCode } catch { $exit = $null }
    $done = $false
    if (Test-Path $jobLog) { $done = [bool](Select-String -LiteralPath $jobLog -SimpleMatch ("STAGE3_JOB_DONE {0} {1} attempt {2}" -f $Job.id, $Replica, $attempt) -Quiet) }
    if (-not $outcome) {
        if ($exit -eq 0 -and (Test-Path $out) -and $done -and -not (Test-Path (Join-Path $dir 'out.partial.mat'))) { $outcome = 'ok' }
        elseif ($exit -eq 0) { $outcome = 'incomplete' } else { $outcome = 'crash' }
    }
    $reason = ''
    if ($outcome -eq 'ok') {
        if (-not (Test-Path $fpFile)) { $outcome = 'failed'; $reason = 'no fingerprint' }
        elseif ($St.fingerprintRef -and ((Get-Content -LiteralPath $fpFile -Raw) -ne (Get-Content -LiteralPath $St.fingerprintRef -Raw))) {
            $outcome = 'fingerprint_mismatch'; $reason = "fingerprint differs from $($St.fingerprintRef)"
        } else {
            $fp = Read-Json $fpFile
            if (@($fp.assertion_failures).Count -gt 0) { Add-Flag $St 'test_mode_assertions_failed'; $reason = 'TEST MODE: ' + (@($fp.assertion_failures) -join '; ') }
        }
    }
    $app = 0
    try { $app = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $t0; EndTime = $t1.AddSeconds(5) } -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'MATLAB\.exe' }).Count } catch { $app = 0 }
    if ($outcome -ne 'ok') { Remove-AttemptOutputs $dir }
    foreach ($f in $flags) { Add-Flag $St $f }
    $St.history = @($St.history) + [pscustomobject]@{ replica = $Replica; attempt = $attempt; pid = $p.Id; start = $t0.ToString('s'); end = $t1.ToString('s'); exitCode = $exit; outcome = $outcome; reason = $reason; wallSeconds = [math]::Round(($t1 - $t0).TotalSeconds, 1); maxTempC = $maxT; appErrors1000 = $app }
    $St.status = $St.prevStatus; $St.running = $null
    if ($outcome -eq 'ok') {
        Set-Output $St $Replica $out
        if (-not $St.fingerprintRef) { $St.fingerprintRef = $fpFile }
    }
    Save-JobState $St
    Add-Journal $batchDir 'job_end' $Job.id $Replica $attempt $p.Id $exit -Detail ("{0} {1:N0} s max {2} C {3}" -f $outcome, ($t1 - $t0).TotalSeconds, $maxT, $reason)
    if ($flags -contains 'hwinfo_header_changed') { Stop-Batch 'STOPPED_HWINFO_HEADER' 'HWiNFO header changed during a job' }
    $outcome -eq 'ok'
}

function Invoke-Replica($Job, $St, [string]$Replica, [int]$TimeoutS, [int]$MaxAttempts) {
    while ((Get-Attempts $St $Replica) -lt $MaxAttempts) {
        if (Invoke-Attempt $Job $St $Replica $TimeoutS) { return $true }
    }
    $false
}

function Invoke-Compare($Job, [string]$X, [string]$Y, [string]$Label) {
    # S3a-INF-1 sec. 3 and S3a-INF-1-clar1: a 'different' verdict is recomputed by a second process;
    # if the two verdicts disagree: treated as different, flagged compare_inconsistent
    $res = @()
    foreach ($k in 1..2) {
        $j = Join-Path $batchDir ("compare\{0}_{1}_{2}.json" -f $Job.id, $Label, $k)
        if (Test-Path $j) { Remove-Item -LiteralPath $j }
        $lg = "$j.log"
        $cmd = "addpath('$infra'); stage3_compare('$X', '$Y', '$($Job.compareKind)', '$j')"
        $r = Invoke-MatlabSimple $cfg $cmd $lg (Split-Path $j) $cfg.CompareTimeoutS
        if ($r.ExitCode -ne 0 -or -not (Test-Path $j)) {
            $r = Invoke-MatlabSimple $cfg $cmd $lg (Split-Path $j) $cfg.CompareTimeoutS        # one retry of a failed compare process
            if ($r.ExitCode -ne 0 -or -not (Test-Path $j)) { return [pscustomobject]@{ ok = $false; equal = $false; inconsistent = $false; files = @(); reason = "compare process failed (exit $($r.ExitCode))" } }
        }
        $c = Read-Json $j
        $res += [pscustomobject]@{ file = $j; equal = [bool]$c.equal; json = $c }
        Add-Journal $batchDir 'compare' $Job.id $Label $k $r.Pid $r.ExitCode -Detail ("equal={0}" -f $c.equal)
        if ($c.equal) { break }
    }
    $inconsistent = ($res.Count -eq 2) -and ($res[0].equal -ne $res[1].equal)
    $equal = ($res.Count -eq 1) -and $res[0].equal
    [pscustomobject]@{ ok = $true; equal = $equal; inconsistent = $inconsistent; files = @($res | ForEach-Object { $_.file }); last = $res[$res.Count - 1].json; reason = '' }
}

function Add-CompareRecord($St, [string]$Label, $C) {
    $St.compares = @($St.compares) + [pscustomobject]@{ label = $Label; equal = $C.equal; inconsistent = $C.inconsistent; files = $C.files; reason = $C.reason }
    if ($C.inconsistent) { Add-Flag $St 'compare_inconsistent' }
}

function Update-MismatchCount {
    $n = 0
    foreach ($sf in @(Get-ChildItem -LiteralPath (Join-Path $batchDir 'state') -Filter '*.json')) { if ((Read-Json $sf.FullName).mismatch) { $n++ } }
    $batch.mismatchCount = $n; Save-Batch
    $n
}

function Get-Median([double[]]$V) {
    $s = @($V | Sort-Object); $n = $s.Count
    if ($n -eq 0) { return $null }
    if ($n % 2) { return $s[($n - 1) / 2] }
    ($s[$n / 2 - 1] + $s[$n / 2]) / 2
}

# ============================================================== Batch mode
if ($Mode -eq 'Batch') {
    if (-not $resume) {
        $checks = @()
        if ($SkipPrechecksForTest) {
            $checks += [pscustomobject]@{ check = 'ALL'; ok = $true; detail = 'SKIPPED: TestMode configuration with -SkipPrechecksForTest' }
            $batch.timeoutS = $cfg.TestTimeoutS
        } else {
            $checks = & (Join-Path $infra 'Test-Stage3Prechecks.ps1') -Config $Config -JobList $JobList -WorkDir $batchDir
            $tf = Join-Path $runsRoot 'timeouts.json'
            if (Test-Path $tf) { $batch.timeoutsFile = $tf; $batch.timeoutsSha256 = Get-Sha256File $tf; $batch.timeoutS = (Read-Json $tf).timeoutS }
        }
        $batch.prechecks = @($checks)
        Save-Batch
        $bad = @($checks | Where-Object { -not $_.ok })
        if ($bad.Count -gt 0) { Stop-Batch 'STOPPED_PRECHECK' (($bad | ForEach-Object { "$($_.check): $($_.detail)" }) -join ' | ') 3 }
        if ($CarryOverFrom) {
            & (Join-Path $infra 'Copy-Stage3VerifiedState.ps1') -Config $Config -FromBatch $CarryOverFrom -ToBatch $BatchId
        }
    }
    foreach ($job in @($batch.jobs)) {
        $st = Get-JobState $job
        $timeout = [int]$batch.timeoutS.($job.recType)
        if ($timeout -le 0) { Stop-Batch 'STOPPED_PRECHECK' "no timeout for recording type $($job.recType)" 3 }
        $maxA = 1 + $cfg.MaxRetries
        while ($st.status -notin @('verified', 'flagged', 'failed', 'quarantined')) {
            switch ($st.status) {
                'pending' {
                    if (Invoke-Replica $job $st 'A' $timeout $maxA) { $st.status = 'A_done' } else { $st.status = 'failed'; $st.failureReason = 'replica A: attempts exhausted' }
                    Save-JobState $st
                }
                'A_done' {
                    if (Invoke-Replica $job $st 'B' $timeout $maxA) { $st.status = 'B_done' } else { $st.status = 'failed'; $st.failureReason = 'replica B: attempts exhausted' }
                    Save-JobState $st
                }
                'B_done' {
                    $c = Invoke-Compare $job $st.outputs.A $st.outputs.B 'AB'
                    Add-CompareRecord $st 'AB' $c
                    if (-not $c.ok) { $st.status = 'failed'; $st.failureReason = $c.reason; Save-JobState $st; break }
                    if ($c.equal) {
                        $st.canonical = [pscustomobject]@{ replica = 'A'; path = $st.outputs.A; sha256 = (Get-Sha256File $st.outputs.A); verified = (Get-Date).ToString('s') }
                        Remove-Item -LiteralPath $st.outputs.B -Force; Add-Journal $batchDir 'replica_deleted' $job.id 'B' -Detail 'A = B'
                        $st.status = 'verified'; Save-JobState $st
                    } else {
                        $st.mismatch = $true; Save-JobState $st
                        $n = Update-MismatchCount
                        Add-Journal $batchDir 'mismatch' $job.id 'AB' -Detail ("recordings with a mismatch: {0}; inconsistent compare: {1}" -f $n, $c.inconsistent)
                        if ($n -ge $cfg.MaxMismatchRecordings) { Stop-Batch 'STOPPED_MISMATCH' "$n recordings with A != B (or an inconsistent compare)" }
                        if (Invoke-Replica $job $st 'C' $timeout $maxA) { $st.status = 'C_done' } else { $st.status = 'failed'; $st.failureReason = 'replica C: attempts exhausted' }
                        Save-JobState $st
                    }
                }
                'C_done' {
                    $done = $false
                    foreach ($pair in @(@('A', 'AC'), @('B', 'BC'))) {
                        $c = Invoke-Compare $job $st.outputs.($pair[0]) $st.outputs.C $pair[1]
                        Add-CompareRecord $st $pair[1] $c
                        if ($c.inconsistent) {
                            Save-JobState $st
                            $n = Update-MismatchCount
                            if ($n -ge $cfg.MaxMismatchRecordings) { Stop-Batch 'STOPPED_MISMATCH' "$n recordings with A != B (or an inconsistent compare)" }
                        }
                        if ($c.ok -and $c.equal) {
                            $keep = $pair[0]; $odd = if ($keep -eq 'A') { 'B' } else { 'A' }
                            $st.canonical = [pscustomobject]@{ replica = $keep; pair = "$keep=C"; path = $st.outputs.$keep; sha256 = (Get-Sha256File $st.outputs.$keep); verified = (Get-Date).ToString('s') }
                            Remove-Item -LiteralPath $st.outputs.$odd -Force; Add-Journal $batchDir 'replica_deleted' $job.id $odd -Detail "$keep = C"
                            Add-Flag $st 'A_ne_B_resolved_by_C'
                            $st.status = 'flagged'; $done = $true; break
                        }
                    }
                    if (-not $done) { $st.status = 'quarantined'; $st.failureReason = 'C equals neither A nor B' }
                    Save-JobState $st
                }
                default { throw "unexpected state $($st.status) for $($job.id)" }
            }
        }
    }
    $batch.status = 'DONE'; $batch.endTime = (Get-Date).ToString('s'); Save-Batch
    Add-Journal $batchDir 'batch_end'
    & (Join-Path $infra 'Write-Stage3Summary.ps1') -BatchDir $batchDir -Config $Config
    Remove-Item -LiteralPath $lockFile -ErrorAction SilentlyContinue
    exit 0
}

# ============================================================== Acceptance and BurnIn modes
$job = @($batch.jobs)[0]
$st = Get-JobState $job
if ($Mode -eq 'Acceptance') {
    $names = @(1..$batch.replicasRequested | ForEach-Object { 'R{0:D2}' -f $_ })
    $timeout = $cfg.AcceptanceTimeoutS
} else {
    $names = if ($batch.calibrate) { @('A') } else { @('A', 'B') }
    if ($batch.calibrate) { $timeout = $cfg.AcceptanceTimeoutS }
    else {
        if ($batch.calibrationBatch) {
            $cal = Read-Json (Join-Path (Join-Path $runsRoot $batch.calibrationBatch) 'acceptance.json')
            if ($cal.kind -ne 'burnin_calibration') { throw "$($batch.calibrationBatch) is not a burn-in calibration" }
            $secPerIt = [double]$cal.meanIterationSeconds
        } else {
            if (-not $cfg.BurnInIterationSeconds) { throw 'BurnIn mode needs -Calibrate, -CalibrationBatch, or BurnInIterationSeconds in the configuration' }
            $secPerIt = [double]$cfg.BurnInIterationSeconds                                          # recorded in S3a-INF-1-clar1
        }
        $timeout = [int][math]::Ceiling(3 * $batch.iterations * $secPerIt)                          # 3 x expected (clar1)
        Add-Journal $batchDir 'burnin_timeout' -Detail ("3 x {0} iterations x {1:N3} s = {2} s" -f $batch.iterations, $secPerIt, $timeout)
    }
}
foreach ($r in $names) {
    if ((Get-Attempts $st $r) -ge 1) { continue }                                   # no retries (S3a-INF-1 sec. 8)
    [void](Invoke-Attempt $job $st $r $timeout)
}
$st = Get-JobState $job
$ref = $names[0]
$okNames = @($names | Where-Object { $n = $_; @($st.history | Where-Object { $_.replica -eq $n -and $_.outcome -eq 'ok' }).Count -gt 0 })
$cmpRes = @()
if (-not $batch.calibrate -and -not $batch.timingOnly -and $okNames -contains $ref) {
    foreach ($r in $okNames) {
        if ($r -eq $ref) { continue }
        $already = @($st.compares | Where-Object { $_.label -eq "$ref$r" })
        if ($already.Count -gt 0) { $cmpRes += $already[0]; continue }
        $c = Invoke-Compare $job $st.outputs.$ref $st.outputs.$r "$ref$r"
        Add-CompareRecord $st "$ref$r" $c; Save-JobState $st
        $cmpRes += @($st.compares)[-1]
    }
}
$ev = Get-Stage3SystemEventCounts ([datetime]::Parse($batch.startTime))
$hist = @($st.history)
$wall = @($hist | Where-Object { $_.outcome -eq 'ok' } | ForEach-Object { [double]$_.wallSeconds })
$fp = $null
if ($okNames.Count -gt 0) { $fp = Read-Json (Join-Path (Split-Path $st.outputs.($okNames[0])) 'fingerprint.json') }
$acc = [ordered]@{
    batchId = $BatchId; startTime = $batch.startTime; endTime = (Get-Date).ToString('s')
    recType = $job.recType; jobId = $job.id; replicasRequested = $names.Count
    replicasOk = $okNames.Count; wallSecondsSuccessful = $wall; medianWallSeconds = (Get-Median $wall)
    crashes = @($hist | Where-Object { $_.outcome -in @('crash', 'incomplete', 'failed', 'fingerprint_mismatch') }).Count
    timeouts = @($hist | Where-Object { $_.outcome -eq 'timeout' }).Count
    thermalAborts = @($hist | Where-Object { $_.outcome -eq 'thermal_abort' }).Count
    systemEvents = $ev
    compares = $cmpRes
    fingerprint = $fp
    configSnapshot = [ordered]@{ Threads = $cfg.Threads; MklCbwr = $cfg.MklCbwr; MatlabExe = $cfg.MatlabExe; ProcessorStateMaxPct = $cfg.ProcessorStateMaxPct; configSha256 = $cfg._Sha256 }
}
$reasons = @()
if ($Mode -eq 'Acceptance' -and $batch.timingOnly) {
    $acc.kind = 'timing'; $acc.verdict = 'TIMING_ONLY'
} elseif ($Mode -eq 'BurnIn' -and $batch.calibrate) {
    $acc.kind = 'burnin_calibration'
    $lg = Join-Path (Split-Path $st.outputs.A) 'job.log'
    $it = @(Select-String -LiteralPath $lg -Pattern 'burn-in iteration (\d+)/(\d+): D5 ([0-9.]+) s, GEMM ([0-9.]+) s' | ForEach-Object { $g = $_.Matches[0].Groups; [pscustomobject]@{ i = [int]$g[1].Value; d5 = [double]$g[3].Value; gemm = [double]$g[4].Value } })
    $acc.iterationTimes = $it
    $acc.meanD5Seconds = ($it | Measure-Object d5 -Average).Average
    $acc.meanGemmSeconds = ($it | Measure-Object gemm -Average).Average
    $acc.meanIterationSeconds = $acc.meanD5Seconds + $acc.meanGemmSeconds
    $acc.suggestedIterationsFor60Min = [int][math]::Round(3600 / $acc.meanIterationSeconds)
    $acc.verdict = if ($st.outputs.A) { 'CALIBRATED' } else { 'FAILED' }
} else {
    $acc.kind = if ($Mode -eq 'BurnIn') { 'burnin' } else { 'acceptance' }
    if ($okNames.Count -ne $names.Count) { $reasons += "$($names.Count - $okNames.Count) replica(s) did not finish with exit code 0 and output" }
    if ($acc.crashes -gt 0) { $reasons += "$($acc.crashes) crash(es)/failed attempt(s)" }
    if ($acc.timeouts -gt 0) { $reasons += "$($acc.timeouts) timeout(s)" }
    if ($acc.thermalAborts -gt 0) { $reasons += "$($acc.thermalAborts) thermal abort(s)" }
    if ($ev.AppError1000_MATLAB -gt 0) { $reasons += "$($ev.AppError1000_MATLAB) Application Error 1000 event(s) for MATLAB.exe" }
    if ($ev.KernelPower41 -gt 0 -or $ev.BugCheck1001 -gt 0) { $reasons += 'kernel crash event(s)' }
    if (@($cmpRes | Where-Object { -not $_.equal }).Count -gt 0) { $reasons += 'output(s) differ from the reference replica' }
    if (@($cmpRes | Where-Object { $_.inconsistent }).Count -gt 0) { $reasons += 'compare_inconsistent event(s)' }
    $cmpCrash = @($cmpRes | Where-Object { $_.reason }).Count
    if ($cmpCrash -gt 0) { $acc.crashes += $cmpCrash; $reasons += "$cmpCrash compare process crash(es), counted as MATLAB crashes" }
    if (@($hist | Where-Object { $_.outcome -eq 'fingerprint_mismatch' }).Count -gt 0) { $reasons += 'fingerprint mismatch' }
    if ($Mode -eq 'BurnIn' -and $okNames.Count -eq 2) {
        $cj = Read-Json @($st.compares)[-1].files[-1]
        $acc.burnin = [ordered]@{
            withinMismatch = [ordered]@{ A = $cj.within_mismatch_X; B = $cj.within_mismatch_Y }
            iterationsDiffering = $cj.iterations_differing
            finalEqual = [bool]$cj.equal
        }
        $wm = [int]$cj.within_mismatch_X.d5 + [int]$cj.within_mismatch_X.gemm + [int]$cj.within_mismatch_Y.d5 + [int]$cj.within_mismatch_Y.gemm
        $xm = [int]$cj.iterations_differing.d5 + [int]$cj.iterations_differing.gemm
        if ($wm -gt 0) { $reasons += "$wm within-process mismatch(es)" }
        if ($xm -gt 0) { $reasons += "$xm iteration hash mismatch(es) A vs B" }
    }
    $acc.verdict = if ($reasons.Count -eq 0) { 'PASS' } else { 'FAIL' }
}
$acc.failReasons = $reasons
Write-JsonAtomic (Join-Path $batchDir 'acceptance.json') $acc
$batch.status = 'DONE'; $batch.endTime = (Get-Date).ToString('s'); Save-Batch
Add-Journal $batchDir 'batch_end' -Detail "verdict $($acc.verdict) $($reasons -join '; ')"
& (Join-Path $infra 'Write-Stage3Summary.ps1') -BatchDir $batchDir -Config $Config
Remove-Item -LiteralPath $lockFile -ErrorAction SilentlyContinue
if ($acc.verdict -in @('FAIL', 'FAILED')) { exit 4 }                                        # lets a chained command stop
exit 0
