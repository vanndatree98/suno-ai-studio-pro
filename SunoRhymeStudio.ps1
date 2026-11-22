# ==============================================================================
# Suno AI Studio Pro - Lyrics & Rhyme Structure Laboratory (SunoRhymeStudio.ps1)
# Architect perfect Suno v3.5/v4 lyrics with metatags, rhythm & syllable balance
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# High DPI Awareness
$win32Dpi = @"
using System;
using System.Runtime.InteropServices;
public class SunoRhymeDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
try {
    Add-Type -TypeDefinition $win32Dpi -ErrorAction SilentlyContinue
    [SunoRhymeDpi]::SetProcessDPIAware() | Out-Null
} catch { }

$sunoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $sunoDir -or -not (Test-Path $sunoDir)) {
    $sunoDir = "C:\Users\PS\AppData\Local\Programs\Suno"
}
$queueFile = Join-Path $sunoDir "song_queue.json"

$form = New-Object System.Windows.Forms.Form
$form.Text = "✍️ Suno AI Studio Pro - Lyrics & Rhyme Structure Studio"
$form.Size = New-Object System.Drawing.Size 1060, 780
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 23)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$form.MinimumSize = New-Object System.Drawing.Size 960, 680

# Header
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlHeader.Height = 85
$pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(23, 27, 38)
$pnlHeader.Padding = New-Object System.Windows.Forms.Padding(20, 14, 20, 10)
$form.Controls.Add($pnlHeader)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "✍️ Suno Lyrics & Song Structure Studio (v3.5 / v4)"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 13.5, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(168, 85, 247)
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(18, 12)
$pnlHeader.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "រៀបចំរចនាសម្ព័ន្ធទំនុកច្រៀង បញ្ចូល Suno Metatags ([Chorus], [Drop], [Bridge]) និងផ្ទៀងផ្ទាត់ចង្វាក់ពាក្យជួន"
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(160, 175, 200)
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(20, 46)
$pnlHeader.Controls.Add($lblSub)

# Metatag Quick Buttons Bar
$pnlTags = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlTags.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlTags.Height = 52
$pnlTags.BackColor = [System.Drawing.Color]::FromArgb(18, 22, 32)
$pnlTags.Padding = New-Object System.Windows.Forms.Padding(18, 10, 18, 5)
$form.Controls.Add($pnlTags)

$tags = @(
    "[Intro]", "[Verse 1]", "[Pre-Chorus]", "[Chorus]",
    "[Verse 2]", "[Guitar Solo]", "[Bridge]", "[Drop]",
    "[Outro]", "[Fade Out]", "[Whispering]", "[Duet]"
)

foreach ($t in $tags) {
    $btnT = New-Object System.Windows.Forms.Button
    $btnT.Text = $t
    $btnT.Font = New-Object System.Drawing.Font("Segoe UI", 8.8, [System.Drawing.FontStyle]::Bold)
    $btnT.AutoSize = $true
    $btnT.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 4)
    $btnT.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 58)
    $btnT.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
    $btnT.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnT.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(50, 65, 90)
    $btnT.Cursor = [System.Windows.Forms.Cursors]::Hand
    $tagVal = $t
    $btnT.Add_Click({
        param($s, $e)
        Insert-Metatag $s.Text
    })
    $pnlTags.Controls.Add($btnT)
}

# Main Split Container
$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = [System.Windows.Forms.DockStyle]::Fill
$split.SplitterDistance = 700
$split.BackColor = [System.Drawing.Color]::FromArgb(30, 36, 50)
$form.Controls.Add($split)
$split.BringToFront()

# Left: Lyrics Text Area
$pnlLeft = $split.Panel1
$pnlLeft.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 23)
$pnlLeft.Padding = New-Object System.Windows.Forms.Padding(18, 12, 10, 12)

$lblEditor = New-Object System.Windows.Forms.Label
$lblEditor.Text = "📝 ទំនុកច្រៀង និងកូដរចនាសម្ព័ន្ធ (Lyrics & Metatags):"
$lblEditor.Font = New-Object System.Drawing.Font("Segoe UI", 9.2, [System.Drawing.FontStyle]::Bold)
$lblEditor.ForeColor = [System.Drawing.Color]::FromArgb(200, 215, 235)
$lblEditor.Dock = [System.Windows.Forms.DockStyle]::Top
$lblEditor.Height = 26
$pnlLeft.Controls.Add($lblEditor)

$txtLyrics = New-Object System.Windows.Forms.TextBox
$txtLyrics.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtLyrics.Multiline = $true
$txtLyrics.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtLyrics.BackColor = [System.Drawing.Color]::FromArgb(12, 14, 20)
$txtLyrics.ForeColor = [System.Drawing.Color]::White
$txtLyrics.Font = New-Object System.Drawing.Font("Consolas", 10.5)
$txtLyrics.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$pnlLeft.Controls.Add($txtLyrics)
$txtLyrics.BringToFront()

# Right: Templates & Structure Analyzer
$pnlRight = $split.Panel2
$pnlRight.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 34)
$pnlRight.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 12)

$lblTpl = New-Object System.Windows.Forms.Label
$lblTpl.Text = "📑 គំរូរចនាសម្ព័ន្ធបទចម្រៀង (Song Templates):"
$lblTpl.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblTpl.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 60)
$lblTpl.Location = New-Object System.Drawing.Point(14, 10)
$lblTpl.Size = New-Object System.Drawing.Size 300, 24
$pnlRight.Controls.Add($lblTpl)

$cmbTemplates = New-Object System.Windows.Forms.ComboBox
$cmbTemplates.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbTemplates.Location = New-Object System.Drawing.Point(14, 38)
$cmbTemplates.Size = New-Object System.Drawing.Size 300, 28
$cmbTemplates.BackColor = [System.Drawing.Color]::FromArgb(28, 33, 46)
$cmbTemplates.ForeColor = [System.Drawing.Color]::White
$cmbTemplates.Items.AddRange(@(
    "Pop Hit Standard (Verse-Chorus-Bridge)",
    "EDM Festival Club (Build-Drop-Rave)",
    "Emotional Acoustic Ballad (Melody-Outro)",
    "Khmer Romvong Folk (ចង្វាក់រាំវង់ប្រជាប្រិយ)",
    "Rap / Hip-Hop Flow (Bars-Hook-Outro)"
))
$cmbTemplates.SelectedIndex = 0
$pnlRight.Controls.Add($cmbTemplates)

$btnApplyTpl = New-Object System.Windows.Forms.Button
$btnApplyTpl.Text = "⚡ ផ្ទុកគំរូរចនាសម្ព័ន្ធនេះ"
$btnApplyTpl.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$btnApplyTpl.Size = New-Object System.Drawing.Size 300, 34
$btnApplyTpl.Location = New-Object System.Drawing.Point(14, 74)
$btnApplyTpl.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$btnApplyTpl.ForeColor = [System.Drawing.Color]::White
$btnApplyTpl.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnApplyTpl.FlatAppearance.BorderSize = 0
$btnApplyTpl.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlRight.Controls.Add($btnApplyTpl)

# Stats Group
$grpStats = New-Object System.Windows.Forms.GroupBox
$grpStats.Text = " 📊 ស្ថិតិចង្វាក់ទំនុក (Rhythm & Meter Stats) "
$grpStats.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$grpStats.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
$grpStats.Location = New-Object System.Drawing.Point(14, 120)
$grpStats.Size = New-Object System.Drawing.Size 300, 130
$pnlRight.Controls.Add($grpStats)

$lblLineCount = New-Object System.Windows.Forms.Label
$lblLineCount.Text = "ចំនួនបន្ទាត់: 0 បន្ទាត់"
$lblLineCount.ForeColor = [System.Drawing.Color]::FromArgb(200, 215, 235)
$lblLineCount.Location = New-Object System.Drawing.Point(15, 28)
$lblLineCount.Size = New-Object System.Drawing.Size 260, 22
$grpStats.Controls.Add($lblLineCount)

$lblWordCount = New-Object System.Windows.Forms.Label
$lblWordCount.Text = "ចំនួនពាក្យសរុប: 0 ពាក្យ"
$lblWordCount.ForeColor = [System.Drawing.Color]::FromArgb(200, 215, 235)
$lblWordCount.Location = New-Object System.Drawing.Point(15, 52)
$lblWordCount.Size = New-Object System.Drawing.Size 260, 22
$grpStats.Controls.Add($lblWordCount)

$lblSectionCount = New-Object System.Windows.Forms.Label
$lblSectionCount.Text = "ផ្នែក Metatags: 0 ផ្នែក"
$lblSectionCount.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
$lblSectionCount.Location = New-Object System.Drawing.Point(15, 76)
$lblSectionCount.Size = New-Object System.Drawing.Size 260, 22
$grpStats.Controls.Add($lblSectionCount)

$lblCharCount = New-Object System.Windows.Forms.Label
$lblCharCount.Text = "តួអក្សរសរុប: 0 / 3000 (Suno Limit)"
$lblCharCount.ForeColor = [System.Drawing.Color]::FromArgb(160, 175, 200)
$lblCharCount.Location = New-Object System.Drawing.Point(15, 100)
$lblCharCount.Size = New-Object System.Drawing.Size 260, 22
$grpStats.Controls.Add($lblCharCount)

# Action Buttons on Right
$btnPushQueue = New-Object System.Windows.Forms.Button
$btnPushQueue.Text = "🚀 បញ្ជូនទៅ Suno (Queue F6)"
$btnPushQueue.Font = New-Object System.Drawing.Font("Segoe UI", 10.0, [System.Drawing.FontStyle]::Bold)
$btnPushQueue.Size = New-Object System.Drawing.Size 300, 44
$btnPushQueue.Location = New-Object System.Drawing.Point(14, 270)
$btnPushQueue.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$btnPushQueue.ForeColor = [System.Drawing.Color]::White
$btnPushQueue.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPushQueue.FlatAppearance.BorderSize = 0
$btnPushQueue.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlRight.Controls.Add($btnPushQueue)

$btnCopyLyrics = New-Object System.Windows.Forms.Button
$btnCopyLyrics.Text = "📋 ចម្លងទំនុកច្រៀង (Copy)"
$btnCopyLyrics.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnCopyLyrics.Size = New-Object System.Drawing.Size 300, 36
$btnCopyLyrics.Location = New-Object System.Drawing.Point(14, 322)
$btnCopyLyrics.BackColor = [System.Drawing.Color]::FromArgb(40, 48, 68)
$btnCopyLyrics.ForeColor = [System.Drawing.Color]::White
$btnCopyLyrics.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCopyLyrics.FlatAppearance.BorderSize = 0
$btnCopyLyrics.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlRight.Controls.Add($btnCopyLyrics)

$btnClearLyrics = New-Object System.Windows.Forms.Button
$btnClearLyrics.Text = "🗑️ សម្អាតទាំងអស់ (Clear)"
$btnClearLyrics.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnClearLyrics.Size = New-Object System.Drawing.Size 300, 36
$btnClearLyrics.Location = New-Object System.Drawing.Point(14, 366)
$btnClearLyrics.BackColor = [System.Drawing.Color]::FromArgb(35, 42, 54)
$btnClearLyrics.ForeColor = [System.Drawing.Color]::FromArgb(250, 150, 150)
$btnClearLyrics.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClearLyrics.FlatAppearance.BorderSize = 0
$btnClearLyrics.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlRight.Controls.Add($btnClearLyrics)

function Insert-Metatag($tag) {
    $selStart = $txtLyrics.SelectionStart
    $txtLyrics.Text = $txtLyrics.Text.Insert($selStart, "$tag`r`n")
    $txtLyrics.SelectionStart = $selStart + $tag.Length + 2
    $txtLyrics.Focus()
}

function Update-LyricStats {
    $raw = $txtLyrics.Text
    $lines = $raw.Split("`n") | Where-Object { $_.Trim() -ne "" }
    $lblLineCount.Text = "ចំនួនបន្ទាត់: $($lines.Count) បន្ទាត់"
    
    $words = $raw.Split(@(' ', "`r", "`n", "`t"), [System.StringSplitOptions]::RemoveEmptyEntries)
    $lblWordCount.Text = "ចំនួនពាក្យសរុប: $($words.Count) ពាក្យ"

    $sections = [System.Text.RegularExpressions.Regex]::Matches($raw, '\[.*?\]').Count
    $lblSectionCount.Text = "ផ្នែក Metatags: $sections ផ្នែក"

    $chars = $raw.Length
    $lblCharCount.Text = "តួអក្សរសរុប: $chars / 3000"
}

$txtLyrics.Add_TextChanged({ Update-LyricStats })

$btnApplyTpl.Add_Click({
    $tpl = switch ($cmbTemplates.SelectedIndex) {
        0 {
@'
[Intro]
(Soft melodic piano and ambient synth pads)

[Verse 1]
Walking through the neon rain tonight
Every shadow fading into light
I can hear the rhythm in my mind
Leaving all the worries far behind

[Pre-Chorus]
The music starts to lift me high
Reaching out to touch the sky

[Chorus]
This is our moment, this is our song
Dancing together where we belong
Feel the beat taking over the floor
We're gonna party and ask for more!

[Verse 2]
City lights are shining in your eyes
Underneath the midnight velvet skies
Hold my hand and never let it go
Moving with the gentle summer glow

[Chorus]
This is our moment, this is our song
Dancing together where we belong
Feel the beat taking over the floor
We're gonna party and ask for more!

[Bridge]
(Electric guitar solo building intensity)
No yesterday, no tomorrow, just today!

[Chorus]
This is our moment, this is our song
Dancing together where we belong!

[Outro]
(Beat slowly fades into smooth piano)
[Fade Out]
'@
        }
        1 {
@'
[Intro]
[Heavy 808 Sub-Bass and fast hi-hats]

[Build-up]
Feel the tension rising up
Fill the rhythm in your cup
3... 2... 1... LET'S GO!

[Drop]
(Insane synthesizer lasers, distorted brass, heavy festival kicks)

[Verse]
We don't stop when the sun goes down
We are the kings of this party town
Hands in the air, scream and shout
Show this world what we're all about!

[Build-up]
Bass is pumping in my chest
Never gonna settle for second best!
DROP IT!

[Drop]
(Maximum energy rave bounce, laser arpeggios, hard punchy kicks)

[Outro]
[Fade Out]
'@
        }
        3 {
@'
[Intro]
(សំឡេងទ្រអ៊ូ និងរនាតឯក រួមផ្សំចង្វាក់ស្គររាំវង់ពិរោះរណ្តំ)

[Verse 1]
ឱពន្លឺចន្ទ័ភ្លឺថ្លាពេញបូណ៌មី
រាំវង់កម្សាន្តស្រីស្អាតពិសី
ឮសូរស្គរដៃរណ្តំទឹកដី
ញញឹមរីករាយក្នុងចិត្តឥតបី។

[Chorus]
រាំរាំទៅអូន រាំឱ្យសប្បាយ
បំភ្លេចកង្វល់ទុក្ខសោកទាំងឡាយ
តោះរាំរាំវង់ទាំងអស់គ្នាណា
សាមគ្គីសប្បាយគ្រប់ៗកាយា!

[Verse 2]
ខ្យល់រំភើយបក់បោកមកត្រជាក់
ដៃឆ្វេងដៃស្តាំរាំតាមចង្វាក់
ស្នាមញញឹមស្រស់គួរឱ្យស្រឡាញ់
រាំវង់ខ្មែរយើងមិនដែលចាញ់។

[Chorus]
រាំរាំទៅអូន រាំឱ្យសប្បាយ
បំភ្លេចកង្វល់ទុក្ខសោកទាំងឡាយ
តោះរាំរាំវង់ទាំងអស់គ្នាណា
សាមគ្គីសប្បាយគ្រប់ៗកាយា!

[Outro]
(ស្គររាំវង់លាន់ឮថ្នមៗ រួចបន្លឺសំឡេងហ៊ោសប្បាយ)
[Fade Out]
'@
        }
        default {
@'
[Intro]
(Gentle acoustic guitar arpeggios)

[Verse 1]
Under the quiet starlit glow
Whispering secrets winds bestow
Time stands still when you are near
Wiping away my every fear

[Chorus]
You are the melody in the breeze
Singing softly through the trees
Forever in my heart you'll stay
Until the night turns into day

[Outro]
(Harmonica melody softly fades out)
[Fade Out]
'@
        }
    }
    $txtLyrics.Text = $tpl
})

$btnCopyLyrics.Add_Click({
    if ($txtLyrics.Text.Trim() -ne "") {
        [System.Windows.Forms.Clipboard]::SetText($txtLyrics.Text)
        [System.Windows.Forms.MessageBox]::Show("បានចម្លងទំនុកច្រៀងទៅក្នុង Clipboard រួចរាល់!", "ជោគជ័យ", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})

$btnClearLyrics.Add_Click({
    $txtLyrics.Text = ""
})

$btnPushQueue.Add_Click({
    $lyrics = $txtLyrics.Text.Trim()
    if ($lyrics -eq "") {
        [System.Windows.Forms.MessageBox]::Show("សូមសរសេរទំនុកច្រៀងជាមុនសិន!", "បញ្ជាក់", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
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
            title = "New Rhyme Studio Track"
            lyrics = $lyrics
            prompt = "Melodic Vocal Master, Studio Sound"
            tags = "Melodic Vocal Master, Studio Sound"
            make_instrumental = $false
            timestamp = [DateTime]::UtcNow.Ticks
        }
        $queue += $item
        
        $json = ConvertTo-Json -InputObject $queue -Compress
        Set-Content -Path $queueFile -Value $json -Encoding UTF8

        # Try posting to Port 48999 bridge
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("Content-Type", "application/json; charset=utf-8")
            $postData = ConvertTo-Json @{ action = "push_song"; lyrics = $lyrics; title = "New Track" }
            $wc.UploadString("http://127.0.0.1:48999/api/lyrics", $postData) | Out-Null
        } catch { }

        [System.Windows.Forms.MessageBox]::Show("បានបញ្ជូនទំនុកច្រៀងចូលទៅក្នុងជួរ Suno ដោយជោគជ័យ!`n(រួចរាល់សម្រាប់ការ Create នៅលើ Suno)", "ជោគជ័យ", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("មានបញ្ហាក្នុងការបញ្ជូន: $($_.Exception.Message)", "កំហុស", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

# Auto load first template
$cmbTemplates.SelectedIndex = 0
$btnApplyTpl.PerformClick()

[System.Windows.Forms.Application]::Run($form)
