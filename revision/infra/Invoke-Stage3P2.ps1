<#
.SYNOPSIS
  Stage 3 part 2 (S3a-P2, S3a-P2-impl). Serial and resumable with the same command; log
  <EegOutRoot>\stage3_runs\p2.log. One chain per -Name:
    job list jobs_<Name>.json (type p2; -Only restricts it, e.g. the D14 subjects) ->
    timing run on -TimingJob (3 replicas, per-replica timeout 3000 s; the chain STOPS if any replica takes
    longer than 2700 s = 45 min or times out: Amirhossein's rule for this laptop) ->
    timeouts_<Name>.json -> A/B batch -BatchId -> export: hard link <EegOutRoot>\stage3_part2\<sub>_s3p2.mat to each
    verified bundle, and manifest_<BatchId>.tsv (never overwritten).
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Invoke-Stage3P2.ps1 -Name p2d14 -BatchId p2_d14 -Only sub-25,sub-08,sub-15 -TimingJob sub-25
#>
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$BatchId,
    [Parameter(Mandatory = $true)][string]$TimingJob,
    [string[]]$Only,
    [string]$Config
)
$ErrorActionPreference = 'Stop'
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'runner_config.psd1' }
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$runs = Join-Path $cfg.EegOutRoot 'stage3_runs'
$log = Join-Path $runs 'p2.log'
$exp = Join-Path $cfg.EegOutRoot 'stage3_part2'
function Say([string]$Msg) { $l = '{0} {1}' -f (Get-Date).ToString('s'), $Msg; [System.IO.File]::AppendAllText($log, "$l`r`n"); Write-Host $l }
function Get-Sha([string]$F) { (Get-FileHash -LiteralPath $F -Algorithm SHA256).Hash.ToLower() }
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

Say "Stage 3 part 2: chain $Name, batch $BatchId, only $($Only -join ',') (pid $PID)"
$jl = Join-Path $runs "jobs_$Name.json"
if (-not (Test-Path $jl)) {
    $a = @{ Type = 'p2'; Out = $jl; Config = $Config }
    if ($Only) { $a.Only = $Only }
    & (Join-Path $PSScriptRoot 'New-Stage3JobList.ps1') @a | Out-Host
    Say "job list written: $jl ($((Read-JsonArray $jl).Count) jobs)"
}
$a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Invoke-Stage3JobTypeChain.ps1'),
       '-Type', 'p2', '-Name', $Name, '-TimingJobs', $TimingJob, '-BatchId', $BatchId, '-TimingTimeoutS', '3000',
       '-MaxTimingSeconds', '2700', '-Config', $Config)
& powershell.exe @a | Out-Host
$c = $LASTEXITCODE
$bf = Join-Path $runs "$BatchId\batch.json"
if (-not (Test-Path $bf) -or (Read-Json $bf).status -eq 'RUNNING') { Say "STOPPED: chain $Name exit $c (see chain_$Name.log)"; exit 3 }
$b = Read-Json $bf
Say "$BatchId ended: status $($b.status) $($b.stopReason)"
if (-not (Test-Path $exp)) { New-Item -ItemType Directory -Path $exp | Out-Null }
$rows = New-Object System.Collections.Generic.List[string]
foreach ($sf in Get-ChildItem (Join-Path $runs "$BatchId\state") -Filter *.json | Sort-Object Name) {
    $st = Read-Json $sf.FullName
    if ($st.status -notin @('verified', 'flagged')) { Say "not exported: $($st.id) ($($st.status))"; continue }
    if ((Get-Sha $st.canonical.path) -ne $st.canonical.sha256) { Say "STOPPED: $($st.id) canonical output does not match its SHA-256"; exit 3 }
    $dst = Join-Path $exp "$($st.id)_s3p2.mat"
    if (Test-Path -LiteralPath $dst) {
        if ((Get-Sha $dst) -ne $st.canonical.sha256) { Say "STOPPED: $dst exists with other content"; exit 3 }
    } else { New-Item -ItemType HardLink -Path $dst -Target $st.canonical.path | Out-Null }
    $rows.Add(("{0}`t{1}`t{2}`t{3}" -f (Split-Path $dst -Leaf), (Get-Item -LiteralPath $dst).Length, $st.canonical.sha256, $st.canonical.path))
}
$man = Join-Path $exp "manifest_$BatchId.tsv"
$text = "file`tbytes`tsha256`tcanonical`r`n" + (($rows | ForEach-Object { $_ }) -join "`r`n") + "`r`n"
if ((Test-Path $man) -and ((Get-Content -LiteralPath $man -Raw) -ne $text)) { Say "STOPPED: $man exists with other content"; exit 3 }
if (-not (Test-Path $man)) { [System.IO.File]::WriteAllText($man, $text) }
Say "export: $($rows.Count) bundles; manifest $man"
Say "part 2 batch $BatchId done"
exit 0
