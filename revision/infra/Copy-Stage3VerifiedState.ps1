<#
.SYNOPSIS
  Q9 rule of S3a-INF-1 sec. 5 / sec. 7: after a kernel-crash stop, a new batch carries over the
  verified (or flagged) recordings of the old batch whose canonical output still has its recorded
  SHA-256 and loads. Any other recording stays pending in the new batch.
#>
param(
    [Parameter(Mandatory = $true)][string]$Config,
    [Parameter(Mandatory = $true)][string]$FromBatch,
    [Parameter(Mandatory = $true)][string]$ToBatch
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$runs = Join-Path $cfg.EegOutRoot 'stage3_runs'
$from = Join-Path $runs $FromBatch; $to = Join-Path $runs $ToBatch
$cand = @()
foreach ($sf in @(Get-ChildItem -LiteralPath (Join-Path $from 'state') -Filter '*.json')) {
    $st = Read-Json $sf.FullName
    if ($st.status -in @('verified', 'flagged') -and $st.canonical -and (Test-Path $st.canonical.path)) {
        if ((Get-Sha256File $st.canonical.path) -eq $st.canonical.sha256) { $cand += $st }
        else { Add-Journal $to 'carry_over_rejected' $st.id -Detail 'SHA-256 differs from the value recorded at verification' }
    } elseif ($st.status -in @('verified', 'flagged')) { Add-Journal $to 'carry_over_rejected' $st.id -Detail 'canonical output missing' }
}
if ($cand.Count -eq 0) { return }
$list = Join-Path $to 'carry_over_list.txt'
[System.IO.File]::WriteAllText($list, (($cand | ForEach-Object { $_.canonical.path }) -join "`n"))
$js = Join-Path $to 'carry_over_loadcheck.json'
$r = Invoke-MatlabSimple $cfg "addpath('$PSScriptRoot'); stage3_loadcheck('$list', '$js')" "$js.log" $to 900
if ($r.ExitCode -ne 0 -or -not (Test-Path $js)) { Add-Journal $to 'carry_over_rejected' -Detail 'load-check process failed; nothing carried over'; return }
$loads = @{}; foreach ($x in (Read-JsonArray $js)) { $loads[$x.file] = [bool]$x.loads }
foreach ($st in $cand) {
    if ($loads[$st.canonical.path]) {
        $st.flags = @($st.flags) + "carried_over_from_$FromBatch"
        Write-JsonAtomic (Join-Path $to "state\$($st.id).json") $st
        Add-Journal $to 'carried_over' $st.id -Detail "from $FromBatch; SHA-256 and load check passed"
    } else { Add-Journal $to 'carry_over_rejected' $st.id -Detail 'canonical output does not load' }
}
