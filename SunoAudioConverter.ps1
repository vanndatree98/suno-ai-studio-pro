# ==============================================================================
# Suno AI Studio Pro - Audio Converter, Trimmer & Normalizer (SunoAudioConverter.ps1)
# Convert, Master, Trim Silence, and Normalize Audio files using high-speed FFmpeg
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# High DPI Awareness
$win32Dpi = @"
using System;
using System.Runtime.InteropServices;
public class SunoConverterDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
try {
    Add-Type -TypeDefinition $win32Dpi -ErrorAction SilentlyContinue
    [SunoConverterDpi]::SetProcessDPIAware() | Out-Null
} catch { }

$sunoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $sunoDir -or -not (Test-Path $sunoDir)) {
    $sunoDir = "C:\Users\PS\AppData\Local\Programs\Suno"
}
$downloadsDir = Join-Path $sunoDir "Data\Downloads"
$outputDir = Join-Path $downloadsDir "Converted"
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

# Resolve FFmpeg
function Get-FFmpeg {
    $where = (where.exe ffmpeg 2>$null) | Select-Object -First 1
    if ($where -and (Test-Path $where)) { return $where }
    
    $common = "C:\Users\PS\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-9.0.2-full_build\bin\ffmpeg.exe"
    if (Test-Path $common) { return $common }
    return "ffmpeg.exe"
}
$ffmpegExe = Get-FFmpeg

$form = New-Object System.Windows.Forms.Form
$form.Text = "🎛️ Suno AI Studio Pro - Audio Converter & Normalizer"
$form.Size = New-Object System.Drawing.Size 1020, 720
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 23)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$form.MinimumSize = New-Object System.Drawing.Size 940, 640

# Top Header
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlHeader.Height = 85
$pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(23, 27, 38)
$pnlHeader.Padding = New-Object System.Windows.Forms.Padding(20, 14, 20, 10)
$form.Controls.Add($pnlHeader)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "🎛️ Suno Studio Audio Converter, Trimmer & Normalizer"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 13.0, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 94, 58)
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(18, 14)
$pnlHeader.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "បំប្លែងទម្រង់ឯកសារចម្រៀង (WAV, MP3, FLAC, AAC), កាត់បន្ថយសំឡេងស្ងាត់ដើម/ចុង និងកែតម្រូវកម្រិតសំឡេង Loudness"
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(160, 175, 200)
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(20, 48)
$pnlHeader.Controls.Add($lblSub)

# Main Split Container
$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = [System.Windows.Forms.DockStyle]::Fill
$split.SplitterDistance = 600
$split.BackColor = [System.Drawing.Color]::FromArgb(30, 36, 50)
$form.Controls.Add($split)
$split.BringToFront()

# Left: File List
$pnlLeft = $split.Panel1
$pnlLeft.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 23)
$pnlLeft.Padding = New-Object System.Windows.Forms.Padding(16, 12, 10, 12)

$lblList = New-Object System.Windows.Forms.Label
$lblList.Text = "📁 ជ្រើសរើសឯកសារចម្រៀង (Files in Downloads):"
$lblList.Font = New-Object System.Drawing.Font("Segoe UI", 9.2, [System.Drawing.FontStyle]::Bold)
$lblList.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
$lblList.Dock = [System.Windows.Forms.DockStyle]::Top
$lblList.Height = 28
$pnlLeft.Controls.Add($lblList)

$gridFiles = New-Object System.Windows.Forms.DataGridView
$gridFiles.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridFiles.BackgroundColor = [System.Drawing.Color]::FromArgb(18, 21, 30)
$gridFiles.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$gridFiles.GridColor = [System.Drawing.Color]::FromArgb(30, 36, 50)
$gridFiles.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$gridFiles.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$gridFiles.MultiSelect = $true
$gridFiles.ReadOnly = $true
$gridFiles.AllowUserToAddRows = $false
$gridFiles.RowHeadersVisible = $false
$gridFiles.EnableHeadersVisualStyles = $false
$gridFiles.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(26, 32, 46)
$gridFiles.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 60)
$gridFiles.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$gridFiles.ColumnHeadersHeight = 32
$gridFiles.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(18, 21, 30)
$gridFiles.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$gridFiles.RowTemplate.Height = 28
$pnlLeft.Controls.Add($gridFiles)
$gridFiles.BringToFront()

$colCheck = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$colCheck.HeaderText = "ជ្រើស"
$colCheck.Width = 50
$gridFiles.Columns.Add($colCheck) | Out-Null

$colName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colName.HeaderText = "ឈ្មោះឯកសារ (File Name)"
$colName.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
$gridFiles.Columns.Add($colName) | Out-Null

$colExt = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colExt.HeaderText = "ប្រភេទ"
$colExt.Width = 70
$gridFiles.Columns.Add($colExt) | Out-Null

$colSize = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colSize.HeaderText = "ទំហំ"
$colSize.Width = 85
$gridFiles.Columns.Add($colSize) | Out-Null

$colPath = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPath.HeaderText = "Path"
$colPath.Visible = $false
$gridFiles.Columns.Add($colPath) | Out-Null

# Left Bottom Buttons
$pnlLeftBottom = New-Object System.Windows.Forms.Panel
$pnlLeftBottom.Dock = [System.Windows.Forms.DockStyle]::Bottom
$pnlLeftBottom.Height = 44
$pnlLeft.Controls.Add($pnlLeftBottom)

$btnSelectAll = New-Object System.Windows.Forms.Button
$btnSelectAll.Text = "☑️ ជ្រើសទាំងអស់"
$btnSelectAll.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$btnSelectAll.Size = New-Object System.Drawing.Size 130, 32
$btnSelectAll.Location = New-Object System.Drawing.Point(0, 8)
$btnSelectAll.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 58)
$btnSelectAll.ForeColor = [System.Drawing.Color]::White
$btnSelectAll.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSelectAll.FlatAppearance.BorderSize = 0
$pnlLeftBottom.Controls.Add($btnSelectAll)

$btnBrowseFile = New-Object System.Windows.Forms.Button
$btnBrowseFile.Text = "➕ បន្ថែមឯកសារក្រៅ"
$btnBrowseFile.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$btnBrowseFile.Size = New-Object System.Drawing.Size 140, 32
$btnBrowseFile.Location = New-Object System.Drawing.Point(140, 8)
$btnBrowseFile.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 58)
$btnBrowseFile.ForeColor = [System.Drawing.Color]::White
$btnBrowseFile.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowseFile.FlatAppearance.BorderSize = 0
$pnlLeftBottom.Controls.Add($btnBrowseFile)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "🔄 ផ្ទុកឡើងវិញ"
$btnRefresh.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$btnRefresh.Size = New-Object System.Drawing.Size 110, 32
$btnRefresh.Location = New-Object System.Drawing.Point(290, 8)
$btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 58)
$btnRefresh.ForeColor = [System.Drawing.Color]::White
$btnRefresh.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRefresh.FlatAppearance.BorderSize = 0
$pnlLeftBottom.Controls.Add($btnRefresh)

# Right: Conversion Settings Panel
$pnlRight = $split.Panel2
$pnlRight.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 34)
$pnlRight.Padding = New-Object System.Windows.Forms.Padding(18, 14, 18, 14)

$lblSettings = New-Object System.Windows.Forms.Label
$lblSettings.Text = "⚙️ ការកំណត់ការបំប្លែង (Conversion Settings)"
$lblSettings.Font = New-Object System.Drawing.Font("Segoe UI", 11.0, [System.Drawing.FontStyle]::Bold)
$lblSettings.ForeColor = [System.Drawing.Color]::FromArgb(255, 94, 58)
$lblSettings.Location = New-Object System.Drawing.Point(16, 12)
$lblSettings.Size = New-Object System.Drawing.Size 360, 26
$pnlRight.Controls.Add($lblSettings)

# Format Selection
$lblFormat = New-Object System.Windows.Forms.Label
$lblFormat.Text = "ទម្រង់ឯកសារចេញ (Output Format):"
$lblFormat.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 220)
$lblFormat.Location = New-Object System.Drawing.Point(18, 48)
$lblFormat.Size = New-Object System.Drawing.Size 320, 20
$pnlRight.Controls.Add($lblFormat)

$cmbFormat = New-Object System.Windows.Forms.ComboBox
$cmbFormat.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbFormat.Location = New-Object System.Drawing.Point(18, 70)
$cmbFormat.Size = New-Object System.Drawing.Size 350, 28
$cmbFormat.BackColor = [System.Drawing.Color]::FromArgb(28, 33, 46)
$cmbFormat.ForeColor = [System.Drawing.Color]::White
$cmbFormat.Items.AddRange(@(
    "WAV (Studio Master 24-bit 48kHz)",
    "MP3 (High Quality 320 kbps)",
    "FLAC (Lossless Audio)",
    "AAC (High Efficiency 256 kbps)",
    "M4A (Apple Lossless ALAC)"
))
$cmbFormat.SelectedIndex = 0
$pnlRight.Controls.Add($cmbFormat)

# Normalization Option
$chkNormalize = New-Object System.Windows.Forms.CheckBox
$chkNormalize.Text = "🔊 Normalize Loudness (-14 LUFS Streaming Standard)"
$chkNormalize.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$chkNormalize.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
$chkNormalize.Location = New-Object System.Drawing.Point(18, 115)
$chkNormalize.Size = New-Object System.Drawing.Size 360, 26
$chkNormalize.Checked = $true
$pnlRight.Controls.Add($chkNormalize)

# Silence Trim Option
$chkTrimSilence = New-Object System.Windows.Forms.CheckBox
$chkTrimSilence.Text = "✂️ Auto-Trim Silence (កាត់ចោលសំឡេងស្ងាត់ដើម និងចុង)"
$chkTrimSilence.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$chkTrimSilence.ForeColor = [System.Drawing.Color]::FromArgb(200, 215, 235)
$chkTrimSilence.Location = New-Object System.Drawing.Point(18, 148)
$chkTrimSilence.Size = New-Object System.Drawing.Size 360, 26
$chkTrimSilence.Checked = $true
$pnlRight.Controls.Add($chkTrimSilence)

# Gain Boost
$lblGain = New-Object System.Windows.Forms.Label
$lblGain.Text = "កម្រិតពង្រីកសំឡេងបន្ថែម (Volume Gain Boost):"
$lblGain.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 220)
$lblGain.Location = New-Object System.Drawing.Point(18, 185)
$lblGain.Size = New-Object System.Drawing.Size 320, 20
$pnlRight.Controls.Add($lblGain)

$cmbGain = New-Object System.Windows.Forms.ComboBox
$cmbGain.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbGain.Location = New-Object System.Drawing.Point(18, 208)
$cmbGain.Size = New-Object System.Drawing.Size 350, 28
$cmbGain.BackColor = [System.Drawing.Color]::FromArgb(28, 33, 46)
$cmbGain.ForeColor = [System.Drawing.Color]::White
$cmbGain.Items.AddRange(@("0 dB (ធម្មតា)", "+2 dB (បង្កើនថ្នមៗ)", "+4 dB (បង្កើនល្មម)", "+6 dB (បង្កើនខ្លាំង)"))
$cmbGain.SelectedIndex = 0
$pnlRight.Controls.Add($cmbGain)

# Log Console
$txtConvertLog = New-Object System.Windows.Forms.RichTextBox
$txtConvertLog.Location = New-Object System.Drawing.Point(18, 250)
$txtConvertLog.Size = New-Object System.Drawing.Size 350, 220
$txtConvertLog.BackColor = [System.Drawing.Color]::FromArgb(12, 14, 20)
$txtConvertLog.ForeColor = [System.Drawing.Color]::FromArgb(180, 200, 230)
$txtConvertLog.Font = New-Object System.Drawing.Font("Consolas", 8.8)
$txtConvertLog.ReadOnly = $true
$txtConvertLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$pnlRight.Controls.Add($txtConvertLog)

# Action Buttons on Right
$btnStartConvert = New-Object System.Windows.Forms.Button
$btnStartConvert.Text = "🚀 ចាប់ផ្តើមបំប្លែង (Start Conversion)"
$btnStartConvert.Font = New-Object System.Drawing.Font("Segoe UI", 10.0, [System.Drawing.FontStyle]::Bold)
$btnStartConvert.Size = New-Object System.Drawing.Size 350, 44
$btnStartConvert.Location = New-Object System.Drawing.Point(18, 485)
$btnStartConvert.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$btnStartConvert.ForeColor = [System.Drawing.Color]::White
$btnStartConvert.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnStartConvert.FlatAppearance.BorderSize = 0
$btnStartConvert.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlRight.Controls.Add($btnStartConvert)

$btnOpenOutput = New-Object System.Windows.Forms.Button
$btnOpenOutput.Text = "📂 បើកថត Converted"
$btnOpenOutput.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnOpenOutput.Size = New-Object System.Drawing.Size 350, 36
$btnOpenOutput.Location = New-Object System.Drawing.Point(18, 538)
$btnOpenOutput.BackColor = [System.Drawing.Color]::FromArgb(40, 48, 68)
$btnOpenOutput.ForeColor = [System.Drawing.Color]::White
$btnOpenOutput.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenOutput.FlatAppearance.BorderSize = 0
$btnOpenOutput.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlRight.Controls.Add($btnOpenOutput)

function Append-CLog($msg, $color = [System.Drawing.Color]::White) {
    $txtConvertLog.SelectionStart = $txtConvertLog.TextLength
    $txtConvertLog.SelectionLength = 0
    $txtConvertLog.SelectionColor = $color
    $txtConvertLog.AppendText("$msg`r`n")
    $txtConvertLog.ScrollToCaret()
}

function Load-DownloadFiles {
    $gridFiles.Rows.Clear()
    if (-not (Test-Path $downloadsDir)) { return }
    $files = Get-ChildItem -Path $downloadsDir -File | Where-Object { $_.Extension -match "\.(mp3|wav|m4a|aac|flac|ogg)$" }
    foreach ($f in $files) {
        $sizeMB = "{0:N2} MB" -f ($f.Length / 1MB)
        $gridFiles.Rows.Add($false, $f.Name, $f.Extension.ToUpper().TrimStart('.'), $sizeMB, $f.FullName) | Out-Null
    }
}

$btnRefresh.Add_Click({ Load-DownloadFiles })

$btnSelectAll.Add_Click({
    $check = $btnSelectAll.Text.StartsWith("☑️")
    foreach ($row in $gridFiles.Rows) {
        $row.Cells[0].Value = $check
    }
    if ($check) {
        $btnSelectAll.Text = "⬜ ដោះជ្រើសទាំងអស់"
    } else {
        $btnSelectAll.Text = "☑️ ជ្រើសទាំងអស់"
    }
})

$btnBrowseFile.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "Audio Files (*.mp3;*.wav;*.m4a;*.aac;*.flac)|*.mp3;*.wav;*.m4a;*.aac;*.flac|All Files (*.*)|*.*"
    $ofd.Multiselect = $true
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        foreach ($fn in $ofd.FileNames) {
            $fi = New-Object System.IO.FileInfo($fn)
            $sizeMB = "{0:N2} MB" -f ($fi.Length / 1MB)
            $gridFiles.Rows.Add($true, $fi.Name, $fi.Extension.ToUpper().TrimStart('.'), $sizeMB, $fi.FullName) | Out-Null
        }
    }
})

$btnOpenOutput.Add_Click({
    [System.Diagnostics.Process]::Start("explorer.exe", $outputDir)
})

$btnStartConvert.Add_Click({
    $selectedPaths = @()
    foreach ($row in $gridFiles.Rows) {
        if ($row.Cells[0].Value -eq $true) {
            $selectedPaths += $row.Cells[4].Value
        }
    }

    if ($selectedPaths.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("សូមជ្រើសរើសឯកសារចម្រៀងយ៉ាងហោចណាស់ ១ ពីបញ្ជីខាងឆ្វេង!", "បញ្ជាក់", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $fmtIndex = $cmbFormat.SelectedIndex
    $targetExt = switch ($fmtIndex) {
        0 { ".wav" }
        1 { ".mp3" }
        2 { ".flac" }
        3 { ".aac" }
        4 { ".m4a" }
        default { ".wav" }
    }

    $txtConvertLog.Clear()
    Append-CLog "========================================" ([System.Drawing.Color]::FromArgb(255, 94, 58))
    Append-CLog "🚀 ចាប់ផ្តើមបំប្លែងឯកសារចំនួន $($selectedPaths.Count) បទ..." ([System.Drawing.Color]::FromArgb(52, 211, 153))
    Append-CLog "Target Format: $targetExt | Engine: FFmpeg" ([System.Drawing.Color]::FromArgb(160, 175, 200))
    Append-CLog "========================================" ([System.Drawing.Color]::FromArgb(255, 94, 58))

    $btnStartConvert.Enabled = $false
    $form.Update()

    $successCount = 0
    foreach ($src in $selectedPaths) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($src)
        $outFile = Join-Path $outputDir "$baseName$targetExt"

        Append-CLog "⏳ កំពុងដំណើរការ: $baseName..." ([System.Drawing.Color]::FromArgb(251, 146, 60))
        $form.Update()

        # Build ffmpeg args
        $filters = @()
        if ($chkTrimSilence.Checked) {
            $filters += "silenceremove=start_periods=1:start_duration=0.5:start_threshold=-50dB:detection=peak,areverse,silenceremove=start_periods=1:start_duration=0.5:start_threshold=-50dB:detection=peak,areverse"
        }
        if ($chkNormalize.Checked) {
            $filters += "loudnorm=I=-14:TP=-1.0:LRA=11"
        }
        if ($cmbGain.SelectedIndex -gt 0) {
            $gainDb = switch ($cmbGain.SelectedIndex) { 1 { "2dB" } 2 { "4dB" } 3 { "6dB" } default { "0dB" } }
            $filters += "volume=$gainDb"
        }

        $filterArg = if ($filters.Count -gt 0) { "-af `"" + [string]::Join(",", $filters) + "`"" } else { "" }

        $codecArgs = switch ($targetExt) {
            ".wav" { "-c:a pcm_s24le -ar 48000" }
            ".mp3" { "-c:a libmp3lame -b:a 320k" }
            ".flac" { "-c:a flac" }
            ".aac" { "-c:a aac -b:a 256k" }
            ".m4a" { "-c:a alac" }
            default { "" }
        }

        $cmdArgs = "-y -i `"$src`" $filterArg $codecArgs `"$outFile`""
        
        $proc = Start-Process -FilePath $ffmpegExe -ArgumentList $cmdArgs -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -eq 0 -and (Test-Path $outFile)) {
            Append-CLog "  ✅ ជោគជ័យ: $([System.IO.Path]::GetFileName($outFile))" ([System.Drawing.Color]::FromArgb(34, 197, 94))
            $successCount++
        } else {
            Append-CLog "  ❌ បរាជ័យលើ: $baseName" ([System.Drawing.Color]::FromArgb(239, 68, 68))
        }
    }

    Append-CLog "`n🎉 បានបញ្ចប់ការបំប្លែង $successCount / $($selectedPaths.Count) ឯកសារ!" ([System.Drawing.Color]::FromArgb(52, 211, 153))
    $btnStartConvert.Enabled = $true
    [System.Windows.Forms.MessageBox]::Show("បានបំប្លែង និង Master ឯកសារចម្រៀងចំនួន $successCount បទដោយជោគជ័យ!`n`nទីតាំង: $outputDir", "ជោគជ័យ", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
})

$form.Add_Shown({
    Load-DownloadFiles
})

[System.Windows.Forms.Application]::Run($form)
