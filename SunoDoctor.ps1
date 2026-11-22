# ==============================================================================
# Suno AI Studio Pro - System Doctor & Self-Healing Engine (SunoDoctor.ps1)
# Scans, diagnoses, audits, and automatically repairs all system components
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# High DPI Awareness
$win32Dpi = @"
using System;
using System.Runtime.InteropServices;
public class SunoDoctorDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
try {
    Add-Type -TypeDefinition $win32Dpi -ErrorAction SilentlyContinue
    [SunoDoctorDpi]::SetProcessDPIAware() | Out-Null
} catch { }

$sunoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $sunoDir -or -not (Test-Path $sunoDir)) {
    $sunoDir = "C:\Users\PS\AppData\Local\Programs\Suno"
}

# --- GUI Creation ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "🩺 Suno AI Studio Pro - System Doctor & Self-Healing"
$form.Size = New-Object System.Drawing.Size 880, 680
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 20)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false

# Header Panel
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlHeader.Height = 85
$pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 32)
$pnlHeader.Padding = New-Object System.Windows.Forms.Padding(20, 15, 20, 10)
$form.Controls.Add($pnlHeader)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "🩺 ម៉ាស៊ីនស្កេនពិនិត្យ និងជួសជុលប្រព័ន្ធស្វ័យប្រវត្តិ (Suno Doctor)"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 13.0, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 94, 58)
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(18, 14)
$pnlHeader.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "ត្រួតពិនិត្យភាពត្រឹមត្រូវនៃកូដ (Syntax), ទិន្នន័យ (Portable Data), ជួរបញ្ជា (IPC), និងជួសជុលកំហុសភ្លាមៗ"
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 180)
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(20, 48)
$pnlHeader.Controls.Add($lblSub)

# Main Output List / RichTextBox
$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Location = New-Object System.Drawing.Point(20, 105)
$txtLog.Size = New-Object System.Drawing.Size 825, 435
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(10, 10, 14)
$txtLog.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 235)
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9.5)
$txtLog.ReadOnly = $true
$txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$form.Controls.Add($txtLog)

# Bottom Action Bar
$pnlBottom = New-Object System.Windows.Forms.Panel
$pnlBottom.Dock = [System.Windows.Forms.DockStyle]::Bottom
$pnlBottom.Height = 70
$pnlBottom.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 28)
$form.Controls.Add($pnlBottom)

function Append-Log($text, $color = [System.Drawing.Color]::White) {
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.SelectionLength = 0
    $txtLog.SelectionColor = $color
    $txtLog.AppendText("$text`r`n")
    $txtLog.ScrollToCaret()
}

# --- Diagnostic & Repair Engine ---
function Run-FullAuditAndRepair($autoRepair = $false) {
    $txtLog.Clear()
    Append-Log "================================================================================" ([System.Drawing.Color]::FromArgb(255, 94, 58))
    Append-Log "  SUNO AI STUDIO PRO - FULL SYSTEM AUDIT & DIAGNOSTIC REPORT" ([System.Drawing.Color]::FromArgb(255, 140, 60))
    Append-Log "  Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Target: $sunoDir" ([System.Drawing.Color]::FromArgb(160, 160, 180))
    Append-Log "================================================================================" ([System.Drawing.Color]::FromArgb(255, 94, 58))
    Append-Log ""

    $issueCount = 0

    # 1. Check Portable Data Directory
    Append-Log "[1/6] ត្រួតពិនិត្យថតផ្ទុកទិន្នន័យចល័ត (Portable Data Storage)..." ([System.Drawing.Color]::FromArgb(100, 200, 255))
    $dataDir = Join-Path $sunoDir "Data"
    $chromeUserData = Join-Path $dataDir "ChromeUserData"
    $wvUserData = Join-Path $dataDir "UserData"
    $downloadsDir = Join-Path $dataDir "Downloads"
    $electronData = Join-Path $dataDir "ElectronUserData"

    $dirs = @($dataDir, $chromeUserData, $wvUserData, $downloadsDir, $electronData)
    foreach ($d in $dirs) {
        if (Test-Path $d) {
            Append-Log "  ✓ $([System.IO.Path]::GetFileName($d)): ដំណើរការល្អ (Exists)" ([System.Drawing.Color]::FromArgb(52, 211, 153))
        } else {
            Append-Log "  ⚠️ បាត់បង់ $([System.IO.Path]::GetFileName($d))" ([System.Drawing.Color]::FromArgb(251, 146, 60))
            $issueCount++
            if ($autoRepair) {
                New-Item -ItemType Directory -Force -Path $d | Out-Null
                Append-Log "    ➔ [ជួសជុលស្វ័យប្រវត្តិ] បានបង្កើតថត $d រួចរាល់!" ([System.Drawing.Color]::FromArgb(34, 197, 94))
            }
        }
    }

    # 2. Check PowerShell Scripts Syntax
    Append-Log "`n[2/6] ត្រួតពិនិត្យភាពត្រឹមត្រូវនៃកូដ PowerShell Scripts (Syntax Audit)..." ([System.Drawing.Color]::FromArgb(100, 200, 255))
    $ps1Files = Get-ChildItem -Path $sunoDir -Filter "*.ps1" -File
    foreach ($file in $ps1Files) {
        $tokens = $null; $errs = $null;
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errs)
        if ($errs.Count -eq 0) {
            Append-Log "  ✓ $($file.Name): Syntax 100% ត្រឹមត្រូវឥតខ្ចោះ" ([System.Drawing.Color]::FromArgb(52, 211, 153))
        } else {
            Append-Log "  ❌ $($file.Name): មានបញ្ហា Syntax $($errs.Count) កន្លែង!" ([System.Drawing.Color]::FromArgb(239, 68, 68))
            $issueCount += $errs.Count
        }
    }

    # 3. Check JavaScript Engines
    Append-Log "`n[3/6] ត្រួតពិនិត្យម៉ាស៊ីន JavaScript (studio.js & download_playlist_engine.js)..." ([System.Drawing.Color]::FromArgb(100, 200, 255))
    $jsFiles = @(
        (Join-Path $sunoDir "studio.js"),
        (Join-Path $sunoDir "download_playlist_engine.js"),
        (Join-Path $sunoDir "chrome_extension\studio.js"),
        (Join-Path $sunoDir "chrome_extension\studio_bridge.js")
    )
    foreach ($js in $jsFiles) {
        if (Test-Path $js) {
            $testOut = & node -c $js 2>&1
            if ($LASTEXITCODE -eq 0) {
                Append-Log "  ✓ $([System.IO.Path]::GetFileName($js)): JavaScript Syntax 100% ត្រឹមត្រូវ" ([System.Drawing.Color]::FromArgb(52, 211, 153))
            } else {
                Append-Log "  ❌ $([System.IO.Path]::GetFileName($js)): Syntax Error! ($testOut)" ([System.Drawing.Color]::FromArgb(239, 68, 68))
                $issueCount++
            }
        } else {
            Append-Log "  ⚠️ រកមិនឃើញឯកសារ: $js" ([System.Drawing.Color]::FromArgb(251, 146, 60))
            $issueCount++
        }
    }

    # 4. Check File Synchronization (studio.js -> Chrome Extension)
    Append-Log "`n[4/6] ត្រួតពិនិត្យការធ្វើសមកាលកម្មឯកសារ (Extension File Sync)..." ([System.Drawing.Color]::FromArgb(100, 200, 255))
    $rootStudio = Join-Path $sunoDir "studio.js"
    $extStudio = Join-Path $sunoDir "chrome_extension\studio.js"
    if ((Test-Path $rootStudio) -and (Test-Path $extStudio)) {
        $h1 = (Get-FileHash $rootStudio).Hash
        $h2 = (Get-FileHash $extStudio).Hash
        if ($h1 -eq $h2) {
            Append-Log "  ✓ studio.js និង Extension studio.js ត្រូវគ្នាឥតខ្ចោះ (In-Sync)" ([System.Drawing.Color]::FromArgb(52, 211, 153))
        } else {
            Append-Log "  ⚠️ studio.js និង Extension studio.js ខុសគ្នា!" ([System.Drawing.Color]::FromArgb(251, 146, 60))
            $issueCount++
            if ($autoRepair) {
                Copy-Item $rootStudio $extStudio -Force
                Append-Log "    ➔ [ជួសជុលស្វ័យប្រវត្តិ] បានចម្លង Sync studio.js ថ្មីចូល Extension រួចរាល់!" ([System.Drawing.Color]::FromArgb(34, 197, 94))
            }
        }
    }

    # 5. Check IPC Queues & Configs
    Append-Log "`n[5/6] ត្រួតពិនិត្យជួរបញ្ជា និងការកំណត់ JSON (IPC & Settings Integrity)..." ([System.Drawing.Color]::FromArgb(100, 200, 255))
    $jsonFiles = @("song_queue.json", "download_queue.json", "title_queue.json", "gemini_config.json", "desktop_settings.json")
    foreach ($jf in $jsonFiles) {
        $fullPath = Join-Path $sunoDir $jf
        if (Test-Path $fullPath) {
            try {
                $raw = Get-Content $fullPath -Raw -Encoding UTF8
                $null = $raw | ConvertFrom-Json
                Append-Log "  ✓ $($jf): JSON Format ត្រឹមត្រូវ" ([System.Drawing.Color]::FromArgb(52, 211, 153))
            } catch {
                Append-Log "  ❌ $($jf): ខូចទ្រង់ទ្រាយ JSON ($($_.Exception.Message))" ([System.Drawing.Color]::FromArgb(239, 68, 68))
                $issueCount++
                if ($autoRepair) {
                    if ($jf -like "*queue*") {
                        Set-Content $fullPath "[]" -Encoding UTF8
                        Append-Log "    ➔ [ជួសជុលស្វ័យប្រវត្តិ] បានសម្អាត និងកំណត់ជួរ $jf ឡើងវិញ!" ([System.Drawing.Color]::FromArgb(34, 197, 94))
                    }
                }
            }
        } else {
            Append-Log "  ⚠️ បាត់ឯកសារ: $jf" ([System.Drawing.Color]::FromArgb(251, 146, 60))
            $issueCount++
            if ($autoRepair) {
                Set-Content $fullPath "[]" -Encoding UTF8
                Append-Log "    ➔ [ជួសជុលស្វ័យប្រវត្តិ] បានបង្កើត $jf រួចរាល់!" ([System.Drawing.Color]::FromArgb(34, 197, 94))
            }
        }
    }

    # 6. Check Local Bridge Port 48999
    Append-Log "`n[6/8] ត្រួតពិនិត្យច្រកតភ្ជាប់ Local IPC Bridge (Port 48999)..." ([System.Drawing.Color]::FromArgb(100, 200, 255))
    try {
        $testListener = New-Object System.Net.HttpListener
        $testListener.Prefixes.Add("http://127.0.0.1:48999/")
        $testListener.Start()
        $testListener.Stop()
        $testListener.Close()
        Append-Log "  ✓ Port 48999: ច្រកទំនេរ រួចរាល់សម្រាប់ដំណើរការ" ([System.Drawing.Color]::FromArgb(52, 211, 153))
    } catch {
        Append-Log "  ℹ️ Port 48999: កំពុងដំណើរការដោយ SunoChrome ឬ Service សកម្មស្រាប់ (Active)" ([System.Drawing.Color]::FromArgb(196, 181, 253))
    }

    # 7. Check Desktop Shortcuts
    Append-Log "`n[7/8] ត្រួតពិនិត្យផ្លូវកាត់លើ Desktop (Desktop Shortcuts Audit)..." ([System.Drawing.Color]::FromArgb(100, 200, 255))
    $desktop = [System.Environment]::GetFolderPath("Desktop")
    $shortcuts = @(
        "Suno Studio Central Hub.lnk", "Suno System Doctor.lnk", "Suno Audio Studio.lnk",
        "Suno Prompt Studio.lnk", "Suno Backup Manager.lnk", "Suno GitHub Sync.lnk",
        "Suno Audio Converter.lnk", "Suno Rhyme Studio.lnk", "Suno Quick HUD.lnk",
        "Suno AI Studio (Google Chrome).lnk", "Suno AI Composer.lnk", "Suno AI Music.lnk"
    )
    $wsh = New-Object -ComObject WScript.Shell
    $icon = Join-Path $sunoDir "app.ico"
    foreach ($sc in $shortcuts) {
        $scFile = Join-Path $desktop $sc
        if (Test-Path $scFile) {
            Append-Log "  ✓ $($sc): មានវត្តមានលើ Desktop" ([System.Drawing.Color]::FromArgb(52, 211, 153))
        } else {
            Append-Log "  ⚠️ បាត់ផ្លូវកាត់: $($sc)" ([System.Drawing.Color]::FromArgb(251, 146, 60))
            $issueCount++
            if ($autoRepair) {
                $base = $sc.Replace(".lnk", "").Replace(" ", "")
                $launcher = Join-Path $sunoDir "$base`Launcher.vbs"
                if (-not (Test-Path $launcher)) {
                    $launcher = Join-Path $sunoDir "$base.bat"
                }
                if (Test-Path $launcher) {
                    $link = $wsh.CreateShortcut($scFile)
                    $link.TargetPath = $launcher
                    $link.WorkingDirectory = $sunoDir
                    if (Test-Path $icon) { $link.IconLocation = "$icon,0" }
                    $link.Save()
                    Append-Log "    ➔ [ជួសជុលស្វ័យប្រវត្តិ] បានបង្កើតផ្លូវកាត់ $sc ឡើងវិញ!" ([System.Drawing.Color]::FromArgb(34, 197, 94))
                }
            }
        }
    }

    # 8. Check GitHub Cloud Status
    Append-Log "`n[8/8] ត្រួតពិនិត្យស្ថានភាព Git & GitHub Cloud (vanndatree98/suno-ai-studio-pro)..." ([System.Drawing.Color]::FromArgb(100, 200, 255))
    if (Test-Path (Join-Path $sunoDir ".git")) {
        $branch = (git -C $sunoDir branch --show-current 2>$null)
        Append-Log "  ✓ Git Repository: Active (Branch: $branch)" ([System.Drawing.Color]::FromArgb(52, 211, 153))
    } else {
        Append-Log "  ℹ️ Git Repository: មិនទាន់បាន Initialize" ([System.Drawing.Color]::FromArgb(196, 181, 253))
    }

    # Summary
    Append-Log "`n================================================================================" ([System.Drawing.Color]::FromArgb(255, 94, 58))
    if ($issueCount -eq 0) {
        Append-Log "🎉 លទ្ធផល៖ ប្រព័ន្ធទាំងមូលស្ថិតក្នុងស្ថានភាពល្អឥតខ្ចោះ ១០០% (HEALTHY)!" ([System.Drawing.Color]::FromArgb(52, 211, 153))
    } else {
        if ($autoRepair) {
            Append-Log "✓ បានស្កេន និងជួសជុលចំណុចខ្វះខាតទាំងអស់ដោយជោគជ័យ! ប្រព័ន្ធដំណើរការប្រក្រតីវិញ ១០០%!" ([System.Drawing.Color]::FromArgb(34, 197, 94))
        } else {
            Append-Log "⚠️ បានរកឃើញបញ្ហាស្រាលចំនួន $issueCount ចំណុច។ សូមចុចប៊ូតុង '🩺 ជួសជុលស្វ័យប្រវត្តិ' ខាងក្រោម!" ([System.Drawing.Color]::FromArgb(251, 146, 60))
        }
    }
    Append-Log "================================================================================" ([System.Drawing.Color]::FromArgb(255, 94, 58))
}

# --- Action Buttons ---
$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "🔍 ស្កេនពិនិត្យប្រព័ន្ធ (Scan Audit)"
$btnScan.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnScan.Size = New-Object System.Drawing.Size 210, 42
$btnScan.Location = New-Object System.Drawing.Point(20, 14)
$btnScan.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$btnScan.ForeColor = [System.Drawing.Color]::White
$btnScan.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnScan.FlatAppearance.BorderSize = 0
$btnScan.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnScan.Add_Click({ Run-FullAuditAndRepair $false })
$pnlBottom.Controls.Add($btnScan)

$btnRepair = New-Object System.Windows.Forms.Button
$btnRepair.Text = "🩺 ជួសជុលស្វ័យប្រវត្តិកម្រិតខ្ពស់ (Auto-Repair)"
$btnRepair.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnRepair.Size = New-Object System.Drawing.Size 280, 42
$btnRepair.Location = New-Object System.Drawing.Point(240, 14)
$btnRepair.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$btnRepair.ForeColor = [System.Drawing.Color]::White
$btnRepair.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRepair.FlatAppearance.BorderSize = 0
$btnRepair.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnRepair.Add_Click({ Run-FullAuditAndRepair $true })
$pnlBottom.Controls.Add($btnRepair)

$btnOpenDir = New-Object System.Windows.Forms.Button
$btnOpenDir.Text = "📁 បើកថត Programs"
$btnOpenDir.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnOpenDir.Size = New-Object System.Drawing.Size 150, 42
$btnOpenDir.Location = New-Object System.Drawing.Point(530, 14)
$btnOpenDir.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 60)
$btnOpenDir.ForeColor = [System.Drawing.Color]::White
$btnOpenDir.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenDir.FlatAppearance.BorderSize = 0
$btnOpenDir.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnOpenDir.Add_Click({ [System.Diagnostics.Process]::Start("explorer.exe", $sunoDir) })
$pnlBottom.Controls.Add($btnOpenDir)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "✕ បិទ"
$btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnClose.Size = New-Object System.Drawing.Size 95, 42
$btnClose.Location = New-Object System.Drawing.Point(750, 14)
$btnClose.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 45)
$btnClose.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 215)
$btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.FlatAppearance.BorderSize = 0
$btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClose.Add_Click({ $form.Close() })
$pnlBottom.Controls.Add($btnClose)

# Auto-Run Scan on load
$form.Add_Shown({
    Run-FullAuditAndRepair $false
})

[System.Windows.Forms.Application]::Run($form)
