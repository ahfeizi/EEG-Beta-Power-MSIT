<#
.SYNOPSIS
  Fake HWiNFO CSV logger for the runner tests. Writes a header like HWiNFO's (quoted names, two
  "CPU Package [degC]" columns, trailing comma) and one row per second, in code page 1252.
  Behaviour is switched through a JSON control file read every second:
    write      (bool)  append rows (false = log goes stale)
    temp       (num)   CPU Package value of new rows
    extraField (bool)  rows carry one extra field (as after a mid-log HWiNFO column insertion)
    header     'normal' | 'changed'   'changed' rewrites the file with an extra header column
    restart    (int)   when it increases, the log is restarted: file rewritten with the normal header
    quit       (bool)  stop the writer
#>
param([Parameter(Mandatory = $true)][string]$Csv, [Parameter(Mandatory = $true)][string]$Control)
$enc = [System.Text.Encoding]::GetEncoding(1252)
$deg = [char]0xB0
$hdrNormal = 'Date,Time,"Virtual Memory Committed [MB]","CPU Package [' + $deg + 'C]","Core Max [' + $deg + 'C]","CPU Package [' + $deg + 'C]","CPU Package Power [W]",'
$hdrChanged = 'Date,Time,"Virtual Memory Committed [MB]","CPU Package [' + $deg + 'C]","Core Max [' + $deg + 'C]","CPU Package [' + $deg + 'C]","CPU Package Power [W]","iGPU VID [V]",'
function New-Log([string]$Header) { [System.IO.File]::WriteAllText($Csv, $Header + "`n", $enc) }
New-Log $hdrNormal
$state = 'normal'; $restarts = 0
while ($true) {
    try { $c = Get-Content -LiteralPath $Control -Raw | ConvertFrom-Json } catch { Start-Sleep -Milliseconds 200; continue }
    if ($c.quit) { break }
    if ($c.header -eq 'changed' -and $state -ne 'changed') { New-Log $hdrChanged; $state = 'changed' }
    if ([int]$c.restart -gt $restarts) { $restarts = [int]$c.restart; New-Log $hdrNormal; $state = 'normal' }
    if ($c.write) {
        $now = Get-Date
        $t = [double]$c.temp
        $f = @($now.ToString('d.M.yyyy'), ('{0}:{1:D2}:{2}.{3:D3}' -f $now.Hour, $now.Minute, $now.Second, $now.Millisecond), '8000',
               $t.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture), ($t - 1).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture),
               ($t - 2).ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture), '18.2')
        if ($state -eq 'changed') { $f += '0.9' }
        if ($c.extraField) { $f += '0.8' }
        [System.IO.File]::AppendAllText($Csv, (($f -join ',') + ",`n"), $enc)
    }
    Start-Sleep -Seconds 1
}
