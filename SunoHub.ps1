# ==============================================================================
# Suno AI Studio Pro - Central Master Hub (SunoHub.ps1)
# Central Launcher, Control Center & System Dashboard
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# High DPI Awareness
$win32Dpi = @"
using System;
using System.Runtime.InteropServices;
public class SunoHubDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
try {
    Add-Type -TypeDefinition $win32Dpi -ErrorAction SilentlyContinue
    [SunoHubDpi]::SetProcessDPIAware() | Out-Null
} catch { }

$sunoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $sunoDir -or -not (Test-Path $sunoDir)) {
    $sunoDir = "C:\Users\PS\AppData\Local\Programs\Suno"
}
$dataDir = Join-Path $sunoDir "Data"
$downloadsDir = Join-Path $dataDir "Downloads"
if (-not (Test-Path $downloadsDir)) {
    New-Item -ItemType Directory -Force -Path $downloadsDir | Out-Null
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "🌟 Suno AI Studio Pro - Central Master Hub"
$form.Size = New-Object System.Drawing.Size 1100, 820
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = [System.Drawing.Color]::FromArgb(13, 17, 23)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$form.MinimumSize = New-Object System.Drawing.Size 980, 720

# --- Top Header Panel ---
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlHeader.Height = 110
$pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(22, 27, 34)
$pnlHeader.Padding = New-Object System.Windows.Forms.Padding(25, 14, 25, 10)
$form.Controls.Add($pnlHeader)

$lblBrand = New-Object System.Windows.Forms.Label
$lblBrand.Text = "🌟 SUNO AI STUDIO PRO — CENTRAL MASTER HUB"
$lblBrand.Font = New-Object System.Drawing.Font("Segoe UI", 14.0, [System.Drawing.FontStyle]::Bold)
$lblBrand.ForeColor = [System.Drawing.Color]::FromArgb(255, 94, 58)
$lblBrand.AutoSize = $true
$lblBrand.Location = New-Object System.Drawing.Point(22, 12)
$pnlHeader.Controls.Add($lblBrand)

$lblDesc = New-Object System.Windows.Forms.Label
$lblDesc.Text = "មជ្ឈមណ្ឌលគ្រប់គ្រង បើកដំណើរការកម្មវិធី និងត្រួតពិនិត្យប្រព័ន្ធ Suno AI ទាំងអស់ក្នុងកន្លែងតែមួយ"
$lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 9.2)
$lblDesc.ForeColor = [System.Drawing.Color]::FromArgb(160, 175, 200)
$lblDesc.AutoSize = $true
$lblDesc.Location = New-Object System.Drawing.Point(24, 46)
$pnlHeader.Controls.Add($lblDesc)

# Status Badges Bar
$pnlBadges = New-Object System.Windows.Forms.Panel
$pnlBadges.Location = New-Object System.Drawing.Point(24, 76)
$pnlBadges.Size = New-Object System.Drawing.Size 1030, 26
$pnlBadges.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$pnlHeader.Controls.Add($pnlBadges)

$lblStatusData = New-Object System.Windows.Forms.Label
$lblStatusData.Text = "📁 ទិន្នន័យរួម: Programs\Suno\Data"
$lblStatusData.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblStatusData.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
$lblStatusData.AutoSize = $true
$lblStatusData.Location = New-Object System.Drawing.Point(0, 3)
$pnlBadges.Controls.Add($lblStatusData)

$lblStatusTracks = New-Object System.Windows.Forms.Label
$lblStatusTracks.Text = "🎵 ចម្រៀងក្នុងម៉ាស៊ីន: 0 បទ"
$lblStatusTracks.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblStatusTracks.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
$lblStatusTracks.AutoSize = $true
$lblStatusTracks.Location = New-Object System.Drawing.Point(260, 3)
$pnlBadges.Controls.Add($lblStatusTracks)

$lblStatusHealth = New-Object System.Windows.Forms.Label
$lblStatusHealth.Text = "🟢 ស្ថានភាពប្រព័ន្ធ: ១០០% ល្អឥតខ្ចោះ (Healthy)"
$lblStatusHealth.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$lblStatusHealth.ForeColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
$lblStatusHealth.AutoSize = $true
$lblStatusHealth.Location = New-Object System.Drawing.Point(480, 3)
$pnlBadges.Controls.Add($lblStatusHealth)

# --- Bottom Footer Panel ---
$pnlFooter = New-Object System.Windows.Forms.Panel
$pnlFooter.Dock = [System.Windows.Forms.DockStyle]::Bottom
$pnlFooter.Height = 60
$pnlFooter.BackColor = [System.Drawing.Color]::FromArgb(18, 22, 28)
$pnlFooter.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)
$form.Controls.Add($pnlFooter)

$lblFooterNote = New-Object System.Windows.Forms.Label
$lblFooterNote.Text = "Suno AI Studio Suite v3.5 Pro • 100% Unified Portable Architecture"
$lblFooterNote.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$lblFooterNote.ForeColor = [System.Drawing.Color]::FromArgb(120, 135, 160)
$lblFooterNote.AutoSize = $true
$lblFooterNote.Location = New-Object System.Drawing.Point(20, 18)
$pnlFooter.Controls.Add($lblFooterNote)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "🔄 ផ្ទុកស្ថានភាពឡើងវិញ"
$btnRefresh.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnRefresh.Size = New-Object System.Drawing.Size 170, 34
$btnRefresh.Location = New-Object System.Drawing.Point(760, 12)
$btnRefresh.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 58)
$btnRefresh.ForeColor = [System.Drawing.Color]::White
$btnRefresh.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRefresh.FlatAppearance.BorderSize = 0
$btnRefresh.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlFooter.Controls.Add($btnRefresh)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "✕ បិទ"
$btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnClose.Size = New-Object System.Drawing.Size 95, 34
$btnClose.Location = New-Object System.Drawing.Point(945, 12)
$btnClose.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnClose.BackColor = [System.Drawing.Color]::FromArgb(30, 34, 44)
$btnClose.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 215)
$btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.FlatAppearance.BorderSize = 0
$btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClose.Add_Click({ $form.Close() })
$pnlFooter.Controls.Add($btnClose)

# --- Main Scrollable Flow Panel ---
$flowMain = New-Object System.Windows.Forms.FlowLayoutPanel
$flowMain.Dock = [System.Windows.Forms.DockStyle]::Fill
$flowMain.AutoScroll = $true
$flowMain.BackColor = [System.Drawing.Color]::FromArgb(13, 17, 23)
$flowMain.Padding = New-Object System.Windows.Forms.Padding(25, 15, 25, 20)
$form.Controls.Add($flowMain)
$flowMain.BringToFront()

# Helper function to launch scripts or apps
function Launch-Target($relPath, $isDir = $false) {
    $full = Join-Path $sunoDir $relPath
    if ($isDir) {
        if (-not (Test-Path $full)) { New-Item -ItemType Directory -Force -Path $full | Out-Null }
        [System.Diagnostics.Process]::Start("explorer.exe", $full)
        return
    }
    
    if (-not (Test-Path $full)) {
        [System.Windows.Forms.MessageBox]::Show("រកមិនឃើញឯកសារ: $full", "កំហុស", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    $ext = [System.IO.Path]::GetExtension($full).ToLower()
    if ($ext -eq ".bat" -or $ext -eq ".cmd") {
        Start-Process "cmd.exe" "/c `"$full`"" -WindowStyle Hidden
    } elseif ($ext -eq ".vbs") {
        Start-Process "wscript.exe" "`"$full`""
    } elseif ($ext -eq ".ps1") {
        Start-Process "powershell.exe" "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$full`""
    } elseif ($ext -eq ".exe") {
        Start-Process $full
    } else {
        [System.Diagnostics.Process]::Start($full)
    }
}

# Helper to create Category Header
function Add-CategoryHeader($text, $icon, $color) {
    $pnlCat = New-Object System.Windows.Forms.Panel
    $pnlCat.Size = New-Object System.Drawing.Size 1020, 42
    $pnlCat.Margin = New-Object System.Windows.Forms.Padding(0, 15, 0, 8)
    
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "$icon $text"
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 11.5, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = $color
    $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point(4, 8)
    $pnlCat.Controls.Add($lbl)
    
    $flowMain.Controls.Add($pnlCat)
}

# Helper to create App Card Tile
function Add-AppCard($title, $desc, $badge, $badgeColor, $btnText, $btnColor, $targetRelPath, $isDir = $false) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Size = New-Object System.Drawing.Size 326, 175
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 14, 14)
    $card.BackColor = [System.Drawing.Color]::FromArgb(22, 27, 34)
    $card.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    
    # Title
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = $title
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10.2, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Location = New-Object System.Drawing.Point(12, 10)
    $lblTitle.Size = New-Object System.Drawing.Size 215, 24
    $card.Controls.Add($lblTitle)
    
    # Badge (e.g. Recommended, Pro, Native)
    if ($badge) {
        $lblBadge = New-Object System.Windows.Forms.Label
        $lblBadge.Text = $badge
        $lblBadge.Font = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
        $lblBadge.ForeColor = $badgeColor
        $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 54)
        $lblBadge.Location = New-Object System.Drawing.Point(232, 11)
        $lblBadge.Size = New-Object System.Drawing.Size 80, 20
        $lblBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $card.Controls.Add($lblBadge)
    }

    # Description
    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = $desc
    $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
    $lblDesc.ForeColor = [System.Drawing.Color]::FromArgb(150, 165, 190)
    $lblDesc.Location = New-Object System.Drawing.Point(12, 38)
    $lblDesc.Size = New-Object System.Drawing.Size 300, 75
    $card.Controls.Add($lblDesc)

    # Launch Button
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $btnText
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
    $btn.Size = New-Object System.Drawing.Size 302, 36
    $btn.Location = New-Object System.Drawing.Point(11, 124)
    $btn.BackColor = $btnColor
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Add_Click({
        Launch-Target $targetRelPath $isDir
    })
    $card.Controls.Add($btn)

    $flowMain.Controls.Add($card)
}

# --- SECTION 1: AI GENERATION ENGINES ---
Add-CategoryHeader "ម៉ាស៊ីនបង្កើតចម្រៀង (AI Generation Engines)" "🚀" ([System.Drawing.Color]::FromArgb(255, 94, 58))

Add-AppCard `
    "🌐 Suno Chrome Studio" `
    "ដំណើរការតាម Chrome Engine & Bridge Extension រំលង hCaptcha / Cloudflare យ៉ាងរលូន ១០០% ដោយគ្មានបញ្ហារាំងស្ទះ។" `
    "RECOMMENDED" ([System.Drawing.Color]::FromArgb(34, 197, 94)) `
    "🚀 បើក Suno Chrome Engine" ([System.Drawing.Color]::FromArgb(37, 99, 235)) `
    "SunoChrome.bat"

Add-AppCard `
    "⚡ Suno Electron Native" `
    "កម្មវិធី Desktop ដើម (High Performance) បង្កប់ដោយ Suno Studio Topbar, ជួរបញ្ជា Queue IPC, និងស្ទីលទំនើប។" `
    "NATIVE DESKTOP" ([System.Drawing.Color]::FromArgb(56, 189, 248)) `
    "⚡ បើក Suno Electron App" ([System.Drawing.Color]::FromArgb(124, 58, 237)) `
    "Suno.bat"

Add-AppCard `
    "🖥️ Suno WebView2 Studio" `
    "ម៉ាស៊ីន Windows WebView2 បង្កប់ក្នុង WinForms ជាមួយរបារឧបករណ៍ចម្រុះ និងប្រព័ន្ធទាញយកចម្រៀងស្វ័យប្រវត្តិ។" `
    "LEGACY" ([System.Drawing.Color]::FromArgb(156, 163, 175)) `
    "🖥️ បើក WebView2 Studio" ([System.Drawing.Color]::FromArgb(55, 65, 81)) `
    "SunoApp.ps1"

# --- SECTION 2: AI CREATIVE & AUTOMATION SUITE ---
Add-CategoryHeader "ឧបករណ៍ជំនួយការនិពន្ធ AI (AI Creative Suite)" "🎨" ([System.Drawing.Color]::FromArgb(56, 189, 248))

Add-AppCard `
    "🎨 Suno Theme Selector" `
    "ជ្រើសរើសស្ទីលពណ៌ Themes (Dark Studio, Cyberpunk, Midnight Neon, Sunset, Forest) សម្រាប់ផ្ទាំងបញ្ជា។" `
    "CUSTOM UI" ([System.Drawing.Color]::FromArgb(251, 146, 60)) `
    "🎨 បើក Theme Selector" ([System.Drawing.Color]::FromArgb(234, 88, 12)) `
    "SunoThemeSelector.bat"

Add-AppCard `
    "✍️ Suno Lyric Composer" `
    "ស្ទូឌីយោនិពន្ធទំនុកច្រៀង បង្កើត Prompt តាមរចនាបថ និងបញ្ជូន Auto-queue ទៅក្នុង Suno ដោយស្វ័យប្រវត្តិ។" `
    "AUTO COMPOSER" ([System.Drawing.Color]::FromArgb(168, 85, 247)) `
    "✍️ បើកស្ទូឌីយោនិពន្ធ" ([System.Drawing.Color]::FromArgb(147, 51, 234)) `
    "SunoComposer.bat"

Add-AppCard `
    "🤖 Gemini AI Title Generator" `
    "បង្កើតចំណងជើងបទចម្រៀងពីរោះៗ ភាសាខ្មែរ/អន្តរជាតិ រៀបចំជា Playlist ដោយប្រើប្រាស់ Gemini AI ទំនើប។" `
    "GEMINI FLASH" ([System.Drawing.Color]::FromArgb(34, 197, 94)) `
    "🤖 បង្កើតចំណងជើង AI" ([System.Drawing.Color]::FromArgb(16, 185, 129)) `
    "GeminiTitle.bat"

Add-AppCard `
    "🧪 Suno Prompt Laboratory" `
    "មន្ទីរពិសោធន៍បង្កើត Music Style Prompt តាមរចនាបថតន្ត្រី ឧបករណ៍ បរិយាកាស និងគុណភាពផលិត។" `
    "STYLE LAB" ([System.Drawing.Color]::FromArgb(168, 85, 247)) `
    "🧪 បើក Prompt Studio" ([System.Drawing.Color]::FromArgb(147, 51, 234)) `
    "SunoPromptStudio.bat"

# --- SECTION 3: MEDIA & PLAYLIST MANAGEMENT ---
Add-CategoryHeader "គ្រប់គ្រង និងទាញយកចម្រៀង (Media & Downloads)" "🎵" ([System.Drawing.Color]::FromArgb(52, 211, 153))

Add-AppCard `
    "🎵 Suno Audio Studio" `
    "ស្ទូឌីយោចាក់ស្តាប់បទចម្រៀង កែប្រែព័ត៌មានបទ (Title/Artist) និងរៀបចំបញ្ជីបទចម្រៀង Suno របស់អ្នក។" `
    "NEW COMPANION" ([System.Drawing.Color]::FromArgb(34, 197, 94)) `
    "🎵 បើក Audio Studio" ([System.Drawing.Color]::FromArgb(13, 148, 136)) `
    "SunoAudioStudio.bat"

Add-AppCard `
    "📥 Suno WAV Downloader" `
    "ទាញយកឯកសារចម្រៀង WAV/MP3 គុណភាពខ្ពស់បំផុតពី Suno ដោយផ្ទាល់ ដោយមិនបាត់បង់គុណភាពសំឡេង។" `
    "HI-RES AUDIO" ([System.Drawing.Color]::FromArgb(56, 189, 248)) `
    "📥 ទាញយកចម្រៀង WAV" ([System.Drawing.Color]::FromArgb(2, 132, 199)) `
    "SunoDownloader.bat"

Add-AppCard `
    "📦 Suno Playlist Downloader" `
    "ទាញយកចម្រៀងទាំងមូលពី Playlist ខ្ចប់ជាកញ្ចប់ ZIP និងទាញយកដោយស្វ័យប្រវត្តិតាមជួរ Queue។" `
    "BATCH ZIP" ([System.Drawing.Color]::FromArgb(251, 146, 60)) `
    "📦 បើក Playlist Downloader" ([System.Drawing.Color]::FromArgb(217, 119, 6)) `
    "SunoPlaylistDownloader.bat"

# --- SECTION 4: SYSTEM UTILITIES & DATA ---
Add-CategoryHeader "ឧបករណ៍ថែទាំ និងថតផ្ទុកទិន្នន័យ (System Utilities)" "🛠️" ([System.Drawing.Color]::FromArgb(168, 85, 247))

Add-AppCard `
    "🩺 Suno System Doctor" `
    "ស្កេនពិនិត្យប្រព័ន្ធ រកមើលចំណុចខ្វះខាត និងជួសជុលស្វ័យប្រវត្តិកម្រិតខ្ពស់ (Self-Healing Engine)។" `
    "DIAGNOSTIC" ([System.Drawing.Color]::FromArgb(239, 68, 68)) `
    "🩺 ស្កេន & ជួសជុលប្រព័ន្ធ" ([System.Drawing.Color]::FromArgb(220, 38, 38)) `
    "SunoDoctor.bat"

Add-AppCard `
    "📦 Suno Backup Manager" `
    "បង្កើតកញ្ចប់ Backup និងស្ដារទិន្នន័យចល័ត Data ទាំងមូល (Sessions, Logins, Downloads) ដោយចុចតែ ១ ដង។" `
    "PORTABLE BACKUP" ([System.Drawing.Color]::FromArgb(56, 189, 248)) `
    "📦 បើក Backup Manager" ([System.Drawing.Color]::FromArgb(2, 132, 199)) `
    "SunoBackupManager.bat"

Add-AppCard `
    "🐙 Suno GitHub Cloud Sync" `
    "ធ្វើសមកាលកម្មកូដ គម្រោង និងឧបករណ៍ទាំងអស់ឡើង GitHub Repository (vanndatree98/suno-ai-studio-pro)។" `
    "GITHUB CLOUD" ([System.Drawing.Color]::FromArgb(168, 85, 247)) `
    "🐙 បើក GitHub Sync" ([System.Drawing.Color]::FromArgb(147, 51, 234)) `
    "SunoGitHubSync.bat"

Add-AppCard `
    "📂 ថតទិន្នន័យ Downloads" `
    "បើកមើលឯកសារចម្រៀងដែលបានទាញយករួចទាំងអស់ក្នុងថត Data\Downloads នៃម៉ាស៊ីន Suno។" `
    "LOCAL DATA" ([System.Drawing.Color]::FromArgb(52, 211, 153)) `
    "📂 បើកថត Downloads" ([System.Drawing.Color]::FromArgb(5, 150, 105)) `
    "Data\Downloads" $true

Add-AppCard `
    "📁 ថតកម្មវិធីមេ Programs" `
    "បើកមើលថត Programs\Suno ដែលផ្ទុកកូដ ប្រព័ន្ធទិន្នន័យចល័ត (Portable) និងម៉ាស៊ីនទាំងមូល។" `
    "ROOT DIR" ([System.Drawing.Color]::FromArgb(156, 163, 175)) `
    "📁 បើកថត Programs\Suno" ([System.Drawing.Color]::FromArgb(75, 85, 99)) `
    "" $true

# Update Stats on load & refresh
function Update-DashboardStats {
    if (Test-Path $downloadsDir) {
        $audioFiles = Get-ChildItem -Path $downloadsDir -File | Where-Object { $_.Extension -match "\.(mp3|wav|m4a|aac)$" }
        $lblStatusTracks.Text = "🎵 ចម្រៀងក្នុងម៉ាស៊ីន: $($audioFiles.Count) បទ"
    }
}

$btnRefresh.Add_Click({ Update-DashboardStats })
$form.Add_Shown({ Update-DashboardStats })

[System.Windows.Forms.Application]::Run($form)
