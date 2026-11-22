param(
    [string]$url = "",
    [string]$format = "wav",
    [switch]$auto
)

$ErrorActionPreference = "SilentlyContinue"

# Check single instance
$mutexName = "Local\SunoDownloader_App_Mutex_78912"
$isNew = $false
$appMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$isNew)

$sunoDir = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Programs\Suno" } else { "C:\Users\PS\AppData\Local\Programs\Suno" }
$queueFile = Join-Path $sunoDir "download_queue.json"

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
            foreach ($sub in $entry) { $result += $sub }
        } else {
            $result += $entry
        }
    }
    return ,$result
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Win32Dl {
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
                if (title.Contains("Suno Downloader") || title.Contains("ទាញយកបទចម្រៀង")) {
                    found = hWnd;
                    return false;
                }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
public class DwmHelperDl {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}
"@

try {
    $cWnd = [Win32Dl]::GetConsoleWindow()
    if ($cWnd -ne [IntPtr]::Zero) { [Win32Dl]::ShowWindow($cWnd, 0) | Out-Null }
} catch { }

if (-not $isNew) {
    if ($url) {
        try {
            $queue = @()
            if (Test-Path $queueFile) {
                $raw = Get-Content $queueFile -Raw
                if ($raw) { $queue = @($raw | ConvertFrom-Json) }
            }
            $item = @{ source = "downloader_app"; url = $url; format = $format; timestamp = [DateTime]::UtcNow.Ticks; processed = $false }
            $queue += $item
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false); [System.IO.File]::WriteAllText($queueFile, (ConvertTo-JsonArray $queue), $utf8NoBom)
        } catch { }
    }
    $existingHwnd = [Win32Dl]::FindDlWindow()
    if ($existingHwnd -ne [IntPtr]::Zero) {
        [Win32Dl]::ShowWindow($existingHwnd, 9)
        [Win32Dl]::SetForegroundWindow($existingHwnd)
        exit 0
    } else {
        Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*SunoDownloader.ps1*" -and $_.ProcessId -ne $PID } | ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
        }
        Start-Sleep -Milliseconds 400
    }
}

try { [Win32Dl]::SetProcessDPIAware() | Out-Null } catch { }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "Suno Downloader - កម្មវិធីទាញយកបទចម្រៀង Suno (WAV / MP3)"
$form.Width = 920
$form.Height = 720
$form.MinimumSize = New-Object System.Drawing.Size(820, 640)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 20)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

$iconPath = Join-Path $sunoDir "app.ico"
if (Test-Path $iconPath) {
    $form.Icon = New-Object System.Drawing.Icon($iconPath)
}

# Dark titlebar
$darkMode = 1
[void][DwmHelperDl]::DwmSetWindowAttribute($form.Handle, 20, [ref]$darkMode, 4)
[void][DwmHelperDl]::DwmSetWindowAttribute($form.Handle, 19, [ref]$darkMode, 4)

# Locate FFmpeg
$ffmpegPath = "ffmpeg.exe"
$wingetFfmpeg = "C:\Users\PS\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-9.0.2-full_build\bin\ffmpeg.exe"
if (Test-Path $wingetFfmpeg) { $ffmpegPath = $wingetFfmpeg }

# State
$script:isDownloading = $false
$script:processedClips = New-Object System.Collections.Generic.HashSet[string]

# ----------------- UI LAYOUT -----------------

# Header
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlHeader.Height = 70
$pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(22, 22, 28)

$lblHeaderTitle = New-Object System.Windows.Forms.Label
$lblHeaderTitle.Text = "🎵 Suno Song Downloader (កម្មវិធីទាញយកបទចម្រៀង Suno)"
$lblHeaderTitle.Font = New-Object System.Drawing.Font("Segoe UI", 13.5, [System.Drawing.FontStyle]::Bold)
$lblHeaderTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 110, 80)
$lblHeaderTitle.AutoSize = $true
$lblHeaderTitle.Location = New-Object System.Drawing.Point(18, 12)

$lblHeaderSub = New-Object System.Windows.Forms.Label
$lblHeaderSub.Text = "ទាញយកបទចម្រៀងតាមរយៈ Link URL ដោយផ្ទាល់ និង បំលែងជា Lossless 16-bit 44.1kHz WAV ឬ 320kbps MP3"
$lblHeaderSub.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$lblHeaderSub.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 175)
$lblHeaderSub.AutoSize = $true
$lblHeaderSub.Location = New-Object System.Drawing.Point(20, 40)

[void]$pnlHeader.Controls.Add($lblHeaderTitle)
[void]$pnlHeader.Controls.Add($lblHeaderSub)
[void]$form.Controls.Add($pnlHeader)

# Body Panel
$pnlBody = New-Object System.Windows.Forms.Panel
$pnlBody.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlBody.AutoScroll = $true
$pnlBody.Padding = New-Object System.Windows.Forms.Padding(20, 15, 20, 15)
[void]$form.Controls.Add($pnlBody)

function CreateCard([int]$height, [int]$top) {
    $pnl = New-Object System.Windows.Forms.Panel
    $pnl.Location = New-Object System.Drawing.Point(20, $top)
    $pnl.Width = $form.ClientSize.Width - 60
    $pnl.Height = $height
    $pnl.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 30)
    $pnl.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    return $pnl
}

# 1. INPUT CARD
$cardInput = CreateCard 190 15

$lblUrlPrompt = New-Object System.Windows.Forms.Label
$lblUrlPrompt.Text = "🔗 បញ្ចូល Link URL បទចម្រៀង Suno (Song Link URL):"
$lblUrlPrompt.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblUrlPrompt.ForeColor = [System.Drawing.Color]::FromArgb(230, 230, 240)
$lblUrlPrompt.Location = New-Object System.Drawing.Point(16, 14)
$lblUrlPrompt.AutoSize = $true

$txtUrl = New-Object System.Windows.Forms.TextBox
$txtUrl.Location = New-Object System.Drawing.Point(18, 38)
$txtUrl.Width = $cardInput.Width - 230
$txtUrl.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$txtUrl.Font = New-Object System.Drawing.Font("Segoe UI", 10.5)
$txtUrl.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 36)
$txtUrl.ForeColor = [System.Drawing.Color]::White
$txtUrl.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
if ($url) { $txtUrl.Text = $url }

$btnPaste = New-Object System.Windows.Forms.Button
$btnPaste.Text = "📋 បិទភ្ជាប់ (Paste)"
$btnPaste.Location = New-Object System.Drawing.Point($cardInput.Width - 200, 36)
$btnPaste.Size = New-Object System.Drawing.Size(100, 30)
$btnPaste.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnPaste.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 52)
$btnPaste.ForeColor = [System.Drawing.Color]::White
$btnPaste.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPaste.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 70, 90)

$btnInspect = New-Object System.Windows.Forms.Button
$btnInspect.Text = "🔍 ពិនិត្យបទ"
$btnInspect.Location = New-Object System.Drawing.Point($cardInput.Width - 92, 36)
$btnInspect.Size = New-Object System.Drawing.Size(80, 30)
$btnInspect.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnInspect.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 52)
$btnInspect.ForeColor = [System.Drawing.Color]::White
$btnInspect.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnInspect.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 70, 90)

# Format Radios
$lblFormat = New-Object System.Windows.Forms.Label
$lblFormat.Text = "🎵 ទម្រង់សម្លេង (Format):"
$lblFormat.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$lblFormat.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 215)
$lblFormat.Location = New-Object System.Drawing.Point(16, 80)
$lblFormat.AutoSize = $true

$rbWav = New-Object System.Windows.Forms.RadioButton
$rbWav.Text = "WAV (Lossless 16-bit 44.1kHz Stereo PCM) ⭐ [ណែនាំ]"
$rbWav.Location = New-Object System.Drawing.Point(190, 78)
$rbWav.AutoSize = $true
$rbWav.Checked = ($format -eq "wav")
$rbWav.ForeColor = [System.Drawing.Color]::FromArgb(100, 220, 255)
$rbWav.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)

$rbMp3 = New-Object System.Windows.Forms.RadioButton
$rbMp3.Text = "MP3 (320 kbps High Quality Audio)"
$rbMp3.Location = New-Object System.Drawing.Point(530, 78)
$rbMp3.AutoSize = $true
$rbMp3.Checked = ($format -eq "mp3")
$rbMp3.ForeColor = [System.Drawing.Color]::FromArgb(210, 210, 220)

# Save Folder
$lblSaveTo = New-Object System.Windows.Forms.Label
$lblSaveTo.Text = "📁 រក្សាទុកក្នុង (Save To):"
$lblSaveTo.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$lblSaveTo.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 215)
$lblSaveTo.Location = New-Object System.Drawing.Point(16, 114)
$lblSaveTo.AutoSize = $true

$progDataDl = Join-Path $sunoDir "Data\Downloads"
if (-not (Test-Path $progDataDl)) { New-Item -ItemType Directory -Force -Path $progDataDl | Out-Null }
$defaultDl = $progDataDl
$txtSavePath = New-Object System.Windows.Forms.TextBox
$txtSavePath.Location = New-Object System.Drawing.Point(190, 110)
$txtSavePath.Width = $cardInput.Width - 305
$txtSavePath.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$txtSavePath.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$txtSavePath.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 36)
$txtSavePath.ForeColor = [System.Drawing.Color]::White
$txtSavePath.Text = $defaultDl
$txtSavePath.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "📂 ជ្រើសរើស..."
$btnBrowse.Location = New-Object System.Drawing.Point($cardInput.Width - 105, 108)
$btnBrowse.Size = New-Object System.Drawing.Size(92, 28)
$btnBrowse.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnBrowse.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 52)
$btnBrowse.ForeColor = [System.Drawing.Color]::White
$btnBrowse.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowse.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 70, 90)
$btnBrowse.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.SelectedPath = $txtSavePath.Text
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtSavePath.Text = $fbd.SelectedPath
    }
})

# Auto Watch Checkbox
$chkAutoWatch = New-Object System.Windows.Forms.CheckBox
$chkAutoWatch.Text = "⚡ ស្វ័យប្រវត្តិចាប់យកបទចម្រៀងថ្មីពី Suno នៅពេលបង្កើតរួច (Auto-Download Watcher Active)"
$chkAutoWatch.Location = New-Object System.Drawing.Point(18, 150)
$chkAutoWatch.AutoSize = $true
$chkAutoWatch.Checked = $true
$chkAutoWatch.ForeColor = [System.Drawing.Color]::FromArgb(80, 230, 160)
$chkAutoWatch.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

$btnOpenPlaylistDl = New-Object System.Windows.Forms.Button
$btnOpenPlaylistDl.Text = "📦 ទាញយក Playlist ជា File ZIP"
$btnOpenPlaylistDl.Location = New-Object System.Drawing.Point($cardInput.Width - 260, 147)
$btnOpenPlaylistDl.Size = New-Object System.Drawing.Size(248, 30)
$btnOpenPlaylistDl.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnOpenPlaylistDl.BackColor = [System.Drawing.Color]::FromArgb(45, 95, 175)
$btnOpenPlaylistDl.ForeColor = [System.Drawing.Color]::White
$btnOpenPlaylistDl.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$btnOpenPlaylistDl.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenPlaylistDl.FlatAppearance.BorderSize = 0
$btnOpenPlaylistDl.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnOpenPlaylistDl.Add_Click({
    Start-Process "wscript.exe" -ArgumentList "`"$sunoDir\SunoPlaylistDownloaderLauncher.vbs`""
})

[void]$cardInput.Controls.Add($lblUrlPrompt)
[void]$cardInput.Controls.Add($txtUrl)
[void]$cardInput.Controls.Add($btnPaste)
[void]$cardInput.Controls.Add($btnInspect)
[void]$cardInput.Controls.Add($lblFormat)
[void]$cardInput.Controls.Add($rbWav)
[void]$cardInput.Controls.Add($rbMp3)
[void]$cardInput.Controls.Add($lblSaveTo)
[void]$cardInput.Controls.Add($txtSavePath)
[void]$cardInput.Controls.Add($btnBrowse)
[void]$cardInput.Controls.Add($chkAutoWatch)
[void]$cardInput.Controls.Add($btnOpenPlaylistDl)
[void]$pnlBody.Controls.Add($cardInput)

# 2. STATUS & ACTION CARD
$cardStatus = CreateCard 150 220

$picCover = New-Object System.Windows.Forms.PictureBox
$picCover.Location = New-Object System.Drawing.Point(16, 16)
$picCover.Size = New-Object System.Drawing.Size(118, 118)
$picCover.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 40)
$picCover.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$picCover.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

$lblSongTitle = New-Object System.Windows.Forms.Label
$lblSongTitle.Text = "រង់ចាំ Link URL ឬ បទចម្រៀងថ្មីពី Suno..."
$lblSongTitle.Font = New-Object System.Drawing.Font("Segoe UI", 11.5, [System.Drawing.FontStyle]::Bold)
$lblSongTitle.ForeColor = [System.Drawing.Color]::White
$lblSongTitle.Location = New-Object System.Drawing.Point(148, 16)
$lblSongTitle.Size = New-Object System.Drawing.Size($cardStatus.Width - 360, 28)
$lblSongTitle.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblSongMeta = New-Object System.Windows.Forms.Label
$lblSongMeta.Text = "បញ្ចូល Link ខាងលើ រួចចុចប៊ូតុងទាញយក ឬ បង្កើតចម្រៀងក្នុង Suno ដើម្បីទាញយកស្វ័យប្រវត្តិ។"
$lblSongMeta.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$lblSongMeta.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 175)
$lblSongMeta.Location = New-Object System.Drawing.Point(150, 48)
$lblSongMeta.Size = New-Object System.Drawing.Size($cardStatus.Width - 360, 24)
$lblSongMeta.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(150, 78)
$progressBar.Size = New-Object System.Drawing.Size($cardStatus.Width - 360, 20)
$progressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$progressBar.Value = 0

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "🟢 រួចរាល់សម្រាប់ការទាញយក (Ready)"
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Italic)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(120, 220, 140)
$lblStatus.Location = New-Object System.Drawing.Point(150, 104)
$lblStatus.AutoSize = $true

$btnDownload = New-Object System.Windows.Forms.Button
$btnDownload.Text = "⬇️ ទាញយកចម្រៀង`n(Download Now)"
$btnDownload.Location = New-Object System.Drawing.Point($cardStatus.Width - 190, 18)
$btnDownload.Size = New-Object System.Drawing.Size(174, 114)
$btnDownload.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnDownload.BackColor = [System.Drawing.Color]::FromArgb(255, 90, 60)
$btnDownload.ForeColor = [System.Drawing.Color]::White
$btnDownload.Font = New-Object System.Drawing.Font("Segoe UI", 11.0, [System.Drawing.FontStyle]::Bold)
$btnDownload.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDownload.FlatAppearance.BorderSize = 0
$btnDownload.Cursor = [System.Windows.Forms.Cursors]::Hand

[void]$cardStatus.Controls.Add($picCover)
[void]$cardStatus.Controls.Add($lblSongTitle)
[void]$cardStatus.Controls.Add($lblSongMeta)
[void]$cardStatus.Controls.Add($progressBar)
[void]$cardStatus.Controls.Add($lblStatus)
[void]$cardStatus.Controls.Add($btnDownload)
[void]$pnlBody.Controls.Add($cardStatus)

# 3. HISTORY CARD
$cardHistory = CreateCard 240 385
$cardHistory.Height = $form.ClientSize.Height - 480
$cardHistory.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblHistTitle = New-Object System.Windows.Forms.Label
$lblHistTitle.Text = "📜 បញ្ជីបទចម្រៀងដែលបានទាញយក (Download History):"
$lblHistTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblHistTitle.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 235)
$lblHistTitle.Location = New-Object System.Drawing.Point(16, 12)
$lblHistTitle.AutoSize = $true

$lvHistory = New-Object System.Windows.Forms.ListView
$lvHistory.Location = New-Object System.Drawing.Point(16, 38)
$lvHistory.Size = New-Object System.Drawing.Size($cardHistory.Width - 32, $cardHistory.Height - 88)
$lvHistory.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$lvHistory.View = [System.Windows.Forms.View]::Details
$lvHistory.FullRowSelect = $true
$lvHistory.GridLines = $true
$lvHistory.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 30)
$lvHistory.ForeColor = [System.Drawing.Color]::White
$lvHistory.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$lvHistory.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

[void]$lvHistory.Columns.Add("ចំណងជើងបទចម្រៀង (Title)", 300)
[void]$lvHistory.Columns.Add("ទម្រង់ (Format)", 90)
[void]$lvHistory.Columns.Add("ទំហំ (Size)", 100)
[void]$lvHistory.Columns.Add("កាលបរិច្ឆេទ (Date)", 140)
[void]$lvHistory.Columns.Add("ទីតាំងឯកសារ (Path)", 220)

$btnPlay = New-Object System.Windows.Forms.Button
$btnPlay.Text = "▶️ ចាក់ស្តាប់ (Play)"
$btnPlay.Location = New-Object System.Drawing.Point(16, $cardHistory.Height - 42)
$btnPlay.Size = New-Object System.Drawing.Size(130, 30)
$btnPlay.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnPlay.BackColor = [System.Drawing.Color]::FromArgb(36, 140, 100)
$btnPlay.ForeColor = [System.Drawing.Color]::White
$btnPlay.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPlay.FlatAppearance.BorderSize = 0
$btnPlay.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$btnPlay.Add_Click({
    if ($lvHistory.SelectedItems.Count -gt 0) {
        $path = $lvHistory.SelectedItems[0].Tag
        if ($path -and (Test-Path $path)) { Start-Process $path }
    }
})

$btnOpenFolder = New-Object System.Windows.Forms.Button
$btnOpenFolder.Text = "📂 បើកថតផ្ទុក (Open Folder)"
$btnOpenFolder.Location = New-Object System.Drawing.Point(155, $cardHistory.Height - 42)
$btnOpenFolder.Size = New-Object System.Drawing.Size(160, 30)
$btnOpenFolder.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$btnOpenFolder.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 65)
$btnOpenFolder.ForeColor = [System.Drawing.Color]::White
$btnOpenFolder.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenFolder.FlatAppearance.BorderSize = 0
$btnOpenFolder.Add_Click({
    if ($lvHistory.SelectedItems.Count -gt 0) {
        $path = $lvHistory.SelectedItems[0].Tag
        if ($path -and (Test-Path $path)) {
            Start-Process "explorer.exe" "/select,`"$path`""
            return
        }
    }
    Start-Process "explorer.exe" $txtSavePath.Text
})

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = "🗑️ សម្អាតបញ្ជី (Clear)"
$btnClear.Location = New-Object System.Drawing.Point($cardHistory.Width - 130, $cardHistory.Height - 42)
$btnClear.Size = New-Object System.Drawing.Size(114, 30)
$btnClear.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$btnClear.BackColor = [System.Drawing.Color]::FromArgb(50, 50, 65)
$btnClear.ForeColor = [System.Drawing.Color]::FromArgb(220, 180, 180)
$btnClear.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClear.FlatAppearance.BorderSize = 0
$btnClear.Add_Click({ $lvHistory.Items.Clear() })

[void]$cardHistory.Controls.Add($lblHistTitle)
[void]$cardHistory.Controls.Add($lvHistory)
[void]$cardHistory.Controls.Add($btnPlay)
[void]$cardHistory.Controls.Add($btnOpenFolder)
[void]$cardHistory.Controls.Add($btnClear)
[void]$pnlBody.Controls.Add($cardHistory)

# ----------------- FUNCTIONS -----------------

function ExtractClipId([string]$raw) {
    if (-not $raw) { return "" }
    $m = [regex]::Match($raw, '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    return if ($m.Success) { $m.Value } else { "" }
}

function InspectSong([string]$inputUrl) {
    if ($inputUrl -match "playlist") {
        $lblStatus.Text = "📦 រកឃើញ Link Playlist! កំពុងបើកកម្មវិធី Suno Playlist Downloader..."
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 200, 255)
        Start-Process "wscript.exe" -ArgumentList "`"$sunoDir\SunoPlaylistDownloaderLauncher.vbs`" `"$inputUrl`""
        return
    }

    $clipId = ExtractClipId $inputUrl
    if (-not $clipId) {
        $lblStatus.Text = "⚠️ សូមបញ្ចូល Link URL ឬ UUID របស់បទចម្រៀង Suno អោយបានត្រឹមត្រូវ។"
        $lblStatus.ForeColor = [System.Drawing.Color]::Orange
        return
    }

    $lblStatus.Text = "🔍 កំពុងទាញយកព័ត៌មានបទចម្រៀង..."
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 200, 255)
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $meta = Invoke-RestMethod -Uri "https://studio-api.prod.suno.com/api/clip/$clipId" -Headers @{ "User-Agent" = "Mozilla/5.0" }
        $title = if ($meta.title) { $meta.title } else { "Suno Song" }
        $status = if ($meta.status) { $meta.status } else { "unknown" }
        $sec = [double]($meta.metadata.duration)
        $durationStr = "{0:D2}:{1:D2}" -f [int]($sec / 60), [int]($sec % 60)

        $lblSongTitle.Text = $title
        $lblSongMeta.Text = "រយៈពេល៖ $durationStr | ស្ថានភាព៖ $status | ID: $clipId"
        $lblStatus.Text = "✅ បានរកឃើញបទចម្រៀង! ចុច 'ទាញយកចម្រៀង' ដើម្បីទាញយក។"
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(80, 230, 160)

        if ($meta.image_large_url) {
            try { $picCover.LoadAsync($meta.image_large_url) } catch { }
        }
    } catch {
        $lblStatus.Text = "⚠️ មិនអាចទាញយកព័ត៌មានពី Suno: $($_.Exception.Message)"
        $lblStatus.ForeColor = [System.Drawing.Color]::Orange
    }
}

$btnPaste.Add_Click({
    if ([System.Windows.Forms.Clipboard]::ContainsText()) {
        $txtUrl.Text = [System.Windows.Forms.Clipboard]::GetText().Trim()
        InspectSong $txtUrl.Text
    }
})

$btnInspect.Add_Click({ InspectSong $txtUrl.Text })

function DownloadSong([string]$inputUrl, [string]$fmt) {
    if ($script:isDownloading) { return }

    if ($inputUrl -match "playlist") {
        $lblStatus.Text = "📦 រកឃើញ Link Playlist! កំពុងបើកកម្មវិធី Suno Playlist Downloader..."
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 200, 255)
        Start-Process "wscript.exe" -ArgumentList "`"$sunoDir\SunoPlaylistDownloaderLauncher.vbs`" `"$inputUrl`""
        return
    }

    $clipId = ExtractClipId $inputUrl
    if (-not $clipId) {
        [System.Windows.Forms.MessageBox]::Show("សូមបញ្ចូល Link URL របស់ Suno អោយបានត្រឹមត្រូវ!`n(ឧ. https://suno.com/song/c9505feb-5492-400b-9648-c8af417b24eb)", "Suno Downloader", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $script:isDownloading = $true
    $btnDownload.Enabled = $false
    $progressBar.Value = 10
    $lblStatus.Text = "⏳ កំពុងដំណើរការទាញយកសម្លេងពី Suno..."
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 60)
    [System.Windows.Forms.Application]::DoEvents()

    $saveDir = $txtSavePath.Text.Trim()
    if (-not (Test-Path $saveDir)) { New-Item -ItemType Directory -Force -Path $saveDir | Out-Null }

    try {
        # 1. Fetch metadata
        $title = "Suno_Song"
        $imgUrl = ""
        try {
            $meta = Invoke-RestMethod -Uri "https://studio-api.prod.suno.com/api/clip/$clipId" -Headers @{ "User-Agent" = "Mozilla/5.0" }
            if ($meta.title) { $title = $meta.title }
            if ($meta.image_large_url) { $imgUrl = $meta.image_large_url }
        } catch { }

        $lblSongTitle.Text = $title
        if ($imgUrl) { try { $picCover.LoadAsync($imgUrl) } catch { } }
        $progressBar.Value = 30
        $lblStatus.Text = "⏳ កំពុងស្វែងរក Master Audio Stream..."
        [System.Windows.Forms.Application]::DoEvents()

        # 2. Audio URL resolution
        $tempMp3 = Join-Path ([System.IO.Path]::GetTempPath()) "suno_${clipId}_$([DateTime]::UtcNow.Ticks).mp3"
        $downloadSuccess = $false

        # Attempt 1: Direct CDN URL
        try {
            $audioUrl = "https://cdn1.suno.ai/$clipId.mp3"
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "Mozilla/5.0")
            $wc.DownloadFile($audioUrl, $tempMp3)
            if ((Test-Path $tempMp3) -and (Get-Item $tempMp3).Length -gt 10000) {
                $downloadSuccess = $true
            }
        } catch { }

        # Attempt 2: Suno download endpoint
        if (-not $downloadSuccess) {
            try {
                $dlApiUrl = "https://suno.com/a/api/download/clip/$clipId?format=mp3"
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "Mozilla/5.0")
                $wc.DownloadFile($dlApiUrl, $tempMp3)
                if ((Test-Path $tempMp3) -and (Get-Item $tempMp3).Length -gt 10000) {
                    $downloadSuccess = $true
                }
            } catch { }
        }

        # Attempt 3: S3 master upload stream
        if (-not $downloadSuccess) {
            try {
                $s3Url = "https://suno-data-uploads.s3.amazonaws.com/studio/uploads/${clipId}_lyrics.mp3"
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "Mozilla/5.0")
                $wc.DownloadFile($s3Url, $tempMp3)
                if ((Test-Path $tempMp3) -and (Get-Item $tempMp3).Length -gt 10000) {
                    $downloadSuccess = $true
                }
            } catch { }
        }

        if (-not $downloadSuccess) {
            # Try delegating to Suno Desktop which holds the active authenticated session
            $lblStatus.Text = "⏳ កំពុងស្នើសុំទាញយកតាម Suno Desktop (Authenticated Session)..."
            [System.Windows.Forms.Application]::DoEvents()

            $queue = @()
            if (Test-Path $queueFile) {
                try {
                    $raw = Get-Content $queueFile -Raw -ErrorAction SilentlyContinue
                    if ($raw) { $queue = @($raw | ConvertFrom-Json) }
                } catch { }
            }
            $item = @{
                source = "downloader_app"
                url = $inputUrl
                clipId = $clipId
                title = $title
                format = $fmt
                timestamp = [DateTime]::UtcNow.Ticks
                processed = $false
            }
            $queue += $item
            try {
                $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
                [System.IO.File]::WriteAllText($queueFile, (ConvertTo-JsonArray $queue), $utf8NoBom)
            } catch { }

            # Ensure Suno desktop is running
            $sunoRunning = Get-Process -ErrorAction SilentlyContinue | Where-Object { ($_.ProcessName -match "Suno AI Music|powershell|electron") -and ($_.MainWindowTitle -match "Suno") }
            if (-not $sunoRunning) {
                $sunoLauncher = Join-Path $sunoDir "SunoLauncher.vbs"
                if (Test-Path $sunoLauncher) { Start-Process "wscript.exe" "`"$sunoLauncher`"" }
            }

            # Wait for file in downloads folder up to 15 seconds
            $waited = 0
            $foundFile = $null

            while ($waited -lt 15) {
                Start-Sleep -Milliseconds 1000
                $waited++
                $progressBar.Value = [Math]::Min(95, 30 + ($waited * 4))
                [System.Windows.Forms.Application]::DoEvents()

                # Look for recently modified/created wav/mp3 file in saveDir
                $recent = Get-ChildItem -Path $saveDir -Filter "*$($fmt)*" -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-2) } |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1

                if ($recent -and ($recent.Length -gt 10000)) {
                    $foundFile = $recent
                    break
                }
            }

            if ($foundFile) {
                $finalPath = $foundFile.FullName
                $sizeMb = "{0:N2} MB" -f ($foundFile.Length / 1MB)
                $progressBar.Value = 100
                $lblStatus.Text = "🎉 ទាញយកបានជោគជ័យ! រក្សាទុកក្នុង៖ $($foundFile.Name)"
                $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(80, 230, 160)

                # Add to ListView
                $item = New-Object System.Windows.Forms.ListViewItem($foundFile.BaseName)
                $item.SubItems.Add($fmt.ToUpper()) | Out-Null
                $item.SubItems.Add($sizeMb) | Out-Null
                $item.SubItems.Add([DateTime]::Now.ToString("HH:mm:ss")) | Out-Null
                $item.SubItems.Add($finalPath) | Out-Null
                $item.Tag = $finalPath
                $lvHistory.Items.Insert(0, $item)

                try { [System.Media.SystemSounds]::Asterisk.Play() } catch { }
                return
            } else {
                throw "មិនអាចទាញយកសម្លេងពី Suno បានទេ។ សូមប្រាកដថាកម្មវិធី Suno កំពុងបើក និងបាន Login!"
            }
        }

        $progressBar.Value = 70
        $lblStatus.Text = if ($fmt -eq "wav") { "⚙️ កំពុងបំលែងទៅជា 16-bit 44.1kHz Stereo WAV (PCM)..." } else { "💾 កំពុងរក្សាទុកឯកសារ MP3..." }
        [System.Windows.Forms.Application]::DoEvents()

        # Clean file name
        $cleanTitle = ($title -replace '[/\\?%*:|"<>]', '_').Trim()
        if (-not $cleanTitle) { $cleanTitle = "Suno_Song_$($clipId.Substring(0,8))" }

        $finalExt = if ($fmt -eq "wav") { ".wav" } else { ".mp3" }
        $finalPath = Join-Path $saveDir "$cleanTitle$finalExt"

        $cnt = 1
        while (Test-Path $finalPath) {
            $finalPath = Join-Path $saveDir "$cleanTitle ($cnt)$finalExt"
            $cnt++
        }

        if ($fmt -eq "wav") {
            & $ffmpegPath -i $tempMp3 -c:a pcm_s16le -ar 44100 -ac 2 $finalPath -y 2>$null
            if (-not (Test-Path $finalPath) -or (Get-Item $finalPath).Length -lt 1000) {
                throw "FFmpeg conversion failed or output is empty."
            }
        } else {
            Copy-Item $tempMp3 $finalPath -Force
        }

        try { if (Test-Path $tempMp3) { Remove-Item $tempMp3 -Force } } catch { }

        $fi = Get-Item $finalPath
        $sizeMb = "{0:N2} MB" -f ($fi.Length / 1MB)

        $progressBar.Value = 100
        $lblStatus.Text = "🎉 ទាញយកបានជោគជ័យ! រក្សាទុកក្នុង៖ $(Split-Path $finalPath -Leaf)"
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(80, 230, 160)

        # Add to ListView
        $item = New-Object System.Windows.Forms.ListViewItem($cleanTitle)
        $item.SubItems.Add($fmt.ToUpper()) | Out-Null
        $item.SubItems.Add($sizeMb) | Out-Null
        $item.SubItems.Add([DateTime]::Now.ToString("HH:mm:ss")) | Out-Null
        $item.SubItems.Add($finalPath) | Out-Null
        $item.Tag = $finalPath
        $lvHistory.Items.Insert(0, $item)

        try { [System.Media.SystemSounds]::Asterisk.Play() } catch { }
    } catch {
        $progressBar.Value = 0
        $lblStatus.Text = "⚠️ បរាជ័យក្នុងការទាញយក៖ $($_.Exception.Message)"
        $lblStatus.ForeColor = [System.Drawing.Color]::OrangeRed
        [System.Windows.Forms.MessageBox]::Show("បរាជ័យក្នុងការទាញយកបទចម្រៀង៖`n$($_.Exception.Message)", "Suno Downloader Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } finally {
        $script:isDownloading = $false
        $btnDownload.Enabled = $true
    }
}

$btnDownload.Add_Click({
    $fmt = if ($rbWav.Checked) { "wav" } else { "mp3" }
    DownloadSong $txtUrl.Text $fmt
})

# Queue Timer (Auto-Download Watcher)
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1200
$timer.Add_Tick({
    if (-not $chkAutoWatch.Checked -or $script:isDownloading) { return }

    if (Test-Path $queueFile) {
        try {
            $raw = Get-Content $queueFile -Raw -ErrorAction SilentlyContinue
            if ($raw -and $raw.Trim() -ne "[]") {
                $queue = Get-FlatJsonArray $raw
                foreach ($item in $queue) {
                    $itemUrl = $item.url
                    if ($itemUrl -and (-not $script:processedClips.Contains($itemUrl))) {
                        $script:processedClips.Add($itemUrl) | Out-Null
                        $itemFmt = if ($item.format) { $item.format } else { "wav" }

                        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
                        $form.BringToFront()
                        $form.Activate()

                        $txtUrl.Text = $itemUrl
                        DownloadSong $itemUrl $itemFmt
                        break
                    }
                }
            }
        } catch { }
    }
})
$timer.Start()

$form.Add_Load({
    if ($url) {
        $txtUrl.Text = $url
        if ($auto) {
            DownloadSong $url $format
        } else {
            InspectSong $url
        }
    }
})

$form.Add_Shown({
    try {
        $form.Activate()
        $form.BringToFront()
        [Win32Dl]::ShowWindow($form.Handle, 5) | Out-Null
        [Win32Dl]::SetForegroundWindow($form.Handle) | Out-Null
    } catch { }
})

$form.Add_FormClosing({
    $timer.Stop()
    if ($appMutex) {
        try { $appMutex.ReleaseMutex() } catch { }
        $appMutex.Dispose()
    }
})

[System.Windows.Forms.Application]::EnableVisualStyles()
$null = $form.ShowDialog()
