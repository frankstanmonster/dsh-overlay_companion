$ErrorActionPreference = 'Continue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $dir 'launcher.log'
$pidFile = Join-Path $dir 'harness.pid'

function Log([string]$msg) {
  try { Add-Content -Path $log -Value ("[" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "] " + $msg) -Encoding UTF8 } catch {}
}

function Test-Port([int]$port) {
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    $w = $c.BeginConnect('127.0.0.1', $port, $null, $null)
    $ok = $w.AsyncWaitHandle.WaitOne(500) -and $c.Connected
    $c.Close()
    return [bool]$ok
  } catch { return $false }
}

# Single-instance guard
$mutex = New-Object System.Threading.Mutex($false, 'WhaleHarnessLauncherMutex')
if (-not $mutex.WaitOne(0)) {
  Log 'another launcher instance is already running; exiting'
  exit
}

Log '=== launcher started ==='

# 1. Ensure the harness is running
if (Test-Port 3080) {
  Log 'harness already running (port 3080 open)'
} else {
  Log 'starting harness: npx -y @deepseek-ai/dsh web'
  try {
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','npx -y @deepseek-ai/dsh web' -WindowStyle Hidden -PassThru
    Set-Content -Path $pidFile -Value $p.Id -Encoding ASCII
    Log ('harness root pid = ' + $p.Id)
  } catch {
    Log ('failed to start harness: ' + $_.Exception.Message)
  }
}

# 2. Wait for the harness port to open
$ready = $false
for ($i = 0; $i -lt 120; $i++) {
  Start-Sleep -Seconds 1
  if (Test-Port 3080) { $ready = $true; break }
}
if ($ready) { Log 'harness ready' } else { Log 'harness NOT ready after 120s (will still show whale)' }

# 3. Launch the whale window (blocks until the window is closed)
Log 'launching whale window'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File (Join-Path $dir 'whale-window.ps1')
Log 'whale window closed; launcher exiting'
