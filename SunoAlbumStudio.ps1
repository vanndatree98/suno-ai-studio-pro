# ==============================================================================
# Suno AI Studio Pro - Album & Mixtape Architect (SunoAlbumStudio.ps1)
# Generate complete albums, tracklists, cohesive prompts, and batch queue to Suno
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# High DPI Awareness
$win32Dpi = @"
using System;
using System.Runtime.InteropServices;
public class SunoAlbumDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
try {
    Add-Type -TypeDefinition $win32Dpi -ErrorAction SilentlyContinue
    [SunoAlbumDpi]::SetProcessDPIAware() | Out-Null
} catch { }

$sunoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $sunoDir -or -not (Test-Path $sunoDir)) {
    $sunoDir = "C:\Users\PS\AppData\Local\Programs\Suno"
}
$queueFile = Join-Path $sunoDir "song_queue.json"

$form = New-Object System.Windows.Forms.Form
$form.Text = "💿 Suno AI Studio Pro - Album & Mixtape Architect"
$form.Size = New-Object System.Drawing.Size 1080, 800
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 23)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$form.MinimumSize = New-Object System.Drawing.Size 980, 700

# Top Header
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlHeader.Height = 85
$pnlHeader.BackColor = [System.Drawing.Color]::FromArgb(23, 27, 38)
$pnlHeader.Padding = New-Object System.Windows.Forms.Padding(20, 14, 20, 10)
$form.Controls.Add($pnlHeader)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "💿 Suno Album & Mixtape Concept Architect"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 13.5, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 94, 58)
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(18, 12)
$pnlHeader.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "បង្កើតគំនិតអាល់ប៊ុមចម្រៀងពេញលេញ (Album Concept, Tracklist Prompts) និងបញ្ជូនផលិតស្វ័យប្រវត្តិតាមជួរ Queue"
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(160, 175, 200)
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(20, 46)
$pnlHeader.Controls.Add($lblSub)

# Left Inputs Panel
$pnlLeft = New-Object System.Windows.Forms.Panel
$pnlLeft.Dock = [System.Windows.Forms.DockStyle]::Left
$pnlLeft.Width = 360
$pnlLeft.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 34)
$pnlLeft.Padding = New-Object System.Windows.Forms.Padding(18, 14, 18, 14)
$form.Controls.Add($pnlLeft)

$lblConfig = New-Object System.Windows.Forms.Label
$lblConfig.Text = "⚙️ ការកំណត់អាល់ប៊ុម (Album Settings):"
$lblConfig.Font = New-Object System.Drawing.Font("Segoe UI", 10.0, [System.Drawing.FontStyle]::Bold)
$lblConfig.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
$lblConfig.Location = New-Object System.Drawing.Point(16, 12)
$lblConfig.Size = New-Object System.Drawing.Size 320, 24
$pnlLeft.Controls.Add($lblConfig)

# Album Title
$lblAlbTitle = New-Object System.Windows.Forms.Label
$lblAlbTitle.Text = "ចំណងជើងអាល់ប៊ុម (Album Title):"
$lblAlbTitle.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 220)
$lblAlbTitle.Location = New-Object System.Drawing.Point(18, 46)
$lblAlbTitle.AutoSize = $true
$pnlLeft.Controls.Add($lblAlbTitle)

$txtAlbTitle = New-Object System.Windows.Forms.TextBox
$txtAlbTitle.Location = New-Object System.Drawing.Point(18, 70)
$txtAlbTitle.Size = New-Object System.Drawing.Size 320, 28
$txtAlbTitle.BackColor = [System.Drawing.Color]::FromArgb(28, 33, 46)
$txtAlbTitle.ForeColor = [System.Drawing.Color]::White
$txtAlbTitle.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtAlbTitle.Text = "រាត្រីទីក្រុងភ្នំពេញ (Phnom Penh Nights)"
$pnlLeft.Controls.Add($txtAlbTitle)

# Artist Name
$lblArtist = New-Object System.Windows.Forms.Label
$lblArtist.Text = "ឈ្មោះសិល្បករ / ផលិតករ (Artist):"
$lblArtist.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 220)
$lblArtist.Location = New-Object System.Drawing.Point(18, 110)
$lblArtist.AutoSize = $true
$pnlLeft.Controls.Add($lblArtist)

$txtArtist = New-Object System.Windows.Forms.TextBox
$txtArtist.Location = New-Object System.Drawing.Point(18, 134)
$txtArtist.Size = New-Object System.Drawing.Size 320, 28
$txtArtist.BackColor = [System.Drawing.Color]::FromArgb(28, 33, 46)
$txtArtist.ForeColor = [System.Drawing.Color]::White
$txtArtist.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtArtist.Text = "Suno Master Pro"
$pnlLeft.Controls.Add($txtArtist)

# Core Genre
$lblGenre = New-Object System.Windows.Forms.Label
$lblGenre.Text = "រចនាបថតន្ត្រីចម្បង (Core Genre):"
$lblGenre.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 220)
$lblGenre.Location = New-Object System.Drawing.Point(18, 174)
$lblGenre.AutoSize = $true
$pnlLeft.Controls.Add($lblGenre)

$cmbGenre = New-Object System.Windows.Forms.ComboBox
$cmbGenre.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbGenre.Location = New-Object System.Drawing.Point(18, 198)
$cmbGenre.Size = New-Object System.Drawing.Size 320, 28
$cmbGenre.BackColor = [System.Drawing.Color]::FromArgb(28, 33, 46)
$cmbGenre.ForeColor = [System.Drawing.Color]::White
$cmbGenre.Items.AddRange(@(
    "Khmer Retro Pop & 80s Synthwave",
    "Khmer Traditional Festival (Romvong & Kantrum)",
    "Cyberpunk Electronic & Industrial EDM",
    "Lo-Fi Chillhop & Rainy Day Beats",
    "Emotional Acoustic Piano & Strings Ballads",
    "Modern Trap & Hip-Hop 808",
    "Epic Cinematic Soundtrack & Orchestral"
))
$cmbGenre.SelectedIndex = 0
$pnlLeft.Controls.Add($cmbGenre)

# Number of Tracks
$lblTrackNum = New-Object System.Windows.Forms.Label
$lblTrackNum.Text = "ចំនួនបទក្នុងអាល់ប៊ុម (Track Count):"
$lblTrackNum.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 220)
$lblTrackNum.Location = New-Object System.Drawing.Point(18, 238)
$lblTrackNum.AutoSize = $true
$pnlLeft.Controls.Add($lblTrackNum)

$cmbCount = New-Object System.Windows.Forms.ComboBox
$cmbCount.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbCount.Location = New-Object System.Drawing.Point(18, 262)
$cmbCount.Size = New-Object System.Drawing.Size 320, 28
$cmbCount.BackColor = [System.Drawing.Color]::FromArgb(28, 33, 46)
$cmbCount.ForeColor = [System.Drawing.Color]::White
$cmbCount.Items.AddRange(@("5 Tracks (EP Album)", "8 Tracks (Standard Album)", "10 Tracks (Full LP Album)", "12 Tracks (Deluxe Album)"))
$cmbCount.SelectedIndex = 1
$pnlLeft.Controls.Add($cmbCount)

# Generate Button
$btnGenerate = New-Object System.Windows.Forms.Button
$btnGenerate.Text = "✨ បង្កើតគំនិតអាល់ប៊ុម (Architect Album)"
$btnGenerate.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnGenerate.Size = New-Object System.Drawing.Size 320, 42
$btnGenerate.Location = New-Object System.Drawing.Point(18, 312)
$btnGenerate.BackColor = [System.Drawing.Color]::FromArgb(124, 58, 237)
$btnGenerate.ForeColor = [System.Drawing.Color]::White
$btnGenerate.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnGenerate.FlatAppearance.BorderSize = 0
$btnGenerate.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlLeft.Controls.Add($btnGenerate)

# Batch Queue Button
$btnBatchQueue = New-Object System.Windows.Forms.Button
$btnBatchQueue.Text = "🚀 បញ្ជូនអាល់ប៊ុមទាំងមូលទៅ Suno (Queue)"
$btnBatchQueue.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnBatchQueue.Size = New-Object System.Drawing.Size 320, 42
$btnBatchQueue.Location = New-Object System.Drawing.Point(18, 364)
$btnBatchQueue.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$btnBatchQueue.ForeColor = [System.Drawing.Color]::White
$btnBatchQueue.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBatchQueue.FlatAppearance.BorderSize = 0
$btnBatchQueue.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlLeft.Controls.Add($btnBatchQueue)

# Export Markdown Button
$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "📄 នាំចេញជាឯកសារ (Export Tracklist)"
$btnExport.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnExport.Size = New-Object System.Drawing.Size 320, 36
$btnExport.Location = New-Object System.Drawing.Point(18, 416)
$btnExport.BackColor = [System.Drawing.Color]::FromArgb(40, 48, 68)
$btnExport.ForeColor = [System.Drawing.Color]::White
$btnExport.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnExport.FlatAppearance.BorderSize = 0
$btnExport.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlLeft.Controls.Add($btnExport)

# Right: Tracklist DataGridView
$pnlRight = New-Object System.Windows.Forms.Panel
$pnlRight.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlRight.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 23)
$pnlRight.Padding = New-Object System.Windows.Forms.Padding(18, 14, 18, 14)
$form.Controls.Add($pnlRight)
$pnlRight.BringToFront()

$lblTracklist = New-Object System.Windows.Forms.Label
$lblTracklist.Text = "🎼 បញ្ជីបទចម្រៀងក្នុងអាល់ប៊ុម (Generated Tracklist Prompts):"
$lblTracklist.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblTracklist.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
$lblTracklist.Dock = [System.Windows.Forms.DockStyle]::Top
$lblTracklist.Height = 28
$pnlRight.Controls.Add($lblTracklist)

$gridTracks = New-Object System.Windows.Forms.DataGridView
$gridTracks.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridTracks.BackgroundColor = [System.Drawing.Color]::FromArgb(18, 21, 30)
$gridTracks.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$gridTracks.GridColor = [System.Drawing.Color]::FromArgb(30, 36, 50)
$gridTracks.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$gridTracks.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$gridTracks.MultiSelect = $false
$gridTracks.AllowUserToAddRows = $false
$gridTracks.RowHeadersVisible = $false
$gridTracks.EnableHeadersVisualStyles = $false
$gridTracks.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(26, 32, 46)
$gridTracks.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 60)
$gridTracks.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$gridTracks.ColumnHeadersHeight = 32
$gridTracks.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(18, 21, 30)
$gridTracks.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$gridTracks.RowTemplate.Height = 30
$pnlRight.Controls.Add($gridTracks)
$gridTracks.BringToFront()

$colNum = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colNum.HeaderText = "#"
$colNum.Width = 40
$gridTracks.Columns.Add($colNum) | Out-Null

$colTTitle = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colTTitle.HeaderText = "ចំណងជើងបទ (Track Title)"
$colTTitle.Width = 200
$gridTracks.Columns.Add($colTTitle) | Out-Null

$colRole = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colRole.HeaderText = "តួនាទីក្នុងអាល់ប៊ុម"
$colRole.Width = 140
$gridTracks.Columns.Add($colRole) | Out-Null

$colPrompt = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPrompt.HeaderText = "Music Style Prompt"
$colPrompt.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
$gridTracks.Columns.Add($colPrompt) | Out-Null

function Generate-AlbumStructure {
    $gridTracks.Rows.Clear()
    $alb = $txtAlbTitle.Text.Trim()
    $genreIdx = $cmbGenre.SelectedIndex
    $count = switch ($cmbCount.SelectedIndex) { 0 { 5 } 1 { 8 } 2 { 10 } 3 { 12 } default { 8 } }

    $roles = @(
        "Intro (Overture)", "Lead Single (High-Energy)", "Second Hit (Melodic)",
        "Deep Story (Mid-tempo)", "Emotional Ballad", "Instrumental Interlude",
        "Festival Climax (Drop)", "Outro / Finale"
    )
    if ($count -gt 8) {
        $roles += @("Club Remix Bonus", "Acoustic Reprise", "Midnight Anthem", "Final Farewell")
    }

    $titles = switch ($genreIdx) {
        0 { @("ពន្លឺភ្លើងទីក្រុង", "រាត្រីរាំវង់បែប Synth", "ស្រមោលអតីតកាល", "ស្នេហាក្នុងភ្លៀង", "កង់រទេះពេលវេលា", "ភ្លេងបំពេរាត្រី", "ជួបគ្នាឡើងវិញ", "លារាត្រីរ៉េត្រូ", "តន្ត្រីស្រុកស្រែ 80s", "ក្តីសង្ឃឹមស្អែក", "រាំលេងសប្បាយ", "ពន្លឺថ្ងៃថ្មី") }
        1 { @("ស្គរដៃបើកឆាក", "រាំវង់ចូលឆ្នាំថ្មី", "សារាវ៉ាន់កម្សាន្តចិត្ត", "កន្ទ្រាក់អារម្មណ៍កន្ទ្រឹម", "ស្នេហ៍ស្រុកស្រែ", "ភ្លេងការសន្តិភាព", "ចង្វាក់រាំក្បាច់", "លារាំវង់រាត្រី", "រាំលេងវត្តភ្នំ", "កំលោះស្រុកលើ", "មន្តស្នេហ៍កញ្ញា", "សប្បាយទាំងអស់គ្នា") }
        2 { @("Neon Genesis", "Cyber Overdrive", "Digital Soul", "Dark Alley Protocol", "Binary Tears", "Core Override (SFX)", "Neon Horizon Rave", "System Shutdown", "Matrix Glitch Bonus", "Rebel Runner", "Synthetic Heart", "Terminal Velocity") }
        3 { @("Rainy Window", "Morning Coffee Beats", "Midnight Study Session", "Warm Tea Thoughts", "Lazy Sunday Sunlight", "Vinyl Static Interlude", "Sunset Stroll", "Night Sky Dreams", "City Skyline Chill", "Old Memories", "Soft Pillow", "Sweet Dreams") }
        default { @("Silent Dawn", "Heartfelt Whispers", "Echoes of You", "Gentle Waves", "Forgotten Tears", "Piano Breeze", "Eternal Light", "Fading Shadows", "Acoustic Sunset", "Tears in Heaven", "Promise Kept", "Peace at Last") }
    }

    $prompts = switch ($genreIdx) {
        0 { @("80s Retro Synthwave, analog pads, tape saturation, dreamy male vocals, 110 BPM", "High-energy synthpop, punchy electronic drums, catchy synthesizer lead, 125 BPM", "Melodic retro wave, smooth bass, nostalgia saxophone, male vocals, 105 BPM", "Melancholic 80s ballad, reverb vocals, electric guitar arpeggios, 85 BPM", "Emotional retro synth ballad, lush cathedral reverb, slow tempo, 78 BPM", "Instrumental synthwave, analog moog bassline, arpeggiated synths, 120 BPM", "Upbeat synth dance festival, euphoric drop, punchy kicks, 128 BPM", "Slow nostalgic outro, vinyl crackle, fading synth pads, 70 BPM") }
        1 { @("Traditional Khmer Romvong Overture, Roneat Ek, Tro Ou, festive acoustic drums, 100 BPM", "Fast Khmer Saravan dance, catchy chorus, energetic vocal duet, 128 BPM", "Khmer Kantrum beats, rapid percussion, joyous party celebration, 135 BPM", "Romantic Khmer folk ballad, acoustic Tro, soft emotional vocals, 85 BPM", "Gentle Khmer folk story, melodic flute and strings, sweet female singer, 90 BPM", "Traditional Khmer instrumental, Roneat Ek solo, Tro Sau harmony, 105 BPM", "Massive Khmer festival dance, energetic drop, clapping and cheers, 130 BPM", "Traditional outro, celebratory drum fade out, joyous laughter, 80 BPM") }
        2 { @("Industrial dark cyberpunk intro, heavy sub-bass drones, distorted vocoder, 120 BPM", "Peak-time cyberpunk techno, massive acid bass, aggressive synth leads, 135 BPM", "Melodic darkwave, punchy electronic drums, eerie male baritone, 124 BPM", "Mid-tempo industrial bass, heavy reverb snare, gritty atmosphere, 110 BPM", "Emotional synthwave ballad, vocoder harmonies, deep bass warmth, 90 BPM", "Heavy instrumental bass drop, laser sound effects, glitched synths, 140 BPM", "Rave festival climax, huge distorted synth drops, euphoric lasers, 138 BPM", "Ambient dark outro, glitching radio static, robotic shutdown voice, 65 BPM") }
        default { @("Lo-fi hip-hop intro, warm electric piano, vinyl crackle, slow mellow drums, 80 BPM", "Catchy chillhop groove, jazzy saxophone licks, relaxed head-nodding drums, 85 BPM", "Rainy day lo-fi beat, gentle acoustic guitar chords, soothing vocal chops, 75 BPM", "Melancholic lo-fi piano ballad, tape wow and flutter, emotional melody, 70 BPM", "Deep chillout vibe, muted trumpet, smooth bassline, late night study mood, 82 BPM", "Instrumental lo-fi jazz interlude, acoustic upright bass, brush drums, 78 BPM", "Sunset lo-fi groove, warm rhodes piano, uplifting melody, 88 BPM", "Late night bedroom lo-fi outro, cricket ambient sounds, rain falling, 65 BPM") }
    }

    for ($i = 0; $i -lt $count; $i++) {
        $trackTitle = $titles[$i % $titles.Count]
        $trackRole = $roles[$i % $roles.Count]
        $trackPrompt = $prompts[$i % $prompts.Count]
        $gridTracks.Rows.Add(($i + 1), $trackTitle, $trackRole, $trackPrompt) | Out-Null
    }

    $lblTracklist.Text = "🎼 បញ្ជីបទចម្រៀងក្នុងអាល់ប៊ុម ($count បទ ត្រូវបានរៀបចំរួចរាល់):"
}

$btnGenerate.Add_Click({ Generate-AlbumStructure })

$btnBatchQueue.Add_Click({
    if ($gridTracks.Rows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("សូមចុចប៊ូតុង '✨ បង្កើតគំនិតអាល់ប៊ុម' ជាមុនសិន!", "បញ្ជាក់", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $conf = [System.Windows.Forms.MessageBox]::Show("តើអ្នកពិតជាចង់បញ្ជូនបទចម្រៀងទាំង $($gridTracks.Rows.Count) បទ ចូលក្នុងជួរ Suno Queue មែនទេ?", "បញ្ជាក់ការបញ្ជូន", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($conf -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        $queue = @()
        if (Test-Path $queueFile) {
            $raw = Get-Content $queueFile -Raw -Encoding UTF8
            if ($raw.Trim() -ne "") {
                $queue = $raw | ConvertFrom-Json
            }
        }

        foreach ($row in $gridTracks.Rows) {
            $num = $row.Cells[0].Value
            $tTitle = $row.Cells[1].Value
            $tRole = $row.Cells[2].Value
            $tPrompt = $row.Cells[3].Value

            $item = [PSCustomObject]@{
                title = "$tTitle ($tRole)"
                prompt = $tPrompt
                tags = $tPrompt
                lyrics = ""
                make_instrumental = $tRole.Contains("Instrumental")
                timestamp = [DateTime]::UtcNow.Ticks
            }
            $queue += $item
        }

        $json = ConvertTo-Json -InputObject $queue -Compress
        Set-Content -Path $queueFile -Value $json -Encoding UTF8

        [System.Windows.Forms.MessageBox]::Show("បានបញ្ជូនបទចម្រៀងក្នុងអាល់ប៊ុមទាំង $($gridTracks.Rows.Count) បទ ចូលក្នុងជួរ Suno ដោយជោគជ័យ!`n(Suno នឹងបង្កើតបទចម្រៀងទាំងនេះជាបន្តបន្ទាប់)", "ជោគជ័យ", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("មានបញ្ហាក្នុងការបញ្ជូន: $($_.Exception.Message)", "កំហុស", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$btnExport.Add_Click({
    if ($gridTracks.Rows.Count -eq 0) { return }
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "Markdown Tracklist (*.md)|*.md|Text File (*.txt)|*.txt"
    $sfd.FileName = "$($txtAlbTitle.Text) - Album Tracklist.md"
    if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $sb = New-Object System.Text.StringBuilder
        $sb.AppendLine("# 💿 $($txtAlbTitle.Text)") | Out-Null
        $sb.AppendLine("**Artist**: $($txtArtist.Text) | **Genre**: $($cmbGenre.SelectedItem)") | Out-Null
        $sb.AppendLine("`n---`n") | Out-Null
        $sb.AppendLine("| # | ចំណងជើងបទ (Title) | តួនាទីក្នុងអាល់ប៊ុម | Style Prompt |") | Out-Null
        $sb.AppendLine("|:---:|:---|:---|:---|") | Out-Null
        foreach ($row in $gridTracks.Rows) {
            $sb.AppendLine("| **$($row.Cells[0].Value)** | $($row.Cells[1].Value) | $($row.Cells[2].Value) | \`$($row.Cells[3].Value)\` |") | Out-Null
        }
        [System.IO.File]::WriteAllText($sfd.FileName, $sb.ToString(), [System.Text.Encoding]::UTF8)
        [System.Windows.Forms.MessageBox]::Show("បាននាំចេញបញ្ជី Tracklist ដោយជោគជ័យ!", "ជោគជ័យ", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})

$form.Add_Shown({
    Generate-AlbumStructure
})

[System.Windows.Forms.Application]::Run($form)
