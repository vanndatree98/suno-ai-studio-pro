param(
    [switch]$hidden = $false
)

$sunoLog = "C:\Users\PS\AppData\Local\Programs\Suno\suno_app.log"
function Log-Step([string]$msg) {
    "[$([DateTime]::Now.ToString('HH:mm:ss.fff'))] $msg" | Out-File $sunoLog -Append -Encoding utf8
}
"=== SunoApp Started (PID: $PID, hidden=$hidden) ===" | Out-File $sunoLog -Encoding utf8

$settingsFile = "C:\Users\PS\AppData\Local\Programs\Suno\desktop_settings.json"
function Get-DesktopSettings {
    if (Test-Path $settingsFile) {
        try {
            $json = Get-Content $settingsFile -Raw -Encoding utf8 | ConvertFrom-Json
            return $json
        } catch { }
    }
    return [PSCustomObject]@{
        runOnStartup = $true
        closeToTray = $true
        startMinimized = $false
    }
}

$script:desktopSettings = Get-DesktopSettings

function Save-DesktopSettings {
    try {
        $script:desktopSettings | ConvertTo-Json -Depth 3 | Set-Content $settingsFile -Encoding utf8
        Log-Step "Saved desktop settings: closeToTray=$($script:desktopSettings.closeToTray), runOnStartup=$($script:desktopSettings.runOnStartup)"
    } catch { }
}

function Set-RunOnStartup([bool]$enable) {
    $script:desktopSettings.runOnStartup = $enable
    Save-DesktopSettings
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $vbsPath = "C:\Users\PS\AppData\Local\Programs\Suno\SunoLauncher.vbs"
    if ($enable) {
        try {
            Set-ItemProperty -Path $regPath -Name "SunoDesktop" -Value "wscript.exe `"$vbsPath`" -hidden" -Force
            Log-Step "Set Run On Startup in Registry"
        } catch { Log-Step "Error setting startup registry: $_" }
    } else {
        try {
            Remove-ItemProperty -Path $regPath -Name "SunoDesktop" -ErrorAction SilentlyContinue
            Log-Step "Removed Run On Startup from Registry"
        } catch { Log-Step "Error removing startup registry: $_" }
    }
}

Log-Step "Step 1: Setting up Win32 helper"
if (-not ([System.Management.Automation.PSTypeName]'SunoWin32').Type) {
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    using System.Text;
    public class SunoWin32 {
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
        [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        public static IntPtr FindSunoWindow() {
            IntPtr found = IntPtr.Zero;
            EnumWindows((hWnd, lParam) => {
                if (IsWindowVisible(hWnd)) {
                    var sb = new StringBuilder(256);
                    GetWindowText(hWnd, sb, 256);
                    string title = sb.ToString();
                    if (title.Contains("Suno - AI Music") || title.Contains("Suno Desktop")) {
                        found = hWnd;
                        return false;
                    }
                }
                return true;
            }, IntPtr.Zero);
            return found;
        }
    }
"@
}

Log-Step "Step 2: Checking Mutex"
$mutexName = "Local\SunoDesktop_App_Mutex_98723"
$isNew = $false
$appMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$isNew)
Log-Step "Mutex isNew: $isNew"

if (-not $isNew) {
    $existingHwnd = [SunoWin32]::FindSunoWindow()
    Log-Step "Existing HWND: $existingHwnd"
    if ($existingHwnd -ne [IntPtr]::Zero) {
        Log-Step "Restoring existing window and exiting"
        [SunoWin32]::ShowWindow($existingHwnd, 9) | Out-Null
        [SunoWin32]::SetForegroundWindow($existingHwnd) | Out-Null
        exit 0
    } else {
        Log-Step "Cleaning stale processes"
        Get-CimInstance Win32_Process | Where-Object {
            $_.CommandLine -like "*SunoApp.ps1*" -and $_.ProcessId -ne $PID
        } | ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
        }
        Start-Sleep -Milliseconds 600
    }
}

Log-Step "Step 3: Loading Assemblies"
try { [SunoWin32]::SetProcessDPIAware() | Out-Null } catch { }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({
    param($s, $e)
    Log-Step "FATAL ThreadException: $($e.Exception.ToString())"
})
[System.AppDomain]::CurrentDomain.add_UnhandledException({
    param($s, $e)
    Log-Step "FATAL UnhandledException: $($e.ExceptionObject.ToString())"
})
$script:sunoDir = "C:\Users\PS\AppData\Local\Programs\Suno"
$sunoDir = $script:sunoDir
Add-Type -Path (Join-Path $sunoDir "Microsoft.Web.WebView2.Core.dll")
Add-Type -Path (Join-Path $sunoDir "Microsoft.Web.WebView2.WinForms.dll")

Log-Step "Step 4: Creating Form"
$script:form = New-Object System.Windows.Forms.Form
$form = $script:form
$form.Text = "Suno - AI Music & Songs Maker"
$form.Width = 1360
$form.Height = 860
$form.MinimumSize = New-Object System.Drawing.Size(1000, 640)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 22)
$form.ForeColor = [System.Drawing.Color]::White
$form.KeyPreview = $true

$iconPath = Join-Path $sunoDir "app.ico"
if (Test-Path $iconPath) {
    $form.Icon = New-Object System.Drawing.Icon($iconPath)
}

$darkMode = 1
[SunoWin32]::DwmSetWindowAttribute($form.Handle, 20, [ref]$darkMode, 4) | Out-Null
[SunoWin32]::DwmSetWindowAttribute($form.Handle, 19, [ref]$darkMode, 4) | Out-Null

Log-Step "Step 5: Setting up Menu"
$menuStrip = New-Object System.Windows.Forms.MenuStrip
$menuStrip.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 30)
$menuStrip.ForeColor = [System.Drawing.Color]::FromArgb(230, 230, 240)
$menuStrip.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$menuStrip.Visible = $false

$fileMenu = New-Object System.Windows.Forms.ToolStripMenuItem("ឯកសារ (File)")
$fileMenu.DropDown.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 32)
$fileMenu.DropDown.ForeColor = [System.Drawing.Color]::FromArgb(230, 230, 245)
$fileMenu.DropDown.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 9.5)

$itemHome = $fileMenu.DropDownItems.Add("🏠 ទំព័រដើម (Home)")
$itemCreate = $fileMenu.DropDownItems.Add("🎵 បង្កើតបទចម្រៀង (Create)")
$fileMenu.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$itemCloseTray = New-Object System.Windows.Forms.ToolStripMenuItem("🌟 ពេលបិទពី Taskbar ឱ្យបន្តដំណើរការ (Close to Tray)")
$itemCloseTray.CheckOnClick = $true
$itemCloseTray.Checked = $script:desktopSettings.closeToTray
$itemCloseTray.Add_CheckedChanged({
    $script:desktopSettings.closeToTray = $itemCloseTray.Checked
    Save-DesktopSettings
    if ($script:tCloseTray) { $script:tCloseTray.Checked = $itemCloseTray.Checked }
})
$fileMenu.DropDownItems.Add($itemCloseTray) | Out-Null

$itemStartup = New-Object System.Windows.Forms.ToolStripMenuItem("🚀 Run On Startup (ដំណើរការស្វ័យប្រវត្តពេលបើកម៉ាស៊ីន)")
$itemStartup.CheckOnClick = $true
$itemStartup.Checked = $script:desktopSettings.runOnStartup
$itemStartup.Add_CheckedChanged({
    Set-RunOnStartup $itemStartup.Checked
    if ($script:tStartup) { $script:tStartup.Checked = $itemStartup.Checked }
})
$fileMenu.DropDownItems.Add($itemStartup) | Out-Null

$fileMenu.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$itemHide = $fileMenu.DropDownItems.Add("🚪 លាក់ក្នុង System Tray (Hide to Tray)")
$itemHide.Add_Click({
    $form.Hide()
    $form.ShowInTaskbar = $false
})
$itemExit = $fileMenu.DropDownItems.Add("❌ ចាកចេញពីកម្មវិធីទាំងស្រុង (Exit Completely)")
$itemExit.Add_Click({
    $script:isQuitting = $true
    if ($notifyIcon) { $notifyIcon.Visible = $false; $notifyIcon.Dispose() }
    $form.Close()
})

$toolsMenu = New-Object System.Windows.Forms.ToolStripMenuItem("ឧបករណ៍ (Tools)")
$toolsMenu.DropDown.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 32)
$toolsMenu.DropDown.ForeColor = [System.Drawing.Color]::FromArgb(230, 230, 245)
$toolsMenu.DropDown.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 9.5)

$itemComposer = $toolsMenu.DropDownItems.Add("🎼 កម្មវិធីនិពន្ធបទចម្រៀង និង បទភ្លេង (Suno Composer App)")
$itemTheme = $toolsMenu.DropDownItems.Add("🎨 ជ្រើសរើស Theme & ស្ទីលតន្ត្រី (Theme Selector - Ctrl+T)")
$itemStudio = $toolsMenu.DropDownItems.Add("🎵 និពន្ធទំនុកច្រៀង និង បទភ្លេងស្វ័យប្រវត្តិ (AI Studio - Ctrl+M)")
$itemWav = $toolsMenu.DropDownItems.Add("🔊 ផ្ទាំងទាញយកជា WAV ស្វ័យប្រវត្តិ (WAV Grabber - Ctrl+W)")
$itemDl = $toolsMenu.DropDownItems.Add("📥 កម្មវិធីទាញយកចម្រៀង Desktop (Suno Downloader - Ctrl+D)")
$toolsMenu.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$itemReload = $toolsMenu.DropDownItems.Add("🔄 ផ្ទុកឡើងវិញ (Reload - F5)")
$itemFull = $toolsMenu.DropDownItems.Add("🖥️ ពេញអេក្រង់ (Full Screen - F11)")

$btnGen = New-Object System.Windows.Forms.ToolStripMenuItem("✨ បង្កើត ចំណងជើង ទំនុកច្រៀង ស្ទីល (F6)")
$btnGen.ForeColor = [System.Drawing.Color]::FromArgb(255, 150, 40)
$btnGen.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

$btnStudio = New-Object System.Windows.Forms.ToolStripMenuItem("🎵 AI និពន្ធចម្រៀង (Ctrl+M)")
$btnStudio.ForeColor = [System.Drawing.Color]::FromArgb(255, 110, 80)
$btnStudio.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

$btnTheme = New-Object System.Windows.Forms.ToolStripMenuItem("🎨 ជ្រើសរើស Theme (Ctrl+T)")
$btnTheme.ForeColor = [System.Drawing.Color]::FromArgb(244, 114, 182)
$btnTheme.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

$btnComposer = New-Object System.Windows.Forms.ToolStripMenuItem("🎼 កម្មវិធីនិពន្ធចម្រៀង (Composer App)")
$btnComposer.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 50)
$btnComposer.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

$btnWav = New-Object System.Windows.Forms.ToolStripMenuItem("🔊 ទាញយក WAV (Ctrl+W)")
$btnWav.ForeColor = [System.Drawing.Color]::FromArgb(60, 180, 255)
$btnWav.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

$btnDl = New-Object System.Windows.Forms.ToolStripMenuItem("📥 Suno Downloader (Ctrl+D)")
$btnDl.ForeColor = [System.Drawing.Color]::FromArgb(100, 220, 255)
$btnDl.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

$btnPlDl = New-Object System.Windows.Forms.ToolStripMenuItem("📦 ទាញយក Playlist ZIP")
$btnPlDl.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 90)
$btnPlDl.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

$menuStrip.Items.Add($fileMenu) | Out-Null
$menuStrip.Items.Add($toolsMenu) | Out-Null
$menuStrip.Items.Add($btnGen) | Out-Null
$menuStrip.Items.Add($btnStudio) | Out-Null
$menuStrip.Items.Add($btnTheme) | Out-Null
$menuStrip.Items.Add($btnComposer) | Out-Null
$menuStrip.Items.Add($btnWav) | Out-Null
$menuStrip.Items.Add($btnDl) | Out-Null
$menuStrip.Items.Add($btnPlDl) | Out-Null
$form.MainMenuStrip = $menuStrip
$form.Controls.Add($menuStrip)

# --- STANDARD SUNO STUDIO TOP NAVIGATION BAR ENGINE (ស្ទីលធម្មតា) ---
Log-Step "Step 5b: Setting up Standard Suno Studio Top Navigation Bar"

function New-SunoStandardNavButton($text, $colStart = $null, $colEnd = $null, $hoverStart = $null, $hoverEnd = $null, $textColor = [System.Drawing.Color]::White, $onClick = $null, $fixedWidth = 0, $isPrimary = $false, $isBrand = $false) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::Transparent
    $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::Transparent
    $btn.BackColor = [System.Drawing.Color]::Transparent
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
    $btn.Height = 28
    $btn.Margin = New-Object System.Windows.Forms.Padding(2, 2, 2, 2)

    $btnState = [PSCustomObject]@{
        Label = $text
        IsHovered = $false
        IsPressed = $false
    }
    $btn.Tag = $btnState

    if ($fixedWidth -gt 0) {
        $btn.Width = $fixedWidth
    } else {
        $sz = [System.Windows.Forms.TextRenderer]::MeasureText($text, $btn.Font)
        $btn.Width = [Math]::Max([int]($sz.Width + 18), 58)
    }

    # Do not set $btn.Text so Windows base button renderer doesn't draw duplicate ghost text underneath!
    $btn.Text = ""

    $btn.Add_MouseEnter({
        $this.Tag.IsHovered = $true
        $this.Invalidate()
    })
    $btn.Add_MouseLeave({
        $this.Tag.IsHovered = $false
        $this.Tag.IsPressed = $false
        $this.Invalidate()
    })
    $btn.Add_MouseDown({
        $this.Tag.IsPressed = $true
        $this.Invalidate()
    })
    $btn.Add_MouseUp({
        $this.Tag.IsPressed = $false
        $this.Invalidate()
    })

    if ($onClick) {
        $btn.Add_Click($onClick)
    }

    $btn.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        $w = $s.ClientSize.Width
        $h = $s.ClientSize.Height
        if ($w -le 4 -or $h -le 4) { return }

        $isHover = $s.Tag.IsHovered
        $isPress = $s.Tag.IsPressed

        # Standard Modern Rounded Rectangle (Radius = 6px) - ស្ទីលធម្មតាស្របគ្នាជាមួយ Suno
        $radius = 6
        $diam = $radius * 2
        $rect = New-Object System.Drawing.Rectangle 1, 1, ($w - 2), ($h - 2)

        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $arc = New-Object System.Drawing.Rectangle ($rect.X), ($rect.Y), $diam, $diam
        $path.AddArc($arc, 180, 90)
        $arc.X = $rect.Right - $diam
        $path.AddArc($arc, 270, 90)
        $arc.Y = $rect.Bottom - $diam
        $path.AddArc($arc, 0, 90)
        $arc.X = $rect.Left
        $path.AddArc($arc, 90, 90)
        $path.CloseFigure()

        if ($isPrimary) {
            # Suno Standard Orange Primary Button (#ea580c / #f97316)
            $fillCol = if ($isPress) {
                [System.Drawing.Color]::FromArgb(194, 65, 12)
            } elseif ($isHover) {
                [System.Drawing.Color]::FromArgb(249, 115, 22)
            } else {
                [System.Drawing.Color]::FromArgb(234, 88, 12)
            }
            $fillBrush = New-Object System.Drawing.SolidBrush($fillCol)
            $g.FillPath($fillBrush, $path)
            $fillBrush.Dispose()

            $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(251, 146, 60), 1.0)
            $g.DrawPath($borderPen, $path)
            $borderPen.Dispose()
        } elseif ($isBrand) {
            # Suno Brand Pill/Button (Standard Dark)
            $fillCol = if ($isHover) { [System.Drawing.Color]::FromArgb(39, 39, 42) } else { [System.Drawing.Color]::FromArgb(24, 24, 27) }
            $bgBrush = New-Object System.Drawing.SolidBrush($fillCol)
            $g.FillPath($bgBrush, $path)
            $bgBrush.Dispose()

            $borderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(63, 63, 70), 1.0)
            $g.DrawPath($borderPen, $path)
            $borderPen.Dispose()
        } else {
            # Suno Standard Dark Studio Button (#18181b idle, #27272a hover, #141416 press)
            $fillCol = if ($isPress) {
                [System.Drawing.Color]::FromArgb(20, 20, 22)
            } elseif ($isHover) {
                [System.Drawing.Color]::FromArgb(39, 39, 42)
            } else {
                [System.Drawing.Color]::FromArgb(24, 24, 27)
            }
            $fillBrush = New-Object System.Drawing.SolidBrush($fillCol)
            $g.FillPath($fillBrush, $path)
            $fillBrush.Dispose()

            $borderCol = if ($isHover) {
                [System.Drawing.Color]::FromArgb(82, 82, 91)
            } else {
                [System.Drawing.Color]::FromArgb(45, 45, 52)
            }
            $borderPen = New-Object System.Drawing.Pen($borderCol, 1.0)
            $g.DrawPath($borderPen, $path)
            $borderPen.Dispose()
        }

        # Crisp Text Rendering Centered
        $yOff = if ($isPress) { 1 } else { 0 }
        $flags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::SingleLine -bor [System.Windows.Forms.TextFormatFlags]::NoPadding
        $tRect = New-Object System.Drawing.Rectangle 0, $yOff, $w, $h
        $txtCol = if ($isPrimary) {
            [System.Drawing.Color]::White
        } elseif ($isHover) {
            [System.Drawing.Color]::FromArgb(255, 255, 255)
        } else {
            [System.Drawing.Color]::FromArgb(228, 228, 231)
        }
        $lblText = if ($s.Tag -and $s.Tag.Label) { $s.Tag.Label } else { $text }
        [System.Windows.Forms.TextRenderer]::DrawText($g, $lblText, $s.Font, $tRect, $txtCol, $flags)

        $path.Dispose()
    })

    return $btn
}

# Backward compatibility alias
function New-IOS27CapsuleButton {
    param($a,$b,$c,$d,$e,$f,$g,$h,$i,$j)
    New-SunoStandardNavButton $a $b $c $d $e $f $g $h $i $j
}

# --- Build Suno-Native Top Capsule Navigation Bar Container & Auto-Hide Engine ---
$topContainer = New-Object System.Windows.Forms.Panel
$topContainer.Dock = [System.Windows.Forms.DockStyle]::Top
$topContainer.Height = 40
$topContainer.BackColor = [System.Drawing.Color]::FromArgb(9, 9, 11)

$topBar = New-Object System.Windows.Forms.Panel
$topBar.Dock = [System.Windows.Forms.DockStyle]::Fill
$topBar.BackColor = [System.Drawing.Color]::Transparent

$topContainer.Controls.Add($topBar)

# Auto-Hide & Animation State
$script:isTopBarExpanded = $true
$script:isTopBarPinned = $true  # Pinned by default: sits above Suno cleanly without covering anything!
$script:targetContainerHeight = 40
$script:leaveTicks = 0

$script:topAnimTimer = New-Object System.Windows.Forms.Timer
$script:topAnimTimer.Interval = 15
$script:topAnimTimer.Add_Tick({
    $curH = $topContainer.Height
    $tarH = $script:targetContainerHeight
    if ($curH -lt $tarH) {
        $nextH = [Math]::Min($curH + 8, $tarH)
        $topContainer.Height = $nextH
    } elseif ($curH -gt $tarH) {
        $nextH = [Math]::Max($curH - 8, $tarH)
        $topContainer.Height = $nextH
    }
    if ($topContainer.Height -eq $tarH) {
        $script:topAnimTimer.Stop()
        if ($tarH -le 4) {
            $topBar.Visible = $false
        }
    }
})

function Expand-TopBar {
    if ($script:isTopBarExpanded) { return }
    $script:isTopBarExpanded = $true
    $topBar.Visible = $true
    $script:targetContainerHeight = 40
    $script:leaveTicks = 0
    $script:topAnimTimer.Start()
}

function Collapse-TopBar {
    if (-not $script:isTopBarExpanded -or $script:isTopBarPinned) { return }
    $script:isTopBarExpanded = $false
    $script:targetContainerHeight = 4 # Ambient glowing line
    $script:topAnimTimer.Start()
}

function Toggle-TopBar {
    if ($script:isTopBarExpanded) {
        Collapse-TopBar
    } else {
        Expand-TopBar
    }
}

# Auto-Hide Timer when mouse leaves
$topBarLeaveTimer = New-Object System.Windows.Forms.Timer
$topBarLeaveTimer.Interval = 200
$topBarLeaveTimer.Add_Tick({
    try {
        if ($script:isTopBarPinned) { return }
        if (-not $form.Visible -or $form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { return }

        $mPt = $form.PointToClient([System.Windows.Forms.Cursor]::Position)
        $inWindow = ($mPt.X -ge 0 -and $mPt.X -le $form.ClientSize.Width -and $mPt.Y -ge 0 -and $mPt.Y -le $form.ClientSize.Height)

        if ($inWindow -and $mPt.Y -le 6) {
            # Hovering near top edge
            Expand-TopBar
            $script:leaveTicks = 0
        } elseif ($script:isTopBarExpanded) {
            if (-not $inWindow -or $mPt.Y -gt $topContainer.Height) {
                $isMenuOpen = ($fileMenu.DropDown.Visible -or $toolsMenu.DropDown.Visible)
                if (-not $isMenuOpen) {
                    $script:leaveTicks++
                    if ($script:leaveTicks -ge 7) { # ~1.4 seconds
                        Collapse-TopBar
                    }
                } else {
                    $script:leaveTicks = 0
                }
            } else {
                $script:leaveTicks = 0
            }
        }
    } catch { }
})
$topBarLeaveTimer.Start()

# Ambient line paint for collapsed topContainer
$topContainer.Add_Paint({
    param($s, $e)
    if ($s.Height -le 6) {
        $g = $e.Graphics
        $g.Clear([System.Drawing.Color]::FromArgb(9, 9, 11))
        $penGlow = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180, 56, 189, 248), 2)
        $g.DrawLine($penGlow, 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
        $penGlow.Dispose()
    }
})

# Paint event for Suno Obsidian Bar
$topBar.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $w = $s.ClientSize.Width
    $h = $s.ClientSize.Height
    if ($w -le 2 -or $h -le 2) { return }

    # Suno Obsidian Black Background
    $bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(9, 9, 11))
    $g.FillRectangle($bgBrush, 0, 0, $w, $h)
    $bgBrush.Dispose()

    # Hairline Bottom Divider matching Suno column split lines
    $penBottom = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(30, 31, 36), 1)
    $g.DrawLine($penBottom, 0, ($h - 1), $w, ($h - 1))
    $penBottom.Dispose()
})

# Pinned Right Panel for Utilities (Pin, F5, F11)
$topRightPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$topRightPanel.Dock = [System.Windows.Forms.DockStyle]::Right
$topRightPanel.Width = 150
$topRightPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
$topRightPanel.WrapContents = $false
$topRightPanel.BackColor = [System.Drawing.Color]::FromArgb(9, 9, 11)
$topRightPanel.Padding = New-Object System.Windows.Forms.Padding(2, 5, 6, 5)

# Left Flow Panel for Primary Navigation Capsules
$topFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$topFlow.Dock = [System.Windows.Forms.DockStyle]::Fill
$topFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$topFlow.WrapContents = $false
$topFlow.AutoScroll = $false
$topFlow.BackColor = [System.Drawing.Color]::Transparent
$topFlow.Padding = New-Object System.Windows.Forms.Padding(6, 5, 2, 5)

# Dock order: Add Right Dock FIRST, Fill Dock SECOND, and Send Right to Back for 100% collision-free layout
$topBar.Controls.Add($topRightPanel)
$topBar.Controls.Add($topFlow)
$topRightPanel.SendToBack()

# 0. Suno Studio Brand Badge
$btnTopBrand = New-IOS27CapsuleButton "SUNO ✦" `
    ([System.Drawing.Color]::White) `
    $null $null $null `
    ([System.Drawing.Color]::White) `
    { if ($wv.CoreWebView2) { $wv.Source = New-Object System.Uri("https://suno.com") } } `
    75 $false $true

# 1. File Menu Pill (Frosted Obsidian Capsule)
$btnTopFile = New-IOS27CapsuleButton "📁 ឯកសារ" `
    ([System.Drawing.Color]::FromArgb(195, 205, 230)) `
    $null $null $null `
    ([System.Drawing.Color]::White) `
    { $fileMenu.DropDown.Show($btnTopFile, 0, $btnTopFile.Height + 2) } `
    65

# 2. Tools Menu Pill (Frosted Obsidian Capsule)
$btnTopTools = New-IOS27CapsuleButton "🛠️ ឧបករណ៍" `
    ([System.Drawing.Color]::FromArgb(195, 205, 230)) `
    $null $null $null `
    ([System.Drawing.Color]::White) `
    { $toolsMenu.DropDown.Show($btnTopTools, 0, $btnTopTools.Height + 2) } `
    70

# 3. F6 Auto-Generate (Flagship Suno Solar Aurora Flame Gradient)
$btnTopGen = New-IOS27CapsuleButton "✨ បង្កើត F6" `
    ([System.Drawing.Color]::FromArgb(255, 94, 58)) `
    $null $null $null `
    ([System.Drawing.Color]::White) `
    { GenerateSongFromHost } `
    95 $true

# 4. Ctrl+M AI Studio (Neon Rose Glow)
$btnTopStudio = New-IOS27CapsuleButton "🎵 Studio" `
    ([System.Drawing.Color]::FromArgb(233, 64, 87)) `
    $null $null $null `
    ([System.Drawing.Color]::White) `
    { GenerateSongFromHost } `
    68

# 4b. Theme & Style Selector Pill (Fuchsia Pink Rose Glow)
$btnTopTheme = New-IOS27CapsuleButton "🎨 Theme" `
    ([System.Drawing.Color]::FromArgb(244, 114, 182)) `
    $null $null $null `
    ([System.Drawing.Color]::White) `
    { LaunchThemeSelectorApp } `
    68

# 5. Composer App (Emerald Mint Glow)
$btnTopComposer = New-IOS27CapsuleButton "🎼 និពន្ធ" `
    ([System.Drawing.Color]::FromArgb(16, 185, 129)) `
    $null $null $null `
    ([System.Drawing.Color]::White) `
    { LaunchComposerApp } `
    65

# 6. WAV Grabber (Electric Azure Glow)
$btnTopWav = New-IOS27CapsuleButton "🔊 WAV" `
    ([System.Drawing.Color]::FromArgb(56, 189, 248)) `
    $null $null $null `
    ([System.Drawing.Color]::White) `
    { ToggleWav } `
    60

# 7. Downloader (Indigo Sapphire Glow)
$btnTopDl = New-IOS27CapsuleButton "📥 ទាញយក" `
    ([System.Drawing.Color]::FromArgb(99, 102, 241)) `
    $null $null $null `
    ([System.Drawing.Color]::White) `
    { LaunchDownloaderApp } `
    70

# 8. Playlist ZIP (Golden Amber Glow)
$btnTopPlDl = New-IOS27CapsuleButton "📦 Playlist" `
    ([System.Drawing.Color]::FromArgb(245, 158, 11)) `
    $null $null $null `
    ([System.Drawing.Color]::White) `
    { LaunchPlaylistDownloaderApp } `
    70

# 9. Auto-Loop Pill (Amethyst Purple Glow)
$btnTopLoop = New-IOS27CapsuleButton "🔁 Loop" `
    ([System.Drawing.Color]::FromArgb(168, 85, 247)) `
    $null $null $null `
    ([System.Drawing.Color]::White) `
    {
        if ($wv.CoreWebView2) {
            $wv.ExecuteScriptAsync("if (window.toggleAutoLoop) { window.toggleAutoLoop(); }") | Out-Null
        }
    } `
    65
$script:btnTopLoop = $btnTopLoop

# 10. Reload F5 (Frosted Silver Outline)
$btnTopReload = New-IOS27CapsuleButton "🔄" `
    ([System.Drawing.Color]::FromArgb(195, 205, 230)) `
    $null $null $null `
    ([System.Drawing.Color]::White) `
    { if ($wv.CoreWebView2) { $wv.Reload() } } `
    34

# 11. Fullscreen F11 (Frosted Silver Outline)
$btnTopFull = New-IOS27CapsuleButton "🖥️" `
    ([System.Drawing.Color]::FromArgb(195, 205, 230)) `
    $null $null $null `
    ([System.Drawing.Color]::White) `
    { ToggleFull } `
    34

$topFlow.Controls.AddRange(@(
    $btnTopBrand,
    $btnTopFile,
    $btnTopTools,
    $btnTopGen,
    $btnTopStudio,
    $btnTopTheme,
    $btnTopComposer,
    $btnTopWav,
    $btnTopDl,
    $btnTopPlDl,
    $btnTopLoop
))

# 12. Pin / Auto-Hide Toggle Pill (Frosted Silver Outline)
$btnTopPin = New-IOS27CapsuleButton "📌 ខ្ទាស់" `
    ([System.Drawing.Color]::FromArgb(195, 205, 230)) `
    $null $null $null `
    ([System.Drawing.Color]::White) `
    {
        $script:isTopBarPinned = -not $script:isTopBarPinned
        if ($script:isTopBarPinned) {
            $btnTopPin.Tag.Label = "📌 ខ្ទាស់"
            $btnTopPin.Invalidate()
            Expand-TopBar
        } else {
            $btnTopPin.Tag.Label = "🔓 លាក់"
            $btnTopPin.Invalidate()
        }
    } `
    65

$topRightPanel.Controls.AddRange(@(
    $btnTopPin,
    $btnTopReload,
    $btnTopFull
))

# --- System Tray Implementation (Close to Tray & Background Persistence) ---
$script:isQuitting = $false
$script:hasShownBalloon = $false

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
if ($form.Icon) {
    $notifyIcon.Icon = $form.Icon
}
$notifyIcon.Text = "Suno AI Desktop (កំពុងដំណើរការជាធម្មតា)"
$notifyIcon.Visible = $true

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$trayMenu.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 30)
$trayMenu.ForeColor = [System.Drawing.Color]::FromArgb(230, 230, 240)
$trayMenu.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

# Open Window
$tOpen = $trayMenu.Items.Add("🎼 បើកផ្ទាំង Suno Studio (Open Suno)")
$tOpen.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$tOpen.Add_Click({
    $form.Show()
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.ShowInTaskbar = $true
    $form.Activate()
    $form.BringToFront()
    [SunoWin32]::ShowWindow($form.Handle, 9) | Out-Null
    [SunoWin32]::SetForegroundWindow($form.Handle) | Out-Null
})

$tGen = $trayMenu.Items.Add("🎵 និពន្ធចម្រៀងស្វ័យប្រវត្តិ (F6)")
$tGen.Add_Click({ GenerateSongFromHost })

$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$tComp = $trayMenu.Items.Add("✨ កម្មវិធីនិពន្ធចម្រៀង (Suno Composer)")
$tComp.Add_Click({ LaunchComposerApp })

$tTheme = $trayMenu.Items.Add("🎨 កម្មវិធីជ្រើសរើស Theme (Theme Selector - Ctrl+T)")
$tTheme.Add_Click({ LaunchThemeSelectorApp })

$tDl = $trayMenu.Items.Add("📥 កម្មវិធីទាញយកចម្រៀង (Suno Downloader)")
$tDl.Add_Click({ LaunchDownloaderApp })

$tPlDl = $trayMenu.Items.Add("📦 ទាញយក Playlist ZIP (Playlist Downloader)")
$tPlDl.Add_Click({ LaunchPlaylistDownloaderApp })

$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$tLoop = $trayMenu.Items.Add("🔁 បិទ/បើក វិលជុំស្វ័យប្រវត្តិ (Toggle Auto-Loop)")
$tLoop.Add_Click({
    if ($wv.CoreWebView2) {
        $wv.ExecuteScriptAsync("if (window.toggleAutoLoop) { window.toggleAutoLoop(); }") | Out-Null
    }
})

$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

# Feature 1: Close to Tray Toggle
$script:tCloseTray = New-Object System.Windows.Forms.ToolStripMenuItem("🌟 ពេលបិទពី Taskbar ឱ្យបន្តដំណើរការ (Close to Tray)")
$script:tCloseTray.CheckOnClick = $true
$script:tCloseTray.Checked = $script:desktopSettings.closeToTray
$script:tCloseTray.Add_CheckedChanged({
    $script:desktopSettings.closeToTray = $script:tCloseTray.Checked
    Save-DesktopSettings
    if ($itemCloseTray) { $itemCloseTray.Checked = $script:tCloseTray.Checked }
})
$trayMenu.Items.Add($script:tCloseTray) | Out-Null

# Feature 2: Run On Startup Toggle
$script:tStartup = New-Object System.Windows.Forms.ToolStripMenuItem("🚀 Run On Startup (ដំណើរការស្វ័យប្រវត្តពេលបើកកុំព្យូទ័រ)")
$script:tStartup.CheckOnClick = $true
$script:tStartup.Checked = $script:desktopSettings.runOnStartup
$script:tStartup.Add_CheckedChanged({
    Set-RunOnStartup $script:tStartup.Checked
    if ($itemStartup) { $itemStartup.Checked = $script:tStartup.Checked }
})
$trayMenu.Items.Add($script:tStartup) | Out-Null

$trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$tQuit = $trayMenu.Items.Add("❌ ចាកចេញពីកម្មវិធីទាំងស្រុង (Quit Completely)")
$tQuit.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 100)
$tQuit.Add_Click({
    $script:isQuitting = $true
    if ($notifyIcon) { $notifyIcon.Visible = $false; $notifyIcon.Dispose() }
    $form.Close()
})

$notifyIcon.ContextMenuStrip = $trayMenu

$notifyIcon.Add_Click({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($form.Visible -and $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized) {
            $form.Hide()
            $form.ShowInTaskbar = $false
        } else {
            $form.Show()
            $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
            $form.ShowInTaskbar = $true
            $form.Activate()
            $form.BringToFront()
            [SunoWin32]::ShowWindow($form.Handle, 9) | Out-Null
            [SunoWin32]::SetForegroundWindow($form.Handle) | Out-Null
        }
    }
})

$notifyIcon.Add_DoubleClick({
    $form.Show()
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.ShowInTaskbar = $true
    $form.Activate()
    $form.BringToFront()
    [SunoWin32]::ShowWindow($form.Handle, 9) | Out-Null
    [SunoWin32]::SetForegroundWindow($form.Handle) | Out-Null
})

Log-Step "Step 6: Setting up WebView2"
$script:wv = New-Object Microsoft.Web.WebView2.WinForms.WebView2
$wv = $script:wv
$wv.Dock = [System.Windows.Forms.DockStyle]::Fill
$wv.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 22)
$form.Controls.Add($wv)
$form.Controls.Add($topContainer)
$topContainer.SendToBack()

function ConvertTo-JsonArray($items) {
    if ($null -eq $items) { return "[]" }
    $arr = @($items)
    if ($arr.Count -eq 0) { return "[]" }
    if ($arr.Count -eq 1) {
        $single = $arr[0] | ConvertTo-Json -Depth 4 -Compress
        return "[$single]"
    }
    return ($arr | ConvertTo-Json -Depth 4)
}

function Get-FlatJsonArray($rawJson) {
    if ([string]::IsNullOrWhiteSpace($rawJson)) { return @() }
    $parsed = $rawJson | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($null -eq $parsed) { return @() }
    $result = @()
    foreach ($entry in $parsed) {
        if ($entry -is [System.Array]) {
            foreach ($sub in $entry) { if ($sub) { $result += $sub } }
        } elseif ($entry -and $entry.PSObject -and $entry.PSObject.Properties['value'] -and ($entry.value -is [System.Array])) {
            foreach ($sub in $entry.value) { if ($sub) { $result += $sub } }
        } elseif ($entry) {
            $result += $entry
        }
    }
    return ,$result
}

function Parse-WebMessage($rawMsg) {
    if ([string]::IsNullOrWhiteSpace($rawMsg)) { return $null }
    try {
        $p = $rawMsg | ConvertFrom-Json -ErrorAction Stop
        if ($p -is [string]) {
            try { $p = $p | ConvertFrom-Json -ErrorAction Stop } catch { }
        }
        return $p
    } catch {
        return $null
    }
}

function LaunchDownloaderApp([string]$url = "") {
    $dlBat = Join-Path $sunoDir "SunoDownloader.bat"
    $dlVbs = Join-Path $sunoDir "SunoDownloaderLauncher.vbs"
    $dlPs1 = Join-Path $sunoDir "SunoDownloader.ps1"
    if ($url) {
        Start-Process "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $dlPs1, "-url", "`"$url`"")
    } elseif (Test-Path $dlBat) {
        Start-Process $dlBat
    } elseif (Test-Path $dlVbs) {
        Start-Process "wscript.exe" -ArgumentList "`"$dlVbs`""
    } elseif (Test-Path $dlPs1) {
        Start-Process "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $dlPs1)
    }
}

function LaunchComposerApp {
    $cBat = Join-Path $sunoDir "SunoComposer.bat"
    $cPs1 = Join-Path $sunoDir "SunoComposerApp.ps1"
    if (Test-Path $cBat) {
        Start-Process $cBat
    } elseif (Test-Path $cPs1) {
        Start-Process "powershell.exe" -ArgumentList @("-ExecutionPolicy", "Bypass", "-File", $cPs1)
    }
}

function LaunchThemeSelectorApp {
    $tsBat = Join-Path $sunoDir "SunoThemeSelector.bat"
    $tsPs1 = Join-Path $sunoDir "SunoThemeSelector.ps1"
    if (Test-Path $tsBat) {
        Start-Process $tsBat
    } elseif (Test-Path $tsPs1) {
        Start-Process "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $tsPs1)
    }
}

function LaunchPlaylistDownloaderApp([string]$url = "") {
    $plBat = Join-Path $sunoDir "SunoPlaylistDownloader.bat"
    $plVbs = Join-Path $sunoDir "SunoPlaylistDownloaderLauncher.vbs"
    $plPs1 = Join-Path $sunoDir "SunoPlaylistDownloader.ps1"
    if ($url) {
        Start-Process "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $plPs1, "-playlistUrl", "`"$url`"")
    } elseif (Test-Path $plBat) {
        Start-Process $plBat
    } elseif (Test-Path $plVbs) {
        Start-Process "wscript.exe" -ArgumentList "`"$plVbs`""
    } elseif (Test-Path $plPs1) {
        Start-Process "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $plPs1)
    }
}

function ToggleStudio() {
    if ($wv.CoreWebView2) {
        $sJsPath = Join-Path $sunoDir "studio.js"
        if (Test-Path $sJsPath) {
            $sJs = [System.IO.File]::ReadAllText($sJsPath, [System.Text.Encoding]::UTF8)
            $wv.ExecuteScriptAsync($sJs) | Out-Null
        }
        $wv.ExecuteScriptAsync("if (window.openStudioDrawer) { window.openStudioDrawer('composer'); } else { document.getElementById('suno-studio-toggle')?.click(); }") | Out-Null
    }
}

function ToggleWav() {
    if ($wv.CoreWebView2) {
        $wv.ExecuteScriptAsync("document.getElementById('suno-wav-toggle')?.click();") | Out-Null
    }
}

function GenerateSongFromHost() {
    if ($wv.CoreWebView2) {
        $sJsPath = Join-Path $sunoDir "studio.js"
        if (Test-Path $sJsPath) {
            $sJs = [System.IO.File]::ReadAllText($sJsPath, [System.Text.Encoding]::UTF8)
            $wv.ExecuteScriptAsync($sJs) | Out-Null
        }
        $wv.ExecuteScriptAsync("if (window.openStudioDrawer) { window.openStudioDrawer('composer'); }") | Out-Null
        $wv.ExecuteScriptAsync("if (window.generateSong) { window.generateSong(); } else { (document.getElementById('suno-generate-btn-top') || document.getElementById('suno-generate-btn') || document.getElementById('suno-dock-btn-gen') || document.getElementById('suno-dock-btn-composer'))?.click(); }") | Out-Null
    }
}

$btnGen.Add_Click({ GenerateSongFromHost })
$itemDl.Add_Click({ LaunchDownloaderApp })
$btnDl.Add_Click({ LaunchDownloaderApp })
$btnPlDl.Add_Click({ LaunchPlaylistDownloaderApp })
$itemComposer.Add_Click({ LaunchComposerApp })
$btnComposer.Add_Click({ LaunchComposerApp })
$itemTheme.Add_Click({ LaunchThemeSelectorApp })
$btnTheme.Add_Click({ LaunchThemeSelectorApp })
$itemStudio.Add_Click({ GenerateSongFromHost })
$btnStudio.Add_Click({ GenerateSongFromHost })
$itemWav.Add_Click({ ToggleWav })
$btnWav.Add_Click({ ToggleWav })

$itemHome.Add_Click({ if ($wv.CoreWebView2) { $wv.Source = New-Object System.Uri("https://suno.com") } })
$itemCreate.Add_Click({ if ($wv.CoreWebView2) { $wv.Source = New-Object System.Uri("https://suno.com/create") } })
$itemReload.Add_Click({ if ($wv.CoreWebView2) { $wv.Reload() } })

$isFull = $false
$prevBorder = $form.FormBorderStyle
$prevState = $form.WindowState
function ToggleFull() {
    if (-not $script:isFull) {
        $script:prevBorder = $form.FormBorderStyle
        $script:prevState = $form.WindowState
        if ($topContainer) { $topContainer.Visible = $false }
        $menuStrip.Visible = $false
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
        $script:isFull = $true
    } else {
        if ($topContainer) { $topContainer.Visible = $true }
        $menuStrip.Visible = $false
        $form.FormBorderStyle = $script:prevBorder
        $form.WindowState = $script:prevState
        $script:isFull = $false
    }
}
$itemFull.Add_Click({ ToggleFull })

$form.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
        if ($wv.CoreWebView2) { $wv.Reload() }
        $e.Handled = $true
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::F6) {
        GenerateSongFromHost
        $e.Handled = $true
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::F11) {
        ToggleFull
        $e.Handled = $true
    } elseif ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::M) {
        GenerateSongFromHost
        $e.Handled = $true
    } elseif ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::W) {
        ToggleWav
        $e.Handled = $true
    } elseif ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::D) {
        LaunchDownloaderApp
        $e.Handled = $true
    } elseif ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::T) {
        LaunchThemeSelectorApp
        $e.Handled = $true
    }
})

# Queue Processor Timer (IPC Watcher)
$appQueueTimer = New-Object System.Windows.Forms.Timer
$appQueueTimer.Interval = 1000
$appQueueTimer.Add_Tick({
    try {
        $targetWv = if ($script:wv) { $script:wv } else { $wv }
        $baseDir = if ($script:sunoDir) { $script:sunoDir } else { $sunoDir }
        $mainForm = if ($script:form) { $script:form } else { $form }

        # 1. Download Queue
        $qPath = Join-Path $baseDir "download_queue.json"
        if (Test-Path $qPath) {
            try {
                $content = Get-Content $qPath -Raw -ErrorAction SilentlyContinue
                if ($content -and $content.Trim() -ne "[]") {
                    $items = Get-FlatJsonArray $content
                    $remaining = @()
                    $changed = $false
                    foreach ($it in $items) {
                        if ($it.source -eq "downloader_app" -and (-not $it.processed)) {
                            if ($targetWv -and $targetWv.CoreWebView2 -and $it.url) {
                                $it.processed = $true
                                $safeUrl = $it.url.Trim()
                                $js = "if (window.sunoDirectDownload) { window.sunoDirectDownload('$safeUrl'); }"
                                $targetWv.ExecuteScriptAsync($js) | Out-Null
                                $changed = $true
                                Log-Step "Processed download_queue item: $safeUrl"
                            } else {
                                $remaining += $it
                            }
                        } else {
                            $remaining += $it
                        }
                    }
                    if ($changed) {
                        [System.IO.File]::WriteAllText($qPath, (ConvertTo-JsonArray $remaining), [System.Text.Encoding]::UTF8)
                    }
                }
            } catch { Log-Step "DownloadQueue error: $_" }
        }

        # 2. Title Queue
        $tPath = Join-Path $baseDir "title_queue.json"
        if (Test-Path $tPath) {
            try {
                $tContent = Get-Content $tPath -Raw -ErrorAction SilentlyContinue
                if ($tContent -and $tContent.Trim() -ne "[]") {
                    $tItems = Get-FlatJsonArray $tContent
                    $tRemaining = @()
                    $tChanged = $false
                    foreach ($tIt in $tItems) {
                        if (-not $tIt.processed) {
                            if ($targetWv -and $targetWv.CoreWebView2 -and $tIt.title) {
                                $tIt.processed = $true
                                $safeTitleJson = $tIt.title | ConvertTo-Json -Compress
                                $js = "if (window.sunoSetTitle) { window.sunoSetTitle($safeTitleJson); }"
                                $targetWv.ExecuteScriptAsync($js) | Out-Null
                                $tChanged = $true
                                Log-Step "Processed title_queue item: $($tIt.title)"
                            } else {
                                $tRemaining += $tIt
                            }
                        } else {
                            $tRemaining += $tIt
                        }
                    }
                    if ($tChanged) {
                        [System.IO.File]::WriteAllText($tPath, (ConvertTo-JsonArray $tRemaining), [System.Text.Encoding]::UTF8)
                    }
                }
            } catch { Log-Step "TitleQueue error: $_" }
        }

        # 3. Song Queue (Auto-Loop, Compose, Clear, Title)
        $sSongPath = Join-Path $baseDir "song_queue.json"
        if (Test-Path $sSongPath) {
            try {
                $sContent = Get-Content $sSongPath -Raw -ErrorAction SilentlyContinue
                if ($sContent -and $sContent.Trim() -ne "[]") {
                    $sItems = Get-FlatJsonArray $sContent
                    $sRemaining = @()
                    $sChanged = $false
                    foreach ($sIt in $sItems) {
                        $isProcessed = $false
                        if ($sIt -and $sIt.PSObject -and $sIt.PSObject.Properties['processed']) {
                            $isProcessed = [bool]$sIt.processed
                        }
                        if (-not $isProcessed) {
                            if ($targetWv -and $targetWv.CoreWebView2) {
                                $sChanged = $true
                                Log-Step "Processing song_queue item: action=$($sIt.action)"
                                if ($sIt.action -eq "clear") {
                                    $js = "if (window.sunoClearAll) { window.sunoClearAll(); }"
                                    $targetWv.ExecuteScriptAsync($js) | Out-Null
                                } elseif ($sIt.action -eq "clear_lyrics") {
                                    $js = "if (window.sunoClearLyrics) { window.sunoClearLyrics(); }"
                                    $targetWv.ExecuteScriptAsync($js) | Out-Null
                                } elseif ($sIt.action -eq "start_auto_loop") {
                                    $js = "if (window.sunoAutoLoop) { window.sunoAutoLoop.start(); } if (window.toggleAutoLoop) { window.toggleAutoLoop(); }"
                                    $targetWv.ExecuteScriptAsync($js) | Out-Null
                                } elseif ($sIt.action -eq "stop_auto_loop") {
                                    $js = "if (window.sunoAutoLoop) { window.sunoAutoLoop.stop(); }"
                                    $targetWv.ExecuteScriptAsync($js) | Out-Null
                                } elseif ($sIt.action -eq "toggle_auto_loop") {
                                    $js = "if (window.toggleAutoLoop) { window.toggleAutoLoop(); }"
                                    $targetWv.ExecuteScriptAsync($js) | Out-Null
                                } elseif ($sIt.action -eq "gen_title") {
                                    $js = "if (window.sunoGenerateTitleOnly) { window.sunoGenerateTitleOnly(); }"
                                    $targetWv.ExecuteScriptAsync($js) | Out-Null
                                } elseif ($sIt.action -eq "reload") {
                                    $targetWv.Reload()
                                    Log-Step "Reloaded WebView2 via IPC"
                                } elseif ($sIt.action -eq "set_gemini_model") {
                                    $newModel = $sIt.model
                                    if ($newModel) {
                                        $cfgPath = Join-Path $baseDir "gemini_config.json"
                                        if (Test-Path $cfgPath) {
                                            try {
                                                $cfgObj = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
                                                $cfgObj.model = $newModel
                                                if ($sIt.apiKey) { $cfgObj.apiKey = $sIt.apiKey }
                                                $cfgObj | ConvertTo-Json -Depth 3 | Set-Content $cfgPath -Encoding UTF8
                                            } catch { }
                                        }
                                        $syncJs = "if (window.syncGeminiModel) { window.syncGeminiModel('$newModel'); } else { localStorage.setItem('gemini_model_choice', '$newModel'); }"
                                        $targetWv.ExecuteScriptAsync($syncJs) | Out-Null
                                        Log-Step "Synced Gemini model ($newModel) via IPC across application"
                                    }
                                } elseif ($sIt.action -eq "inject_studio") {
                                    $sJsPath = Join-Path $baseDir "studio.js"
                                    if (Test-Path $sJsPath) {
                                        $sJs = [System.IO.File]::ReadAllText($sJsPath, [System.Text.Encoding]::UTF8)
                                        $targetWv.ExecuteScriptAsync($sJs) | Out-Null
                                        Log-Step "Hot-injected studio.js via IPC"
                                    }
                                } elseif ($sIt.action -eq "switch_suno_model") {
                                    $targetM = if ($sIt.model) { $sIt.model } else { "v6-wild" }
                                    $js = "if (window.switchSunoModel) { window.switchSunoModel('$targetM'); }"
                                    $targetWv.ExecuteScriptAsync($js) | Out-Null
                                    Log-Step "Switched Suno model to $targetM via IPC"
                                } elseif ($sIt.action -eq "select_batch_songs") {
                                    $bCount = if ($sIt.count) { [int]$sIt.count } else { 14 }
                                    $js = "if (window.selectBatchSongs) { window.selectBatchSongs($bCount); }"
                                    $targetWv.ExecuteScriptAsync($js) | Out-Null
                                    Log-Step "Batch selected $bCount songs via IPC"
                                } elseif ($sIt.action -eq "deselect_all_songs") {
                                    $js = "if (window.deselectAllSongs) { window.deselectAllSongs(); }"
                                    $targetWv.ExecuteScriptAsync($js) | Out-Null
                                    Log-Step "Deselected all songs via IPC"
                                } elseif ($sIt.action -eq "create_playlist") {
                                    $bCount = if ($sIt.count) { [int]$sIt.count } else { 14 }
                                    $safePlJson = if ($sIt.name) { $sIt.name | ConvertTo-Json -Compress } else { '""' }
                                    $js = "if (window.createAndAddToPlaylist) { window.createAndAddToPlaylist($safePlJson, $bCount); }"
                                    $targetWv.ExecuteScriptAsync($js) | Out-Null
                                    Log-Step "Created playlist $($sIt.name) ($bCount tracks) via IPC"
                                } elseif ($sIt.action -eq "dedup_titles") {
                                    $js = "if (window.renameDuplicateSiblingClips) { window.renameDuplicateSiblingClips(); }"
                                    $targetWv.ExecuteScriptAsync($js) | Out-Null
                                    Log-Step "Triggered rename duplicate sibling clips via IPC"
                                } elseif ($sIt.action -eq "set_duration") {
                                    $durVal = if ($sIt.duration) { $sIt.duration } else { "auto" }
                                    $js = "if (window.setSunoSongDuration) { window.setSunoSongDuration('$durVal'); }"
                                    $targetWv.ExecuteScriptAsync($js) | Out-Null
                                    Log-Step "Set song duration to '$durVal' via IPC"
                                } else {
                                    $titleJson = if ($sIt.title) { $sIt.title | ConvertTo-Json -Compress } else { '""' }
                                    $styleJson = if ($sIt.style) { $sIt.style | ConvertTo-Json -Compress } else { '""' }
                                    $lyricsJson = if ($sIt.lyrics) { $sIt.lyrics | ConvertTo-Json -Compress } else { '""' }
                                    $js = "(function() { const l = $lyricsJson; const s = $styleJson; const t = $titleJson; if (window.mapAndFillSunoFields) { window.mapAndFillSunoFields(l, s, t); } const elT = document.getElementById('suno-title-output'); if (elT) elT.value = t; const elS = document.getElementById('suno-style-output'); if (elS) elS.value = s; const elL = document.getElementById('suno-lyrics-output'); if (elL) elL.value = l; if (window.openStudioDrawer) { window.openStudioDrawer('composer'); } })();"
                                    $targetWv.ExecuteScriptAsync($js) | Out-Null
                                    if ($sIt.action -eq "generate_with_data") {
                                        Start-Sleep -Milliseconds 500
                                        $clickCreateJs = @'
(function() {
    setTimeout(function() {
        if (typeof window.triggerSunoCreate === 'function') {
            window.triggerSunoCreate();
        } else {
            const b = document.querySelector('button[aria-label="Create song"]') || Array.from(document.querySelectorAll('button')).find(el => {
                const a = (el.getAttribute('aria-label')||'').toLowerCase();
                const t = (el.textContent||'').trim().toLowerCase();
                return (a.includes('create song') || t === 'create') && !el.id.startsWith('suno-');
            });
            if (b && !b.disabled && b.getAttribute('aria-disabled') !== 'true') {
                b.click();
            }
        }
    }, 600);
})();
'@
                                        $targetWv.ExecuteScriptAsync($clickCreateJs) | Out-Null
                                        Log-Step "Triggered native Suno Create song button via song_queue"
                                    }
                                }
                                try {
                                    $mainForm.Activate()
                                    $mainForm.BringToFront()
                                    [SunoWin32]::ShowWindow($mainForm.Handle, 5) | Out-Null
                                    [SunoWin32]::SetForegroundWindow($mainForm.Handle) | Out-Null
                                } catch { }
                            } else {
                                $sRemaining += $sIt
                            }
                        }
                    }
                    if ($sChanged) {
                        [System.IO.File]::WriteAllText($sSongPath, (ConvertTo-JsonArray $sRemaining), [System.Text.Encoding]::UTF8)
                    }
                }
            } catch { Log-Step "SongQueue error: $_" }
        }

        # 4. Queue Input (Theme Selector & Direct Command IPC)
        $qInPath = Join-Path $baseDir "queue_input.json"
        if (Test-Path $qInPath) {
            try {
                $qInContent = Get-Content $qInPath -Raw -ErrorAction SilentlyContinue
                if ($qInContent -and $qInContent.Trim()) {
                    $qInObj = $qInContent | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($qInObj -and (-not $qInObj.processed)) {
                        Remove-Item $qInPath -Force -ErrorAction SilentlyContinue
                        if ($targetWv -and $targetWv.CoreWebView2) {
                            $titleJson = if ($qInObj.title) { $qInObj.title | ConvertTo-Json -Compress } else { '""' }
                            $styleJson = if ($qInObj.style) { $qInObj.style | ConvertTo-Json -Compress } else { '""' }
                            $lyricsJson = if ($qInObj.lyrics) { $qInObj.lyrics | ConvertTo-Json -Compress } else { '""' }
                            $js = "(function() { const l = $lyricsJson; const s = $styleJson; const t = $titleJson; if (window.mapAndFillSunoFields) { window.mapAndFillSunoFields(l, s, t); } const elT = document.getElementById('suno-title-output'); if (elT) elT.value = t; const elS = document.getElementById('suno-style-output'); if (elS) elS.value = s; const elL = document.getElementById('suno-lyrics-output'); if (elL) elL.value = l; if (window.openStudioDrawer) { window.openStudioDrawer('composer'); } })();"
                            $targetWv.ExecuteScriptAsync($js) | Out-Null
                            if ($qInObj.action -eq "generate_with_data") {
                                Start-Sleep -Milliseconds 500
                                $clickCreateJs = @'
(function() {
    setTimeout(function() {
        if (typeof window.triggerSunoCreate === 'function') {
            window.triggerSunoCreate();
        } else {
            const b = document.querySelector('button[aria-label="Create song"]') || Array.from(document.querySelectorAll('button')).find(el => {
                const a = (el.getAttribute('aria-label')||'').toLowerCase();
                const t = (el.textContent||'').trim().toLowerCase();
                return (a.includes('create song') || t === 'create') && !el.id.startsWith('suno-');
            });
            if (b && !b.disabled && b.getAttribute('aria-disabled') !== 'true') {
                b.click();
            }
        }
    }, 600);
})();
'@
                                $targetWv.ExecuteScriptAsync($clickCreateJs) | Out-Null
                                Log-Step "Triggered native Suno Create song button via queue_input"
                            }
                            Log-Step "Processed queue_input.json: action=$($qInObj.action), title=$($qInObj.title)"
                            try {
                                $mainForm.Activate()
                                $mainForm.BringToFront()
                                [SunoWin32]::ShowWindow($mainForm.Handle, 5) | Out-Null
                                [SunoWin32]::SetForegroundWindow($mainForm.Handle) | Out-Null
                            } catch { }
                        }
                    }
                }
            } catch { Log-Step "QueueInput error: $_" }
        }
    } catch {
        Log-Step "FATAL in Add_Tick: $_"
    }
})
$form.Tag = $appQueueTimer
$appQueueTimer.Start()

$form.Add_Load({
    Log-Step "Step 7: Form Load event triggered"
    $dataDir = Join-Path $sunoDir "Data"
    if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Force -Path $dataDir | Out-Null }
    $userDataFolder = Join-Path $dataDir "UserData"
    if (-not (Test-Path $userDataFolder)) { New-Item -ItemType Directory -Force -Path $userDataFolder | Out-Null }

    $props = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
    $props.UserDataFolder = $userDataFolder
    $props.AdditionalBrowserArguments = "--disable-blink-features=AutomationControlled --enable-features=NetworkService,NetworkServiceInProcess"
    $wv.CreationProperties = $props

    $wv.add_CoreWebView2InitializationCompleted({
        param($s, $e)
        Log-Step "Step 8: CoreWebView2 init completed. IsSuccess: $($e.IsSuccess)"
        if (-not $e.IsSuccess) {
            Log-Step "CoreWebView2 init failed: $($e.InitializationException)"
            if ("$($e.InitializationException)" -match "0x800700AA" -or "$($e.InitializationException)" -match "resource is in use") {
                Log-Step "Retrying CoreWebView2 initialization after releasing directory lock..."
                Start-Sleep -Milliseconds 800
                $wv.EnsureCoreWebView2Async()
            }
            return
        }

        # Modern Chrome Stealth User-Agent (avoids bot detection and Turnstile CSP blocks)
        try {
            $wv.CoreWebView2.Settings.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
            $wv.CoreWebView2.Settings.AreDefaultScriptDialogsEnabled = $true
        } catch { }

        $wv.CoreWebView2.Settings.IsStatusBarEnabled = $false
        $wv.CoreWebView2.Settings.AreDefaultContextMenusEnabled = $true
        $wv.CoreWebView2.Settings.IsZoomControlEnabled = $true

        $wv.CoreWebView2.add_DownloadStarting({
            param($sender, $eventArgs)
            try {
                $dlFolder = Join-Path $dataDir "Downloads"
                if (-not (Test-Path $dlFolder)) { New-Item -ItemType Directory -Force -Path $dlFolder | Out-Null }

                $fileName = $eventArgs.SuggestedFileName
                if (-not $fileName) { $fileName = "Suno_Song_$([DateTime]::UtcNow.Ticks).wav" }
                $eventArgs.ResultFilePath = Join-Path $dlFolder $fileName
                $eventArgs.Handled = $true
            } catch { }
        })

        $wv.CoreWebView2.add_WebMessageReceived({
            param($sender, $eventArgs)
            try {
                $rawMsg = $eventArgs.WebMessageAsJson
                $parsed = Parse-WebMessage $rawMsg
                $action = if ($parsed) { if ($parsed.action) { $parsed.action } else { $parsed.type } } else { "" }
                $url = if ($parsed -and $parsed.url) { $parsed.url } else { "" }
                if (-not $url -and $rawMsg -match 'https?://suno\.com/(?:playlist|song)/[a-f0-9\-]+') {
                    $url = $matches[0]
                }

                if ($action -eq 'open_playlist_downloader' -or $action -eq 'download_playlist_zip' -or ($url -match '/playlist/')) {
                    if ($url) { LaunchPlaylistDownloaderApp $url } else { LaunchPlaylistDownloaderApp }
                } elseif ($action -eq 'open_downloader' -or ($url -match '/song/')) {
                    if ($url) { LaunchDownloaderApp $url } else { LaunchDownloaderApp }
                } elseif ($action -eq 'open_composer') {
                    LaunchComposerApp
                } elseif ($action -eq 'auto_loop_status' -or $rawMsg -match 'auto_loop_status') {
                    if ($parsed -and ($null -ne $parsed.active)) {
                        $isActive = [bool]$parsed.active
                        if ($script:btnTopLoop) {
                            $loopText = if ($isActive) { "🔁 Loop (ON)" } else { "🔁 Loop" }
                            $script:btnTopLoop.Tag.Label = $loopText
                            $sz = [System.Windows.Forms.TextRenderer]::MeasureText($loopText, $script:btnTopLoop.Font)
                            $script:btnTopLoop.Width = [Math]::Max([int]($sz.Width + 18), 75)
                            $script:btnTopLoop.Invalidate()
                        }
                    }
                } elseif ($action -eq 'set_gemini_model') {
                    if ($parsed -and $parsed.model) {
                        $cfgPath = Join-Path $sunoDir "gemini_config.json"
                        $cfgObj = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { [PSCustomObject]@{} }
                        $cfgObj.model = $parsed.model
                        if ($parsed.apiKey) { $cfgObj.apiKey = $parsed.apiKey }
                        $cfgObj | ConvertTo-Json -Depth 3 | Set-Content $cfgPath -Encoding UTF8
                        Log-Step "Saved Gemini model from WebMessage: $($parsed.model)"
                    }
                } elseif ($action -eq 'set_song_language') {
                    if ($parsed -and $parsed.language) {
                        $cfgPath = Join-Path $sunoDir "gemini_config.json"
                        $cfgObj = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { [PSCustomObject]@{} }
                        $cfgObj.language = $parsed.language
                        if ($parsed.customLanguage) { $cfgObj.customLanguage = $parsed.customLanguage }
                        $cfgObj | ConvertTo-Json -Depth 3 | Set-Content $cfgPath -Encoding UTF8
                        Log-Step "Saved Song Language from WebMessage: $($parsed.language)"
                    }
                } elseif ($action -eq 'set_desktop_settings') {
                    if ($parsed) {
                        if ($null -ne $parsed.closeToTray) {
                            $script:desktopSettings.closeToTray = [bool]$parsed.closeToTray
                            if ($itemCloseTray) { $itemCloseTray.Checked = $script:desktopSettings.closeToTray }
                            if ($script:tCloseTray) { $script:tCloseTray.Checked = $script:desktopSettings.closeToTray }
                        }
                        if ($null -ne $parsed.runOnStartup) {
                            Set-RunOnStartup ([bool]$parsed.runOnStartup)
                            if ($itemStartup) { $itemStartup.Checked = [bool]$parsed.runOnStartup }
                            if ($script:tStartup) { $script:tStartup.Checked = [bool]$parsed.runOnStartup }
                        }
                        Save-DesktopSettings
                    }
                }
            } catch { Log-Step "Error in WebMessageReceived: $_" }
        })

        $studioScriptPath = Join-Path $sunoDir "studio.js"
        if (Test-Path $studioScriptPath) {
            $studioJs = [System.IO.File]::ReadAllText($studioScriptPath, [System.Text.Encoding]::UTF8)
            try {
                $null = $wv.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync($studioJs)
                Log-Step "Step 9: Added studio.js to WebView2 via AddScriptToExecuteOnDocumentCreatedAsync"
            } catch {
                Log-Step "Warning: AddScriptToExecuteOnDocumentCreatedAsync error: $_"
            }
        }

        $wv.CoreWebView2.add_NavigationCompleted({
            param($sender, $eventArgs)
            Log-Step "NavigationCompleted. IsSuccess: $($eventArgs.IsSuccess)"
            if ($eventArgs.IsSuccess) {
                try {
                    $sJsPath = Join-Path $sunoDir "studio.js"
                    if (Test-Path $sJsPath) {
                        $sJs = [System.IO.File]::ReadAllText($sJsPath, [System.Text.Encoding]::UTF8)
                        $wv.ExecuteScriptAsync($sJs) | Out-Null
                        Log-Step "Injected studio.js via NavigationCompleted"

                        # Sync gemini_config.json to WebView2
                        $cfgPath = Join-Path $sunoDir "gemini_config.json"
                        if (Test-Path $cfgPath) {
                            try {
                                $cfgObj = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
                                $mCode = $cfgObj.model
                                $mKey = if ($cfgObj.apiKey) { $cfgObj.apiKey } else { "" }
                                $syncJs = "(function() { localStorage.setItem('gemini_model_choice', '$mCode'); if ('$mKey') { localStorage.setItem('gemini_api_key', '$mKey'); } if (window.syncGeminiModel) { window.syncGeminiModel('$mCode'); } })();"
                                $wv.ExecuteScriptAsync($syncJs) | Out-Null
                                Log-Step "Synced gemini_config ($mCode) to WebView2 on NavigationCompleted"
                            } catch { }
                        }
                    }
                } catch {
                    Log-Step "Warning: NavigationCompleted inject error: $_"
                }
            }
        })

        $wv.CoreWebView2.add_DocumentTitleChanged({
            try {
                $title = $wv.CoreWebView2.DocumentTitle
                if ($title -and (-not $title.Contains("http"))) {
                    $form.Text = "$title - Suno Desktop"
                }
            } catch { }
        })
    })

    Log-Step "Step 10: Setting wv.Source to suno.com/create"
    $wv.Source = New-Object System.Uri("https://suno.com/create")
})

$form.Add_Shown({
    Log-Step "Step 11: Form Shown event triggered (hidden=$hidden)"
    if ($hidden) {
        $form.Hide()
        $form.ShowInTaskbar = $false
        Log-Step "Started silently in System Tray (-hidden specified)"
    } else {
        try {
            $form.ShowInTaskbar = $true
            $form.Activate()
            $form.BringToFront()
            [SunoWin32]::ShowWindow($form.Handle, 5) | Out-Null
            [SunoWin32]::SetForegroundWindow($form.Handle) | Out-Null
        } catch { }
    }
})

$form.Add_FormClosing({
    param($s, $e)
    Log-Step "Form Closing event triggered. CloseReason: $($e.CloseReason), isQuitting: $($script:isQuitting)"

    if (-not $script:isQuitting -and $script:desktopSettings.closeToTray) {
        $e.Cancel = $true
        $form.Hide()
        $form.ShowInTaskbar = $false
        Log-Step "Window hidden to System Tray (Taskbar unpinned, background loop active)"

        if (-not $script:hasShownBalloon) {
            $script:hasShownBalloon = $true
            try {
                $notifyIcon.ShowBalloonTip(3000, "Suno AI Desktop", "កម្មវិធីនៅតែបន្តដំណើរការជាធម្មតាក្នុងរបារ System Tray (ចុចលើរូប Icon ដើម្បីបើកវិញ)។", [System.Windows.Forms.ToolTipIcon]::Info)
            } catch { }
        }
        return
    }

    if ($notifyIcon) {
        try {
            $notifyIcon.Visible = $false
            $notifyIcon.Dispose()
        } catch { }
    }
    if ($appQueueTimer) {
        try { $appQueueTimer.Stop() } catch { }
    }
    if ($appMutex) {
        try { $appMutex.ReleaseMutex() } catch { }
        $appMutex.Dispose()
    }
})

Log-Step "Step 12: Calling ShowDialog()"
[System.Windows.Forms.Application]::EnableVisualStyles()
$null = $form.ShowDialog()
Log-Step "SunoApp Exited naturally"

