<#
.SYNOPSIS
  Summary writer of S3a-INF-1 sec. 9: summary.csv (one row per recording, or per replica in
  Acceptance/BurnIn modes) and summary.txt (header) in the batch folder, copied to
  <outRoot>\stage3\runs\<BatchId>_summary.csv|txt. Written once, at batch end or stop.
#>
param(
    [Parameter(Mandatory = $true)][string]$BatchDir,
    [Parameter(Mandatory = $true)][string]$Config
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$batch = Read-Json (Join-Path $BatchDir 'batch.json')
$states = @(Get-ChildItem -LiteralPath (Join-Path $BatchDir 'state') -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object { Read-Json $_.FullName })
$accFile = Join-Path $BatchDir 'acceptance.json'
$acc = if (Test-Path $accFile) { Read-Json $accFile } else { $null }

function Add-CompareColumns($Row, [string]$Label, $Cmp) {
    $Row["${Label}_equal"] = $Cmp.equal
    $Row["${Label}_inconsistent"] = $Cmp.inconsistent
    if (@($Cmp.files).Count -gt 0 -and (Test-Path @($Cmp.files)[-1])) {
        $j = Read-Json @($Cmp.files)[-1]
        foreach ($f in @($j.fields)) {
            $Row["${Label}_$($f.field)_equal"] = $f.equal
            $Row["${Label}_$($f.field)_ndiff"] = $f.n_diff
            $Row["${Label}_$($f.field)_maxabs"] = $f.max_abs_diff
        }
    }
}

$rows = New-Object System.Collections.Generic.List[object]
if ($batch.mode -eq 'Batch') {
    foreach ($st in $states) {
        $h = @($st.history)
        $r = [ordered]@{
            recording = $st.id; final_state = $st.status
            attempts_A = $st.attempts.A; attempts_B = $st.attempts.B; attempts_C = $st.attempts.C
            crashes = @($h | Where-Object { $_.outcome -in @('crash', 'incomplete') }).Count
            other_failed = @($h | Where-Object { $_.outcome -in @('failed', 'fingerprint_mismatch') }).Count
            timeouts = @($h | Where-Object { $_.outcome -eq 'timeout' }).Count
            job_seconds = ($h | Where-Object { $null -ne $_.wallSeconds } | Measure-Object wallSeconds -Sum).Sum
            interrupted = @($h | Where-Object { $_.outcome -eq 'interrupted' }).Count
            app_errors_1000 = ($h | Measure-Object appErrors1000 -Sum).Sum
            flags = (@($st.flags) -join ';'); failure_reason = $st.failureReason
            canonical_replica = $(if ($st.canonical) { $st.canonical.replica } else { '' })
            canonical_sha256 = $(if ($st.canonical) { $st.canonical.sha256 } else { '' })
            canonical_path = $(if ($st.canonical) { $st.canonical.path } else { '' })
        }
        foreach ($c in @($st.compares)) { Add-CompareColumns $r $c.label $c }
        $rows.Add([pscustomobject]$r)
    }
} else {
    $st = $states | Select-Object -First 1
    if ($st) {
        foreach ($h in @($st.history)) {
            $r = [ordered]@{ replica = $h.replica; attempt = $h.attempt; outcome = $h.outcome; exit_code = $h.exitCode; wall_s = $h.wallSeconds; app_errors_1000 = $h.appErrors1000; start = $h.start; end = $h.end; pid = $h.pid; reason = $h.reason }
            foreach ($c in @($st.compares | Where-Object { $_.label -like "*$($h.replica)" -and $_.label.Length -gt $h.replica.Length })) { Add-CompareColumns $r 'vs_ref' $c }
            $rows.Add([pscustomobject]$r)
        }
    }
}
# union of columns over rows
$cols = New-Object System.Collections.Generic.List[string]
foreach ($r in $rows) { foreach ($p in $r.PSObject.Properties.Name) { if (-not $cols.Contains($p)) { $cols.Add($p) } } }
$csv = Join-Path $BatchDir 'summary.csv'
if ($rows.Count -gt 0) { $rows | Select-Object -Property $cols.ToArray() | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8 }
else { [System.IO.File]::WriteAllText($csv, "no recordings`n") }

$ev = Get-Stage3SystemEventCounts ([datetime]::Parse($batch.startTime))
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$t = New-Object System.Collections.Generic.List[string]
$t.Add("S3a-INF-1 batch summary"); $t.Add("batch id      : $($batch.batchId)"); $t.Add("mode          : $($batch.mode)")
$t.Add("start / end   : $($batch.startTime) / $($batch.endTime)"); $t.Add("status        : $($batch.status) $($batch.stopReason)")
$t.Add("runner config : $($batch.configPath)  SHA-256 $($batch.configSha256)")
foreach ($p in $batch.entryHashes.PSObject.Properties) { $t.Add(("log entry     : {0} SHA-256 {1}" -f $p.Name, $p.Value)) }
$t.Add(("system events since batch start: WHEA {0}; BugCheck 1001 {1}; Kernel-Power 41 {2}; Application Error 1000 (MATLAB.exe) {3}" -f $ev.WHEA, $ev.BugCheck1001, $ev.KernelPower41, $ev.AppError1000_MATLAB))
# crash rate over every replica attempt of the batch (S3a-INF-1-amend1)
$allH = @($states | ForEach-Object { @($_.history) })
$nCr = @($allH | Where-Object { $_.outcome -in @('crash', 'incomplete') }).Count
$sec = ($allH | Where-Object { $null -ne $_.wallSeconds } | Measure-Object wallSeconds -Sum).Sum
$rate = if ($sec -gt 0) { '{0:N3}' -f ($nCr / ($sec / 3600)) } else { 'n/a' }
$t.Add(("attempts      : {0}; crashed (non-zero exit or incomplete) {1}; job hours {2:N3}; crashes per job-hour {3}; kernel-crash recoveries {4}" -f $allH.Count, $nCr, ($sec / 3600), $rate, $batch.kernelRecoveries))
if ($batch.mode -eq 'Batch') {
    if ($batch.timeoutsFile) { $t.Add("timeouts.json : $($batch.timeoutsFile)  SHA-256 $($batch.timeoutsSha256)") }
    if ($batch.PSObject.Properties.Name -contains 'jobTimeoutsFile' -and $batch.jobTimeoutsFile) { $t.Add("job timeouts  : $($batch.jobTimeoutsFile)  SHA-256 $($batch.jobTimeoutsSha256) (S3a-INF-1-amend2)") }
    $t.Add("timeouts (s)  : $(($batch.timeoutS | ConvertTo-Json -Compress))")
    $t.Add('pre-checks:')
    foreach ($c in @($batch.prechecks)) { $t.Add(("  [{0}] {1}: {2}" -f $(if ($c.ok) { 'ok' } else { 'FAIL' }), $c.check, $c.detail)) }
    $t.Add(("recordings: {0}; " -f $states.Count) + ((@($states | Group-Object status | ForEach-Object { "$($_.Name) $($_.Count)" })) -join '; '))
    $t.Add("recordings with A != B or an inconsistent compare: $($batch.mismatchCount) (no stop; the batch stops at $($cfg.MaxQuarantinedRecordings) quarantined)")
}
if ($acc) {
    $t.Add("kind          : $($acc.kind)   VERDICT: $($acc.verdict)")
    foreach ($x in @($acc.failReasons)) { $t.Add("  reason: $x") }
    $t.Add("replicas ok   : $($acc.replicasOk) / $($acc.replicasRequested); median wall time $($acc.medianWallSeconds) s")
    if ($acc.PSObject.Properties.Name -contains 'meanIterationSeconds') {
        $t.Add(("calibration   : mean D5 block {0:N3} s, mean GEMM block {1:N3} s, mean iteration {2:N3} s, suggested iterations for 60 min: {3}" -f $acc.meanD5Seconds, $acc.meanGemmSeconds, $acc.meanIterationSeconds, $acc.suggestedIterationsFor60Min))
    }
    if ($acc.PSObject.Properties.Name -contains 'burnin' -and $acc.burnin) {
        $b = $acc.burnin
        $t.Add(("burn-in mismatches: within A: D5 {0}, GEMM {1}; within B: D5 {2}, GEMM {3}; A vs B iteration hashes: D5 {4}, GEMM {5}; final results equal: {6}" -f $b.withinMismatch.A.d5, $b.withinMismatch.A.gemm, $b.withinMismatch.B.d5, $b.withinMismatch.B.gemm, $b.iterationsDiffering.d5, $b.iterationsDiffering.gemm, $b.finalEqual))
    }
}
$txt = Join-Path $BatchDir 'summary.txt'
[System.IO.File]::WriteAllText($txt, ($t -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
$dest = Join-Path $cfg.OutRoot 'stage3\runs'
if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
Copy-Item -LiteralPath $csv -Destination (Join-Path $dest "$($batch.batchId)_summary.csv") -Force
Copy-Item -LiteralPath $txt -Destination (Join-Path $dest "$($batch.batchId)_summary.txt") -Force
if ($acc) { Copy-Item -LiteralPath $accFile -Destination (Join-Path $dest "$($batch.batchId)_acceptance.json") -Force }
Write-Host "summary -> $txt ; copy in $dest"
