# ==============================================================================
# Suno AI Studio Pro - Suno Audio Studio (SunoAudioStudio.ps1)
# Professional Audio Player, Metadata Manager & Playlist Organizer
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# High DPI Awareness
$win32Dpi = @"
using System;
using System.Runtime.InteropServices;
public class AudioStudioDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
try {
    Add-Type -TypeDefinition $win32Dpi -ErrorAction SilentlyContinue
    [AudioStudioDpi]::SetProcessDPIAware() | Out-Null
} catch { }

$sunoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $sunoDir -or -not (Test-Path $sunoDir)) {
    $sunoDir = "C:\Users\PS\AppData\Local\Programs\Suno"
}
$downloadsDir = Join-Path $sunoDir "Data\Downloads"
if (-not (Test-Path $downloadsDir)) {
    New-Item -ItemType Directory -Force -Path $downloadsDir | Out-Null
}

# --- Audio Player Instance ---
$mediaPlayer = New-Object System.Windows.Media.MediaPlayer
$currentTrackPath = ""
$isPlaying = $false
$isSeeking = $false
$durationSeconds = 0

# --- WinForms UI Setup ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "🎵 Suno AI Audio Studio - ចាក់ និងគ្រប់គ្រងចម្រៀង Suno"
$form.Size = New-Object System.Drawing.Size 1060, 720
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 23)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$form.MinimumSize = New-Object System.Drawing.Size 960, 640

# --- Top Header Panel ---
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlHeader.Height = 80
$pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(23, 27, 38)
$pnlHeader.Padding = New-Object System.Windows.Forms.Padding(20, 12, 20, 10)
$form.Controls.Add($pnlHeader)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "🎵 Suno AI Audio Studio & Playlist Manager"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 13.5, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 94, 58)
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(18, 12)
$pnlHeader.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "ស្ទូឌីយោចាក់ស្តាប់ គ្រប់គ្រងព័ត៌មានបទចម្រៀង (Metadata) និងរៀបចំបញ្ជីចម្រៀងទាញយកពី Suno"
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(160, 175, 200)
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(20, 46)
$pnlHeader.Controls.Add($lblSub)

$btnChangeDir = New-Object System.Windows.Forms.Button
$btnChangeDir.Text = "📁 ប្តូរថតចម្រៀង"
$btnChangeDir.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnChangeDir.Size = New-Object System.Drawing.Size 130, 36
$btnChangeDir.Location = New-Object System.Drawing.Point(740, 22)
$btnChangeDir.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnChangeDir.BackColor = [System.Drawing.Color]::FromArgb(40, 48, 68)
$btnChangeDir.ForeColor = [System.Drawing.Color]::White
$btnChangeDir.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnChangeDir.FlatAppearance.BorderSize = 0
$btnChangeDir.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlHeader.Controls.Add($btnChangeDir)

$btnOpenFolder = New-Object System.Windows.Forms.Button
$btnOpenFolder.Text = "📂 បើកថត Downloads"
$btnOpenFolder.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnOpenFolder.Size = New-Object System.Drawing.Size 155, 36
$btnOpenFolder.Location = New-Object System.Drawing.Point(880, 22)
$btnOpenFolder.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnOpenFolder.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$btnOpenFolder.ForeColor = [System.Drawing.Color]::White
$btnOpenFolder.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenFolder.FlatAppearance.BorderSize = 0
$btnOpenFolder.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlHeader.Controls.Add($btnOpenFolder)

# --- Bottom Playback Bar ---
$pnlBottom = New-Object System.Windows.Forms.Panel
$pnlBottom.Dock = [System.Windows.Forms.DockStyle]::Bottom
$pnlBottom.Height = 115
$pnlBottom.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 34)
$pnlBottom.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)
$form.Controls.Add($pnlBottom)

# Now Playing Info
$lblNowPlaying = New-Object System.Windows.Forms.Label
$lblNowPlaying.Text = "⏹️ មិនទាន់មានចម្រៀងកំពុងចាក់ (ជ្រើសរើសចម្រៀងពីបញ្ជីខាងលើ)"
$lblNowPlaying.Font = New-Object System.Drawing.Font("Segoe UI", 10.0, [System.Drawing.FontStyle]::Bold)
$lblNowPlaying.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
$lblNowPlaying.Location = New-Object System.Drawing.Point(20, 8)
$lblNowPlaying.Size = New-Object System.Drawing.Size 650, 24
$pnlBottom.Controls.Add($lblNowPlaying)

# Time Display
$lblTime = New-Object System.Windows.Forms.Label
$lblTime.Text = "00:00 / 00:00"
$lblTime.Font = New-Object System.Drawing.Font("Consolas", 10.0)
$lblTime.ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 230)
$lblTime.Location = New-Object System.Drawing.Point(920, 8)
$lblTime.Size = New-Object System.Drawing.Size 110, 24
$lblTime.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblTime.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$pnlBottom.Controls.Add($lblTime)

# Seek TrackBar
$tbSeek = New-Object System.Windows.Forms.TrackBar
$tbSeek.Location = New-Object System.Drawing.Point(15, 34)
$tbSeek.Size = New-Object System.Drawing.Size 1015, 30
$tbSeek.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$tbSeek.TickStyle = [System.Windows.Forms.TickStyle]::None
$tbSeek.Minimum = 0
$tbSeek.Maximum = 100
$tbSeek.Value = 0
$tbSeek.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 34)
$pnlBottom.Controls.Add($tbSeek)

# Control Buttons
$btnPrev = New-Object System.Windows.Forms.Button
$btnPrev.Text = "⏮️ មុន"
$btnPrev.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnPrev.Size = New-Object System.Drawing.Size(75, 34)
$btnPrev.Location = New-Object System.Drawing.Point(20, 72)
$btnPrev.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 58)
$btnPrev.ForeColor = [System.Drawing.Color]::White
$btnPrev.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPrev.FlatAppearance.BorderSize = 0
$btnPrev.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlBottom.Controls.Add($btnPrev)

$btnPlay = New-Object System.Windows.Forms.Button
$btnPlay.Text = "▶ ចាក់ (Play)"
$btnPlay.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnPlay.Size = New-Object System.Drawing.Size(125, 34)
$btnPlay.Location = New-Object System.Drawing.Point(105, 72)
$btnPlay.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$btnPlay.ForeColor = [System.Drawing.Color]::White
$btnPlay.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPlay.FlatAppearance.BorderSize = 0
$btnPlay.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlBottom.Controls.Add($btnPlay)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "⏹️ បញ្ឈប់"
$btnStop.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnStop.Size = New-Object System.Drawing.Size(85, 34)
$btnStop.Location = New-Object System.Drawing.Point(240, 72)
$btnStop.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 58)
$btnStop.ForeColor = [System.Drawing.Color]::White
$btnStop.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnStop.FlatAppearance.BorderSize = 0
$btnStop.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlBottom.Controls.Add($btnStop)

$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Text = "⏭️ បន្ទាប់"
$btnNext.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnNext.Size = New-Object System.Drawing.Size(75, 34)
$btnNext.Location = New-Object System.Drawing.Point(335, 72)
$btnNext.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 58)
$btnNext.ForeColor = [System.Drawing.Color]::White
$btnNext.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnNext.FlatAppearance.BorderSize = 0
$btnNext.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlBottom.Controls.Add($btnNext)

$chkLoop = New-Object System.Windows.Forms.CheckBox
$chkLoop.Text = "🔂 ចាក់សារឡើងវិញ (Repeat)"
$chkLoop.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$chkLoop.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 220)
$chkLoop.Location = New-Object System.Drawing.Point(430, 75)
$chkLoop.Size = New-Object System.Drawing.Size 190, 26
$chkLoop.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlBottom.Controls.Add($chkLoop)

# Volume controls
$lblVol = New-Object System.Windows.Forms.Label
$lblVol.Text = "🔊 សំឡេង:"
$lblVol.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$lblVol.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 220)
$lblVol.Location = New-Object System.Drawing.Point(740, 77)
$lblVol.Size = New-Object System.Drawing.Size 70, 24
$lblVol.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$pnlBottom.Controls.Add($lblVol)

$tbVol = New-Object System.Windows.Forms.TrackBar
$tbVol.Location = New-Object System.Drawing.Point(815, 72)
$tbVol.Size = New-Object System.Drawing.Size 215, 30
$tbVol.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$tbVol.TickStyle = [System.Windows.Forms.TickStyle]::None
$tbVol.Minimum = 0
$tbVol.Maximum = 100
$tbVol.Value = 85
$tbVol.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 34)
$pnlBottom.Controls.Add($tbVol)

# --- Main Split Container ---
$splitMain = New-Object System.Windows.Forms.SplitContainer
$splitMain.Dock = [System.Windows.Forms.DockStyle]::Fill
$splitMain.SplitterDistance = 640
$splitMain.BackColor = [System.Drawing.Color]::FromArgb(28, 32, 45)
$form.Controls.Add($splitMain)

# Left Panel: Track List & Search
$pnlLeft = $splitMain.Panel1
$pnlLeft.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 23)
$pnlLeft.Padding = New-Object System.Windows.Forms.Padding(15, 12, 10, 12)

# Search Bar
$pnlSearch = New-Object System.Windows.Forms.Panel
$pnlSearch.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlSearch.Height = 44
$pnlLeft.Controls.Add($pnlSearch)

$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text = "🔍 ស្វែងរក:"
$lblSearch.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$lblSearch.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 220)
$lblSearch.Location = New-Object System.Drawing.Point(2, 8)
$lblSearch.Size = New-Object System.Drawing.Size 70, 24
$pnlSearch.Controls.Add($lblSearch)

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(75, 6)
$txtSearch.Size = New-Object System.Drawing.Size 420, 28
$txtSearch.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$txtSearch.BackColor = [System.Drawing.Color]::FromArgb(25, 30, 42)
$txtSearch.ForeColor = [System.Drawing.Color]::White
$txtSearch.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pnlSearch.Controls.Add($txtSearch)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "🔄 ផ្ទុកឡើងវិញ"
$btnRefresh.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$btnRefresh.Size = New-Object System.Drawing.Size 110, 28
$btnRefresh.Location = New-Object System.Drawing.Point(505, 5)
$btnRefresh.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 58)
$btnRefresh.ForeColor = [System.Drawing.Color]::White
$btnRefresh.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRefresh.FlatAppearance.BorderSize = 0
$btnRefresh.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlSearch.Controls.Add($btnRefresh)

# DataGridView Track List
$gridTracks = New-Object System.Windows.Forms.DataGridView
$gridTracks.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridTracks.BackgroundColor = [System.Drawing.Color]::FromArgb(18, 21, 30)
$gridTracks.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$gridTracks.GridColor = [System.Drawing.Color]::FromArgb(30, 36, 50)
$gridTracks.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$gridTracks.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$gridTracks.MultiSelect = $false
$gridTracks.ReadOnly = $true
$gridTracks.AllowUserToAddRows = $false
$gridTracks.AllowUserToDeleteRows = $false
$gridTracks.RowHeadersVisible = $false
$gridTracks.EnableHeadersVisualStyles = $false
$gridTracks.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(26, 32, 46)
$gridTracks.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 60)
$gridTracks.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9.2, [System.Drawing.FontStyle]::Bold)
$gridTracks.ColumnHeadersHeight = 34
$gridTracks.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(18, 21, 30)
$gridTracks.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$gridTracks.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
$gridTracks.RowTemplate.Height = 30
$pnlLeft.Controls.Add($gridTracks)
$gridTracks.BringToFront()

# Columns
$colStatus = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colStatus.HeaderText = ""
$colStatus.Width = 35
$colStatus.DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleCenter
$gridTracks.Columns.Add($colStatus) | Out-Null

$colName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colName.HeaderText = "ចំណងជើងបទចម្រៀង (Song Title)"
$colName.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
$gridTracks.Columns.Add($colName) | Out-Null

$colExt = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colExt.HeaderText = "ប្រភេទ"
$colExt.Width = 65
$gridTracks.Columns.Add($colExt) | Out-Null

$colSize = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colSize.HeaderText = "ទំហំ"
$colSize.Width = 75
$gridTracks.Columns.Add($colSize) | Out-Null

$colDate = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colDate.HeaderText = "កាលបរិច្ឆេទ"
$colDate.Width = 110
$gridTracks.Columns.Add($colDate) | Out-Null

$colPath = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPath.HeaderText = "Path"
$colPath.Visible = $false
$gridTracks.Columns.Add($colPath) | Out-Null

# Right Panel: Track Details & Tag Editor
$pnlRight = $splitMain.Panel2
$pnlRight.BackColor = [System.Drawing.Color]::FromArgb(18, 21, 30)
$pnlRight.Padding = New-Object System.Windows.Forms.Padding(18, 14, 18, 14)

$lblDetailsHeader = New-Object System.Windows.Forms.Label
$lblDetailsHeader.Text = "📝 ព័ត៌មាន និងការកំណត់បទ (Track Details)"
$lblDetailsHeader.Font = New-Object System.Drawing.Font("Segoe UI", 11.0, [System.Drawing.FontStyle]::Bold)
$lblDetailsHeader.ForeColor = [System.Drawing.Color]::FromArgb(255, 94, 58)
$lblDetailsHeader.AutoSize = $true
$lblDetailsHeader.Location = New-Object System.Drawing.Point(16, 12)
$pnlRight.Controls.Add($lblDetailsHeader)

$lblEditTitle = New-Object System.Windows.Forms.Label
$lblEditTitle.Text = "ចំណងជើងបទ (Title):"
$lblEditTitle.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 220)
$lblEditTitle.Location = New-Object System.Drawing.Point(18, 55)
$lblEditTitle.AutoSize = $true
$pnlRight.Controls.Add($lblEditTitle)

$txtEditTitle = New-Object System.Windows.Forms.TextBox
$txtEditTitle.Location = New-Object System.Drawing.Point(18, 78)
$txtEditTitle.Size = New-Object System.Drawing.Size 320, 28
$txtEditTitle.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$txtEditTitle.BackColor = [System.Drawing.Color]::FromArgb(28, 33, 46)
$txtEditTitle.ForeColor = [System.Drawing.Color]::White
$txtEditTitle.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pnlRight.Controls.Add($txtEditTitle)

$lblEditArtist = New-Object System.Windows.Forms.Label
$lblEditArtist.Text = "អ្នកនិពន្ធ / សិល្បករ (Artist):"
$lblEditArtist.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 220)
$lblEditArtist.Location = New-Object System.Drawing.Point(18, 118)
$lblEditArtist.AutoSize = $true
$pnlRight.Controls.Add($lblEditArtist)

$txtEditArtist = New-Object System.Windows.Forms.TextBox
$txtEditArtist.Location = New-Object System.Drawing.Point(18, 141)
$txtEditArtist.Size = New-Object System.Drawing.Size 320, 28
$txtEditArtist.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$txtEditArtist.BackColor = [System.Drawing.Color]::FromArgb(28, 33, 46)
$txtEditArtist.ForeColor = [System.Drawing.Color]::White
$txtEditArtist.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtEditArtist.Text = "Suno AI"
$pnlRight.Controls.Add($txtEditArtist)

$lblEditGenre = New-Object System.Windows.Forms.Label
$lblEditGenre.Text = "ប្រភេទតន្ត្រី (Genre):"
$lblEditGenre.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 220)
$lblEditGenre.Location = New-Object System.Drawing.Point(18, 181)
$lblEditGenre.AutoSize = $true
$pnlRight.Controls.Add($lblEditGenre)

$txtEditGenre = New-Object System.Windows.Forms.TextBox
$txtEditGenre.Location = New-Object System.Drawing.Point(18, 204)
$txtEditGenre.Size = New-Object System.Drawing.Size 320, 28
$txtEditGenre.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$txtEditGenre.BackColor = [System.Drawing.Color]::FromArgb(28, 33, 46)
$txtEditGenre.ForeColor = [System.Drawing.Color]::White
$txtEditGenre.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pnlRight.Controls.Add($txtEditGenre)

$lblInfoPath = New-Object System.Windows.Forms.Label
$lblInfoPath.Text = "ទីតាំងឯកសារ (File Path):"
$lblInfoPath.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 220)
$lblInfoPath.Location = New-Object System.Drawing.Point(18, 245)
$lblInfoPath.AutoSize = $true
$pnlRight.Controls.Add($lblInfoPath)

$txtInfoPath = New-Object System.Windows.Forms.TextBox
$txtInfoPath.Location = New-Object System.Drawing.Point(18, 268)
$txtInfoPath.Size = New-Object System.Drawing.Size 320, 48
$txtInfoPath.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$txtInfoPath.Multiline = $true
$txtInfoPath.ReadOnly = $true
$txtInfoPath.BackColor = [System.Drawing.Color]::FromArgb(22, 26, 36)
$txtInfoPath.ForeColor = [System.Drawing.Color]::FromArgb(160, 175, 200)
$txtInfoPath.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$pnlRight.Controls.Add($txtInfoPath)

# Action Buttons on Right
$btnRename = New-Object System.Windows.Forms.Button
$btnRename.Text = "💾 ប្តូរឈ្មោះតាម Title (Rename File)"
$btnRename.Font = New-Object System.Drawing.Font("Segoe UI", 9.2, [System.Drawing.FontStyle]::Bold)
$btnRename.Size = New-Object System.Drawing.Size 320, 38
$btnRename.Location = New-Object System.Drawing.Point(18, 335)
$btnRename.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$btnRename.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$btnRename.ForeColor = [System.Drawing.Color]::White
$btnRename.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRename.FlatAppearance.BorderSize = 0
$btnRename.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlRight.Controls.Add($btnRename)

$btnShowExplorer = New-Object System.Windows.Forms.Button
$btnShowExplorer.Text = "📁 បង្ហាញក្នុង File Explorer"
$btnShowExplorer.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnShowExplorer.Size = New-Object System.Drawing.Size 320, 36
$btnShowExplorer.Location = New-Object System.Drawing.Point(18, 383)
$btnShowExplorer.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$btnShowExplorer.BackColor = [System.Drawing.Color]::FromArgb(40, 48, 68)
$btnShowExplorer.ForeColor = [System.Drawing.Color]::White
$btnShowExplorer.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnShowExplorer.FlatAppearance.BorderSize = 0
$btnShowExplorer.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlRight.Controls.Add($btnShowExplorer)

$btnExternalPlay = New-Object System.Windows.Forms.Button
$btnExternalPlay.Text = "🎧 បើកតាមកម្មវិធីចាក់ចម្រៀងក្រៅ"
$btnExternalPlay.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnExternalPlay.Size = New-Object System.Drawing.Size 320, 36
$btnExternalPlay.Location = New-Object System.Drawing.Point(18, 429)
$btnExternalPlay.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$btnExternalPlay.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 58)
$btnExternalPlay.ForeColor = [System.Drawing.Color]::White
$btnExternalPlay.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnExternalPlay.FlatAppearance.BorderSize = 0
$btnExternalPlay.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlRight.Controls.Add($btnExternalPlay)

$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text = "🗑️ លុបបទចម្រៀងនេះចោល"
$btnDelete.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$btnDelete.Size = New-Object System.Drawing.Size 320, 34
$btnDelete.Location = New-Object System.Drawing.Point(18, 475)
$btnDelete.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$btnDelete.BackColor = [System.Drawing.Color]::FromArgb(70, 25, 25)
$btnDelete.ForeColor = [System.Drawing.Color]::FromArgb(250, 150, 150)
$btnDelete.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDelete.FlatAppearance.BorderSize = 0
$btnDelete.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlRight.Controls.Add($btnDelete)

# --- Playback Logic & Timer ---
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 400

$timer.Add_Tick({
    if ($mediaPlayer.Source -and $mediaPlayer.NaturalDuration.HasTimeSpan) {
        $dur = $mediaPlayer.NaturalDuration.TimeSpan
        $pos = $mediaPlayer.Position
        $durationSeconds = [Math]::Max(1, [int]$dur.TotalSeconds)

        if (-not $isSeeking) {
            $percent = [Math]::Min(100, [int](($pos.TotalSeconds / $durationSeconds) * 100))
            $tbSeek.Value = $percent
        }

        $posStr = "{0:mm\:ss}" -f $pos
        $durStr = "{0:mm\:ss}" -f $dur
        $lblTime.Text = "$posStr / $durStr"

        if ($pos -ge $dur -and $durationSeconds -gt 2) {
            if ($chkLoop.Checked) {
                $mediaPlayer.Position = [System.TimeSpan]::Zero
                $mediaPlayer.Play()
            } else {
                Play-NextTrack
            }
        }
    }
})

function Load-Tracks($folder) {
    $gridTracks.Rows.Clear()
    if (-not (Test-Path $folder)) { return }
    
    $filter = $txtSearch.Text.Trim().ToLower()
    $files = Get-ChildItem -Path $folder -File | Where-Object {
        $_.Extension -match "\.(mp3|wav|m4a|aac|flac|ogg)$"
    } | Sort-Object LastWriteTime -Descending

    foreach ($f in $files) {
        if ($filter -ne "" -and -not ($f.Name.ToLower().Contains($filter))) {
            continue
        }
        $icon = if ($f.FullName -eq $currentTrackPath) { "▶" } else { "" }
        $sizeMB = "{0:N2} MB" -f ($f.Length / 1MB)
        $dateStr = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
        $gridTracks.Rows.Add($icon, $f.Name, $f.Extension.ToUpper().TrimStart('.'), $sizeMB, $dateStr, $f.FullName) | Out-Null
    }

    $lblSub.Text = "ថតបច្ចុប្បន្ន: $folder | រកឃើញ $($gridTracks.Rows.Count) បទ"
}

function Play-Track($filePath) {
    if (-not (Test-Path $filePath)) { return }
    
    $global:currentTrackPath = $filePath
    $uri = New-Object System.Uri($filePath)
    $mediaPlayer.Open($uri)
    $mediaPlayer.Volume = ($tbVol.Value / 100.0)
    $mediaPlayer.Play()
    $global:isPlaying = $true
    
    $btnPlay.Text = "⏸ ផ្អាក (Pause)"
    $btnPlay.BackColor = [System.Drawing.Color]::FromArgb(234, 179, 8)
    $fileName = [System.IO.Path]::GetFileName($filePath)
    $lblNowPlaying.Text = "▶ កំពុងចាក់: $fileName"
    
    $timer.Start()
    
    # Update grid icons
    foreach ($row in $gridTracks.Rows) {
        if ($row.Cells[5].Value -eq $filePath) {
            $row.Cells[0].Value = "▶"
            $row.Selected = $true
        } else {
            $row.Cells[0].Value = ""
        }
    }
    
    # Update Details
    $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
    $txtEditTitle.Text = $nameWithoutExt
    $txtInfoPath.Text = $filePath
}

function Toggle-PlayPause {
    if (-not $currentTrackPath) {
        if ($gridTracks.Rows.Count -gt 0) {
            $firstPath = $gridTracks.Rows[0].Cells[5].Value
            Play-Track $firstPath
        }
        return
    }
    
    if ($isPlaying) {
        $mediaPlayer.Pause()
        $global:isPlaying = $false
        $btnPlay.Text = "▶ បន្ត (Resume)"
        $btnPlay.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
        $lblNowPlaying.Text = "⏸ ផ្អាក: " + [System.IO.Path]::GetFileName($currentTrackPath)
    } else {
        $mediaPlayer.Play()
        $global:isPlaying = $true
        $btnPlay.Text = "⏸ ផ្អាក (Pause)"
        $btnPlay.BackColor = [System.Drawing.Color]::FromArgb(234, 179, 8)
        $lblNowPlaying.Text = "▶ កំពុងចាក់: " + [System.IO.Path]::GetFileName($currentTrackPath)
    }
}

function Stop-Playback {
    $mediaPlayer.Stop()
    $global:isPlaying = $false
    $timer.Stop()
    $tbSeek.Value = 0
    $lblTime.Text = "00:00 / 00:00"
    $btnPlay.Text = "▶ ចាក់ (Play)"
    $btnPlay.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
    $lblNowPlaying.Text = "⏹️ បានបញ្ឈប់ការចាក់ចម្រៀង"
    foreach ($row in $gridTracks.Rows) {
        $row.Cells[0].Value = ""
    }
}

function Play-NextTrack {
    if ($gridTracks.Rows.Count -eq 0) { return }
    $currentIndex = -1
    for ($i = 0; $i -lt $gridTracks.Rows.Count; $i++) {
        if ($gridTracks.Rows[$i].Cells[5].Value -eq $currentTrackPath) {
            $currentIndex = $i
            break
        }
    }
    $nextIndex = ($currentIndex + 1) % $gridTracks.Rows.Count
    Play-Track $gridTracks.Rows[$nextIndex].Cells[5].Value
}

function Play-PrevTrack {
    if ($gridTracks.Rows.Count -eq 0) { return }
    $currentIndex = -1
    for ($i = 0; $i -lt $gridTracks.Rows.Count; $i++) {
        if ($gridTracks.Rows[$i].Cells[5].Value -eq $currentTrackPath) {
            $currentIndex = $i
            break
        }
    }
    $prevIndex = if ($currentIndex -le 0) { $gridTracks.Rows.Count - 1 } else { $currentIndex - 1 }
    Play-Track $gridTracks.Rows[$prevIndex].Cells[5].Value
}

# --- Event Handlers ---
$btnPlay.Add_Click({ Toggle-PlayPause })
$btnStop.Add_Click({ Stop-Playback })
$btnNext.Add_Click({ Play-NextTrack })
$btnPrev.Add_Click({ Play-PrevTrack })

$tbVol.Add_Scroll({
    $mediaPlayer.Volume = ($tbVol.Value / 100.0)
})

$tbSeek.Add_MouseDown({
    $global:isSeeking = $true
})

$tbSeek.Add_MouseUp({
    if ($mediaPlayer.Source -and $mediaPlayer.NaturalDuration.HasTimeSpan) {
        $totalSec = $mediaPlayer.NaturalDuration.TimeSpan.TotalSeconds
        $targetSec = ($tbSeek.Value / 100.0) * $totalSec
        $mediaPlayer.Position = [System.TimeSpan]::FromSeconds($targetSec)
    }
    $global:isSeeking = $false
})

$gridTracks.Add_CellDoubleClick({
    param($s, $e)
    if ($e.RowIndex -ge 0) {
        $p = $gridTracks.Rows[$e.RowIndex].Cells[5].Value
        Play-Track $p
    }
})

$gridTracks.Add_SelectionChanged({
    if ($gridTracks.SelectedRows.Count -gt 0) {
        $p = $gridTracks.SelectedRows[0].Cells[5].Value
        $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($p)
        $txtEditTitle.Text = $nameWithoutExt
        $txtInfoPath.Text = $p
    }
})

$btnRefresh.Add_Click({ Load-Tracks $downloadsDir })
$txtSearch.Add_TextChanged({ Load-Tracks $downloadsDir })

$btnChangeDir.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.SelectedPath = $downloadsDir
    $fbd.Description = "ជ្រើសរើសថតដែលផ្ទុកបទចម្រៀង Suno"
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $global:downloadsDir = $fbd.SelectedPath
        Load-Tracks $downloadsDir
    }
})

$btnOpenFolder.Add_Click({
    [System.Diagnostics.Process]::Start("explorer.exe", $downloadsDir)
})

$btnShowExplorer.Add_Click({
    if ($txtInfoPath.Text -and (Test-Path $txtInfoPath.Text)) {
        [System.Diagnostics.Process]::Start("explorer.exe", "/select,`"$($txtInfoPath.Text)`"")
    } else {
        [System.Diagnostics.Process]::Start("explorer.exe", $downloadsDir)
    }
})

$btnExternalPlay.Add_Click({
    if ($txtInfoPath.Text -and (Test-Path $txtInfoPath.Text)) {
        [System.Diagnostics.Process]::Start($txtInfoPath.Text)
    }
})

$btnRename.Add_Click({
    $cur = $txtInfoPath.Text
    if (-not $cur -or -not (Test-Path $cur)) {
        [System.Windows.Forms.MessageBox]::Show("សូមជ្រើសរើសបទចម្រៀងពីបញ្ជីជាមុនសិន!", "បញ្ជាក់", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    $newTitle = $txtEditTitle.Text.Trim()
    if (-not $newTitle) { return }
    
    # Sanitize filename
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $cleanTitle = $newTitle
    foreach ($c in $invalid) { $cleanTitle = $cleanTitle.Replace($c, '_') }
    
    $ext = [System.IO.Path]::GetExtension($cur)
    $dir = [System.IO.Path]::GetDirectoryName($cur)
    $targetName = "$cleanTitle$ext"
    $targetPath = Join-Path $dir $targetName
    
    if ($targetPath -ne $cur) {
        try {
            if ($currentTrackPath -eq $cur) {
                Stop-Playback
            }
            Rename-Item -Path $cur -NewName $targetName -Force
            [System.Windows.Forms.MessageBox]::Show("បានប្តូរឈ្មោះបទចម្រៀងទៅជា `"$targetName`" ដោយជោគជ័យ!", "ជោគជ័យ", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            Load-Tracks $downloadsDir
        } catch {
            [System.Windows.Forms.MessageBox]::Show("មិនអាចប្តូរឈ្មោះបានទេ: $($_.Exception.Message)", "កំហុស", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
})

$btnDelete.Add_Click({
    $cur = $txtInfoPath.Text
    if (-not $cur -or -not (Test-Path $cur)) { return }
    $fn = [System.IO.Path]::GetFileName($cur)
    $res = [System.Windows.Forms.MessageBox]::Show("តើអ្នកពិតជាចង់លុបបទចម្រៀង `"$fn`" នេះចោលមែនទេ?", "បញ្ជាក់ការលុប", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            if ($currentTrackPath -eq $cur) {
                Stop-Playback
            }
            Remove-Item -Path $cur -Force
            Load-Tracks $downloadsDir
        } catch {
            [System.Windows.Forms.MessageBox]::Show("មិនអាចលុបឯកសារបានទេ: $($_.Exception.Message)", "កំហុស", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
})

$form.Add_FormClosing({
    $timer.Stop()
    $mediaPlayer.Stop()
    $mediaPlayer.Close()
})

$form.Add_Shown({
    Load-Tracks $downloadsDir
})

[System.Windows.Forms.Application]::Run($form)
