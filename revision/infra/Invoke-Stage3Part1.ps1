<#
.SYNOPSIS
  Stage 3 part 1 (S3a-P1). Serial and resumable with the same command; log <EegOutRoot>\stage3_runs\s3p1.log.
    1. chain s3p1 (S3a-INF-1-amend2): timing runs on sub-06 MSIT+ and sub-06 rest (3 replicas each),
       timeouts_s3p1.json, then the A/B batch s3p1_1 (78 recordings; replica B deleted after A = B);
    2. export: for every verified (or flagged) recording, a hard link
       <EegOutRoot>\stage3_part1\<sub>_task-<task>_s3p1.set -> its canonical output (same volume, no extra
       space), and <EegOutRoot>\stage3_part1\manifest.tsv (file, bytes, SHA-256, canonical path). An existing
       link is kept only if it is the same content (SHA-256); nothing is overwritten.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Invoke-Stage3Part1.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File Invoke-Stage3Part1.ps1 -BatchId s3p1_2 -Only sub-13_rest,sub-13_msit
#>
param([string]$BatchId = 's3p1_1', [string[]]$Only, [string]$Config)
$ErrorActionPreference = 'Stop'
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'runner_config.psd1' }
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$runs = Join-Path $cfg.EegOutRoot 'stage3_runs'
$log = Join-Path $runs 's3p1.log'
$exp = Join-Path $cfg.EegOutRoot 'stage3_part1'
function Say([string]$Msg) { $l = '{0} {1}' -f (Get-Date).ToString('s'), $Msg; [System.IO.File]::AppendAllText($log, "$l`r`n"); Write-Host $l }
function Get-Sha([string]$F) { (Get-FileHash -LiteralPath $F -Algorithm SHA256).Hash.ToLower() }

Say "Stage 3 part 1, batch $BatchId (pid $PID)"
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })   # -File passes a comma list as one string
if ($BatchId -eq 's3p1_1') {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Invoke-Stage3JobTypeChain.ps1'),
           '-Type', 's3p1', '-Name', 's3p1', '-TimingJobs', 'sub-06_msit,sub-06_rest', '-BatchId', 's3p1_1', '-Config', $Config)
} else {
    # a later part-1 batch (S3a-P1-amend2): -Only recordings, with the timeouts of the s3p1 chain
    if (-not $Only) { Say "STOPPED: batch $BatchId needs -Only"; exit 3 }
    $jl = Join-Path $runs "jobs_$BatchId.json"
    if (-not (Test-Path $jl)) {
        & (Join-Path $PSScriptRoot 'New-Stage3JobList.ps1') -Type s3p1 -Out $jl -Only $Only -Config $Config | Out-Host
        Say "job list written: $jl ($((Read-JsonArray $jl).Count) jobs)"
    }
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Invoke-Stage3Batch.ps1'), '-Config', $Config,
           '-Mode', 'Batch', '-BatchId', $BatchId, '-JobList', $jl, '-JobTimeouts', (Join-Path $runs 'timeouts_s3p1.json'))
}
& powershell.exe @a | Out-Host
$c = $LASTEXITCODE
$bd = Join-Path $runs $BatchId
$bf = Join-Path $bd 'batch.json'
if (-not (Test-Path $bf)) { Say "STOPPED: exit $c, no batch $BatchId"; exit 3 }
$b = Read-Json $bf
if ($b.status -eq 'RUNNING') { Say "STOPPED: exit $c, batch $BatchId still RUNNING (resume with the same command)"; exit 3 }
Say "$BatchId ended: status $($b.status) $($b.stopReason)"

if (-not (Test-Path $exp)) { New-Item -ItemType Directory -Path $exp | Out-Null }
$rows = New-Object System.Collections.Generic.List[string]
$n = @{ linked = 0; kept = 0; skipped = 0 }
foreach ($sf in Get-ChildItem (Join-Path $bd 'state') -Filter *.json | Sort-Object Name) {
    $st = Read-Json $sf.FullName
    if ($st.status -notin @('verified', 'flagged')) { $n.skipped++; Say "not exported: $($st.id) ($($st.status))"; continue }
    $src = $st.canonical.path
    if ((Get-Sha $src) -ne $st.canonical.sha256) { Say "STOPPED: $($st.id) canonical output does not match its SHA-256"; exit 3 }
    $dst = Join-Path $exp (($st.id -replace '_(rest|msit)$', '_task-$1') + '_s3p1.set')
    if (Test-Path -LiteralPath $dst) {
        if ((Get-Sha $dst) -ne $st.canonical.sha256) { Say "STOPPED: $dst exists with other content"; exit 3 }
        $n.kept++
    } else {
        New-Item -ItemType HardLink -Path $dst -Target $src | Out-Null
        $n.linked++
    }
    $rows.Add(("{0}`t{1}`t{2}`t{3}" -f (Split-Path $dst -Leaf), (Get-Item -LiteralPath $dst).Length, $st.canonical.sha256, $src))
}
$man = Join-Path $exp $(if ($BatchId -eq 's3p1_1') { 'manifest.tsv' } else { "manifest_$BatchId.tsv" })   # one manifest per batch
$text = "file`tbytes`tsha256`tcanonical`r`n" + (($rows | ForEach-Object { $_ }) -join "`r`n") + "`r`n"
if ((Test-Path $man) -and ((Get-Content -LiteralPath $man -Raw) -ne $text)) { Say "STOPPED: $man exists with other content (not overwritten)"; exit 3 }
if (-not (Test-Path $man)) { [System.IO.File]::WriteAllText($man, $text) }
Say "export: $($rows.Count) .set files ($($n.linked) new links, $($n.kept) existing), $($n.skipped) recordings not exported; manifest $man"
Say "part 1 batch $BatchId done"
exit 0
