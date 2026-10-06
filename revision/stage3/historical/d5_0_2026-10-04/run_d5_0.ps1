# Driver for stage3_d5_0_line_noise.m: one fresh MATLAB process per recording (a long single session
# crashed with heap corruption 0xc0000374; the crash did not reproduce on the same recording alone).
# Results per recording are cached by the MATLAB script; this only changes how it is launched.
$wd    = "C:\Users\Amirhossein\Desktop\Prof. Nasrabadi\github\eeg-beta-project\revision\stage3"
$out   = "C:\Users\Amirhossein\Desktop\Prof. Nasrabadi\Revision_Output\stage3\d5_0"
$cache = Join-Path $out "per_recording"
$log   = Join-Path $out "driver_log.txt"
Set-Location $wd
"driver start $(Get-Date -Format s)" | Out-File $log -Encoding utf8
foreach ($i in 1..42) {
  foreach ($t in @("rest", "msit")) {
    $r = "sub-{0:D2}_{1}" -f $i, $t
    foreach ($try in 1..2) {
      if (Test-Path (Join-Path $cache "$r.mat")) { break }
      & matlab -batch "onlyRecordings={'$r'}; stage3_d5_0_line_noise" *> (Join-Path $out "log_$r.txt")
      $ok = Test-Path (Join-Path $cache "$r.mat")
      "$(Get-Date -Format s) $r try $try exit $LASTEXITCODE ok $ok" | Out-File $log -Append -Encoding utf8
    }
  }
}
& matlab -batch "stage3_d5_0_line_noise" *> (Join-Path $out "log_assemble.txt")
"assemble exit $LASTEXITCODE; run_info exists: $(Test-Path (Join-Path $out 'run_info.txt'))" | Out-File $log -Append -Encoding utf8
"driver end $(Get-Date -Format s)" | Out-File $log -Append -Encoding utf8
