<#
.SYNOPSIS
  System-event check of S3a-INF-1 sec. 7 (read-only): counts since -Since (default: 24 h ago) of
  WHEA-Logger events (all IDs), BugCheck (WER-SystemErrorReporting 1001), Kernel-Power 41 and
  Application Error 1000 events for MATLAB.exe.
.EXAMPLE
  powershell -NoProfile -File Get-Stage3SystemEvents.ps1 -Since '2026-10-06T19:40:46'
#>
param([datetime]$Since = (Get-Date).AddHours(-24), [datetime]$Until = (Get-Date))
Import-Module (Join-Path $PSScriptRoot 'Stage3Runner.psm1') -Force
Get-Stage3SystemEventCounts $Since $Until | Format-List
