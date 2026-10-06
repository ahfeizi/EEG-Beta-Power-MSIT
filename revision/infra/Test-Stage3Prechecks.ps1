<#
.SYNOPSIS
  Batch-start pre-checks of S3a-INF-1-clar1 (all must pass; the runner stops otherwise).
  Returns one object per check: check, ok, detail. Read-only, except for one short MATLAB
  process that writes the current environment fingerprint into -WorkDir.
#>
param(
    [Parameter(Mandatory = $true)][string]$Config,
    [Parameter(Mandatory = $true)][string]$JobList,
    [Parameter(Mandatory = $true)][string]$WorkDir
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
$cfg = Import-Stage3Config $Config
$runsRoot = Join-Path $cfg.EegOutRoot 'stage3_runs'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$out = New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Name, [bool]$Ok, [string]$Detail) { $out.Add([pscustomobject]@{ check = $Name; ok = $Ok; detail = $Detail }) }
$jobs = Read-JsonArray $JobList

# 1. acceptance PASS (burn-in, MSIT+ x 11) and rest timing, via timeouts.json with matching hashes
$tf = Join-Path $runsRoot 'timeouts.json'
$t = $null
if (-not (Test-Path $tf)) { Add-Check '1_acceptance' $false "no $tf" }
else {
    $t = Read-Json $tf
    $bad = @($t.sources | Where-Object { -not (Test-Path $_.file) -or (Get-Sha256File $_.file) -ne $_.sha256 })
    $verd = @{}
    foreach ($s in @($t.sources | Where-Object { $_.file -like '*acceptance.json' })) { $a = Read-Json $s.file; $verd[$s.role] = $a.verdict }
    $types = @($jobs | ForEach-Object { $_.recType } | Sort-Object -Unique)
    $missing = @($types | Where-Object { -not ($t.timeoutS.PSObject.Properties.Name -contains $_) })
    $ok = ($bad.Count -eq 0) -and ($verd['burnin'] -eq 'PASS') -and ($verd['msit'] -eq 'PASS') -and ($verd['rest'] -eq 'TIMING_ONLY') -and ($missing.Count -eq 0)
    Add-Check '1_acceptance' $ok ("timeouts.json {0}; source files changed: {1}; burn-in {2}; MSIT+ {3}; rest {4}; recording types without timeout: {5}" -f (Get-Sha256File $tf), $bad.Count, $verd['burnin'], $verd['msit'], $verd['rest'], ($missing -join ' '))
}

# 2. maximum processor state, AC and DC
$ps = Get-MaxProcessorState
if ($null -eq $ps) { Add-Check '2_processor_state' $false 'powercfg output not parsed' }
else { Add-Check '2_processor_state' (($ps.AC -eq $cfg.ProcessorStateMaxPct) -and ($ps.DC -eq $cfg.ProcessorStateMaxPct)) ("AC {0} %, DC {1} %, required {2} %" -f $ps.AC, $ps.DC, $cfg.ProcessorStateMaxPct) }

# 3. verified raw copy on D:, bidsRoot = the copy, post-reboot verify with every file matching
$rc = Split-Path $cfg.VerifiedManifest
$d3 = @()
$ok3 = Test-Path $cfg.VerifiedManifest
$d3 += "verified_manifest.tsv present: $ok3"
$onD = $cfg.RawRoot -like 'D:\*'
$ok3 = $ok3 -and $onD; $d3 += "RawRoot on D: $onD"
$cl = Join-Path $repo 'config_local.m'
$bids = ''
if (Test-Path $cl) { $m = [regex]::Match((Get-Content -LiteralPath $cl -Raw), "p\.bidsRoot\s*=\s*'([^']+)'"); if ($m.Success) { $bids = $m.Groups[1].Value } }
$same = ($bids.TrimEnd('\') -eq $cfg.RawRoot.TrimEnd('\'))
$ok3 = $ok3 -and $same; $d3 += "config_local bidsRoot = RawRoot: $same ($bids)"
$ver = @(Get-ChildItem -LiteralPath $rc -Filter 'verification_*.tsv' -ErrorAction SilentlyContinue | Sort-Object Name)
$copyLog = Join-Path $rc 'copy_log.tsv'
if ($ver.Count -eq 0 -or -not (Test-Path $copyLog)) { $ok3 = $false; $d3 += 'no verification report or copy log' }
else {
    $v = $ver[-1]
    $rows = @(Import-Csv -LiteralPath $v.FullName -Delimiter "`t")
    $nBad = @($rows | Where-Object { $_.status_vs_reference -ne 'MATCH' -or $_.status_vs_copy -ne 'MATCH' }).Count
    $vStart = [datetime]::ParseExact(($v.BaseName -replace '^verification_', ''), 'yyyyMMdd_HHmmss', $null)
    $lastCopy = [datetime]::Parse((@(Import-Csv -LiteralPath $copyLog -Delimiter "`t")[-1]).time)
    $boots = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-General'; Id = 12; StartTime = $lastCopy; EndTime = $vStart } -ErrorAction SilentlyContinue)
    $ok3 = $ok3 -and ($nBad -eq 0) -and ($rows.Count -gt 0) -and ($boots.Count -gt 0)
    $d3 += "verification $($v.Name): $($rows.Count) files, $nBad not matching, SHA-256 $(Get-Sha256File $v.FullName)"
    $d3 += "reboot (Kernel-General 12) between last copy $($lastCopy.ToString('s')) and verify $($vStart.ToString('s')): $($boots.Count)"
    if (Test-Path $cfg.VerifiedManifest) { $d3 += "verified_manifest SHA-256 $(Get-Sha256File $cfg.VerifiedManifest)" }
}
Add-Check '3_raw_copy' $ok3 ($d3 -join '; ')

# 4. configuration and environment fingerprint identical to the passing acceptance
if ($null -eq $t) { Add-Check '4_config_match' $false 'no timeouts.json' }
else {
    $diff = @()
    foreach ($k in @('Threads', 'MklCbwr', 'MatlabExe', 'ProcessorStateMaxPct')) { if ("$($cfg[$k])" -ne "$($t.acceptanceConfig.$k)") { $diff += "$k ($($cfg[$k]) vs $($t.acceptanceConfig.$k))" } }
    $fpDir = Join-Path $WorkDir 'precheck_fingerprint'
    if (-not (Test-Path $fpDir)) { New-Item -ItemType Directory -Path $fpDir | Out-Null }
    $spec = [ordered]@{ jobId = 'precheck'; replica = 'P'; attempt = 1; func = 'stage3_noop'; params = [ordered]@{ jobFunc = $jobs[0].func }
        common = [ordered]@{ seedGlobal = $cfg.SeedGlobal }; paths = @($PSScriptRoot, (Join-Path $repo 'revision\stage3')) + @($cfg.ExtraMatlabPaths)
        threads = $cfg.Threads; seedGlobal = $cfg.SeedGlobal; configSha256 = $cfg._Sha256; testMode = $false
        outFile = (Join-Path $fpDir 'out.mat'); fingerprintFile = (Join-Path $fpDir 'fingerprint.json') }
    $sf = Join-Path $fpDir 'spec.json'; Write-JsonAtomic $sf $spec
    $r = Invoke-MatlabSimple $cfg "addpath('$PSScriptRoot'); stage3_job('$sf')" (Join-Path $fpDir 'job.log') $fpDir 900
    if ($r.ExitCode -ne 0 -or -not (Test-Path $spec.fingerprintFile)) { $diff += "fingerprint process failed (exit $($r.ExitCode))" }
    else {
        $now = Read-Json $spec.fingerprintFile
        foreach ($p in $t.acceptanceFingerprint.PSObject.Properties) {
            if ($p.Name -in @('runner_config_sha256', 'which_jobfunc')) { continue }
            if (($now.($p.Name) | ConvertTo-Json -Compress) -ne ($p.Value | ConvertTo-Json -Compress)) { $diff += "fingerprint.$($p.Name)" }
        }
    }
    Add-Check '4_config_match' ($diff.Count -eq 0) ($(if ($diff.Count) { 'differs: ' + ($diff -join ', ') } else { 'Threads, MklCbwr, MatlabExe, ProcessorStateMaxPct and the environment fingerprint equal the acceptance' }))
}

# 5. acceptance runs started after the S3a-HW-1 hardware change
if ($null -eq $t) { Add-Check '5_acceptance_after_HW1' $false 'no timeouts.json' }
else {
    $bound = [datetime]::Parse($cfg.HardwareChangeNotBefore, [System.Globalization.CultureInfo]::InvariantCulture)
    $late = @('burnin', 'msit', 'rest' | Where-Object { [datetime]::Parse($t.acceptanceStart.$_) -gt $bound })
    Add-Check '5_acceptance_after_HW1' ($late.Count -eq 3) ("starts burn-in {0}, MSIT+ {1}, rest {2}; bound {3}" -f $t.acceptanceStart.burnin, $t.acceptanceStart.msit, $t.acceptanceStart.rest, $cfg.HardwareChangeNotBefore)
}
$out.ToArray()
