# install.ps1 - register autostart for the Whale Harness Launcher.
# Run as Administrator to register the "At logon" scheduled task (earliest
# startup order); without admin, registers an HKCU Run entry (still works).
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$vbs = Join-Path $dir 'src\launcher.vbs'
$wscript = Join-Path $env:windir 'System32\wscript.exe'

if (-not (Test-Path $vbs)) {
    Write-Error "launcher.vbs not found under $dir\src - make sure you run this from the package root."
    exit 1
}
if (-not (Test-Path $wscript)) {
    Write-Error "wscript.exe not found."
    exit 1
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$taskName = 'WhaleHarnessLauncher'

if ($isAdmin) {
    # Prefer the "At logon" scheduled task: runs before Explorer processes Run keys.
    schtasks /Create /TN $taskName /TR ("{0} {1}" -f $wscript, $vbs) /SC ONLOGON /IT /F | Out-Null
    Remove-ItemProperty -Path $runKey -Name $taskName -ErrorAction SilentlyContinue
    Write-Host "[OK] Registered 'At logon' scheduled task '$taskName' (earliest startup order)."
} else {
    Set-ItemProperty -Path $runKey -Name $taskName -Value ($wscript + ' "' + $vbs + '"')
    Write-Host "[OK] Registered HKCU Run autostart entry '$taskName'."
    Write-Host "Tip: re-run as Administrator to register an 'At logon' task for earlier startup."
}

Write-Host "[OK] Install complete. To start now, double-click: $vbs"
