# ==============================================================================
# Suno AI Studio Pro - Music Prompt & Style Laboratory (SunoPromptStudio.ps1)
# Interactive Tag Lab & Prompt Builder for Suno v3.5 / v4
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# High DPI Awareness
$win32Dpi = @"
using System;
using System.Runtime.InteropServices;
public class SunoPromptDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
try {
    Add-Type -TypeDefinition $win32Dpi -ErrorAction SilentlyContinue
    [SunoPromptDpi]::SetProcessDPIAware() | Out-Null
} catch { }

$sunoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $sunoDir -or -not (Test-Path $sunoDir)) {
    $sunoDir = "C:\Users\PS\AppData\Local\Programs\Suno"
}
$queueFile = Join-Path $sunoDir "song_queue.json"

$form = New-Object System.Windows.Forms.Form
$form.Text = "🧪 Suno AI Studio Pro - Music Prompt & Style Laboratory"
$form.Size = New-Object System.Drawing.Size 1080, 780
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 23)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$form.MinimumSize = New-Object System.Drawing.Size 980, 680

# Header
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlHeader.Height = 85
$pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(23, 27, 38)
$pnlHeader.Padding = New-Object System.Windows.Forms.Padding(20, 14, 20, 10)
$form.Controls.Add($pnlHeader)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "🧪 Suno Music Prompt & Style Laboratory (v3.5 / v4)"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 13.5, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(168, 85, 247)
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(18, 12)
$pnlHeader.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "មន្ទីរពិសោធន៍បង្កើត Music Style Prompt តាមរចនាបថតន្ត្រី ឧបករណ៍ បរិយាកាស និងគុណភាពផលិត"
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(160, 175, 200)
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(20, 46)
$pnlHeader.Controls.Add($lblSub)

# Bottom Bar
$pnlBottom = New-Object System.Windows.Forms.Panel
$pnlBottom.Dock = [System.Windows.Forms.DockStyle]::Bottom
$pnlBottom.Height = 160
$pnlBottom.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 34)
$pnlBottom.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)
$form.Controls.Add($pnlBottom)

$lblPromptTitle = New-Object System.Windows.Forms.Label
$lblPromptTitle.Text = "✨ Music Style Prompt លទ្ធផល:"
$lblPromptTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblPromptTitle.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
$lblPromptTitle.Location = New-Object System.Drawing.Point(20, 8)
$lblPromptTitle.Size = New-Object System.Drawing.Size 250, 22
$pnlBottom.Controls.Add($lblPromptTitle)

$lblCharCount = New-Object System.Windows.Forms.Label
$lblCharCount.Text = "0 / 120 តួអក្សរ (ណែនាំ: < 120)"
$lblCharCount.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$lblCharCount.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
$lblCharCount.Location = New-Object System.Drawing.Point(820, 8)
$lblCharCount.Size = New-Object System.Drawing.Size 220, 22
$lblCharCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblCharCount.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$pnlBottom.Controls.Add($lblCharCount)

$txtResult = New-Object System.Windows.Forms.TextBox
$txtResult.Location = New-Object System.Drawing.Point(20, 32)
$txtResult.Size = New-Object System.Drawing.Size 1025, 60
$txtResult.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$txtResult.Multiline = $true
$txtResult.BackColor = [System.Drawing.Color]::FromArgb(12, 14, 20)
$txtResult.ForeColor = [System.Drawing.Color]::White
$txtResult.Font = New-Object System.Drawing.Font("Consolas", 10.5)
$txtResult.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pnlBottom.Controls.Add($txtResult)

# Bottom Actions
$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = "📋 ចម្លង Prompt (Copy)"
$btnCopy.Font = New-Object System.Drawing.Font("Segoe UI", 9.2, [System.Drawing.FontStyle]::Bold)
$btnCopy.Size = New-Object System.Drawing.Size 180, 38
$btnCopy.Location = New-Object System.Drawing.Point(20, 102)
$btnCopy.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$btnCopy.ForeColor = [System.Drawing.Color]::White
$btnCopy.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCopy.FlatAppearance.BorderSize = 0
$btnCopy.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlBottom.Controls.Add($btnCopy)

$btnPushSuno = New-Object System.Windows.Forms.Button
$btnPushSuno.Text = "⚡ បញ្ជូនទៅ Suno ភ្លាមៗ (Push to Queue)"
$btnPushSuno.Font = New-Object System.Drawing.Font("Segoe UI", 9.2, [System.Drawing.FontStyle]::Bold)
$btnPushSuno.Size = New-Object System.Drawing.Size 270, 38
$btnPushSuno.Location = New-Object System.Drawing.Point(215, 102)
$btnPushSuno.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$btnPushSuno.ForeColor = [System.Drawing.Color]::White
$btnPushSuno.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPushSuno.FlatAppearance.BorderSize = 0
$btnPushSuno.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlBottom.Controls.Add($btnPushSuno)

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = "🗑️ សម្អាត (Clear)"
$btnClear.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnClear.Size = New-Object System.Drawing.Size 120, 38
$btnClear.Location = New-Object System.Drawing.Point(500, 102)
$btnClear.BackColor = [System.Drawing.Color]::FromArgb(40, 48, 68)
$btnClear.ForeColor = [System.Drawing.Color]::White
$btnClear.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClear.FlatAppearance.BorderSize = 0
$btnClear.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlBottom.Controls.Add($btnClear)

# Main Scrollable Tags Panel
$pnlTags = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlTags.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlTags.AutoScroll = $true
$pnlTags.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 23)
$pnlTags.Padding = New-Object System.Windows.Forms.Padding(20, 12, 20, 15)
$form.Controls.Add($pnlTags)
$pnlTags.BringToFront()

function Add-TagToPrompt($tag) {
    $current = $txtResult.Text.Trim()
    if ($current -eq "") {
        $txtResult.Text = $tag
    } else {
        $tags = $current.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        if ($tags -contains $tag) {
            # Toggle off if already present
            $newTags = $tags | Where-Object { $_ -ne $tag }
            $txtResult.Text = [string]::Join(", ", $newTags)
        } else {
            $txtResult.Text = "$current, $tag"
        }
    }
}

function Add-TagSection($title, $icon, $color, $tags) {
    $pnlSec = New-Object System.Windows.Forms.Panel
    $pnlSec.Size = New-Object System.Drawing.Size 1020, 32
    $pnlSec.Margin = New-Object System.Windows.Forms.Padding(0, 12, 0, 4)
    
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "$icon $title"
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = $color
    $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point(4, 4)
    $pnlSec.Controls.Add($lbl)
    $pnlTags.Controls.Add($pnlSec)

    $flowTags = New-Object System.Windows.Forms.FlowLayoutPanel
    $flowTags.AutoSize = $true
    $flowTags.MaximumSize = New-Object System.Drawing.Size 1020, 0
    $flowTags.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)

    foreach ($t in $tags) {
        $btnTag = New-Object System.Windows.Forms.Button
        $btnTag.Text = $t
        $btnTag.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
        $btnTag.AutoSize = $true
        $btnTag.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 8)
        $btnTag.BackColor = [System.Drawing.Color]::FromArgb(28, 33, 46)
        $btnTag.ForeColor = [System.Drawing.Color]::FromArgb(220, 230, 245)
        $btnTag.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btnTag.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(45, 55, 75)
        $btnTag.Cursor = [System.Windows.Forms.Cursors]::Hand
        
        $currentTag = $t
        $btnTag.Add_Click({
            param($s, $e)
            Add-TagToPrompt $s.Text
        })
        $flowTags.Controls.Add($btnTag)
    }

    $pnlTags.Controls.Add($flowTags)
}

# 1. Genres & Cultures
Add-TagSection "រចនាបថចម្រៀង (Genres & Styles)" "🎵" ([System.Drawing.Color]::FromArgb(255, 94, 58)) @(
    "Khmer Traditional Romvong", "Khmer Saravan Groove", "Khmer Kantrum Folk Beats", "Khmer Pop 90s",
    "80s Synthwave Retro", "Cyberpunk Industrial EDM", "Lo-Fi Hip-Hop Chillhop", "Acoustic Indie Ballad",
    "Melodic Progressive House", "Modern K-Pop Anthem", "Heavy Rock Metalcore", "Smooth R&B Neo-Soul",
    "Epic Cinematic Orchestral", "Deep Reggae Dub", "Latin Bossa Nova Jazz", "Dark Club Techno"
)

# 2. Moods & Atmosphere
Add-TagSection "អារម្មណ៍ និងបរិយាកាស (Mood & Atmosphere)" "✨" ([System.Drawing.Color]::FromArgb(56, 189, 248)) @(
    "Euphoric & Energetic", "Melancholic Nostalgia", "Dark & Gritty Cyber", "Dreamy Ethereal Vibe",
    "Heartwarming Romance", "Uplifting Festival Energy", "Late Night Driving Melancholy", "Mysterious & Spooky",
    "Warm Summer Sunshine", "Sad Emotional Tearjerker", "Hypnotic Trance Groovy", "Triumphant Victory"
)

# 3. Vocals
Add-TagSection "លក្ខណៈសំឡេងច្រៀង (Vocal Characteristics)" "🎤" ([System.Drawing.Color]::FromArgb(168, 85, 247)) @(
    "Male Tenor Clear Vocals", "Female Airy Soprano", "Vocoder Robotic Effects", "Raspy Blues Soul Singer",
    "Whispering ASMR Vocals", "Harmonious Duet Singers", "Power Belting Chorus", "Autotune Modern Trap",
    "Deep Bass Baritone Voice", "Choir Background Vocals", "Instrumental (No Vocals)"
)

# 4. Instruments
Add-TagSection "ឧបករណ៍តន្ត្រី (Instrumentation)" "🎸" ([System.Drawing.Color]::FromArgb(52, 211, 153)) @(
    "Traditional Khmer Roneat Ek", "Traditional Khmer Tro Ou", "Overdriven Electric Guitars", "Analog 808 Sub-Bass",
    "Acoustic Grand Piano", "Live Acoustic Drums", "Lush String Orchestra", "Smooth Jazz Saxophone",
    "Plucked Acoustic Guitar", "Analog Moog Synthesizer", "Funky Slap Bass", "Arpeggiated Synth Plucks"
)

# 5. Production Nuances & Mastering
Add-TagSection "គុណភាពផលិត និងសំឡេង (Production & Master Nuances)" "🎛️" ([System.Drawing.Color]::FromArgb(251, 146, 60)) @(
    "Studio Master Quality", "Analog Tape Saturation", "Wide Stereo Panorama", "Vinyl Crackle Warmth",
    "Punchy Kicks & Crispy Snare", "Lush Cathedral Reverb", "128 BPM Dance Tempo", "85 BPM Chill Groove",
    "Build-Up & Epic Drop", "Lo-Fi Low Pass Filter", "Live Concert Hall Acoustics"
)

# Event Handlers
$txtResult.Add_TextChanged({
    $len = $txtResult.Text.Length
    $lblCharCount.Text = "$len / 120 តួអក្សរ"
    if ($len -gt 150) {
        $lblCharCount.ForeColor = [System.Drawing.Color]::FromArgb(239, 68, 68)
    } elseif ($len -gt 120) {
        $lblCharCount.ForeColor = [System.Drawing.Color]::FromArgb(251, 146, 60)
    } else {
        $lblCharCount.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
    }
})

$btnCopy.Add_Click({
    if ($txtResult.Text.Trim() -ne "") {
        [System.Windows.Forms.Clipboard]::SetText($txtResult.Text)
        [System.Windows.Forms.MessageBox]::Show("បានចម្លង Prompt ទៅក្នុង Clipboard រួចរាល់!`n`n$($txtResult.Text)", "ជោគជ័យ", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})

$btnClear.Add_Click({
    $txtResult.Text = ""
})

$btnPushSuno.Add_Click({
    $prompt = $txtResult.Text.Trim()
    if ($prompt -eq "") {
        [System.Windows.Forms.MessageBox]::Show("សូមជ្រើសរើស Style Tags ជាមុនសិន!", "បញ្ជាក់", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    try {
        $queue = @()
        if (Test-Path $queueFile) {
            $raw = Get-Content $queueFile -Raw -Encoding UTF8
            if ($raw.Trim() -ne "") {
                $queue = $raw | ConvertFrom-Json
            }
        }
        
        $item = [PSCustomObject]@{
            prompt = $prompt
            tags = $prompt
            title = "New Suno Track"
            lyrics = ""
            make_instrumental = $prompt.Contains("Instrumental")
            timestamp = [DateTime]::UtcNow.Ticks
        }
        $queue += $item
        
        $json = ConvertTo-Json -InputObject $queue -Compress
        Set-Content -Path $queueFile -Value $json -Encoding UTF8
        
        # Try posting to Port 48999 bridge if active
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("Content-Type", "application/json; charset=utf-8")
            $postData = ConvertTo-Json @{ action = "push_prompt"; prompt = $prompt }
            $wc.UploadString("http://127.0.0.1:48999/api/prompt", $postData) | Out-Null
        } catch { }

        [System.Windows.Forms.MessageBox]::Show("បានបញ្ជូន Music Style Prompt ចូលទៅក្នុងជួរ Suno ដោយជោគជ័យ!`n`nPrompt: $prompt", "ជោគជ័យ", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("មានបញ្ហាក្នុងការបញ្ជូនទៅ Suno: $($_.Exception.Message)", "កំហុស", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

[System.Windows.Forms.Application]::Run($form)
