# uninstall.ps1 - remove the autostart entry for the Whale Harness Launcher.
# The launcher itself keeps working until you right-click the whale -> Exit.
$ErrorActionPreference = 'Continue'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$taskName = 'WhaleHarnessLauncher'

Remove-ItemProperty -Path $runKey -Name $taskName -ErrorAction SilentlyContinue
schtasks /Delete /TN $taskName /F 2>$null | Out-Null

Write-Host "[OK] Autostart entry removed."
Write-Host "You can now close the floating window (right-click -> Exit) and delete this folder."
