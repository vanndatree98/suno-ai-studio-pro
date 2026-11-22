param(
    [string]$playlistUrl = "https://suno.com/playlist/059caa04-8eb7-4cbc-884d-66198d5f286f",
    [string]$format = "mp3",
    [switch]$autoStart
)

$ErrorActionPreference = "SilentlyContinue"

# Check single instance
$mutexName = "Local\SunoPlaylistDownloader_App_Mutex_98234"
$isNew = $false
$appMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$isNew)

$sunoDir = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Programs\Suno" } else { "C:\Users\PS\AppData\Local\Programs\Suno" }
$engineScript = Join-Path $sunoDir "download_playlist_engine.js"
$iconPath = Join-Path $sunoDir "app.ico"

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Win32PlDl {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public static IntPtr FindDlWindow() {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hWnd, lParam) => {
            if (IsWindowVisible(hWnd)) {
                var sb = new StringBuilder(256);
                GetWindowText(hWnd, sb, 256);
                string title = sb.ToString();
                if (title.Contains("Suno Playlist Downloader") || title.Contains("ទាញយកចម្រៀង File Zip")) {
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

try {
    $cWnd = [Win32PlDl]::GetConsoleWindow()
    if ($cWnd -ne [IntPtr]::Zero) { [Win32PlDl]::ShowWindow($cWnd, 0) | Out-Null }
} catch { }

if (-not $isNew) {
    $existingHwnd = [Win32PlDl]::FindDlWindow()
    if ($existingHwnd -ne [IntPtr]::Zero) {
        [Win32PlDl]::ShowWindow($existingHwnd, 9)
        [Win32PlDl]::SetForegroundWindow($existingHwnd)
        exit 0
    }
}

try { [Win32PlDl]::SetProcessDPIAware() | Out-Null } catch { }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# Helper for button hover animations
function Add-ButtonHover($btn, [System.Drawing.Color]$normalBg, [System.Drawing.Color]$hoverBg) {
    $btn.Add_MouseEnter({ param($s,$e) if ($s.Enabled) { $s.BackColor = $hoverBg } })
    $btn.Add_MouseLeave({ param($s,$e) if ($s.Enabled) { $s.BackColor = $normalBg } })
}

# Main Window
$form = New-Object System.Windows.Forms.Form
$form.Text = "Suno Playlist Downloader - កម្មវិធីទាញយកចម្រៀង File Zip ពី Playlist"
$form.Width = 980
$form.Height = 720
$form.MinimumSize = New-Object System.Drawing.Size(900, 620)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 26)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

if (Test-Path $iconPath) {
    try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath) } catch { }
}

# State variables
$script:isDownloading = $false
$script:currentProcess = $null
$script:lastZipPath = ""

# Header Panel (Dock = Top - STYLE iOS 27 Liquid Frosted Glass)
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlHeader.Height = 72
$pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(23, 26, 38)
$pnlHeader.Padding = New-Object System.Windows.Forms.Padding(20, 12, 20, 10)

$pnlHeader.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $w = $s.ClientSize.Width
    $h = $s.ClientSize.Height
    if ($w -le 2 -or $h -le 2) { return }

    $bgRect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush ($bgRect), ([System.Drawing.Color]::FromArgb(29, 32, 48)), ([System.Drawing.Color]::FromArgb(19, 21, 32)), ([float]90.0)
    $g.FillRectangle($bgBrush, $bgRect)
    $bgBrush.Dispose()

    $penTop = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(50, 255, 255, 255), 1)
    $g.DrawLine($penTop, 0, 0, $w, 0)
    $penTop.Dispose()

    $penBottom = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(45, 52, 75), 1)
    $g.DrawLine($penBottom, 0, ($h - 1), $w, ($h - 1))
    $penBottom.Dispose()
})

$lblHeaderTitle = New-Object System.Windows.Forms.Label
$lblHeaderTitle.Text = "📦 Suno Playlist Downloader (កម្មវិធីទាញយកចម្រៀង File Zip)"
$lblHeaderTitle.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 13.0, [System.Drawing.FontStyle]::Bold)
$lblHeaderTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 110, 80)
$lblHeaderTitle.AutoSize = $true
$lblHeaderTitle.Location = New-Object System.Drawing.Point(18, 12)

$lblHeaderSub = New-Object System.Windows.Forms.Label
$lblHeaderSub.Text = "ទាញយកចម្រៀងទាំងអស់ពី Suno Playlist រួចដោះកូដជា MP3 (320kbps) / WAV និងវេចខ្ចប់ជា ZIP ដោយស្វ័យប្រវត្តិ"
$lblHeaderSub.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$lblHeaderSub.ForeColor = [System.Drawing.Color]::FromArgb(160, 165, 185)
$lblHeaderSub.AutoSize = $true
$lblHeaderSub.Location = New-Object System.Drawing.Point(20, 42)

$pnlHeader.Controls.AddRange(@($lblHeaderTitle, $lblHeaderSub))

# Dedicated Bottom Action Bar (Dock = Bottom - 100% ALWAYS VISIBLE)
$pnlFooter = New-Object System.Windows.Forms.Panel
$pnlFooter.Dock = [System.Windows.Forms.DockStyle]::Bottom
$pnlFooter.Height = 84
$pnlFooter.BackColor = [System.Drawing.Color]::FromArgb(20, 23, 34)

$pnlFooter.Add_Paint({
    param($s, $e)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(45, 52, 75), 1)
    $e.Graphics.DrawLine($pen, 0, 0, $s.Width, 0)
    $pen.Dispose()
})

# Bottom CTA Buttons (STYLE iOS 27 ឆ្លាតវៃ - Modern, bold, liquid glass feel)
$btnDownload = New-Object System.Windows.Forms.Button
$btnDownload.Text = "📦 ទាញយកចម្រៀងទាំងអស់ជា File ZIP (Download & Package)"
$btnDownload.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 11.0, [System.Drawing.FontStyle]::Bold)
$btnDownload.BackColor = [System.Drawing.Color]::FromArgb(255, 68, 51)
$btnDownload.ForeColor = [System.Drawing.Color]::White
$btnDownload.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDownload.FlatAppearance.BorderSize = 0
$btnDownload.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnDownload.UseMnemonic = $false
Add-ButtonHover $btnDownload ([System.Drawing.Color]::FromArgb(255, 68, 51)) ([System.Drawing.Color]::FromArgb(255, 105, 85))

$btnOpenZipFolder = New-Object System.Windows.Forms.Button
$btnOpenZipFolder.Text = "📂 បើកមើល File ZIP"
$btnOpenZipFolder.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10.5, [System.Drawing.FontStyle]::Bold)
$btnOpenZipFolder.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 255)
$btnOpenZipFolder.ForeColor = [System.Drawing.Color]::White
$btnOpenZipFolder.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenZipFolder.FlatAppearance.BorderSize = 0
$btnOpenZipFolder.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnOpenZipFolder.UseMnemonic = $false
Add-ButtonHover $btnOpenZipFolder ([System.Drawing.Color]::FromArgb(0, 122, 255)) ([System.Drawing.Color]::FromArgb(40, 145, 255))

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "🔄 ពិនិត្យឡើងវិញ"
$btnRefresh.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10.0, [System.Drawing.FontStyle]::Bold)
$btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(44, 52, 74)
$btnRefresh.ForeColor = [System.Drawing.Color]::FromArgb(220, 230, 250)
$btnRefresh.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRefresh.FlatAppearance.BorderSize = 0
$btnRefresh.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnRefresh.UseMnemonic = $false
Add-ButtonHover $btnRefresh ([System.Drawing.Color]::FromArgb(44, 52, 74)) ([System.Drawing.Color]::FromArgb(62, 74, 104))

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "🛑 បញ្ឈប់"
$btnCancel.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10.0, [System.Drawing.FontStyle]::Bold)
$btnCancel.BackColor = [System.Drawing.Color]::FromArgb(180, 35, 45)
$btnCancel.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 180)
$btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCancel.FlatAppearance.BorderSize = 0
$btnCancel.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnCancel.Enabled = $false
$btnCancel.UseMnemonic = $false
Add-ButtonHover $btnCancel ([System.Drawing.Color]::FromArgb(180, 35, 45)) ([System.Drawing.Color]::FromArgb(215, 45, 55))

$pnlFooter.Controls.AddRange(@($btnDownload, $btnOpenZipFolder, $btnRefresh, $btnCancel))

$pnlFooter.Add_Resize({
    $w = $pnlFooter.ClientSize.Width
    $pad = 18
    $gap = 12
    $btnH = 50
    $topY = [int](($pnlFooter.ClientSize.Height - $btnH) / 2)
    
    $wCancel = 120
    $wRefresh = 140
    $wOpenZip = 175
    $fixedRight = $wOpenZip + $gap + $wRefresh + $gap + $wCancel
    $wDl = [Math]::Max(280, $w - ($pad * 2) - $fixedRight - $gap)
    
    $btnDownload.Location = New-Object System.Drawing.Point($pad, $topY)
    $btnDownload.Size = New-Object System.Drawing.Size($wDl, $btnH)
    
    $curX = $pad + $wDl + $gap
    $btnOpenZipFolder.Location = New-Object System.Drawing.Point($curX, $topY)
    $btnOpenZipFolder.Size = New-Object System.Drawing.Size($wOpenZip, $btnH)
    
    $curX += $wOpenZip + $gap
    $btnRefresh.Location = New-Object System.Drawing.Point($curX, $topY)
    $btnRefresh.Size = New-Object System.Drawing.Size($wRefresh, $btnH)
    
    $curX += $wRefresh + $gap
    $btnCancel.Location = New-Object System.Drawing.Point($curX, $topY)
    $btnCancel.Size = New-Object System.Drawing.Size($wCancel, $btnH)
})

# Main Container Panel (Dock = Fill)
$pnlBody = New-Object System.Windows.Forms.Panel
$pnlBody.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlBody.AutoScroll = $true
$pnlBody.Padding = New-Object System.Windows.Forms.Padding(20, 15, 20, 15)

$form.Controls.Add($pnlBody)
$form.Controls.Add($pnlHeader)
$form.Controls.Add($pnlFooter)
$pnlBody.BringToFront()

# 1. URL & Controls Card
$cardUrl = New-Object System.Windows.Forms.Panel
$cardUrl.Location = New-Object System.Drawing.Point(20, 15)
$cardUrl.Size = New-Object System.Drawing.Size(880, 130)
$cardUrl.BackColor = [System.Drawing.Color]::FromArgb(23, 26, 38)
$cardUrl.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblUrl = New-Object System.Windows.Forms.Label
$lblUrl.Text = "🔗 Link Playlist Suno (ឬ Playlist ID):"
$lblUrl.Location = New-Object System.Drawing.Point(15, 12)
$lblUrl.AutoSize = $true
$lblUrl.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 9.5, [System.Drawing.FontStyle]::Bold)
$lblUrl.ForeColor = [System.Drawing.Color]::FromArgb(220, 225, 240)

$txtUrl = New-Object System.Windows.Forms.TextBox
$txtUrl.Location = New-Object System.Drawing.Point(15, 36)
$txtUrl.Size = New-Object System.Drawing.Size(580, 32)
$txtUrl.Font = New-Object System.Drawing.Font("Consolas", 10.5)
$txtUrl.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 26)
$txtUrl.ForeColor = [System.Drawing.Color]::White
$txtUrl.Text = $playlistUrl

$btnPaste = New-Object System.Windows.Forms.Button
$btnPaste.Text = "📋 បិទភ្ជាប់"
$btnPaste.Location = New-Object System.Drawing.Point(605, 35)
$btnPaste.Size = New-Object System.Drawing.Size(115, 34)
$btnPaste.BackColor = [System.Drawing.Color]::FromArgb(45, 55, 78)
$btnPaste.ForeColor = [System.Drawing.Color]::White
$btnPaste.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10.0, [System.Drawing.FontStyle]::Bold)
$btnPaste.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPaste.FlatAppearance.BorderSize = 0
$btnPaste.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnPaste.UseMnemonic = $false
Add-ButtonHover $btnPaste ([System.Drawing.Color]::FromArgb(45, 55, 78)) ([System.Drawing.Color]::FromArgb(60, 72, 100))

$btnInspect = New-Object System.Windows.Forms.Button
$btnInspect.Text = "🔍 ត្រួតពិនិត្យ"
$btnInspect.Location = New-Object System.Drawing.Point(730, 35)
$btnInspect.Size = New-Object System.Drawing.Size(135, 34)
$btnInspect.BackColor = [System.Drawing.Color]::FromArgb(30, 115, 225)
$btnInspect.ForeColor = [System.Drawing.Color]::White
$btnInspect.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10.5, [System.Drawing.FontStyle]::Bold)
$btnInspect.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnInspect.FlatAppearance.BorderSize = 0
$btnInspect.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnInspect.UseMnemonic = $false
Add-ButtonHover $btnInspect ([System.Drawing.Color]::FromArgb(30, 115, 225)) ([System.Drawing.Color]::FromArgb(50, 135, 245))

# Options row
$lblFormat = New-Object System.Windows.Forms.Label
$lblFormat.Text = "🎵 ប្រភេទ Format:"
$lblFormat.Location = New-Object System.Drawing.Point(15, 84)
$lblFormat.AutoSize = $true
$lblFormat.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 9.5)
$lblFormat.ForeColor = [System.Drawing.Color]::FromArgb(180, 185, 200)

$cmbFormat = New-Object System.Windows.Forms.ComboBox
$cmbFormat.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbFormat.Items.AddRange(@("MP3 (320kbps High Quality)", "WAV (Lossless 44.1kHz)", "M4A (Original Decrypted Opus)"))
$cmbFormat.SelectedIndex = 0
$cmbFormat.Location = New-Object System.Drawing.Point(145, 80)
$cmbFormat.Size = New-Object System.Drawing.Size(220, 28)
$cmbFormat.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 26)
$cmbFormat.ForeColor = [System.Drawing.Color]::White
$cmbFormat.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

$lblOutDir = New-Object System.Windows.Forms.Label
$lblOutDir.Text = "📁 ទីតាំងរក្សាទុក:"
$lblOutDir.Location = New-Object System.Drawing.Point(380, 84)
$lblOutDir.AutoSize = $true
$lblOutDir.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 9.5)
$lblOutDir.ForeColor = [System.Drawing.Color]::FromArgb(180, 185, 200)

$txtOutDir = New-Object System.Windows.Forms.TextBox
$progDataDl = Join-Path $sunoDir "Data\Downloads"
if (-not (Test-Path $progDataDl)) { New-Item -ItemType Directory -Force -Path $progDataDl | Out-Null }
$defaultDownloads = $progDataDl
$txtOutDir.Text = $defaultDownloads
$txtOutDir.Location = New-Object System.Drawing.Point(490, 80)
$txtOutDir.Size = New-Object System.Drawing.Size(140, 28)
$txtOutDir.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 26)
$txtOutDir.ForeColor = [System.Drawing.Color]::White
$txtOutDir.Font = New-Object System.Drawing.Font("Consolas", 9.5)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "📁 រកមើល..."
$btnBrowse.Location = New-Object System.Drawing.Point(640, 78)
$btnBrowse.Size = New-Object System.Drawing.Size(100, 32)
$btnBrowse.BackColor = [System.Drawing.Color]::FromArgb(45, 55, 78)
$btnBrowse.ForeColor = [System.Drawing.Color]::White
$btnBrowse.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 9.5, [System.Drawing.FontStyle]::Bold)
$btnBrowse.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowse.FlatAppearance.BorderSize = 0
$btnBrowse.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnBrowse.UseMnemonic = $false
Add-ButtonHover $btnBrowse ([System.Drawing.Color]::FromArgb(45, 55, 78)) ([System.Drawing.Color]::FromArgb(60, 72, 100))

$btnOpenOut = New-Object System.Windows.Forms.Button
$btnOpenOut.Text = "📂 បើក Folder"
$btnOpenOut.Location = New-Object System.Drawing.Point(750, 78)
$btnOpenOut.Size = New-Object System.Drawing.Size(115, 32)
$btnOpenOut.BackColor = [System.Drawing.Color]::FromArgb(45, 55, 78)
$btnOpenOut.ForeColor = [System.Drawing.Color]::White
$btnOpenOut.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 9.5, [System.Drawing.FontStyle]::Bold)
$btnOpenOut.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenOut.FlatAppearance.BorderSize = 0
$btnOpenOut.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnOpenOut.UseMnemonic = $false
Add-ButtonHover $btnOpenOut ([System.Drawing.Color]::FromArgb(45, 55, 78)) ([System.Drawing.Color]::FromArgb(60, 72, 100))

$cardUrl.Controls.AddRange(@(
    $lblUrl, $txtUrl, $btnPaste, $btnInspect,
    $lblFormat, $cmbFormat, $lblOutDir, $txtOutDir, $btnBrowse, $btnOpenOut
))
$pnlBody.Controls.Add($cardUrl)

$cardUrl.Add_Resize({
    $cw = $cardUrl.ClientSize.Width
    $wInsp = 135
    $wPaste = 115
    $btnInspect.Location = New-Object System.Drawing.Point($cw - 15 - $wInsp, 35)
    $btnPaste.Location = New-Object System.Drawing.Point($cw - 15 - $wInsp - 10 - $wPaste, 35)
    $txtUrl.Size = New-Object System.Drawing.Size([Math]::Max(180, $cw - 15 - $wInsp - 10 - $wPaste - 12 - 15), 32)
    
    $wOpenOut = 115
    $wBrowse = 100
    $btnOpenOut.Location = New-Object System.Drawing.Point($cw - 15 - $wOpenOut, 78)
    $btnBrowse.Location = New-Object System.Drawing.Point($cw - 15 - $wOpenOut - 8 - $wBrowse, 78)
    $availTxtOut = ($cw - 15 - $wOpenOut - 8 - $wBrowse - 12) - 490
    if ($availTxtOut -gt 120) {
        $txtOutDir.Size = New-Object System.Drawing.Size($availTxtOut, 28)
    }
})

# 2. Playlist Metadata & Track Preview Card
$cardInfo = New-Object System.Windows.Forms.Panel
$cardInfo.Location = New-Object System.Drawing.Point(20, 155)
$cardInfo.Size = New-Object System.Drawing.Size(880, 220)
$cardInfo.BackColor = [System.Drawing.Color]::FromArgb(23, 26, 38)
$cardInfo.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$picCover = New-Object System.Windows.Forms.PictureBox
$picCover.Location = New-Object System.Drawing.Point(15, 15)
$picCover.Size = New-Object System.Drawing.Size(125, 125)
$picCover.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$picCover.BackColor = [System.Drawing.Color]::FromArgb(12, 14, 20)
$picCover.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

$btnWeb = New-Object System.Windows.Forms.Button
$btnWeb.Text = "🌐 បើកលើ Web"
$btnWeb.Location = New-Object System.Drawing.Point(15, 150)
$btnWeb.Size = New-Object System.Drawing.Size(125, 34)
$btnWeb.BackColor = [System.Drawing.Color]::FromArgb(40, 50, 75)
$btnWeb.ForeColor = [System.Drawing.Color]::White
$btnWeb.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 9.5, [System.Drawing.FontStyle]::Bold)
$btnWeb.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnWeb.FlatAppearance.BorderSize = 0
$btnWeb.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnWeb.UseMnemonic = $false
Add-ButtonHover $btnWeb ([System.Drawing.Color]::FromArgb(40, 50, 75)) ([System.Drawing.Color]::FromArgb(55, 68, 100))

$lblPlTitle = New-Object System.Windows.Forms.Label
$lblPlTitle.Text = "សូមចុច 'ត្រួតពិនិត្យ' ឬបិទភ្ជាប់ Link Playlist..."
$lblPlTitle.Location = New-Object System.Drawing.Point(155, 15)
$lblPlTitle.Size = New-Object System.Drawing.Size(710, 32)
$lblPlTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12.0, [System.Drawing.FontStyle]::Bold)
$lblPlTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 120, 80)
$lblPlTitle.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblPlMeta = New-Object System.Windows.Forms.Label
$lblPlMeta.Text = "ចំនួនបទ៖ - | អ្នកបង្កើត៖ - | Playlist ID: -"
$lblPlMeta.Location = New-Object System.Drawing.Point(156, 48)
$lblPlMeta.Size = New-Object System.Drawing.Size(710, 22)
$lblPlMeta.ForeColor = [System.Drawing.Color]::FromArgb(170, 175, 195)
$lblPlMeta.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblTracklistHeader = New-Object System.Windows.Forms.Label
$lblTracklistHeader.Text = "🎶 បញ្ជីបទចម្រៀងនៅក្នុង Playlist:"
$lblTracklistHeader.Location = New-Object System.Drawing.Point(156, 75)
$lblTracklistHeader.AutoSize = $true
$lblTracklistHeader.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 9.5, [System.Drawing.FontStyle]::Bold)
$lblTracklistHeader.ForeColor = [System.Drawing.Color]::FromArgb(120, 200, 255)

$lvTracks = New-Object System.Windows.Forms.ListView
$lvTracks.Location = New-Object System.Drawing.Point(156, 100)
$lvTracks.Size = New-Object System.Drawing.Size(710, 105)
$lvTracks.View = [System.Windows.Forms.View]::Details
$lvTracks.FullRowSelect = $true
$lvTracks.GridLines = $true
$lvTracks.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 26)
$lvTracks.ForeColor = [System.Drawing.Color]::White
$lvTracks.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$lvTracks.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom

$colNum = $lvTracks.Columns.Add("#", 38)
$colTitle = $lvTracks.Columns.Add("ចំណងជើងបទចម្រៀង", 280)
$colDur = $lvTracks.Columns.Add("រយៈពេល", 70)
$colStyle = $lvTracks.Columns.Add("ស្ទីលតន្ត្រី", 220)
$colStatus = $lvTracks.Columns.Add("ស្ថានភាព", 100)

$cardInfo.Controls.AddRange(@(
    $picCover, $btnWeb, $lblPlTitle, $lblPlMeta, $lblTracklistHeader, $lvTracks
))
$pnlBody.Controls.Add($cardInfo)

# 3. Action & Progress Console Card
$cardAction = New-Object System.Windows.Forms.Panel
$cardAction.Location = New-Object System.Drawing.Point(20, 385)
$cardAction.Size = New-Object System.Drawing.Size(880, 150)
$cardAction.BackColor = [System.Drawing.Color]::FromArgb(23, 26, 38)
$cardAction.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(15, 14)
$progressBar.Size = New-Object System.Drawing.Size(850, 16)
$progressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "រួចរាល់សម្រាប់ការទាញយក..."
$lblStatus.Location = New-Object System.Drawing.Point(15, 36)
$lblStatus.Size = New-Object System.Drawing.Size(850, 22)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 220, 150)
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 10.0, [System.Drawing.FontStyle]::Bold)
$lblStatus.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

# Log Console
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(15, 62)
$txtLog.Size = New-Object System.Drawing.Size(850, 75)
$txtLog.Multiline = $true
$txtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtLog.ReadOnly = $true
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(10, 11, 16)
$txtLog.ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 230)
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9.0)
$txtLog.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom

$cardAction.Controls.AddRange(@($progressBar, $lblStatus, $txtLog))
$pnlBody.Controls.Add($cardAction)

# Helper functions
function Append-Log([string]$msg) {
    if ($form.InvokeRequired) {
        $form.Invoke([Action[string]]{ param($m) Append-Log $m }, $msg)
        return
    }
    $timestamp = [DateTime]::Now.ToString("HH:mm:ss")
    $txtLog.AppendText("[$timestamp] $msg`r`n")
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.ScrollToCaret()
}

function Extract-PlaylistId([string]$raw) {
    if (-not $raw) { return "" }
    $m = [regex]::Match($raw, '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) { return $m.Value }
    return ""
}

function Inspect-Playlist([string]$inputUrl) {
    $plId = Extract-PlaylistId $inputUrl
    if (-not $plId) {
        $lblStatus.Text = "⚠️ សូមបញ្ចូល Link Playlist Suno អោយបានត្រឹមត្រូវ!"
        $lblStatus.ForeColor = [System.Drawing.Color]::Orange
        return
    }

    $lblStatus.Text = "🔍 កំពុងទាញយកព័ត៌មាន Playlist ពី Suno..."
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 200, 255)
    Append-Log "🔍 កំពុងភ្ជាប់ទៅកាន់ Suno API ដើម្បីពិនិត្យ Playlist ID: $plId..."
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $res = Invoke-RestMethod -Uri "https://studio-api.prod.suno.com/api/playlist/$plId" -Headers @{ "User-Agent" = "Mozilla/5.0" }
        $plName = if ($res.name) { $res.name } else { "Suno Playlist" }
        $creator = if ($res.user_display_name) { $res.user_display_name } elseif ($res.user_handle) { "@$($res.user_handle)" } else { "Suno Creator" }
        $clips = @($res.playlist_clips | ForEach-Object { $_.clip } | Where-Object { $null -ne $_ })

        $lblPlTitle.Text = $plName
        $lblPlMeta.Text = "ចំនួនបទ៖ $($clips.Count) បទ | អ្នកបង្កើត៖ $creator | Playlist ID: $plId"
        
        $lvTracks.Items.Clear()
        $idx = 1
        foreach ($clip in $clips) {
            $numStr = "{0:D2}" -f $idx
            $sec = [double]($clip.metadata.duration)
            $durStr = "{0:D2}:{1:D2}" -f [int]($sec / 60), [int]($sec % 60)
            $style = if ($clip.metadata.tags) { $clip.metadata.tags } else { "-" }
            
            $item = New-Object System.Windows.Forms.ListViewItem($numStr)
            [void]$item.SubItems.Add($clip.title)
            [void]$item.SubItems.Add($durStr)
            [void]$item.SubItems.Add($style)
            [void]$item.SubItems.Add("រួចរាល់")
            [void]$lvTracks.Items.Add($item)
            $idx++
        }

        if ($res.image_url) {
            try { $picCover.LoadAsync($res.image_url) } catch { }
        }

        $lblStatus.Text = "✅ បានរកឃើញ Playlist ជោគជ័យ! មានចំនួន $($clips.Count) បទ។"
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 230, 160)
        Append-Log "✓ ទទួលបានព័ត៌មាន Playlist៖ `"$plName`" ($($clips.Count) បទ)"
    } catch {
        $lblStatus.Text = "⚠️ មិនអាចទាញយកព័ត៌មាន Playlist: $($_.Exception.Message)"
        $lblStatus.ForeColor = [System.Drawing.Color]::Orange
        Append-Log "⚠️ កំហុស៖ $($_.Exception.Message)"
    }
}

function Start-PlaylistDownload {
    if ($script:isDownloading) { return }

    $plUrl = $txtUrl.Text.Trim()
    $plId = Extract-PlaylistId $plUrl
    if (-not $plId) {
        [System.Windows.Forms.MessageBox]::Show("សូមបញ្ចូល Link URL របស់ Suno Playlist អោយបានត្រឹមត្រូវ!", "Suno Playlist Downloader", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $outDir = $txtOutDir.Text.Trim()
    if (-not (Test-Path $outDir)) {
        try { New-Item -ItemType Directory -Force -Path $outDir | Out-Null } catch { }
    }

    $selectedFmt = "mp3"
    if ($cmbFormat.SelectedIndex -eq 1) { $selectedFmt = "wav" }
    elseif ($cmbFormat.SelectedIndex -eq 2) { $selectedFmt = "m4a" }

    $script:isDownloading = $true
    $btnDownload.Enabled = $false
    $btnRefresh.Enabled = $false
    $btnInspect.Enabled = $false
    $btnCancel.Enabled = $true
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $lblStatus.Text = "⏳ កំពុងទាញយក & ដោះកូដបទចម្រៀងទាំងអស់ពី Playlist..."
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 50)

    Append-Log "🚀 ចាប់ផ្តើមដំណើរការទាញយក Playlist ($plId) ជាទម្រង់ $selectedFmt..."

    # Launch node engine asynchronously with redirected stdout
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "node.exe"
    $psi.Arguments = "`"$engineScript`" `"$plUrl`" `"$selectedFmt`" `"$outDir`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.EnableRaisingEvents = $true
    $script:currentProcess = $proc

    $outputHandler = {
        param($sender, $e)
        if ($e.Data) {
            $line = $e.Data
            Append-Log $line

            if ($line -like "*[*/5]*" -or $line -like "*[*/10]*" -or $line -like "*[*/14]*" -or $line -like "*[*/18]*" -or $line -like "*[*/20]*") {
                if ($form.InvokeRequired) {
                    $form.Invoke([Action[string]]{ param($l) $lblStatus.Text = $l }, $line)
                }
            }

            if ($line.StartsWith("RESULT_JSON:")) {
                try {
                    $jsonStr = $line.Substring(12)
                    $resObj = $jsonStr | ConvertFrom-Json
                    if ($resObj.zipPath) {
                        $script:lastZipPath = $resObj.zipPath
                    }
                } catch { }
            }
        }
    }

    Register-ObjectEvent -InputObject $proc -EventName "OutputDataReceived" -Action $outputHandler | Out-Null
    Register-ObjectEvent -InputObject $proc -EventName "ErrorDataReceived" -Action $outputHandler | Out-Null

    $exitHandler = {
        param($sender, $e)
        if ($form.InvokeRequired) {
            $form.Invoke([Action]{
                $script:isDownloading = $false
                $btnDownload.Enabled = $true
                $btnRefresh.Enabled = $true
                $btnInspect.Enabled = $true
                $btnCancel.Enabled = $false
                $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
                $progressBar.Value = 100

                if ($proc.ExitCode -eq 0) {
                    $lblStatus.Text = "🎉 ទាញយក & បង្កើត File ZIP ជោគជ័យ ១០០%!"
                    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(80, 240, 160)
                    Append-Log "🎉 ដំណើរការបានបញ្ចប់ដោយជោគជ័យ ១០០%!"

                    $msg = "ការទាញយក Playlist និងវេចខ្ចប់ជា File ZIP បានជោគជ័យ!`n`nFile ZIP: $($script:lastZipPath)`n`nតើអ្នកចង់បើកមើល Folder ដែរឬទេ?"
                    $choice = [System.Windows.Forms.MessageBox]::Show($msg, "ទាញយកជោគជ័យ", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
                    if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
                        if ($script:lastZipPath -and (Test-Path $script:lastZipPath)) {
                            explorer.exe "/select,$($script:lastZipPath)"
                        } else {
                            explorer.exe $txtOutDir.Text
                        }
                    }
                } else {
                    $lblStatus.Text = "⚠️ ការទាញយកបានបញ្ចប់ដោយមានបញ្ហា (ExitCode: $($proc.ExitCode))"
                    $lblStatus.ForeColor = [System.Drawing.Color]::OrangeRed
                    Append-Log "❌ ដំណើរការបានបរាជ័យ (ExitCode: $($proc.ExitCode))"
                }
            })
        }
    }

    Register-ObjectEvent -InputObject $proc -EventName "Exited" -Action $exitHandler | Out-Null

    $proc.Start() | Out-Null
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()
}

# Button click events
$btnPaste.Add_Click({
    if ([System.Windows.Forms.Clipboard]::ContainsText()) {
        $txtUrl.Text = [System.Windows.Forms.Clipboard]::GetText().Trim()
        Inspect-Playlist $txtUrl.Text
    }
})

$btnInspect.Add_Click({
    Inspect-Playlist $txtUrl.Text
})

$btnBrowse.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.SelectedPath = $txtOutDir.Text
    $fbd.Description = "ជ្រើសរើស Folder សម្រាប់រក្សាទុក File ZIP"
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtOutDir.Text = $fbd.SelectedPath
    }
})

$btnOpenOut.Add_Click({
    if (Test-Path $txtOutDir.Text) {
        explorer.exe $txtOutDir.Text
    }
})

$btnWeb.Add_Click({
    $plUrl = $txtUrl.Text.Trim()
    if ($plUrl -match "http") {
        Start-Process $plUrl
    } else {
        $id = Extract-PlaylistId $plUrl
        if ($id) { Start-Process "https://suno.com/playlist/$id" }
    }
})

$btnDownload.Add_Click({
    Start-PlaylistDownload
})

$btnRefresh.Add_Click({
    Inspect-Playlist $txtUrl.Text
})

$btnOpenZipFolder.Add_Click({
    if ($script:lastZipPath -and (Test-Path $script:lastZipPath)) {
        explorer.exe "/select,$($script:lastZipPath)"
    } else {
        explorer.exe $txtOutDir.Text
    }
})

$btnCancel.Add_Click({
    if ($script:currentProcess -and -not $script:currentProcess.HasExited) {
        try {
            $script:currentProcess.Kill()
            Append-Log "🛑 បានបញ្ឈប់ដំណើរការទាញយកដោយអ្នកប្រើប្រាស់។"
            $lblStatus.Text = "🛑 បានបញ្ឈប់ដំណើរការ។"
            $lblStatus.ForeColor = [System.Drawing.Color]::LightCoral
        } catch { }
    }
})

# Auto inspect on load
$form.Add_Shown({
    if ($txtUrl.Text) {
        Inspect-Playlist $txtUrl.Text
    }
    if ($autoStart) {
        Start-Sleep -Milliseconds 800
        Start-PlaylistDownload
    }
})

# Form closing
$form.Add_FormClosing({
    if ($script:currentProcess -and -not $script:currentProcess.HasExited) {
        try { $script:currentProcess.Kill() } catch { }
    }
    if ($appMutex) {
        $appMutex.ReleaseMutex()
        $appMutex.Dispose()
    }
})

[System.Windows.Forms.Application]::Run($form)
