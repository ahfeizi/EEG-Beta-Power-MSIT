# Stage3Runner.psm1 -- helper functions of the S3a-INF-1 runner (Windows PowerShell 5.1).
# Decision log: S3a-INF-1 and S3a-INF-1-clar1. Used by Invoke-Stage3Batch.ps1,
# Write-Stage3Summary.ps1 and Get-Stage3SystemEvents.ps1. ASCII only (PowerShell 5.1 reads
# BOM-less files as ANSI). HWiNFO functions removed by S3a-INF-1-amend1.

Set-StrictMode -Version 2.0
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------- files, JSON, hashes, journal
function Get-Sha256File([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Sha256Text([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $b = $sha.ComputeHash($script:Utf8NoBom.GetBytes($Text))
    -join ($b | ForEach-Object { $_.ToString('x2') })
}

function Write-TextAtomic([string]$Path, [string]$Text) {
    # S3a-INF-1 sec. 5: write *.tmp, then [IO.File]::Replace (or a first-time move);
    # amend1: *.tmp is flushed to disk first, so a kernel crash cannot leave a renamed empty file
    $tmp = "$Path.tmp"
    $b = $script:Utf8NoBom.GetBytes($Text)
    $fs = New-Object System.IO.FileStream($tmp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try { $fs.Write($b, 0, $b.Length); $fs.Flush($true) } finally { $fs.Dispose() }
    if (Test-Path -LiteralPath $Path) { [System.IO.File]::Replace($tmp, $Path, [NullString]::Value) }
    else { [System.IO.File]::Move($tmp, $Path) }
}

function Write-JsonAtomic([string]$Path, $Object) {
    Write-TextAtomic $Path ($Object | ConvertTo-Json -Depth 30)
}

function Read-Json([string]$Path) {
    [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom) | ConvertFrom-Json
}

function Read-JsonArray([string]$Path) {
    # PS 5.1: ConvertFrom-Json emits a JSON array as ONE object; ForEach-Object unrolls it
    , @(Read-Json $Path | ForEach-Object { $_ })
}

function Add-Journal([string]$BatchDir, [string]$Event, [string]$Job = '', [string]$Replica = '',
                     $Attempt = '', $ProcId = '', $ExitCode = '', [string]$Detail = '') {
    # append-only journal.csv, one line per event; each append opens, writes and closes the file
    $f = Join-Path $BatchDir 'journal.csv'
    if (-not (Test-Path -LiteralPath $f)) {
        [System.IO.File]::AppendAllText($f, "time,event,job,replica,attempt,pid,exit_code,detail`n", $script:Utf8NoBom)
    }
    $d = ($Detail -replace '[\r\n,]', ' ')
    $line = '{0},{1},{2},{3},{4},{5},{6},{7}' -f (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fff'), $Event, $Job, $Replica, $Attempt, $ProcId, $ExitCode, $d
    [System.IO.File]::AppendAllText($f, "$line`n", $script:Utf8NoBom)
    Write-Host $line
}

function Read-Journal([string]$BatchDir) {
    # a truncated last line after a crash is ignored (S3a-INF-1 sec. 5)
    $f = Join-Path $BatchDir 'journal.csv'
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    $lines = [System.IO.File]::ReadAllLines($f, $script:Utf8NoBom)
    $rows = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $p = $lines[$i].Split(',')
        if ($p.Count -ne 8) { continue }
        $rows += [pscustomobject]@{ time = $p[0]; event = $p[1]; job = $p[2]; replica = $p[3]; attempt = $p[4]; pid = $p[5]; exit_code = $p[6]; detail = $p[7] }
    }
    $rows
}

# ---------------------------------------------------------------- decision-log entry hash
function Get-LogEntryHash([string]$LogFile, [string]$Id) {
    # same rule as stage3_log_entry.m (S3a-D5-0-amend1): the single line starting with
    # "## <Id> " + non-space; text up to the next line starting with "## "; CR removed; SHA-256 of UTF-8
    $raw = [System.IO.File]::ReadAllText($LogFile, $script:Utf8NoBom)
    $m = [regex]::Matches($raw, '(?m)^## ' + [regex]::Escape($Id) + ' \S')
    if ($m.Count -ne 1) { throw "log entry '$Id': $($m.Count) heading lines match, expected 1" }
    $rest = $raw.Substring($m[0].Index)
    $n = [regex]::Match($rest.Substring(2), "`n## ")
    if ($n.Success) { $rest = $rest.Substring(0, $n.Index + 2) }        # = MATLAB rest(1:b+1)
    Get-Sha256Text ($rest -replace "`r", '')
}

# ---------------------------------------------------------------- configuration
function Import-Stage3Config([string]$Path) {
    $cfg = Import-PowerShellDataFile -LiteralPath $Path
    $cfg['_Path'] = (Resolve-Path -LiteralPath $Path).Path
    $cfg['_Sha256'] = Get-Sha256File $Path
    $cfg
}

# ---------------------------------------------------------------- system checks
function Get-Stage3SystemEventCounts([datetime]$Since, [datetime]$Until = (Get-Date)) {
    # S3a-INF-1 sec. 7 (read-only queries of the Windows event logs)
    $q = {
        param($log, $provider, $ids)
        $h = @{ LogName = $log; ProviderName = $provider; StartTime = $Since; EndTime = $Until }
        if ($ids) { $h['Id'] = $ids }
        @(Get-WinEvent -FilterHashtable $h -ErrorAction SilentlyContinue)
    }
    $whea = @(& $q 'System' 'Microsoft-Windows-WHEA-Logger' $null)       # @(): an empty result stays an array
    $bug = @(& $q 'System' 'Microsoft-Windows-WER-SystemErrorReporting' 1001)
    $kp = @(& $q 'System' 'Microsoft-Windows-Kernel-Power' 41)
    $app = @(& $q 'Application' 'Application Error' 1000 | Where-Object { $_.Message -match 'MATLAB\.exe' })
    [pscustomobject]@{ Since = $Since.ToString('s'); Until = $Until.ToString('s'); WHEA = $whea.Count; BugCheck1001 = $bug.Count; KernelPower41 = $kp.Count; AppError1000_MATLAB = $app.Count }
}

function Get-MaxProcessorState {
    # read-only: powercfg of the active scheme, PROCTHROTTLEMAX (percent) for AC and DC
    $out = & powercfg /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 2>&1 | Out-String
    $ac = [regex]::Match($out, 'Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)')
    $dc = [regex]::Match($out, 'Current DC Power Setting Index:\s*0x([0-9a-fA-F]+)')
    if (-not ($ac.Success -and $dc.Success)) { return $null }
    [pscustomobject]@{ AC = [Convert]::ToInt32($ac.Groups[1].Value, 16); DC = [Convert]::ToInt32($dc.Groups[1].Value, 16) }
}

function Get-FreeGB([string]$Path) {
    $root = [System.IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $Path).Path)
    [math]::Round((New-Object System.IO.DriveInfo($root)).AvailableFreeSpace / 1GB, 3)
}

# ---------------------------------------------------------------- MATLAB processes
function Start-MatlabProcess($Cfg, [string]$Command, [string]$LogFile, [string]$WorkDir) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Cfg.MatlabExe
    $psi.Arguments = '-batch "' + $Command + '" -logfile "' + $LogFile + '"'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $WorkDir
    $psi.EnvironmentVariables['MKL_CBWR'] = $Cfg.MklCbwr          # child process only
    # own stdout/stderr pipes, drained asynchronously and discarded (-logfile keeps the output);
    # an inherited, unwritable console handle made MATLAB print "Error on flush." and exit non-zero
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.BeginOutputReadLine()
    $p.BeginErrorReadLine()
    $p
}

function Stop-ProcessTree([int]$ProcId) {
    & taskkill /PID $ProcId /T /F 2>&1 | Out-Null
}

function Test-MatlabPid([int]$ProcId) {
    $p = Get-Process -Id $ProcId -ErrorAction SilentlyContinue
    ($null -ne $p) -and ($p.ProcessName -eq 'MATLAB')
}

function Invoke-MatlabSimple($Cfg, [string]$Command, [string]$LogFile, [string]$WorkDir, [int]$TimeoutS) {
    # short helper processes (compare, load check, fingerprint): no gate, timeout only
    $p = Start-MatlabProcess $Cfg $Command $LogFile $WorkDir
    if (-not $p.WaitForExit($TimeoutS * 1000)) { Stop-ProcessTree $p.Id; return [pscustomobject]@{ ExitCode = -1; TimedOut = $true; Pid = $p.Id } }
    [pscustomobject]@{ ExitCode = $p.ExitCode; TimedOut = $false; Pid = $p.Id }
}

Export-ModuleMember -Function *
