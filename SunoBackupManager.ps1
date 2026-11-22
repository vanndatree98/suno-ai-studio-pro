# ==============================================================================
# Suno AI Studio Pro - Portable Backup & Restore Manager (SunoBackupManager.ps1)
# 1-Click Backup & Restore for portable Data, Logins, Sessions & Downloads
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem

# High DPI Awareness
$win32Dpi = @"
using System;
using System.Runtime.InteropServices;
public class SunoBackupDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
try {
    Add-Type -TypeDefinition $win32Dpi -ErrorAction SilentlyContinue
    [SunoBackupDpi]::SetProcessDPIAware() | Out-Null
} catch { }

$sunoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $sunoDir -or -not (Test-Path $sunoDir)) {
    $sunoDir = "C:\Users\PS\AppData\Local\Programs\Suno"
}
$dataDir = Join-Path $sunoDir "Data"
$backupDir = Join-Path $sunoDir "Backups"
if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "📦 Suno AI Studio Pro - Backup & Restore Manager"
$form.Size = New-Object System.Drawing.Size 880, 640
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 23)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false

# Top Header
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlHeader.Height = 85
$pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(23, 27, 38)
$pnlHeader.Padding = New-Object System.Windows.Forms.Padding(20, 14, 20, 10)
$form.Controls.Add($pnlHeader)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "📦 Suno Portable Data Backup & Restore Manager"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 13.0, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(18, 14)
$pnlHeader.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "គ្រប់គ្រងការរក្សាទុកបម្រុង និងស្ដារទិន្នន័យគណនី Login, Sessions, ការកំណត់ និងបទចម្រៀងទាញយករួច"
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(160, 175, 200)
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(20, 48)
$pnlHeader.Controls.Add($lblSub)

# Main Container
$pnlMain = New-Object System.Windows.Forms.Panel
$pnlMain.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlMain.Padding = New-Object System.Windows.Forms.Padding(20, 15, 20, 15)
$form.Controls.Add($pnlMain)
$pnlMain.BringToFront()

# Data Info Box
$grpInfo = New-Object System.Windows.Forms.GroupBox
$grpInfo.Text = " 📊 ស្ថិតិទិន្នន័យចល័តបច្ចុប្បន្ន (Current Portable Storage) "
$grpInfo.Font = New-Object System.Drawing.Font("Segoe UI", 9.2, [System.Drawing.FontStyle]::Bold)
$grpInfo.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 60)
$grpInfo.Location = New-Object System.Drawing.Point(20, 15)
$grpInfo.Size = New-Object System.Drawing.Size 825, 115
$pnlMain.Controls.Add($grpInfo)

$lblDataPath = New-Object System.Windows.Forms.Label
$lblDataPath.Text = "ទីតាំងទិន្នន័យ: $dataDir"
$lblDataPath.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$lblDataPath.ForeColor = [System.Drawing.Color]::FromArgb(200, 210, 230)
$lblDataPath.Location = New-Object System.Drawing.Point(20, 28)
$lblDataPath.Size = New-Object System.Drawing.Size 780, 22
$grpInfo.Controls.Add($lblDataPath)

$lblDataSize = New-Object System.Windows.Forms.Label
$lblDataSize.Text = "ទំហំសរុប: កំពុងគណនា..."
$lblDataSize.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$lblDataSize.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
$lblDataSize.Location = New-Object System.Drawing.Point(20, 54)
$lblDataSize.Size = New-Object System.Drawing.Size 380, 22
$grpInfo.Controls.Add($lblDataSize)

$lblDownloadsCount = New-Object System.Windows.Forms.Label
$lblDownloadsCount.Text = "បទចម្រៀងក្នុង Downloads: 0 បទ"
$lblDownloadsCount.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$lblDownloadsCount.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
$lblDownloadsCount.Location = New-Object System.Drawing.Point(420, 54)
$lblDownloadsCount.Size = New-Object System.Drawing.Size 380, 22
$grpInfo.Controls.Add($lblDownloadsCount)

$lblBackupsCount = New-Object System.Windows.Forms.Label
$lblBackupsCount.Text = "កញ្ចប់ Backup ដែលមាន: 0 កញ្ចប់"
$lblBackupsCount.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$lblBackupsCount.ForeColor = [System.Drawing.Color]::FromArgb(180, 190, 210)
$lblBackupsCount.Location = New-Object System.Drawing.Point(20, 80)
$lblBackupsCount.Size = New-Object System.Drawing.Size 380, 22
$grpInfo.Controls.Add($lblBackupsCount)

# Action Buttons
$btnCreateBackup = New-Object System.Windows.Forms.Button
$btnCreateBackup.Text = "📦 បង្កើតកញ្ចប់ Backup ថ្មី (Full Backup .ZIP)"
$btnCreateBackup.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnCreateBackup.Size = New-Object System.Drawing.Size 265, 42
$btnCreateBackup.Location = New-Object System.Drawing.Point(20, 145)
$btnCreateBackup.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$btnCreateBackup.ForeColor = [System.Drawing.Color]::White
$btnCreateBackup.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCreateBackup.FlatAppearance.BorderSize = 0
$btnCreateBackup.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlMain.Controls.Add($btnCreateBackup)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = "🔄 ស្ដារទិន្នន័យពី Backup ZIP"
$btnRestore.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnRestore.Size = New-Object System.Drawing.Size 220, 42
$btnRestore.Location = New-Object System.Drawing.Point(295, 145)
$btnRestore.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$btnRestore.ForeColor = [System.Drawing.Color]::White
$btnRestore.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRestore.FlatAppearance.BorderSize = 0
$btnRestore.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlMain.Controls.Add($btnRestore)

$btnCleanCache = New-Object System.Windows.Forms.Button
$btnCleanCache.Text = "🧹 សម្អាត Cache សន្សំទំហំ"
$btnCleanCache.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnCleanCache.Size = New-Object System.Drawing.Size 170, 42
$btnCleanCache.Location = New-Object System.Drawing.Point(525, 145)
$btnCleanCache.BackColor = [System.Drawing.Color]::FromArgb(45, 52, 70)
$btnCleanCache.ForeColor = [System.Drawing.Color]::White
$btnCleanCache.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCleanCache.FlatAppearance.BorderSize = 0
$btnCleanCache.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlMain.Controls.Add($btnCleanCache)

$btnOpenBackupDir = New-Object System.Windows.Forms.Button
$btnOpenBackupDir.Text = "📁 បើកថត Backups"
$btnOpenBackupDir.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnOpenBackupDir.Size = New-Object System.Drawing.Size 140, 42
$btnOpenBackupDir.Location = New-Object System.Drawing.Point(705, 145)
$btnOpenBackupDir.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 58)
$btnOpenBackupDir.ForeColor = [System.Drawing.Color]::White
$btnOpenBackupDir.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenBackupDir.FlatAppearance.BorderSize = 0
$btnOpenBackupDir.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlMain.Controls.Add($btnOpenBackupDir)

# Existing Backups List Box
$lblListTitle = New-Object System.Windows.Forms.Label
$lblListTitle.Text = "🗄️ បញ្ជីកញ្ចប់ Backup ដែលបានរក្សាទុក (Saved Backup Archives):"
$lblListTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9.2, [System.Drawing.FontStyle]::Bold)
$lblListTitle.ForeColor = [System.Drawing.Color]::FromArgb(200, 215, 235)
$lblListTitle.Location = New-Object System.Drawing.Point(20, 205)
$lblListTitle.Size = New-Object System.Drawing.Size 500, 24
$pnlMain.Controls.Add($lblListTitle)

$gridBackups = New-Object System.Windows.Forms.DataGridView
$gridBackups.Location = New-Object System.Drawing.Point(20, 232)
$gridBackups.Size = New-Object System.Drawing.Size 825, 260
$gridBackups.BackgroundColor = [System.Drawing.Color]::FromArgb(18, 21, 30)
$gridBackups.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$gridBackups.GridColor = [System.Drawing.Color]::FromArgb(30, 36, 50)
$gridBackups.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$gridBackups.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$gridBackups.MultiSelect = $false
$gridBackups.ReadOnly = $true
$gridBackups.AllowUserToAddRows = $false
$gridBackups.RowHeadersVisible = $false
$gridBackups.EnableHeadersVisualStyles = $false
$gridBackups.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(26, 32, 46)
$gridBackups.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
$gridBackups.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$gridBackups.ColumnHeadersHeight = 32
$gridBackups.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(18, 21, 30)
$gridBackups.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$gridBackups.RowTemplate.Height = 28
$pnlMain.Controls.Add($gridBackups)

$colBackupName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colBackupName.HeaderText = "ឈ្មោះកញ្ចប់ Backup (Archive File)"
$colBackupName.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
$gridBackups.Columns.Add($colBackupName) | Out-Null

$colBackupSize = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colBackupSize.HeaderText = "ទំហំ"
$colBackupSize.Width = 110
$gridBackups.Columns.Add($colBackupSize) | Out-Null

$colBackupDate = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colBackupDate.HeaderText = "កាលបរិច្ឆេទ"
$colBackupDate.Width = 160
$gridBackups.Columns.Add($colBackupDate) | Out-Null

$colBackupPath = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colBackupPath.HeaderText = "Path"
$colBackupPath.Visible = $false
$gridBackups.Columns.Add($colBackupPath) | Out-Null

# Bottom Status Label
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "ស្ថានភាព: រួចរាល់សម្រាប់ដំណើរការ (Ready)"
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
$lblStatus.Location = New-Object System.Drawing.Point(20, 502)
$lblStatus.Size = New-Object System.Drawing.Size 825, 24
$pnlMain.Controls.Add($lblStatus)

function Refresh-Dashboard {
    # Calculate Data Dir Size
    $bytes = 0
    if (Test-Path $dataDir) {
        $files = Get-ChildItem -Path $dataDir -Recurse -File -ErrorAction SilentlyContinue
        foreach ($f in $files) { $bytes += $f.Length }
    }
    $mb = "{0:N2} MB" -f ($bytes / 1MB)
    $lblDataSize.Text = "ទំហំសរុប: $mb"

    # Count Downloads
    $dlDir = Join-Path $dataDir "Downloads"
    $songCount = 0
    if (Test-Path $dlDir) {
        $songs = Get-ChildItem -Path $dlDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match "\.(mp3|wav|m4a|zip)$" }
        $songCount = $songs.Count
    }
    $lblDownloadsCount.Text = "បទចម្រៀងក្នុង Downloads: $songCount បទ"

    # Load Backups Grid
    $gridBackups.Rows.Clear()
    if (Test-Path $backupDir) {
        $zips = Get-ChildItem -Path $backupDir -Filter "*.zip" -File | Sort-Object LastWriteTime -Descending
        $lblBackupsCount.Text = "កញ្ចប់ Backup ដែលមាន: $($zips.Count) កញ្ចប់"
        foreach ($z in $zips) {
            $zSize = "{0:N2} MB" -f ($z.Length / 1MB)
            $zDate = $z.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            $gridBackups.Rows.Add($z.Name, $zSize, $zDate, $z.FullName) | Out-Null
        }
    }
}

$btnCreateBackup.Add_Click({
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $zipName = "Suno_Data_Backup_$ts.zip"
    $zipPath = Join-Path $backupDir $zipName
    
    $lblStatus.Text = "⏳ កំពុងបង្ហាប់ និងបង្កើតកញ្ចប់ Backup សូមរង់ចាំបន្តិច..."
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(251, 146, 60)
    $form.Update()

    try {
        [System.IO.Compression.ZipFile]::CreateFromDirectory($dataDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
        $lblStatus.Text = "✅ បានបង្កើត Backup `"$zipName`" ដោយជោគជ័យ!"
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
        Refresh-Dashboard
        [System.Windows.Forms.MessageBox]::Show("បានបង្កើតកញ្ចប់ Backup `"$zipName`" ដោយជោគជ័យ!`n`nទីតាំង: $zipPath", "ជោគជ័យ", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        $lblStatus.Text = "❌ មានបញ្ហាក្នុងការបង្កើត Backup: $($_.Exception.Message)"
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(239, 68, 68)
        [System.Windows.Forms.MessageBox]::Show("មិនអាចបង្កើត Backup បានទេ: $($_.Exception.Message)", "កំហុស", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$btnRestore.Add_Click({
    $targetZip = ""
    if ($gridBackups.SelectedRows.Count -gt 0) {
        $targetZip = $gridBackups.SelectedRows[0].Cells[3].Value
    }
    
    if (-not $targetZip -or -not (Test-Path $targetZip)) {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.InitialDirectory = $backupDir
        $ofd.Filter = "Backup ZIP (*.zip)|*.zip|All Files (*.*)|*.*"
        $ofd.Title = "ជ្រើសរើសឯកសារ Backup ZIP ដើម្បីស្ដារ"
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $targetZip = $ofd.FileName
        } else {
            return
        }
    }

    $fn = [System.IO.Path]::GetFileName($targetZip)
    $conf = [System.Windows.Forms.MessageBox]::Show("តើអ្នកពិតជាចង់ស្ដារទិន្នន័យពីកញ្ចប់ `"$fn`" មែនទេ?`n(ទិន្នន័យចាស់នឹងត្រូវជំនួសដោយទិន្នន័យក្នុង Backup នេះ)", "បញ្ជាក់ការស្ដារ", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($conf -eq [System.Windows.Forms.DialogResult]::Yes) {
        $lblStatus.Text = "⏳ កំពុងស្ដារទិន្នន័យ..."
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(251, 146, 60)
        $form.Update()

        try {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($targetZip, $dataDir)
            $lblStatus.Text = "✅ បានស្ដារទិន្នន័យដោយជោគជ័យ!"
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
            Refresh-Dashboard
            [System.Windows.Forms.MessageBox]::Show("បានស្ដារទិន្នន័យពី `"$fn`" ចូលក្នុង Data ដោយជោគជ័យ!", "ជោគជ័យ", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            $lblStatus.Text = "❌ មានបញ្ហាក្នុងការស្ដារ: $($_.Exception.Message)"
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(239, 68, 68)
            [System.Windows.Forms.MessageBox]::Show("មិនអាចស្ដារទិន្នន័យបានទេ: $($_.Exception.Message)", "កំហុស", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
})

$btnCleanCache.Add_Click({
    $lblStatus.Text = "⏳ កំពុងសម្អាត Browser Cache..."
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(251, 146, 60)
    $form.Update()

    $cacheDirs = @(
        (Join-Path $dataDir "ChromeUserData\Default\Cache"),
        (Join-Path $dataDir "ChromeUserData\Default\Code Cache"),
        (Join-Path $dataDir "UserData\EBWebView\Default\Cache"),
        (Join-Path $dataDir "ElectronUserData\Cache"),
        (Join-Path $dataDir "ElectronUserData\Code Cache")
    )

    $cleanedCount = 0
    foreach ($cd in $cacheDirs) {
        if (Test-Path $cd) {
            try {
                Remove-Item -Path "$cd\*" -Recurse -Force -ErrorAction SilentlyContinue
                $cleanedCount++
            } catch { }
        }
    }

    $lblStatus.Text = "✅ បានសម្អាត Browser Cache រួចរាល់!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
    Refresh-Dashboard
    [System.Windows.Forms.MessageBox]::Show("បានសម្អាត Cache ដើម្បីសន្សំទំហំ Disk ដោយជោគជ័យ!", "ជោគជ័យ", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
})

$btnOpenBackupDir.Add_Click({
    [System.Diagnostics.Process]::Start("explorer.exe", $backupDir)
})

$form.Add_Shown({
    Refresh-Dashboard
})

[System.Windows.Forms.Application]::Run($form)
