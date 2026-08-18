Option Explicit
' Launch the whale launcher hidden (no console window). Path-independent:
' resolves the start-whale.ps1 next to this script, so the src folder is movable.
Dim sh, fso, scriptDir, psScript
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = fso.BuildPath(scriptDir, "start-whale.ps1")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScript & """", 0, False
