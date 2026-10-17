# dsh-desktop-pet · 桌宠本体（整份重写 v0.4.0）
# 余额卡两行 / 可爱粉泡台词 / 点击从上下压扁（她+泡泡同一曲线）/ 泡泡跟着拖动 /
# ☰ 悬停菜单 / 任意位置拖动（多显示器）/ 通知投递 / 右键菜单
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class PetWin {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int v);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern uint GetDpiForSystem();
  public static string DpiAware() {
    try { if (SetProcessDpiAwareness(2) == 0) return "permonitor"; } catch { }
    try { if (SetProcessDPIAware()) return "system"; } catch { }
    return "failed";
  }
  public static uint Dpi() { try { return GetDpiForSystem(); } catch { return 96; } }
}
"@
$script:dpiMode = [PetWin]::DpiAware()
$script:dpi = [int][PetWin]::Dpi()
if ($script:dpi -le 0) { $script:dpi = 96 }
$script:factor = $script:dpi / 96.0

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$assetDir = Join-Path $root 'assets'
$png = Join-Path $assetDir 'DSniang1.png'
$clickMp3 = Join-Path $assetDir 'Ya1.mp3'
$cfgPath = Join-Path $root 'config.json'
$linesPath = Join-Path $root 'lines.txt'
$logPath = Join-Path $root 'pet.log'
$statePath = Join-Path $env:TEMP 'dsh-pet-state.json'
$inbox = Join-Path $env:TEMP 'dsh-pet-inbox.jsonl'
$alive = Join-Path $env:TEMP 'dsh-pet-alive.txt'
$quitPath = Join-Path $env:TEMP 'dsh-pet-quit.txt'
$cmdPath = Join-Path $env:TEMP 'dsh-pet-cmd.txt'
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$script:ledgerPath = if ($env:DSH_PET_LEDGER) { $env:DSH_PET_LEDGER } else { Join-Path $dshHome '.dshw-usage.json' }

function Log-It([string]$m) {
  try { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Add-Content -Path $logPath -Encoding UTF8 } catch { }
}

$mtx = New-Object System.Threading.Mutex($false, 'Local\DshDesktopPet')
if (-not $mtx.WaitOne(0)) { exit 0 }

$script:cfg = @{
  scale = 220; left = 480; top = 300; clickSound = $true; snap = $true; flipped = $false
  menuBtnHide = $false; anchorBottom = $false
  alertBelow = 5; budget = 10; alertDay = ''; alertedBalance = $false; alertedBudget = $false
  autoCardMinutes = 12; memeDay = ''; memeEnabled = $true
}
try {
  if (Test-Path $cfgPath) {
    $s = [IO.File]::ReadAllText($cfgPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($k in @($script:cfg.Keys)) { if ($null -ne $s.$k) { $script:cfg[$k] = $s.$k } }
  }
} catch { }
function Save-Cfg {
  try { [IO.File]::WriteAllText($cfgPath, ($script:cfg | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false))) } catch { }
}

function Get-Wa { try { return [System.Windows.SystemParameters]::WorkArea } catch { return (New-Object System.Windows.Rect(0, 0, 1920, 1080)) } }
function Get-VScreen {
  try {
    $l = [int]::MaxValue; $t = [int]::MaxValue; $r = [int]::MinValue; $b = [int]::MinValue
    foreach ($sc in [System.Windows.Forms.Screen]::AllScreens) {
      $bb = $sc.Bounds
      if ($bb.Left -lt $l) { $l = $bb.Left }
      if ($bb.Top -lt $t) { $t = $bb.Top }
      if ($bb.Right -gt $r) { $r = $bb.Right }
      if ($bb.Bottom -gt $b) { $b = $bb.Bottom }
    }
    if ($r -le $l -or $b -le $t) { throw 'bad' }
    $f = $script:factor
    return (New-Object System.Windows.Rect(($l / $f), ($t / $f), (($r - $l) / $f), (($b - $t) / $f)))
  } catch { return (Get-Wa) }
}

$bi = New-Object System.Windows.Media.Imaging.BitmapImage
$bi.BeginInit()
$bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
$bi.UriSource = New-Object Uri($png)
$bi.EndInit()
$bi.Freeze()

$img = New-Object System.Windows.Controls.Image
$img.Source = $bi
$img.Stretch = [System.Windows.Media.Stretch]::Uniform
$script:img = $img

$script:btn = New-Object System.Windows.Controls.Border
$script:btn.CornerRadius = New-Object System.Windows.CornerRadius(6)
$script:btn.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(217, 32, 49, 112))
$script:btn.Width = 30
$script:btn.Height = 30
$script:btn.HorizontalAlignment = 'Right'
$script:btn.VerticalAlignment = 'Top'
$script:btn.Margin = New-Object System.Windows.Thickness(0, 46, 2, 0)
$script:btn.Visibility = [System.Windows.Visibility]::Collapsed
$script:btn.ToolTip = '菜单'
$btnSp = New-Object System.Windows.Controls.StackPanel
$btnSp.VerticalAlignment = 'Center'
$btnSp.HorizontalAlignment = 'Center'
for ($i = 0; $i -lt 3; $i++) {
  $bar = New-Object System.Windows.Shapes.Rectangle
  $bar.Width = 15; $bar.Height = 2; $bar.RadiusX = 1; $bar.RadiusY = 1
  $bar.Fill = [System.Windows.Media.Brushes]::White
  $bar.Margin = New-Object System.Windows.Thickness(0, 1.5, 0, 1.5)
  [void]$btnSp.Children.Add($bar)
}
$script:btn.Child = $btnSp

$script:imgHost = New-Object System.Windows.Controls.Grid
[void]$script:imgHost.Children.Add($img)
$grid = New-Object System.Windows.Controls.Grid
[void]$grid.Children.Add($script:imgHost)
[void]$grid.Children.Add($script:btn)

$win = New-Object System.Windows.Window
$win.WindowStyle = [System.Windows.WindowStyle]::None
$win.AllowsTransparency = $true
$win.Background = [System.Windows.Media.Brushes]::Transparent
$win.Topmost = $true
$win.ShowInTaskbar = $false
$win.ShowActivated = $false
$win.ResizeMode = [System.Windows.ResizeMode]::NoResize
$win.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
$win.Width = [double]$script:cfg.scale / $script:factor
$win.Height = [double]$script:cfg.scale / $script:factor
$win.Content = $grid
$script:win = $win

$vs = Get-VScreen
$wD = $win.Width; $hD = $win.Height
$win.Left = [double]$script:cfg.left / $script:factor
$win.Top = [double]$script:cfg.top / $script:factor
if ($win.Left -lt $vs.Left) { $win.Left = $vs.Left }
if ($win.Top -lt $vs.Top) { $win.Top = $vs.Top }
if (($win.Left + $wD) -gt $vs.Right) { $win.Left = $vs.Right - $wD }
if (($win.Top + $hD) -gt $vs.Bottom) { $win.Top = $vs.Bottom - $hD }

$script:player = New-Object System.Windows.Media.MediaPlayer
try { $script:player.Open((New-Object Uri $clickMp3)); $script:player.Volume = 0.35 } catch { }
function Play-Click { if (-not $script:cfg.clickSound) { return }; try { $script:player.Position = [TimeSpan]::Zero; $script:player.Play() } catch { } }

function Q-Squash($el) {
  try {
    if (-not $el) { return }
    $sc = New-Object System.Windows.Media.ScaleTransform(1, 1)
    $el.RenderTransform = $sc
    $el.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 1.0)
    $kx = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $kx.Duration = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(380))
    foreach ($f in @(@(0, 1.00), @(90, 1.13), @(230, 0.97), @(380, 1.00))) {
      $k = New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame ([double]$f[1]), ([System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds([double]$f[0])))
      [void]$kx.KeyFrames.Add($k)
    }
    $ky = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    $ky.Duration = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(380))
    foreach ($f in @(@(0, 1.00), @(90, 0.85), @(230, 1.03), @(380, 1.00))) {
      $k2 = New-Object System.Windows.Media.Animation.LinearDoubleKeyFrame ([double]$f[1]), ([System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds([double]$f[0])))
      [void]$ky.KeyFrames.Add($k2)
    }
    $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $kx)
    $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $ky)
  } catch { }
}

function Pop-In($el, [int]$delayMs) {
  try {
    $sc = New-Object System.Windows.Media.ScaleTransform(0.7, 0.7)
    $el.RenderTransform = $sc
    $el.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
    $el.Opacity = 0
    $dur = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(200))
    $bt = [TimeSpan]::FromMilliseconds($delayMs)
    foreach ($prop in @([System.Windows.Media.ScaleTransform]::ScaleXProperty, [System.Windows.Media.ScaleTransform]::ScaleYProperty)) {
      $a = New-Object System.Windows.Media.Animation.DoubleAnimation(0.7, 1.0, $dur)
      $a.BeginTime = $bt
      $sc.BeginAnimation($prop, $a)
    }
    $ao = New-Object System.Windows.Media.Animation.DoubleAnimation(0.0, 1.0, $dur)
    $ao.BeginTime = $bt
    $el.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $ao)
  } catch { }
}

$script:live = $null
try {
  if (Test-Path $statePath) { $script:live = [IO.File]::ReadAllText($statePath, [Text.Encoding]::UTF8) | ConvertFrom-Json }
} catch { }

$script:sections = @{}
$script:allLines = @()
function Get-Lines {
  $map = @{}
  $all = New-Object System.Collections.ArrayList
  $cur = '日常'
  $map[$cur] = New-Object System.Collections.ArrayList
  try {
    if (Test-Path $linesPath) {
      foreach ($raw in [IO.File]::ReadAllLines($linesPath, [Text.Encoding]::UTF8)) {
        $ln = $raw.Trim()
        if ($ln -eq '') { continue }
        if ($ln.StartsWith('##')) {
          $cur = ($ln.Substring(2).Trim())
          if (-not $map.ContainsKey($cur)) { $map[$cur] = New-Object System.Collections.ArrayList }
          continue
        }
        if ($ln.StartsWith('#')) { continue }
        [void]$map[$cur].Add($ln)
        [void]$all.Add($ln)
      }
    }
  } catch { }
  if ($all.Count -eq 0) {
    $def = @('主人，今天也要好好休息喵', '……我才不是在等你叫我的名字呢喵')
    $map = @{ '日常' = (New-Object System.Collections.ArrayList) }
    foreach ($d in $def) { [void]$map['日常'].Add($d); [void]$all.Add($d) }
  }
  $script:sections = $map
  $script:allLines = @($all)
  return $script:allLines
}

$script:lastLine = ''
function Get-RandomLine([string]$section = '日常') {
  $pool = $null
  if ($script:sections.ContainsKey($section) -and $script:sections[$section].Count -gt 0) { $pool = @($script:sections[$section]) }
  if (-not $pool -or $pool.Count -eq 0) { $pool = $script:allLines }
  if (-not $pool -or $pool.Count -eq 0) { $pool = @('……喵') }
  $n = 0
  do {
    $line = [string]$pool[(Get-Random -Minimum 0 -Maximum $pool.Count)]
    $n++
  } while ($n -lt 3 -and $line -eq $script:lastLine -and $pool.Count -gt 1)
  $script:lastLine = $line
  return $line
}

# 连点记账：点太快就会从"日常"跳到"撒娇 / 生气 / 炸毛"
$script:clickTimes = New-Object System.Collections.ArrayList
function Get-ClickSection {
  $now = Get-Date
  $keep = New-Object System.Collections.ArrayList
  foreach ($ct in $script:clickTimes) { if (($now - $ct).TotalSeconds -lt 20) { [void]$keep.Add($ct) } }
  $script:clickTimes = $keep
  $recent = 0
  foreach ($ct in $script:clickTimes) { if (($now - $ct).TotalSeconds -lt 12) { $recent++ } }
  if ($recent -ge 9) { return '炸毛' }
  if ($recent -ge 6) { return '生气' }
  if ($recent -ge 3) { return '撒娇' }
  return '日常'
}
$script:bubble = $null
$script:bubbleRoot = $null
$script:bubbleTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:bubbleTimer.add_Tick({
    try { if ($script:bubble) { $script:bubble.Close() } } catch { }
    $script:bubble = $null; $script:bubbleRoot = $null
    $script:bubbleTimer.Stop()
  })

function Position-Bubble {
  try {
    if (-not $script:bubble) { return }
    $b = $script:bubble
    $cw = $b.ActualWidth; $ch = $b.ActualHeight
    if ($cw -le 0 -or $ch -le 0) { return }
    $wa = Get-Wa
    $left = $script:win.Left + ($script:win.Width / 2) - ($cw / 2)
    $top = $script:win.Top - $ch + 26
    if ($top -lt 4) { $top = $script:win.Top + $script:win.Height - 26 }
    if ($left -lt 4) { $left = 4 }
    if (($left + $cw) -gt ($wa.Right - 4)) { $left = $wa.Right - 4 - $cw }
    $b.Left = $left
    $b.Top = $top
  } catch { }
}

function Show-Bubble([string]$text, [int]$seconds = 14, [string]$style = 'normal') {
  try { if ($script:bubble) { $script:bubble.Close() } } catch { }
  $script:bubble = $null

  $outline = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(255, 32, 49, 112))
  $white = [System.Windows.Media.Brushes]::White
  $fontSize = 13.5
  $lineH = 21
  $radius = 18
  $bg = $white
  if ($style -eq 'cute') {
    $outline = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(255, 232, 122, 168))
    $bg = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(255, 255, 247, 252))
    $fontSize = 15
    $lineH = 24
    $radius = 24
  } elseif ($style -eq 'angry') {
    # 生气了：番茄红边 + 浅红底
    $outline = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(255, 226, 68, 78))
    $bg = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(255, 255, 243, 243))
    $fontSize = 15.5
    $lineH = 25
    $radius = 22
  }

  if ($style -eq 'cute' -or $style -eq 'angry') { $text = Add-Kao $text }
  $panel = New-Object System.Windows.Controls.StackPanel
  foreach ($ln in ($text -split "`r?`n")) {
    $lb = New-Object System.Windows.Controls.TextBlock
    $lb.Text = $ln
    $lb.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $lb.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $lb.FontSize = $fontSize
    $lb.LineHeight = $lineH
    $lb.Foreground = $outline
    [void]$panel.Children.Add($lb)
  }

  $bd = New-Object System.Windows.Controls.Border
  $bd.CornerRadius = New-Object System.Windows.CornerRadius($radius)
  $bd.Background = $bg
  $bd.BorderBrush = $outline
  $bd.BorderThickness = New-Object System.Windows.Thickness(2.6)
  $bd.Padding = New-Object System.Windows.Thickness(15, 11, 15, 11)
  $bd.MaxWidth = 300
  $bd.Child = $panel

  $e1 = New-Object System.Windows.Shapes.Ellipse
  $e1.Width = 17; $e1.Height = 13
  $e1.Fill = $bg; $e1.Stroke = $outline; $e1.StrokeThickness = 2.4
  $e1.HorizontalAlignment = 'Right'; $e1.VerticalAlignment = 'Top'
  $e1.Margin = New-Object System.Windows.Thickness(0, 2, 26, 0)
  $e2 = New-Object System.Windows.Shapes.Ellipse
  $e2.Width = 11; $e2.Height = 8
  $e2.Fill = $bg; $e2.Stroke = $outline; $e2.StrokeThickness = 2.2
  $e2.HorizontalAlignment = 'Right'; $e2.VerticalAlignment = 'Bottom'
  $e2.Margin = New-Object System.Windows.Thickness(0, 0, 50, 2)

  $tail = New-Object System.Windows.Controls.Grid
  $tail.Height = 24
  [void]$tail.Children.Add($e1)
  [void]$tail.Children.Add($e2)

  $root2 = New-Object System.Windows.Controls.StackPanel
  [void]$root2.Children.Add($bd)
  [void]$root2.Children.Add($tail)

  $b = New-Object System.Windows.Window
  $b.WindowStyle = [System.Windows.WindowStyle]::None
  $b.AllowsTransparency = $true
  $b.Background = [System.Windows.Media.Brushes]::Transparent
  $b.Topmost = $true
  $b.ShowInTaskbar = $false
  $b.ShowActivated = $false
  $b.ResizeMode = [System.Windows.ResizeMode]::NoResize
  $b.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
  $b.SizeToContent = [System.Windows.SizeToContent]::WidthAndHeight
  $b.Content = $root2
  $b.Show()
  $b.UpdateLayout()

  $script:bubble = $b
  $script:bubbleRoot = $root2
  Position-Bubble

  Pop-In $e2 0
  Pop-In $e1 120
  Pop-In $bd 240

  $b.Add_MouseLeftButtonUp({
      try { $this.Close() } catch { }
      $script:bubble = $null; $script:bubbleRoot = $null
      try { $script:bubbleTimer.Stop() } catch { }
    })
  $script:lastBubbleAt = Get-Date

  $script:bubbleTimer.Stop()
  $script:bubbleTimer.Interval = [TimeSpan]::FromSeconds([Math]::Max(3, $seconds))
  $script:bubbleTimer.Start()
}

function Show-Card {
  $s = $script:live
  $bal = if ($s -and $null -ne $s.balance) { '{0:N2}' -f [double]$s.balance } else { '—' }
  $today = if ($s -and $null -ne $s.todayUsed) { '{0:N2}' -f [double]$s.todayUsed } else { '—' }
  Show-Bubble "DeepSeek 余额   ¥$bal`n今日已用   ¥$today" 18 'normal'
}

function Show-Click-Bubble {
  Play-Click
  Q-Squash $script:imgHost
  if ($script:bubbleRoot) { Q-Squash $script:bubbleRoot }
  [void]$script:clickTimes.Add((Get-Date))
  if (-not $script:bubble) { Show-Card; return }
  $sec = Get-ClickSection
  $style = 'cute'
  if ($sec -eq '生气' -or $sec -eq '炸毛') { $style = 'angry' }
  Show-Bubble (Get-RandomLine $sec) 14 $style
}

$img.Add_MouseLeftButtonDown({
    try {
      $p0 = [System.Windows.Forms.Cursor]::Position
      $script:win.DragMove()
      $p1 = [System.Windows.Forms.Cursor]::Position
      $moved = ([Math]::Abs($p1.X - $p0.X) + [Math]::Abs($p1.Y - $p0.Y))
      if ($moved -lt 6) {
        Show-Click-Bubble
      } else {
        try {
          $vs2 = Get-VScreen
          $wD2 = $script:win.Width; $hD2 = $script:win.Height
          $mD = 26 / $script:factor
          if ($script:cfg.snap) {
            if ($script:win.Left -lt ($vs2.Left + $mD)) { $script:win.Left = $vs2.Left; Set-Flip $true }
            elseif (($script:win.Left + $wD2) -gt ($vs2.Right - $mD)) { $script:win.Left = $vs2.Right - $wD2; Set-Flip $false }
            if ($script:win.Top -lt ($vs2.Top + $mD)) { $script:win.Top = $vs2.Top }
            elseif (($script:win.Top + $hD2) -gt ($vs2.Bottom - $mD)) { $script:win.Top = $vs2.Bottom - $hD2 }
          }
          if ($script:win.Left -lt $vs2.Left) { $script:win.Left = $vs2.Left }
          if ($script:win.Top -lt $vs2.Top) { $script:win.Top = $vs2.Top }
          if (($script:win.Left + $wD2) -gt $vs2.Right) { $script:win.Left = $vs2.Right - $wD2 }
          if (($script:win.Top + $hD2) -gt $vs2.Bottom) { $script:win.Top = $vs2.Bottom - $hD2 }
        } catch { }
        $script:cfg.left = [int]($script:win.Left * $script:factor)
        $script:cfg.top = [int]($script:win.Top * $script:factor)
        Save-Cfg
      }
    } catch { }
  })

function Set-Flip([bool]$on) {
  try {
    if ($on) {
      $script:img.RenderTransform = New-Object System.Windows.Media.ScaleTransform(-1, 1)
      $script:img.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
    } else {
      $script:img.RenderTransform = New-Object System.Windows.Media.ScaleTransform(1, 1)
    }
    $script:cfg.flipped = $on
    Save-Cfg
  } catch { }
}

function Set-Scale([double]$v) {
  $script:win.Width = $v / $script:factor
  $script:win.Height = $v / $script:factor
  $script:cfg.scale = [int]$v
  $vs3 = Get-VScreen
  if (($script:win.Left + $script:win.Width) -gt $vs3.Right) { $script:win.Left = $vs3.Right - $script:win.Width }
  if (($script:win.Top + $script:win.Height) -gt $vs3.Bottom) { $script:win.Top = $vs3.Bottom - $script:win.Height }
  $script:cfg.left = [int]($script:win.Left * $script:factor)
  $script:cfg.top = [int]($script:win.Top * $script:factor)
  Save-Cfg
}

$cm = New-Object System.Windows.Controls.ContextMenu
function Add-Mi([string]$h, [scriptblock]$a) {
  $mi = New-Object System.Windows.Controls.MenuItem
  $mi.Header = $h
  if ($a) { $mi.Add_Click($a) }
  [void]$cm.Items.Add($mi)
  return $mi
}
function Add-Sub($p, [string]$h, [scriptblock]$a) {
  $mi = New-Object System.Windows.Controls.MenuItem
  $mi.Header = $h
  if ($a) { $mi.Add_Click($a) }
  [void]$p.Items.Add($mi)
  return $mi
}

function Show-Usage {
  try {
    $u = $null
    if (Test-Path $script:ledgerPath) {
      $lg = [IO.File]::ReadAllText($script:ledgerPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
      $evs = @($lg.events)
      if ($evs.Count -gt 0) {
        $off = [TimeSpan]::FromHours(8)
        $today = ([DateTimeOffset]::UtcNow.ToOffset($off)).ToString('yyyy-MM-dd')
        $tc = 0.0; $tt = 0.0; $all = 0.0; $models = @{}
        foreach ($e in $evs) {
          $ts = [double]$e.ts; $cost = [double]$e.cost; $tok = [double]$e.tokens
          $all += $cost
          $d = ([DateTimeOffset]::FromUnixTimeMilliseconds([int64]$ts).ToOffset($off)).ToString('yyyy-MM-dd')
          if ($d -eq $today) { $tc += $cost; $tt += $tok }
          $m = [string]$e.model
          if (-not $models.ContainsKey($m)) { $models[$m] = [pscustomobject]@{ model = $m; cost = 0.0; count = 0 } }
          $models[$m].cost += $cost
          $models[$m].count = $models[$m].count + 1
        }
        $u = [pscustomobject]@{ todayCost = $tc; todayTokens = $tt; totalCost = $all; models = @($models.Values | Sort-Object cost -Descending) }
      }
    }
    if (-not $u) { Show-Bubble '还没有用量记录喵' 6; return }
    $txt = "今天   ¥{0:N4}`n{1:N0} tokens`n合计   ¥{2:N4}" -f $u.todayCost, $u.todayTokens, $u.totalCost
    foreach ($m in $u.models) { $txt += "`n$($m.model)  ¥$('{0:N4}' -f $m.cost) / $($m.count) 次" }
    Show-Bubble $txt 20
  } catch { Show-Bubble '用量读取失败喵' 6 }
}

$mRole = Add-Mi '角色'
Add-Sub $mRole '小鲸鱼（默认形象）' { Show-Bubble '现在是默认形象喵' 5 }
$mSize = Add-Mi '大小'
Add-Sub $mSize '小（160）' { Set-Scale 160 }
Add-Sub $mSize '中（220）' { Set-Scale 220 }
Add-Sub $mSize '大（300）' { Set-Scale 300 }
$mSound = Add-Mi '音效与提示'
Add-Sub $mSound '音效开关' {
  $script:cfg.clickSound = -not $script:cfg.clickSound
  Save-Cfg; Play-Click
  Show-Bubble ($(if ($script:cfg.clickSound) { '音效：开' } else { '音效：关' })) 5
}
$mSnap = Add-Mi '吸附与翻转'
Add-Sub $mSnap '吸附开关' {
  $script:cfg.snap = -not $script:cfg.snap
  Save-Cfg
  Show-Bubble ($(if ($script:cfg.snap) { '吸边：开' } else { '吸边：关' })) 5
}
Add-Sub $mSnap '手动翻转' { Set-Flip (-not $script:cfg.flipped); Show-Bubble '翻个身喵' 4 }
$mRes = Add-Mi '资源管理'
Add-Sub $mRes '用量记录' { Show-Usage }
Add-Sub $mRes '换一批台词' { $script:lines = Get-Lines; Show-Bubble ('台词已刷新，共 ' + $script:lines.Count + ' 条') 5 }
Add-Mi '隐藏菜单按钮' {
  $script:cfg.menuBtnHide = -not $script:cfg.menuBtnHide
  Save-Cfg
  Update-Btn
  Show-Bubble ($(if ($script:cfg.menuBtnHide) { '菜单按钮藏起来了喵（右键也能开）' } else { '菜单按钮回来了喵' })) 5
}
Add-Mi '关于' { Show-Bubble "大肥鱼 · 桌面小鲸鱼 v0.4.0`n余额 / 今日已用 / 可爱台词 / 通知" 10 }
Add-Mi '退出' {
  try { [IO.File]::Delete($alive) } catch { }
  try { $script:win.Close() } catch { }
  [System.Windows.Application]::Current.Shutdown()
}

function Update-Btn {
  try {
    if ($script:cfg.menuBtnHide) { $script:btn.Visibility = [System.Windows.Visibility]::Collapsed; return }
    if ($script:win.IsMouseOver -or $cm.IsOpen) { $script:btn.Visibility = [System.Windows.Visibility]::Visible }
    else { $script:btn.Visibility = [System.Windows.Visibility]::Collapsed }
  } catch { }
}

$script:btn.Add_MouseLeftButtonDown({
    try {
      $args[1].Handled = $true
      $cm.PlacementTarget = $script:btn
      $cm.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Right
      $cm.IsOpen = $true
    } catch { }
  })
$script:btn.Add_MouseLeftButtonUp({ try { $args[1].Handled = $true } catch { } })
$win.Add_MouseRightButtonUp({
    try { $cm.PlacementTarget = $script:win; $cm.IsOpen = $true } catch { }
  })

$btnTimer = New-Object System.Windows.Threading.DispatcherTimer
$btnTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$cm.Add_Closed({ try { Update-Btn } catch { } })
$btnTimer.add_Tick({ Update-Btn })
$btnTimer.Start()

$win.Add_LocationChanged({ Position-Bubble })

# ---- 颜文字：说话时随机加一个（余额卡不加）----
$script:kao = @('喵～', '(ฅ''ω''ฅ)', '(๑•̀ㅂ•́)و✧', '(´･ω･`)', '(๑´ω`๑)', '(ฅ´ω`ฅ)', '(=^･ω･^=)', '( ´ ▽ ` )', '(๑•́ ₃ •̀๑)', '(｡•́︿•̀｡)', '(๑>؂<๑)', 'ヾ(≧▽≦*)o')
function Add-Kao([string]$s) {
  try {
    if (-not $s) { return $s }
    # 已经带颜文字就不再加
    if ($s -match '[（(][^)）]{0,6}[ωω・´`▽≧≦ㅂ^][^)）]{0,6}[)）]') { return $s }
    if ((Get-Random -Maximum 100) -lt 65) { return ($s + ' ' + [string]$script:kao[(Get-Random -Maximum $script:kao.Count)]) }
    return $s
  } catch { return $s }
}
# ---- 每日网络梗（大肥鱼版）：异步抓热搜，抓不到就用本地梗 ----
$script:memeStage = 0      # 0 未开始 / 1 百度飞行中 / 2 知乎飞行中 / 3 完成
$script:memeTask = $null
$script:memeSince = $null

function Start-MemeFetch([string]$url) {
  try {
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'Mozilla/5.0')
    $script:memeTask = $wc.DownloadDataTaskAsync($url)
    $script:memeSince = Get-Date
    return $true
  } catch { return $false }
}

function Parse-Titles([string]$src, [byte[]]$bytes) {
  $arr = @()
  try {
    $txt = [Text.Encoding]::UTF8.GetString($bytes)
    $j = $txt | ConvertFrom-Json
    if ($src -eq '百度热搜') {
      foreach ($card in @($j.data.cards)) { foreach ($it in @($card.content)) { if ($it.word) { $arr += [string]$it.word } } }
    } else {
      foreach ($it in @($j.data)) { if ($it.target.title) { $arr += [string]$it.target.title } }
    }
  } catch { }
  return $arr
}

function Save-Meme($hot) {
  $net = [bool]$hot.net
  $title = [string]$hot.title
  if ($title.Length -gt 24) { $title = $title.Substring(0, 24) + '…' }
  if ($net) {
    $tmpl = @(
      '刷到「{0}」了喵——大肥鱼表示：那是什么，能吃吗喵？',
      '今天{1}在聊「{0}」，大肥鱼只想算算主人的余额喵',
      '「{0}」？大肥鱼歪头：不如主人多陪我一会儿喵',
      '热点「{0}」，大肥鱼点评：这事儿跟我这条鱼有什么关系喵'
    )
    $line = [string]($tmpl[(Get-Random -Maximum $tmpl.Count)])
    $line = $line.Replace('{0}', $title).Replace('{1}', [string]$hot.src)
  } else {
    $tmpl2 = @(
      '大肥鱼今日观察：{0}，主人的钱包在瑟瑟发抖喵',
      '今日鱼言鱼语：{0}喵～（网没连上，只能瞎编了）',
      '大肥鱼小道消息：{0}，我说的都是真的喵'
    )
    $line = ([string]($tmpl2[(Get-Random -Maximum $tmpl2.Count)])).Replace('{0}', $title)
  }
  try {
    $arr = New-Object System.Collections.ArrayList
    if (Test-Path $linesPath) { foreach ($x in [IO.File]::ReadAllLines($linesPath, [Text.Encoding]::UTF8)) { [void]$arr.Add($x) } }
    $idx = -1
    for ($i = 0; $i -lt $arr.Count; $i++) { if ($arr[$i].Trim() -eq '## 网络梗') { $idx = $i; break } }
    if ($idx -lt 0) { [void]$arr.Add(''); [void]$arr.Add('## 网络梗'); $idx = $arr.Count - 1 }
    $after = @()
    for ($i = $idx + 1; $i -lt $arr.Count; $i++) { if ($arr[$i].Trim().StartsWith('##')) { break }; if ($arr[$i].Trim() -ne '') { $after += $arr[$i] } }
    if ($after.Count -ge 12) { $arr.RemoveAt($idx + 1) }        # 先删最旧的
    if ($after -notcontains $line) { $arr.Insert(($idx + 1), $line) }
    [IO.File]::WriteAllLines($linesPath, $arr, (New-Object Text.UTF8Encoding($false)))
  } catch { }
  $script:cfg.memeDay = (Get-Date).ToString('yyyy-MM-dd')
  Save-Cfg
  Get-Lines | Out-Null
  $script:memeStage = 3
  Show-Bubble ("今日新梗已入库喵（" + [string]$hot.src + "）`n" + $line) 18 'cute'
}

# 每次轮询调用一次：只推进状态机，不做同步网络请求（不卡 UI）
function Tick-Meme {
  if (-not $script:cfg.memeEnabled) { return }
  $today = (Get-Date).ToString('yyyy-MM-dd')
  if ($script:cfg.memeDay -eq $today) { return }

  if ($script:memeStage -eq 0) {
    if (-not (Start-MemeFetch 'https://top.baidu.com/api/board?platform=wise&tab=realtime')) { $script:memeStage = 2 }
    else { $script:memeStage = 1 }
    return
  }

  $timeout = $false
  try { if ($script:memeSince -and ((Get-Date) - $script:memeSince).TotalSeconds -gt 15) { $timeout = $true } } catch { }

  if ($script:memeStage -eq 1) {
    if ($timeout -or ($script:memeTask -and $script:memeTask.IsCompleted)) {
      if (-not $timeout) {
        try {
          $arr = Parse-Titles '百度热搜' $script:memeTask.Result
          if ($arr.Count -gt 0) { Save-Meme @{ title = $arr[(Get-Random -Maximum $arr.Count)]; src = '百度热搜'; net = $true }; return }
        } catch { }
      }
      $script:memeTask = $null
      if (Start-MemeFetch 'https://api.zhihu.com/topstory/hot-lists/total?limit=20') { $script:memeStage = 2 } else { Save-Meme @{ title = '余额又少了'; src = '本地'; net = $false } }
    }
    return
  }

  if ($script:memeStage -eq 2) {
    if ($timeout -or ($script:memeTask -and $script:memeTask.IsCompleted)) {
      if (-not $timeout) {
        try {
          $arr2 = Parse-Titles '知乎热榜' $script:memeTask.Result
          if ($arr2.Count -gt 0) { Save-Meme @{ title = $arr2[(Get-Random -Maximum $arr2.Count)]; src = '知乎热榜'; net = $true }; return }
        } catch { }
      }
      $loc = @('余额又少了', '今日已用', 'token 花得像流水', '峰谷价切换', '键盘敲到冒烟')
      Save-Meme @{ title = [string]$loc[(Get-Random -Maximum $loc.Count)]; src = '本地'; net = $false }
    }
  }
}
# ---- 每隔一段时间自己报一次余额 ----
function Maybe-AutoCard {
  try {
    if (-not $script:cfg.autoCardMinutes -or [double]$script:cfg.autoCardMinutes -le 0) { return }
    if ($script:bubble) { return }
    if (-not $script:lastBubbleAt) { $script:lastBubbleAt = Get-Date; return }
    if (((Get-Date) - $script:lastBubbleAt).TotalMinutes -ge [double]$script:cfg.autoCardMinutes) { Show-Card }
  } catch { }
}
$script:inboxPos = 0
try { if (Test-Path $inbox) { $script:inboxPos = (Get-Item $inbox).Length } } catch { }

$poll = New-Object System.Windows.Threading.DispatcherTimer
$poll.Interval = [TimeSpan]::FromSeconds(1)
$poll.add_Tick({
    try { [IO.File]::WriteAllText($alive, [DateTime]::Now.ToString('o')) } catch { }
    try {
      $hh = (New-Object System.Windows.Interop.WindowInteropHelper $script:win).Handle
      if ($hh -ne [IntPtr]::Zero) { [void][PetWin]::SetWindowPos($hh, [IntPtr](-1), 0, 0, 0, 0, 0x0013) }
    } catch { }

    try {
      if (Test-Path $quitPath) {
        [IO.File]::Delete($quitPath)
        try { [IO.File]::Delete($alive) } catch { }
        try { $script:win.Close() } catch { }
        [System.Windows.Application]::Current.Shutdown()
        return
      }
    } catch { }

    try {
      if (Test-Path $statePath) { $script:live = [IO.File]::ReadAllText($statePath, [Text.Encoding]::UTF8) | ConvertFrom-Json }
    } catch { }

    try {
      if (Test-Path $cmdPath) {
        $cmd = ([IO.File]::ReadAllText($cmdPath, [Text.Encoding]::UTF8)).Trim()
        [IO.File]::Delete($cmdPath)
        if ($cmd -eq 'card') { Show-Card }
        elseif ($cmd -eq 'cute') { Show-Bubble (Get-RandomLine) 14 'cute' }
        elseif ($cmd -eq 'press') { Q-Squash $script:imgHost }
        elseif ($cmd -eq 'usage') { Show-Usage }
        elseif ($cmd -match '^scale\s+(\d+)$') { Set-Scale ([double]$Matches[1]) }
        elseif ($cmd -ne '') { Show-Bubble $cmd 14 }
      }
    } catch { }

    try {
      if (Test-Path $inbox) {
        $len = (Get-Item $inbox).Length
        if ($len -gt $script:inboxPos) {
          $fs = [IO.File]::Open($inbox, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
          $fs.Position = $script:inboxPos
          $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
          $data = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
          $script:inboxPos = $len
          foreach ($line in ($data -split "`r?`n")) {
            if ($line.Trim() -eq '') { continue }
            try { $o = $line | ConvertFrom-Json } catch { continue }
            $t = [string]$o.title; $bd2 = [string]$o.body
            $txt = if ($t -and $bd2) { "$t`n$bd2" } elseif ($bd2) { $bd2 } else { $t }
            if ($txt.Trim() -ne '') { Show-Bubble $txt 15 'cute' }
          }
        }
      }
    } catch { }

    try { Tick-Meme } catch { }
    try { Maybe-AutoCard } catch { }

    try {
      $day = (Get-Date).ToString('yyyy-MM-dd')
      if ($script:cfg.alertDay -ne $day) {
        $script:cfg.alertDay = $day; $script:cfg.alertedBalance = $false; $script:cfg.alertedBudget = $false
        Save-Cfg
      }
      if ($script:live) {
        $th = [double]$script:cfg.alertBelow
        $bd3 = [double]$script:cfg.budget
        if ($th -gt 0 -and -not $script:cfg.alertedBalance -and $null -ne $script:live.balance -and [double]$script:live.balance -lt $th) {
          $script:cfg.alertedBalance = $true; Save-Cfg
          Show-Bubble ('余额预警喵！只剩 ¥{0:N2}（阈值 ¥{1}）' -f [double]$script:live.balance, $th) 14
        } elseif ($bd3 -gt 0 -and -not $script:cfg.alertedBudget -and $null -ne $script:live.todayUsed -and [double]$script:live.todayUsed -gt $bd3) {
          $script:cfg.alertedBudget = $true; Save-Cfg
          Show-Bubble ('今日预算超了喵！已经 ¥{0:N2}（预算 ¥{1}）' -f [double]$script:live.todayUsed, $bd3) 14
        }
      }
    } catch { }
  })
$poll.Start()

$app = New-Object System.Windows.Application
$app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
$app.add_DispatcherUnhandledException({ try { $args[1].Handled = $true } catch { } })
$win.Show()
if ($script:cfg.flipped) { Set-Flip $true }
try { [IO.File]::WriteAllText($alive, [DateTime]::Now.ToString('o')) } catch { }
Log-It ("启动 pid=$PID dpi=$($script:dpi) factor=$($script:factor) 位置=$([int]$win.Left),$([int]$win.Top) 尺寸=$([int]$win.Width)")
$app.Run()
try { [IO.File]::Delete($alive) } catch { }
