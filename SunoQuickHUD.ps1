# ==============================================================================
# Suno AI Studio Pro - Quick Action Desktop HUD Widget (SunoQuickHUD.ps1)
# Sleek, Floating Always-On-Top Mini Dashboard for Suno Creators
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# High DPI Awareness
$win32Dpi = @"
using System;
using System.Runtime.InteropServices;
public class SunoHudDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")]
    public static extern bool ReleaseCapture();
    [DllImport("user32.dll")]
    public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);
}
"@
try {
    Add-Type -TypeDefinition $win32Dpi -ErrorAction SilentlyContinue
    [SunoHudDpi]::SetProcessDPIAware() | Out-Null
} catch { }

$sunoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $sunoDir -or -not (Test-Path $sunoDir)) {
    $sunoDir = "C:\Users\PS\AppData\Local\Programs\Suno"
}
$downloadsDir = Join-Path $sunoDir "Data\Downloads"
$queueFile = Join-Path $sunoDir "song_queue.json"

$form = New-Object System.Windows.Forms.Form
$form.Text = "⚡ Suno Studio HUD"
$form.Size = New-Object System.Drawing.Size 360, 240
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point ($screen.Right - 380), ($screen.Bottom - 260)
$form.BackColor = [System.Drawing.Color]::FromArgb(18, 22, 32)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.TopMost = $true

# Draggable Title Bar
$pnlTitle = New-Object System.Windows.Forms.Panel
$pnlTitle.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlTitle.Height = 36
$pnlTitle.BackColor = [System.Drawing.Color]::FromArgb(26, 32, 46)
$pnlTitle.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$form.Controls.Add($pnlTitle)

$pnlTitle.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        [SunoHudDpi]::ReleaseCapture() | Out-Null
        [SunoHudDpi]::SendMessage($form.Handle, 0xA1, 0x2, 0) | Out-Null
    }
})

$lblBrand = New-Object System.Windows.Forms.Label
$lblBrand.Text = "⚡ SUNO STUDIO PRO HUD"
$lblBrand.Font = New-Object System.Drawing.Font("Segoe UI", 9.2, [System.Drawing.FontStyle]::Bold)
$lblBrand.ForeColor = [System.Drawing.Color]::FromArgb(255, 94, 58)
$lblBrand.AutoSize = $true
$lblBrand.Location = New-Object System.Drawing.Point(12, 8)
$lblBrand.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$pnlTitle.Controls.Add($lblBrand)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "✕"
$btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$btnClose.Size = New-Object System.Drawing.Size 30, 26
$btnClose.Location = New-Object System.Drawing.Point(322, 5)
$btnClose.BackColor = [System.Drawing.Color]::Transparent
$btnClose.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 215)
$btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.FlatAppearance.BorderSize = 0
$btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClose.Add_Click({ $form.Close() })
$pnlTitle.Controls.Add($btnClose)

# Status Pill Area
$pnlStatus = New-Object System.Windows.Forms.Panel
$pnlStatus.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlStatus.Height = 32
$pnlStatus.BackColor = [System.Drawing.Color]::FromArgb(14, 17, 25)
$pnlStatus.Padding = New-Object System.Windows.Forms.Padding(12, 6, 12, 5)
$form.Controls.Add($pnlStatus)
$pnlStatus.BringToFront()

$lblQueueStatus = New-Object System.Windows.Forms.Label
$lblQueueStatus.Text = "🟢 Bridge: Active | Queue: 0"
$lblQueueStatus.Font = New-Object System.Drawing.Font("Segoe UI", 8.2, [System.Drawing.FontStyle]::Bold)
$lblQueueStatus.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
$lblQueueStatus.Location = New-Object System.Drawing.Point(12, 6)
$lblQueueStatus.Size = New-Object System.Drawing.Size 190, 20
$pnlStatus.Controls.Add($lblQueueStatus)

$lblSongCount = New-Object System.Windows.Forms.Label
$lblSongCount.Text = "🎵 0 Songs"
$lblSongCount.Font = New-Object System.Drawing.Font("Segoe UI", 8.2)
$lblSongCount.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
$lblSongCount.Location = New-Object System.Drawing.Point(210, 6)
$lblSongCount.Size = New-Object System.Drawing.Size 130, 20
$lblSongCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$pnlStatus.Controls.Add($lblSongCount)

# Action Buttons Grid Area
$pnlButtons = New-Object System.Windows.Forms.Panel
$pnlButtons.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlButtons.BackColor = [System.Drawing.Color]::FromArgb(18, 22, 32)
$pnlButtons.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 10)
$form.Controls.Add($pnlButtons)
$pnlButtons.BringToFront()

function Launch-App($scriptName) {
    $bat = Join-Path $sunoDir "$scriptName.bat"
    if (Test-Path $bat) {
        Start-Process "cmd.exe" "/c `"$bat`"" -WindowStyle Hidden
    } else {
        $ps1 = Join-Path $sunoDir "$scriptName.ps1"
        if (Test-Path $ps1) {
            Start-Process "powershell.exe" "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ps1`""
        }
    }
}

# Row 1
$btnLaunchSuno = New-Object System.Windows.Forms.Button
$btnLaunchSuno.Text = "🌐 Suno Chrome"
$btnLaunchSuno.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$btnLaunchSuno.Size = New-Object System.Drawing.Size 160, 36
$btnLaunchSuno.Location = New-Object System.Drawing.Point(12, 12)
$btnLaunchSuno.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$btnLaunchSuno.ForeColor = [System.Drawing.Color]::White
$btnLaunchSuno.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnLaunchSuno.FlatAppearance.BorderSize = 0
$btnLaunchSuno.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnLaunchSuno.Add_Click({ Launch-App "SunoChrome" })
$pnlButtons.Controls.Add($btnLaunchSuno)

$btnHub = New-Object System.Windows.Forms.Button
$btnHub.Text = "🌟 Central Hub"
$btnHub.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$btnHub.Size = New-Object System.Drawing.Size 160, 36
$btnHub.Location = New-Object System.Drawing.Point(180, 12)
$btnHub.BackColor = [System.Drawing.Color]::FromArgb(124, 58, 237)
$btnHub.ForeColor = [System.Drawing.Color]::White
$btnHub.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnHub.FlatAppearance.BorderSize = 0
$btnHub.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnHub.Add_Click({ Launch-App "SunoHub" })
$pnlButtons.Controls.Add($btnHub)

# Row 2
$btnComposer = New-Object System.Windows.Forms.Button
$btnComposer.Text = "✍️ Lyric Studio"
$btnComposer.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$btnComposer.Size = New-Object System.Drawing.Size 105, 34
$btnComposer.Location = New-Object System.Drawing.Point(12, 56)
$btnComposer.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 58)
$btnComposer.ForeColor = [System.Drawing.Color]::White
$btnComposer.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnComposer.FlatAppearance.BorderSize = 0
$btnComposer.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnComposer.Add_Click({ Launch-App "SunoComposer" })
$pnlButtons.Controls.Add($btnComposer)

$btnAudio = New-Object System.Windows.Forms.Button
$btnAudio.Text = "🎵 Audio Player"
$btnAudio.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$btnAudio.Size = New-Object System.Drawing.Size 105, 34
$btnAudio.Location = New-Object System.Drawing.Point(124, 56)
$btnAudio.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 58)
$btnAudio.ForeColor = [System.Drawing.Color]::White
$btnAudio.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnAudio.FlatAppearance.BorderSize = 0
$btnAudio.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnAudio.Add_Click({ Launch-App "SunoAudioStudio" })
$pnlButtons.Controls.Add($btnAudio)

$btnPrompt = New-Object System.Windows.Forms.Button
$btnPrompt.Text = "🧪 Style Lab"
$btnPrompt.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$btnPrompt.Size = New-Object System.Drawing.Size 105, 34
$btnPrompt.Location = New-Object System.Drawing.Point(235, 56)
$btnPrompt.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 58)
$btnPrompt.ForeColor = [System.Drawing.Color]::White
$btnPrompt.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPrompt.FlatAppearance.BorderSize = 0
$btnPrompt.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnPrompt.Add_Click({ Launch-App "SunoPromptStudio" })
$pnlButtons.Controls.Add($btnPrompt)

# Row 3
$btnOpenDl = New-Object System.Windows.Forms.Button
$btnOpenDl.Text = "📂 Downloads"
$btnOpenDl.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$btnOpenDl.Size = New-Object System.Drawing.Size 160, 34
$btnOpenDl.Location = New-Object System.Drawing.Point(12, 98)
$btnOpenDl.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$btnOpenDl.ForeColor = [System.Drawing.Color]::White
$btnOpenDl.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenDl.FlatAppearance.BorderSize = 0
$btnOpenDl.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnOpenDl.Add_Click({
    if (-not (Test-Path $downloadsDir)) { New-Item -ItemType Directory -Force -Path $downloadsDir | Out-Null }
    [System.Diagnostics.Process]::Start("explorer.exe", $downloadsDir)
})
$pnlButtons.Controls.Add($btnOpenDl)

$btnDoctor = New-Object System.Windows.Forms.Button
$btnDoctor.Text = "🩺 System Doctor"
$btnDoctor.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$btnDoctor.Size = New-Object System.Drawing.Size 160, 34
$btnDoctor.Location = New-Object System.Drawing.Point(180, 98)
$btnDoctor.BackColor = [System.Drawing.Color]::FromArgb(239, 68, 68)
$btnDoctor.ForeColor = [System.Drawing.Color]::White
$btnDoctor.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDoctor.FlatAppearance.BorderSize = 0
$btnDoctor.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnDoctor.Add_Click({ Launch-App "SunoDoctor" })
$pnlButtons.Controls.Add($btnDoctor)

# Ticker Timer
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({
    # Check queue count
    $qCount = 0
    if (Test-Path $queueFile) {
        try {
            $raw = Get-Content $queueFile -Raw -Encoding UTF8
            if ($raw.Trim() -ne "") {
                $arr = $raw | ConvertFrom-Json
                $qCount = $arr.Count
            }
        } catch { }
    }
    $lblQueueStatus.Text = "🟢 Bridge: Active | Queue: $qCount"

    # Check song count
    if (Test-Path $downloadsDir) {
        $songs = Get-ChildItem -Path $downloadsDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match "\.(mp3|wav|m4a|aac)$" }
        $lblSongCount.Text = "🎵 $($songs.Count) Songs"
    }
})

$form.Add_Shown({
    $timer.Start()
})

$form.Add_FormClosing({
    $timer.Stop()
})

[System.Windows.Forms.Application]::Run($form)
