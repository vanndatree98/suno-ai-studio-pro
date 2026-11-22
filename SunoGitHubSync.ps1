# ==============================================================================
# Suno AI Studio Pro - GitHub Cloud Sync Manager (SunoGitHubSync.ps1)
# 1-Click Git Commit, Push & Cloud Synchronization Suite
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# High DPI Awareness
$win32Dpi = @"
using System;
using System.Runtime.InteropServices;
public class SunoGitSyncDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
try {
    Add-Type -TypeDefinition $win32Dpi -ErrorAction SilentlyContinue
    [SunoGitSyncDpi]::SetProcessDPIAware() | Out-Null
} catch { }

$sunoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $sunoDir -or -not (Test-Path $sunoDir)) {
    $sunoDir = "C:\Users\PS\AppData\Local\Programs\Suno"
}
$repoUrl = "https://github.com/vanndatree98/suno-ai-studio-pro"

$form = New-Object System.Windows.Forms.Form
$form.Text = "🐙 Suno AI Studio Pro - GitHub Cloud Sync"
$form.Size = New-Object System.Drawing.Size 880, 680
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
$lblTitle.Text = "🐙 Suno AI Studio Pro — GitHub Cloud Sync"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 13.0, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(18, 14)
$pnlHeader.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "ធ្វើសមកាលកម្មកូដ គម្រោង និងឧបករណ៍ទាំងអស់ទៅកាន់ GitHub Repository (vanndatree98/suno-ai-studio-pro)"
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(160, 175, 200)
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(20, 48)
$pnlHeader.Controls.Add($lblSub)

# Main Output Box
$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Location = New-Object System.Drawing.Point(20, 100)
$txtLog.Size = New-Object System.Drawing.Size 825, 390
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(10, 12, 16)
$txtLog.ForeColor = [System.Drawing.Color]::FromArgb(220, 225, 240)
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9.5)
$txtLog.ReadOnly = $true
$txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$form.Controls.Add($txtLog)

function Append-Log($text, $color = [System.Drawing.Color]::White) {
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.SelectionLength = 0
    $txtLog.SelectionColor = $color
    $txtLog.AppendText("$text`r`n")
    $txtLog.ScrollToCaret()
}

# Bottom Controls Panel
$pnlBottom = New-Object System.Windows.Forms.Panel
$pnlBottom.Dock = [System.Windows.Forms.DockStyle]::Bottom
$pnlBottom.Height = 135
$pnlBottom.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 34)
$pnlBottom.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)
$form.Controls.Add($pnlBottom)

$lblMsg = New-Object System.Windows.Forms.Label
$lblMsg.Text = "សារកំណត់ចំណាំ (Commit Message):"
$lblMsg.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$lblMsg.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 220)
$lblMsg.Location = New-Object System.Drawing.Point(20, 12)
$lblMsg.Size = New-Object System.Drawing.Size 260, 22
$pnlBottom.Controls.Add($lblMsg)

$txtCommitMsg = New-Object System.Windows.Forms.TextBox
$txtCommitMsg.Location = New-Object System.Drawing.Point(20, 36)
$txtCommitMsg.Size = New-Object System.Drawing.Size 825, 28
$txtCommitMsg.BackColor = [System.Drawing.Color]::FromArgb(28, 33, 46)
$txtCommitMsg.ForeColor = [System.Drawing.Color]::White
$txtCommitMsg.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtCommitMsg.Text = "Update Suno AI Studio Pro Suite - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$pnlBottom.Controls.Add($txtCommitMsg)

$btnPush = New-Object System.Windows.Forms.Button
$btnPush.Text = "🚀 បញ្ជូនទៅ GitHub (Push Update)"
$btnPush.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnPush.Size = New-Object System.Drawing.Size 260, 42
$btnPush.Location = New-Object System.Drawing.Point(20, 76)
$btnPush.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$btnPush.ForeColor = [System.Drawing.Color]::White
$btnPush.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPush.FlatAppearance.BorderSize = 0
$btnPush.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlBottom.Controls.Add($btnPush)

$btnPull = New-Object System.Windows.Forms.Button
$btnPull.Text = "📥 ទាញយកការអាប់ដេត (Pull)"
$btnPull.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnPull.Size = New-Object System.Drawing.Size 200, 42
$btnPull.Location = New-Object System.Drawing.Point(290, 76)
$btnPull.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$btnPull.ForeColor = [System.Drawing.Color]::White
$btnPull.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPull.FlatAppearance.BorderSize = 0
$btnPull.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlBottom.Controls.Add($btnPull)

$btnOpenWeb = New-Object System.Windows.Forms.Button
$btnOpenWeb.Text = "🌐 បើកមើលលើ GitHub Web"
$btnOpenWeb.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnOpenWeb.Size = New-Object System.Drawing.Size 210, 42
$btnOpenWeb.Location = New-Object System.Drawing.Point(500, 76)
$btnOpenWeb.BackColor = [System.Drawing.Color]::FromArgb(40, 48, 68)
$btnOpenWeb.ForeColor = [System.Drawing.Color]::White
$btnOpenWeb.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenWeb.FlatAppearance.BorderSize = 0
$btnOpenWeb.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlBottom.Controls.Add($btnOpenWeb)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "✕ បិទ"
$btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnClose.Size = New-Object System.Drawing.Size 115, 42
$btnClose.Location = New-Object System.Drawing.Point(730, 76)
$btnClose.BackColor = [System.Drawing.Color]::FromArgb(35, 40, 52)
$btnClose.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 215)
$btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.FlatAppearance.BorderSize = 0
$btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClose.Add_Click({ $form.Close() })
$pnlBottom.Controls.Add($btnClose)

function Refresh-GitStatus {
    $txtLog.Clear()
    Append-Log "================================================================================" ([System.Drawing.Color]::FromArgb(56, 189, 248))
    Append-Log "  🐙 GITHUB CLOUD STATUS: vanndatree98/suno-ai-studio-pro" ([System.Drawing.Color]::FromArgb(168, 85, 247))
    Append-Log "  Location: $sunoDir" ([System.Drawing.Color]::FromArgb(160, 175, 200))
    Append-Log "================================================================================" ([System.Drawing.Color]::FromArgb(56, 189, 248))
    Append-Log ""

    Set-Location $sunoDir
    $status = git status --short
    if ($status) {
        Append-Log "📝 ឯកសារដែលមានការផ្លាស់ប្តូរ (Pending Changes):" ([System.Drawing.Color]::FromArgb(251, 146, 60))
        foreach ($line in $status) {
            Append-Log "  $line" ([System.Drawing.Color]::FromArgb(240, 240, 250))
        }
        Append-Log "`n➔ សូមចុចប៊ូតុង '🚀 បញ្ជូនទៅ GitHub' ដើម្បីធ្វើសមកាលកម្មឡើង Cloud!" ([System.Drawing.Color]::FromArgb(52, 211, 153))
    } else {
        Append-Log "✅ ប្រព័ន្ធទាំងមូលស្ថិតក្នុងសភាព In-Sync ឥតខ្ចោះជាមួយ GitHub (Working Tree Clean)!" ([System.Drawing.Color]::FromArgb(34, 197, 94))
    }

    $lastCommit = git log -1 --pretty=format:"%h - %an, %ar : %s" 2>$null
    if ($lastCommit) {
        Append-Log "`n📌 Last Commit: $lastCommit" ([System.Drawing.Color]::FromArgb(180, 195, 220))
    }
}

$btnPush.Add_Click({
    Set-Location $sunoDir
    $msg = $txtCommitMsg.Text.Trim()
    if ($msg -eq "") { $msg = "Update Suno AI Studio Pro Suite - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }

    Append-Log "`n⏳ កំពុងដំណើរការ Stage & Commit..." ([System.Drawing.Color]::FromArgb(251, 146, 60))
    $form.Update()

    git add .
    $commitOut = git commit -m "$msg" 2>&1
    Append-Log "$commitOut" ([System.Drawing.Color]::FromArgb(200, 210, 230))

    Append-Log "⏳ កំពុង Push ឡើង GitHub..." ([System.Drawing.Color]::FromArgb(251, 146, 60))
    $form.Update()

    $pushOut = git push origin main 2>&1
    Append-Log "$pushOut" ([System.Drawing.Color]::FromArgb(52, 211, 153))

    Append-Log "`n🎉 បានបញ្ចប់ការធ្វើសមកាលកម្មឡើង GitHub ដោយជោគជ័យ!" ([System.Drawing.Color]::FromArgb(34, 197, 94))
    [System.Windows.Forms.MessageBox]::Show("បានបញ្ជូនកូដទាំងអស់ឡើងទៅកាន់ GitHub ដោយជោគជ័យ!`n`nRepository: $repoUrl", "ជោគជ័យ", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Refresh-GitStatus
})

$btnPull.Add_Click({
    Set-Location $sunoDir
    Append-Log "`n⏳ កំពុងទាញយកការផ្លាស់ប្តូរពី GitHub (git pull)..." ([System.Drawing.Color]::FromArgb(56, 189, 248))
    $form.Update()

    $pullOut = git pull origin main 2>&1
    Append-Log "$pullOut" ([System.Drawing.Color]::FromArgb(200, 210, 230))
    Refresh-GitStatus
})

$btnOpenWeb.Add_Click({
    [System.Diagnostics.Process]::Start($repoUrl)
})

$form.Add_Shown({
    Refresh-GitStatus
})

[System.Windows.Forms.Application]::Run($form)
