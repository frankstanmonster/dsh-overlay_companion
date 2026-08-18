$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$global:__whaleDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$global:__whalePidFile = Join-Path $global:__whaleDir 'harness.pid'
$global:__workingGif = Join-Path $global:__whaleDir 'working.gif'
$global:__idleGif = Join-Path $global:__whaleDir 'idle.gif'

# Removes the green-screen / gray-black remnant in the bottom-right corner
# of the "working" animation (a leftover from the original cutout).
function global:Remove-CornerArtifacts($bmp, [int]$frameIndex) {
  $W = $bmp.Width; $H = $bmp.Height
  $cx0 = [int]254; $cy0 = [int]202
  $inWindow = ($frameIndex -le 10) -or ($frameIndex -ge 30 -and $frameIndex -le 39) -or ($frameIndex -ge 80)
  $rect = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
  $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $stride = $data.Stride
  $bytes = New-Object byte[] ($stride * $H)
  [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
  $removed = 0
  if ($inWindow) {
    # defect time windows: drop every non-blue pixel in the corner region
    for ($y = $cy0; $y -lt $H; $y++) {
      $rowBase = $y * $stride
      for ($x = $cx0; $x -lt $W; $x++) {
        $idx = $rowBase + $x * 4
        if ($bytes[$idx + 3] -le 40) { continue }
        $b = $bytes[$idx]; $g = $bytes[$idx + 1]; $r = $bytes[$idx + 2]
        if ($b -gt $g + 2 -and $b -gt $r + 2) { continue }
        $bytes[$idx + 3] = 0
        $removed = $removed + 1
      }
    }
  } else {
    # other frames: remove only detached corner components (area >= 3)
    $visited = [bool[,]]::new($H, $W)
    for ($y = $cy0; $y -lt $H; $y++) {
      for ($x = $cx0; $x -lt $W; $x++) {
        if ($visited[$y, $x]) { continue }
        if ($bytes[$y * $stride + $x * 4 + 3] -le 40) { continue }
        $stack = New-Object System.Collections.Stack
        [void]$stack.Push([int]($x * 10000 + $y))
        $visited[$y, $x] = $true
        $area = [int]0; $outside = $false
        $comp = New-Object System.Collections.ArrayList
        $tryAdd = {
          param($nx, $ny)
          if ($nx -lt 0 -or $nx -ge $W -or $ny -lt 0 -or $ny -ge $H) { return }
          if ($visited[$ny, $nx]) { return }
          if ($bytes[$ny * $stride + $nx * 4 + 3] -le 40) { return }
          $visited[$ny, $nx] = $true
          [void]$stack.Push([int]($nx * 10000 + $ny))
        }
        while ($stack.Count -gt 0) {
          $code = [int]$stack.Pop()
          $cx = [int]($code / 10000)
          $cy = [int]($code - $cx * 10000)
          [void]$comp.Add($code)
          $area = $area + 1
          if ($cx -lt $cx0 -or $cy -lt $cy0) { $outside = $true }
          & $tryAdd ($cx + 1) $cy
          & $tryAdd ($cx - 1) $cy
          & $tryAdd $cx ($cy + 1)
          & $tryAdd $cx ($cy - 1)
        }
        if (-not $outside -and $area -ge 3) {
          foreach ($c in $comp) {
            $px = [int]($c / 10000)
            $py = [int]($c - $px * 10000)
            $bytes[$py * $stride + $px * 4 + 3] = 0
            $removed = $removed + 1
          }
        }
      }
    }
  }
  [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
  $bmp.UnlockBits($data)
  return $removed
}

function global:Load-GifFrames($path) {
  $frames = [System.Collections.ArrayList]::new()
  $delays = [System.Collections.ArrayList]::new()
  $img = [System.Drawing.Image]::FromFile($path)
  $dim = [System.Drawing.Imaging.FrameDimension]::Time
  $count = $img.GetFrameCount($dim)
  $delayBytes = $null
  try { $delayBytes = $img.GetPropertyItem(0x5100).Value } catch {}
  # Only auto-clean the ORIGINAL working.gif (its known corner-cutout defect);
  # a gif the user replaced via the popup (file hash differs) is shown as-is.
  $cleanWorking = $false
  if ($path -eq $global:__workingGif) {
    $origHashFile = Join-Path $global:__whaleDir 'working.gif.original-hash'
    $curHash = (Get-FileHash $path -Algorithm MD5).Hash
    if (Test-Path $origHashFile) {
      $origHash = (Get-Content $origHashFile -Raw).Trim()
      $cleanWorking = ($curHash -eq $origHash)
    } else {
      Set-Content -Path $origHashFile -Value $curHash -Encoding ASCII
      $cleanWorking = $true
    }
  }
  for ($i = 0; $i -lt $count; $i++) {
    $img.SelectActiveFrame($dim, $i) | Out-Null
    $scale = [Math]::Min(320.0 / $img.Width, 320.0 / $img.Height)
    $dstW = [int][Math]::Max(1, [Math]::Round($img.Width * $scale))
    $dstH = [int][Math]::Max(1, [Math]::Round($img.Height * $scale))
    $bmp = New-Object System.Drawing.Bitmap($dstW, $dstH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($img, 0, 0, $dstW, $dstH)
    $g.Dispose()
    if ($cleanWorking) {
      Remove-CornerArtifacts $bmp $i
    }
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $ms.Position = 0
    $bs = [System.Windows.Media.Imaging.BitmapFrame]::Create($ms, [System.Windows.Media.Imaging.BitmapCreateOptions]::None, [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    $ms.Close()
    [void]$frames.Add($bs)
    if ($null -ne $delayBytes -and ($i * 4 + 1) -lt $delayBytes.Length) {
      $d100 = $delayBytes[$i * 4] -bor ($delayBytes[$i * 4 + 1] -shl 8)
      $d = [Math]::Max(20, $d100 * 10)
      [void]$delays.Add($d)
    } else {
      [void]$delays.Add(100)
    }
  }
  $img.Dispose()
  return @{ frames = $frames.ToArray(); delays = $delays.ToArray() }
}

function global:Test-HarnessWorking {
  try {
    $body = '{"type":"client-request","rpcId":"whale-' + [guid]::NewGuid().ToString('N') + '","method":"session.list","payload":{}}'
    $req = [System.Net.HttpWebRequest]::Create('http://127.0.0.1:3080/api/session.list')
    $req.Method = 'POST'
    $req.ContentType = 'application/json'
    $req.Timeout = 1500
    $req.ReadWriteTimeout = 1500
    $stream = $req.GetRequestStream()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Close()
    $resp = $req.GetResponse()
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
    $json = $reader.ReadToEnd()
    $reader.Close()
    $resp.Close()
    $obj = $json | ConvertFrom-Json
    if ($null -ne $obj -and $null -ne $obj.result -and $obj.result.ok -and $null -ne $obj.result.value -and $null -ne $obj.result.value.items) {
      foreach ($item in $obj.result.value.items) {
        if ($item.running) { return $true }
      }
    }
    return $false
  } catch {
    return $false
  }
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="180" Height="180" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize" ShowActivated="False">
  <Border x:Name="Root" Width="180" Height="180" Cursor="Hand" Background="Transparent">
    <Image x:Name="GifImage" Width="180" Height="180" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
  </Border>
</Window>
'@

$window = [System.Windows.Markup.XamlReader]::Parse($xaml)

$work = [System.Windows.SystemParameters]::WorkArea
$window.Left = $work.Right - $window.Width - 24
$window.Top = $work.Bottom - $window.Height - 24

$popupXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="240" Height="218" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize" ShowActivated="False">
  <Border CornerRadius="14" Background="#F8FBFE" BorderBrush="#D8E6F2" BorderThickness="1">
    <Border.Effect>
      <DropShadowEffect BlurRadius="18" ShadowDepth="4" Opacity="0.28" Color="#0A1E3C"/>
    </Border.Effect>
    <StackPanel Margin="16,14,16,14">
      <Grid>
        <TextBlock Text="DeepSeek Harness" FontSize="14" FontWeight="Bold" Foreground="#1F2A3A"/>
        <Button x:Name="CloseBtn" Content="×" Width="20" Height="20" HorizontalAlignment="Right" VerticalAlignment="Center" Background="Transparent" BorderThickness="0" Foreground="#8A9AAE" FontSize="13" Cursor="Hand"/>
      </Grid>
      <StackPanel Orientation="Horizontal" Margin="0,12,0,0">
        <Ellipse x:Name="StatusDot" Width="9" Height="9" VerticalAlignment="Center" Fill="#22C55E"/>
        <TextBlock x:Name="StatusText" Text="运行中" Margin="7,0,0,0" FontSize="12.5" Foreground="#3D4D60"/>
      </StackPanel>
      <TextBlock x:Name="ActivityText" Text="—" Margin="16,6,0,0" FontSize="12" Foreground="#0E7C66" TextTrimming="CharacterEllipsis"/>
      <TextBlock Text="127.0.0.1:3080" FontSize="11" Foreground="#93A3B4" Margin="16,4,0,0"/>
      <Button x:Name="OpenBtn" Content="打开 Harness" Margin="0,14,0,0" Height="34" Background="#2B8BE0" Foreground="#FFFFFF" FontSize="13" FontWeight="SemiBold" BorderThickness="0" Cursor="Hand"/>
      <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
        <Button x:Name="ReplaceWorkBtn" Content="更换工作动图" Width="92" Height="30" Background="#F0F4F8" Foreground="#2B8BE0" FontSize="12" FontWeight="SemiBold" BorderBrush="#D8E6F2" BorderThickness="1" Cursor="Hand"/>
        <Button x:Name="ReplaceIdleBtn" Content="更换空闲动图" Width="92" Height="30" Margin="8,0,0,0" Background="#F0F4F8" Foreground="#2B8BE0" FontSize="12" FontWeight="SemiBold" BorderBrush="#D8E6F2" BorderThickness="1" Cursor="Hand"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@

$popup = [System.Windows.Markup.XamlReader]::Parse($popupXaml)

$global:__whaleWindow = $window
$global:__whalePopup = $popup
$global:__whaleImage = $window.FindName('GifImage')
$global:__whaleRoot = $window.FindName('Root')
$global:__whaleStatusDot = $popup.FindName('StatusDot')
$global:__whaleStatusText = $popup.FindName('StatusText')
$global:__whaleActivityText = $popup.FindName('ActivityText')
$global:__whaleOpenBtn = $popup.FindName('OpenBtn')
$global:__whaleCloseBtn = $popup.FindName('CloseBtn')
$global:__whaleReplaceWorkBtn = $popup.FindName('ReplaceWorkBtn')
$global:__whaleReplaceIdleBtn = $popup.FindName('ReplaceIdleBtn')
$global:__whaleDown = $null
$global:__whaleClickTimer = $null
$global:__whalePopupTimer = $null
$global:__whaleLastClick = [DateTime]::MinValue
$global:__whaleDoubleMs = 400
$global:__working = $false
$global:__animIndex = 0

# Load both animations (fast: ~0.8s total) and show the idle first frame immediately
$global:__idleData = Load-GifFrames $global:__idleGif
$global:__workingData = Load-GifFrames $global:__workingGif
$global:__whaleImage.Source = $global:__idleData.frames[0]

# Animation timer
$global:__animTimer = New-Object System.Windows.Threading.DispatcherTimer
$global:__animTimer.Interval = [TimeSpan]::FromMilliseconds(100)
$global:__animTimer.Add_Tick({
  $data = if ($global:__working) { $global:__workingData } else { $global:__idleData }
  $frames = $data.frames
  if ($frames.Count -eq 0) { return }
  $i = $global:__animIndex
  if ($i -ge $frames.Count) { $i = 0 }
  $global:__whaleImage.Source = $frames[$i]
  $global:__animIndex = $i + 1
  $d = 100
  if ($i -lt $data.delays.Count) { $d = $data.delays[$i] }
  if ([int]$global:__animTimer.Interval.TotalMilliseconds -ne $d) {
    $global:__animTimer.Interval = [TimeSpan]::FromMilliseconds($d)
    $global:__animTimer.Start()
  }
})
$global:__animTimer.Start()

# Polling timer: query the harness every 1.5s
$global:__pollTimer = New-Object System.Windows.Threading.DispatcherTimer
$global:__pollTimer.Interval = [TimeSpan]::FromSeconds(1.5)
$global:__pollTimer.Add_Tick({
  $w = Test-HarnessWorking
  if ($w -ne $global:__working) {
    $global:__working = $w
    $global:__animIndex = 0
  }
})
$global:__pollTimer.Start()

# Initial state poll
$global:__working = Test-HarnessWorking
if ($global:__working) { $global:__animIndex = 0 }

# ---- Live activity watcher: poll the harness for the current activity state ----
$global:__activity = [hashtable]::Synchronized(@{ text = '—' })

$activityScript = {
  $st = $activity
  function Get-ToolLabel([string]$name) {
    switch ($name) {
      'pwsh' { '正在调用 pwsh' }
      'bash' { '正在执行命令' }
      'edit' { '正在编辑文件' }
      'write' { '正在写入文件' }
      'read' { '正在读取文件' }
      'grep' { '正在搜索内容' }
      'glob' { '正在查找文件' }
      'web_search' { '正在联网搜索' }
      'web_fetch' { '正在联网获取' }
      'web' { '正在联网' }
      'ask_user_question' { '正在向你提问' }
      'subagent' { '正在运行子代理' }
      'todo_write' { '正在更新任务清单' }
      default { '正在调用工具：' + $name }
    }
  }
  function Get-ActivityLabel($events) {
    $scan = [Math]::Min($events.Count, 400)
    for ($k = 1; $k -le $scan; $k++) {
      $ev = $events[$events.Count - $k].event
      $t = $ev.type
      if ($t -eq 'tool/call') {
        $n = ''
        try { $n = [string]$ev.data.name } catch {}
        return (Get-ToolLabel $n)
      } elseif ($t -eq 'approval/asked') {
        $n = ''
        try { $n = [string]$ev.data.toolName } catch {}
        if ([string]::IsNullOrEmpty($n)) { $n = '工具' }
        return ('等待审批：' + $n)
      } elseif ($t -eq 'user/message') {
        return '等待用户输入…'
      } elseif ($t -eq 'turn/end') {
        return '空闲'
      } elseif ($t -eq 'assistant/chunk') {
        $ct = ''
        try { $ct = [string]$ev.data.chunk.type } catch {}
        if ($ct -eq 'reasoning-delta') { return '正在思考…' }
        if ($ct -eq 'text-delta') { return '正在生成回复…' }
        if ($ct -eq 'tool-call-delta') { return '正在准备工具调用…' }
      }
    }
    return ''
  }
  while ($true) {
    try {
      $listBody = '{"type":"client-request","rpcId":"w-poll1","method":"session.list","payload":{}}'
      $req = [System.Net.HttpWebRequest]::Create('http://127.0.0.1:3080/api/session.list')
      $req.Method = 'POST'; $req.ContentType = 'application/json'; $req.Timeout = 2500
      $s = $req.GetRequestStream()
      $b = [System.Text.Encoding]::UTF8.GetBytes($listBody)
      $s.Write($b, 0, $b.Length); $s.Close()
      $r = $req.GetResponse()
      $rd = New-Object System.IO.StreamReader($r.GetResponseStream(), [System.Text.Encoding]::UTF8)
      $json = $rd.ReadToEnd(); $rd.Close(); $r.Close()
      $obj = $json | ConvertFrom-Json
      $runningSession = $null
      if ($obj.result.ok -and $null -ne $obj.result.value.items) {
        foreach ($it in $obj.result.value.items) { if ($it.running) { $runningSession = $it.sessionId; break } }
      }
      if ($null -eq $runningSession) {
        $st.text = '空闲'
      } else {
        $hBody = '{"type":"client-request","rpcId":"w-poll2","method":"session.history","payload":{"sessionId":"' + $runningSession + '","maxMessages":1}}'
        $req2 = [System.Net.HttpWebRequest]::Create('http://127.0.0.1:3080/api/session.history')
        $req2.Method = 'POST'; $req2.ContentType = 'application/json'; $req2.Timeout = 2500
        $s2 = $req2.GetRequestStream()
        $b2 = [System.Text.Encoding]::UTF8.GetBytes($hBody)
        $s2.Write($b2, 0, $b2.Length); $s2.Close()
        $r2 = $req2.GetResponse()
        $rd2 = New-Object System.IO.StreamReader($r2.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $json2 = $rd2.ReadToEnd(); $rd2.Close(); $r2.Close()
        $obj2 = $json2 | ConvertFrom-Json
        if ($obj2.result.ok -and $null -ne $obj2.result.value.events -and $obj2.result.value.events.Count -gt 0) {
          $label = Get-ActivityLabel $obj2.result.value.events
          if (-not [string]::IsNullOrEmpty($label)) { $st.text = $label }
        }
      }
    } catch { }
    Start-Sleep -Seconds 2
  }
}

$activityPs = [powershell]::Create()
$activityRs = [runspacefactory]::CreateRunspace()
$activityRs.Open()
$activityRs.SessionStateProxy.SetVariable('activity', $global:__activity)
$activityPs.Runspace = $activityRs
$activityPs.AddScript($activityScript) | Out-Null
$null = $activityPs.BeginInvoke()
$global:__activityPs = $activityPs
$global:__activityRs = $activityRs

# Live-refresh the activity line while the popup is open
$global:__activityUiTimer = New-Object System.Windows.Threading.DispatcherTimer
$global:__activityUiTimer.Interval = [TimeSpan]::FromSeconds(1)
$global:__activityUiTimer.Add_Tick({
  if ($global:__whalePopup.IsVisible -and $null -ne $global:__whaleActivityText) {
    try { $global:__whaleActivityText.Text = [string]$global:__activity['text'] } catch {}
  }
})
$global:__activityUiTimer.Start()

function global:Show-WhalePopup {
  $online = $false
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    $w = $c.BeginConnect('127.0.0.1', 3080, $null, $null)
    $online = ($w.AsyncWaitHandle.WaitOne(1200) -and $c.Connected)
    $c.Close()
  } catch { $online = $false }
  if ($online) {
    $global:__whaleStatusDot.Fill = [System.Windows.Media.Brushes]::LimeGreen
    if ($global:__working) {
      $global:__whaleStatusText.Text = '运行中 · 任务执行中'
    } else {
      $global:__whaleStatusText.Text = '运行中 · 空闲'
    }
  } else {
    $global:__whaleStatusDot.Fill = [System.Windows.Media.Brushes]::Red
    $global:__whaleStatusText.Text = '未运行'
  }
  try { $global:__whaleActivityText.Text = [string]$global:__activity['text'] } catch {}
  $wp = $global:__whaleWindow
  $pp = $global:__whalePopup
  $work = [System.Windows.SystemParameters]::WorkArea
  $pp.Left = $wp.Left + $wp.Width - $pp.Width
  if (($wp.Top - $pp.Height - 12) -lt $work.Top) {
    $pp.Top = $wp.Top + $wp.Height + 12
  } else {
    $pp.Top = $wp.Top - $pp.Height - 12
  }
  $pp.Show()
  if ($null -ne $global:__whalePopupTimer) { $global:__whalePopupTimer.Stop() }
  $t = New-Object System.Windows.Threading.DispatcherTimer
  $t.Interval = [TimeSpan]::FromSeconds(8)
  $t.Add_Tick({
    if ($null -ne $global:__whalePopupTimer) { $global:__whalePopupTimer.Stop() }
    $global:__whalePopupTimer = $null
    $global:__whalePopup.Hide()
  })
  $global:__whalePopupTimer = $t
  $t.Start()
}

function global:Hide-WhalePopup {
  if ($null -ne $global:__whalePopupTimer) { $global:__whalePopupTimer.Stop(); $global:__whalePopupTimer = $null }
  $global:__whalePopup.Hide()
}

function global:Stop-Harness {
  $pf = $global:__whalePidFile
  if (Test-Path $pf) {
    Get-Content $pf | ForEach-Object {
      $t = $_.ToString().Trim()
      if ($t -match '^\d+$') {
        Start-Process -FilePath 'taskkill.exe' -ArgumentList "/PID $t /T /F" -WindowStyle Hidden -Wait
      }
    }
    Remove-Item $pf -ErrorAction SilentlyContinue
  }
  $conns = Get-NetTCPConnection -LocalPort 3080 -State Listen -ErrorAction SilentlyContinue
  foreach ($c in $conns) {
    Start-Process -FilePath 'taskkill.exe' -ArgumentList "/PID $($c.OwningProcess) /T /F" -WindowStyle Hidden -Wait
  }
}

# Replace the working or idle animation from a user-picked GIF file.
# Only .gif files are accepted; the file is validated, copied into this
# folder (so the change survives a restart) and reloaded immediately.
function global:Replace-Gif([string]$which) {
  # pause the popup auto-hide while the file dialog is open
  if ($null -ne $global:__whalePopupTimer) { $global:__whalePopupTimer.Stop() }
  $dlg = New-Object Microsoft.Win32.OpenFileDialog
  $dlg.Title = if ($which -eq 'working') { '选择新的工作动图（仅支持 GIF）' } else { '选择新的空闲动图（仅支持 GIF）' }
  $dlg.Filter = 'GIF 动图 (*.gif)|*.gif'
  $ok = $dlg.ShowDialog()
  if (-not $ok) { return }
  $src = $dlg.FileName
  if ([string]::IsNullOrEmpty($src) -or -not (Test-Path $src)) { return }
  if ([System.IO.Path]::GetExtension($src).ToLower() -ne '.gif') {
    [System.Windows.MessageBox]::Show('请选择 .gif 格式的动图文件。', '格式错误', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    return
  }
  $valid = $false
  $tmpImg = $null
  try {
    $tmpImg = [System.Drawing.Image]::FromFile($src)
    $tmpDim = [System.Drawing.Imaging.FrameDimension]::Time
    if ($tmpImg.GetFrameCount($tmpDim) -ge 1) { $valid = $true }
  } catch {
    $valid = $false
  }
  if ($null -ne $tmpImg) { $tmpImg.Dispose() }
  if (-not $valid) {
    [System.Windows.MessageBox]::Show('所选文件不是有效的 GIF 动图，请更换文件。', '格式错误', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    return
  }
  $dest = if ($which -eq 'working') { $global:__workingGif } else { $global:__idleGif }
  Copy-Item -Path $src -Destination $dest -Force
  $newData = Load-GifFrames $dest
  if ($which -eq 'working') { $global:__workingData = $newData } else { $global:__idleData = $newData }
  $global:__animIndex = 0
  [System.Windows.MessageBox]::Show('动图已更换，立即生效。', '完成', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
  # re-arm the popup auto-hide if the popup is still open
  if ($global:__whalePopup.IsVisible) {
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromSeconds(8)
    $t.Add_Tick({
      if ($null -ne $global:__whalePopupTimer) { $global:__whalePopupTimer.Stop() }
      $global:__whalePopupTimer = $null
      $global:__whalePopup.Hide()
    })
    $global:__whalePopupTimer = $t
    $t.Start()
  }
}

$global:__whaleOpenBtn.Add_Click({
  Hide-WhalePopup
  Start-Process 'http://127.0.0.1:3080'
})

$global:__whaleCloseBtn.Add_Click({
  Hide-WhalePopup
})

$global:__whaleReplaceWorkBtn.Add_Click({
  Replace-Gif 'working'
})

$global:__whaleReplaceIdleBtn.Add_Click({
  Replace-Gif 'idle'
})

$global:__whaleRoot.Add_MouseLeftButtonDown({
  param($sender, $e)
  $sender.CaptureMouse()
  $src = [System.Windows.PresentationSource]::FromVisual($global:__whaleWindow)
  $scale = 1.0
  if ($null -ne $src) { $scale = $src.CompositionTarget.TransformFromDevice.M11 }
  $cp = [System.Windows.Forms.Cursor]::Position
  $global:__whaleDown = @{
    winX = $global:__whaleWindow.Left
    winY = $global:__whaleWindow.Top
    mouseX = $cp.X
    mouseY = $cp.Y
    scale = $scale
    moved = $false
  }
})

$global:__whaleRoot.Add_MouseMove({
  param($sender, $e)
  $d = $global:__whaleDown
  if ($null -eq $d) { return }
  if ($e.LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) { return }
  $cp = [System.Windows.Forms.Cursor]::Position
  $dx = ($cp.X - $d.mouseX) / $d.scale
  $dy = ($cp.Y - $d.mouseY) / $d.scale
  if (-not $d.moved -and [Math]::Abs($dx) -lt 4 -and [Math]::Abs($dy) -lt 4) { return }
  if (-not $d.moved) {
    $d.moved = $true
    Hide-WhalePopup
  }
  $global:__whaleWindow.Left = $d.winX + $dx
  $global:__whaleWindow.Top = $d.winY + $dy
})

$global:__whaleRoot.Add_MouseLeftButtonUp({
  param($sender, $e)
  $sender.ReleaseMouseCapture()
  $d = $global:__whaleDown
  $global:__whaleDown = $null
  if ($null -eq $d -or $d.moved) { return }
  $now = [DateTime]::Now
  $isDouble = (($now - $global:__whaleLastClick).TotalMilliseconds) -lt $global:__whaleDoubleMs
  $global:__whaleLastClick = $now
  if ($null -ne $global:__whaleClickTimer) { $global:__whaleClickTimer.Stop(); $global:__whaleClickTimer = $null }
  if ($isDouble) {
    Hide-WhalePopup
    Start-Process 'http://127.0.0.1:3080'
  } else {
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds($global:__whaleDoubleMs)
    $timer.Add_Tick({
      if ($null -ne $global:__whaleClickTimer) { $global:__whaleClickTimer.Stop() }
      $global:__whaleClickTimer = $null
      if ($global:__whalePopup.IsVisible) { Hide-WhalePopup } else { Show-WhalePopup }
    })
    $global:__whaleClickTimer = $timer
    $timer.Start()
  }
})

$global:__whaleRoot.Add_MouseRightButtonDown({
  param($sender, $e)
  $menu = New-Object System.Windows.Controls.ContextMenu
  $open = New-Object System.Windows.Controls.MenuItem
  $open.Header = '打开 Harness'
  $open.Add_Click({ Hide-WhalePopup; Start-Process 'http://127.0.0.1:3080' })
  $stop = New-Object System.Windows.Controls.MenuItem
  $stop.Header = '停止 Harness'
  $stop.Add_Click({ Stop-Harness })
  $exit = New-Object System.Windows.Controls.MenuItem
  $exit.Header = '退出'
  $exit.Add_Click({ $global:__whaleWindow.Close() })
  [void]$menu.Items.Add($open)
  [void]$menu.Items.Add($stop)
  [void]$menu.Items.Add($exit)
  $global:__whaleMenu = $menu
  $menu.IsOpen = $true
})

$global:__whaleWindow.Add_Closed({
  try { $global:__pollTimer.Stop() } catch {}
  try { $global:__animTimer.Stop() } catch {}
  try { $global:__activityUiTimer.Stop() } catch {}
  try { $global:__activityPs.Stop() } catch {}
  try { $global:__activityRs.Close() } catch {}
})

[void]$global:__whaleWindow.ShowDialog()
