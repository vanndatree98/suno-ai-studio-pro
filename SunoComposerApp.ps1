param(
    [string]$topic = "",
    [string]$themeId = "",
    [string]$genreId = ""
)

$ErrorActionPreference = "SilentlyContinue"

# Check single instance
$mutexName = "Local\SunoComposerApp_Mutex_48291"
$isNew = $false
$appMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$isNew)

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Win32Composer {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public static IntPtr FindSunoWindow() {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hWnd, lParam) => {
            if (IsWindowVisible(hWnd)) {
                var sb = new StringBuilder(256);
                GetWindowText(hWnd, sb, 256);
                string title = sb.ToString();
                if (title.Contains("Suno - AI Music") || title.Contains("Suno Desktop")) {
                    found = hWnd;
                    return false;
                }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static IntPtr FindComposerWindow() {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hWnd, lParam) => {
            if (IsWindowVisible(hWnd)) {
                var sb = new StringBuilder(256);
                GetWindowText(hWnd, sb, 256);
                string title = sb.ToString();
                if (title.Contains("Suno AI - Auto Song & Music Composer") || title.Contains("កម្មវិធីនិពន្ធបទចម្រៀង")) {
                    found = hWnd;
                    return false;
                }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@

try {
    $cWnd = [Win32Composer]::GetConsoleWindow()
    if ($cWnd -ne [IntPtr]::Zero) { [Win32Composer]::ShowWindow($cWnd, 0) | Out-Null }
} catch { }

if (-not $isNew) {
    $existingHwnd = [Win32Composer]::FindComposerWindow()
    if ($existingHwnd -ne [IntPtr]::Zero) {
        [Win32Composer]::ShowWindow($existingHwnd, 9)
        [Win32Composer]::SetForegroundWindow($existingHwnd)
        exit 0
    } else {
        # No visible window exists, kill stale background instances so this one opens
        Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*SunoComposerApp.ps1*" -and $_.ProcessId -ne $PID } | ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
        }
        Start-Sleep -Milliseconds 400
    }
}

try { [Win32Composer]::SetProcessDPIAware() | Out-Null } catch { }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$sunoDir = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Programs\Suno" } else { "C:\Users\PS\AppData\Local\Programs\Suno" }
$configFile = Join-Path $sunoDir "gemini_config.json"
$songQueueFile = Join-Path $sunoDir "song_queue.json"
$iconPath = Join-Path $sunoDir "app.ico"

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

# Load Config
$config = @{
    apiKey = ""
    model = "gemini-3.1-flash-lite"
    autoFillSuno = $true
    language = "km"
    customLanguage = ""
}
if (Test-Path $configFile) {
    try {
        $rawConfig = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($rawConfig.apiKey) { $config.apiKey = $rawConfig.apiKey }
        if ($rawConfig.model) { $config.model = $rawConfig.model }
        if ($rawConfig.language) { $config.language = $rawConfig.language }
        if ($rawConfig.customLanguage) { $config.customLanguage = $rawConfig.customLanguage }
    } catch { }
}

function Save-Config {
    try {
        $config | ConvertTo-Json -Depth 3 | Set-Content $configFile -Encoding UTF8
    } catch { }
}

# --- VOCAL ENFORCEMENT ENGINE FOR SUNO AI ---
function Get-VocalProfile($vocalVal) {
    $v = ("$vocalVal").ToLower().Trim()
    $hasFemale = ($v -match "\bfemale\b") -or ($v -like "*ស្រី*")
    $hasMale = ($v -match "\bmale\b") -or ($v -like "*ប្រុស*")
    $isDuet = ($v -like "*duet*") -or ($v -like "*ឆ្លើយឆ្លង*") -or ($hasFemale -and $hasMale)

    if ($isDuet) {
        return @{
            Id = "duet"
            Name = "ឆ្លើយឆ្លង (Duet: Male & Female)"
            Tag = "[Duet: Male and Female Vocals]"
            StylePrefix = "[Duet: Male and Female Vocals], dynamic Khmer duet, alternating male and female vocalists, sweet harmonized chorus, clear dual vocal dynamics"
            LyricTag = "[Duet: Male and Female Vocals]"
            IsInstrumental = $false
            PromptInstruction = "CRITICAL VOCAL DIRECTIVE: The song MUST be a DUET between Male and Female singers. Style MUST start with '[Duet: Male and Female Vocals], dynamic Khmer duet, alternating male and female vocalists'. Lyrics MUST distinguish sections like [Verse 1 - Male Vocals], [Verse 2 - Female Vocals], and [Chorus - Duet Harmony]."
        }
    }
    if ($v -like "*instrumental*" -or $v -like "*no vocals*" -or $v -like "*ភ្លេងសុទ្ធ*") {
        return @{
            Id = "instrumental"
            Name = "ភ្លេងសុទ្ធ (Instrumental)"
            Tag = "[Instrumental]"
            StylePrefix = "[Instrumental], pure acoustic melodic instruments, pristine orchestration, no vocals, melodic solo lead"
            LyricTag = "[Instrumental]`n(Pure acoustic melody - No vocals)"
            IsInstrumental = $true
            PromptInstruction = "CRITICAL DIRECTIVE: Pure INSTRUMENTAL music with NO VOCALS. Style MUST start with '[Instrumental], pure acoustic melodic instruments, no vocals'. Lyrics must only contain instrumental structural cues like [Instrumental], [Main Theme], NO singing words."
        }
    }
    if ($hasMale) {
        return @{
            Id = "male"
            Name = "ប្រុស (Male Vocals)"
            Tag = "[Male Vocals]"
            StylePrefix = "[Male Vocals], warm emotional Khmer male vocals, deep smooth masculine singer, rich resonant tone, clear vocal clarity"
            LyricTag = "[Male Vocals]"
            IsInstrumental = $false
            PromptInstruction = "CRITICAL VOCAL DIRECTIVE: The singer MUST be MALE. Style MUST start with '[Male Vocals], warm emotional Khmer male vocals, deep smooth masculine singer'. Lyrics MUST begin with [Male Vocals] and mark sections like [Verse 1 - Male Vocals], [Chorus - Male Vocals]."
        }
    }
    return @{
        Id = "female"
        Name = "ស្រី (Female Vocals)"
        Tag = "[Female Vocals]"
        StylePrefix = "[Female Vocals], emotional sweet Khmer female vocals, clear feminine singer, high pitch melody, angelic resonance, crystalline vocals"
        LyricTag = "[Female Vocals]"
        IsInstrumental = $false
        PromptInstruction = "CRITICAL VOCAL DIRECTIVE: The singer MUST be FEMALE. Style MUST start with '[Female Vocals], emotional sweet Khmer female vocals, clear feminine singer'. Lyrics MUST begin with [Female Vocals] and mark sections like [Verse 1 - Female Vocals], [Chorus - Female Vocals]."
    }
}

function Format-VocalEnforcedPrompt($rawStyle, $vocalProf) {
    if (-not $rawStyle) { return $vocalProf.StylePrefix }
    $s = $rawStyle.Trim()
    $s = $s -replace '\[(?:Female|Male|Duet|Instrumental)[^\]]*\]\s*,?\s*', ''
    $s = $s -replace '(?i)(?:emotional|heartfelt|deep|warm|clear|sweet|soulful)?\s*(?:female|male|duet|instrumental)\s*(?:vocal|vocals|harmony|singer)?\s*,?\s*', ''
    $s = $s -replace '\s*,\s*,+', ', '
    $s = $s.Trim().Trim(',').Trim()
    return "$($vocalProf.StylePrefix), $s"
}

function Format-VocalEnforcedLyrics($rawLyrics, $vocalProf) {
    if ($vocalProf.IsInstrumental) {
        return @"
[Instrumental]
(Pure acoustic melody - No vocals)

[Intro - Acoustic Lead]
(Melodic traditional kloy and acoustic guitar)

[Main Theme]
(Driving emotional melodic progression)

[Melodic Solo]
(Expressive instrument solo)

[Outro - Fade Out]
(Melody fades into silence)
"@
    }
    if (-not $rawLyrics) {
        return "$($vocalProf.LyricTag)`n`n[Intro]`n`n[Verse 1]`n`n[Chorus]"
    }
    $lyrics = $rawLyrics.Trim()
    $lyrics = $lyrics -replace '(?i)^\[(?:Female|Male|Duet|Instrumental)[^\]]*\]\s*', ''

    if ($vocalProf.Id -eq 'female') {
        $lyrics = $lyrics -replace '(?i)\[(?:Male|Duet)[^\]]*\]\s*', ''
        $lyrics = $lyrics -replace '(?i)\[Verse 1(?:\s*-[^\]]*)?\]', '[Verse 1 - Female Vocals]'
        $lyrics = $lyrics -replace '(?i)\[Verse 2(?:\s*-[^\]]*)?\]', '[Verse 2 - Female Vocals]'
        $lyrics = $lyrics -replace '(?i)\[Chorus(?:\s*-[^\]]*)?\]', '[Chorus - Female Vocals]'
        $lyrics = $lyrics -replace '(?i)\[Bridge(?:\s*-[^\]]*)?\]', '[Bridge - Female Vocals]'
        return Clean-DuplicateLyrics "$($vocalProf.LyricTag)`n`n$lyrics"
    }
    if ($vocalProf.Id -eq 'male') {
        $lyrics = $lyrics -replace '(?i)\[(?:Female|Duet)[^\]]*\]\s*', ''
        $lyrics = $lyrics -replace '(?i)\[Verse 1(?:\s*-[^\]]*)?\]', '[Verse 1 - Male Vocals]'
        $lyrics = $lyrics -replace '(?i)\[Verse 2(?:\s*-[^\]]*)?\]', '[Verse 2 - Male Vocals]'
        $lyrics = $lyrics -replace '(?i)\[Chorus(?:\s*-[^\]]*)?\]', '[Chorus - Male Vocals]'
        $lyrics = $lyrics -replace '(?i)\[Bridge(?:\s*-[^\]]*)?\]', '[Bridge - Male Vocals]'
        return Clean-DuplicateLyrics "$($vocalProf.LyricTag)`n`n$lyrics"
    }
    if ($vocalProf.Id -eq 'duet') {
        $lyrics = $lyrics -replace '(?i)\[(?:Female|Male)[^\]]*\]\s*', ''
        $lyrics = $lyrics -replace '(?i)\[Verse 1(?:\s*-[^\]]*)?\]', '[Verse 1 - Male Vocals]'
        $lyrics = $lyrics -replace '(?i)\[Verse 2(?:\s*-[^\]]*)?\]', '[Verse 2 - Female Vocals]'
        $lyrics = $lyrics -replace '(?i)\[Chorus(?:\s*-[^\]]*)?\]', '[Chorus - Duet Harmony]'
        $lyrics = $lyrics -replace '(?i)\[Bridge(?:\s*-[^\]]*)?\]', '[Bridge - Alternating Vocals]'
        return Clean-DuplicateLyrics "$($vocalProf.LyricTag)`n`n$lyrics"
    }
    return Clean-DuplicateLyrics $lyrics
}

function Clean-DuplicateLyrics($text) {
    if (-not $text) { return "" }
    $str = $text.Trim()

    # 1. Root vocal tag repeated
    $rootMatches = [regex]::Matches($str, '(?i)\[(?:Female|Male|Duet|Instrumental)[^\]]*\]')
    if ($rootMatches.Count -gt 1 -and $rootMatches[1].Index -gt 50) {
        $str = $str.Substring(0, $rootMatches[1].Index).Trim()
    }

    # 2. [Intro ...] repeated
    $introMatches = [regex]::Matches($str, '(?i)\[Intro[^\]]*\]')
    if ($introMatches.Count -gt 1 -and $introMatches[1].Index -gt 50) {
        $str = $str.Substring(0, $introMatches[1].Index).Trim()
    }

    # 3. [Verse 1 ...] repeated
    $verse1Matches = [regex]::Matches($str, '(?i)\[Verse 1[^\]]*\]')
    if ($verse1Matches.Count -gt 1 -and $verse1Matches[1].Index -gt 50) {
        $str = $str.Substring(0, $verse1Matches[1].Index).Trim()
    }

    # 4. Repeating halves
    $len = $str.Length
    if ($len -gt 100) {
        $half = [Math]::Floor($len / 2)
        for ($delta = -40; $delta -le 40; $delta++) {
            $splitPos = $half + $delta
            if ($splitPos -gt 30 -and $splitPos -lt ($len - 30)) {
                $p1 = $str.Substring(0, $splitPos).Trim()
                $p2 = $str.Substring($splitPos).Trim()
                if ($p1 -eq $p2 -or ($p1.Length -gt 80 -and $p2.StartsWith($p1.Substring(0, 80)))) {
                    $str = $p1
                    break
                }
            }
        }
    }

    # 5. First meaningful line repeated
    $lines = $str.Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 12 -and $_ -notmatch '^\[|^Outro' }
    if ($lines -and $lines.Count -gt 0) {
        $firstLine = $lines[0]
        $secondPos = $str.IndexOf($firstLine, $firstLine.Length + 30)
        if ($secondPos -gt 60) {
            $cutPos = $secondPos
            $prevBracket = $str.LastIndexOf('[', $secondPos)
            if ($prevBracket -ne -1 -and ($secondPos - $prevBracket) -lt 80) {
                $cutPos = $prevBracket
            }
            $str = $str.Substring(0, $cutPos).Trim()
        }
    }

    return $str
}

# --- SMART AI KHMER SONG GENERATOR ENGINE (OFFLINE) ---
function Get-SmartKhmerSong($userTopic, $selectedTheme, $selectedGenre, $vocalType, $tempo) {
    $cleanTopic = ($userTopic -replace "^(បទ|ចម្រៀង|បទចម្រៀង)[\s៖:]*", "").Trim()
    $baseName = if ($cleanTopic) { $cleanTopic } else {
        switch ($selectedTheme) {
            "sad" { "ស្រមោលស្នេហ៍បាក់បែក" }
            "mother" { "នឹកអ្នកមានគុណ" }
            "motivational" { "អ្នកចម្បាំងជីវិត" }
            "cafe" { "កាហ្វេជូរចត់ និងរាត្រីភ្លៀង" }
            "party" { "រាំវង់ស្រុកយើង" }
            "wedding" { "ផ្កាស្លាជ័យមង្គល" }
            default { "ស្រមោលស្នេហ៍កណ្តាលរាត្រី" }
        }
    }

    # Generate 5 Creative Catchy Titles
    $titles = @()
    if ($cleanTopic) {
        $titles += "$cleanTopic (Original Mix 2026)"
        $titles += "រឿងរ៉ាវ `"$cleanTopic`" កណ្តាលរាត្រី"
        $titles += "$cleanTopic [Acoustic Ballad Version]"
        $titles += "ស្រមោលនៃ $cleanTopic (Shadows of Heart)"
        $titles += "បទចម្រៀងអំពី `"$cleanTopic`""
    } else {
        switch ($selectedTheme) {
            "sad" {
                $titles += "ដំណក់ទឹកភ្នែកក្រោមតំណក់ភ្លៀង (Broken Tears)"
                $titles += "លាហើយមនុស្សដែលធ្លាប់ស្រឡាញ់ [Sad Acoustic]"
                $titles += "បេះដូងបាក់បែកកណ្តាលរាត្រី (Lost Love)"
                $titles += "ហេតុអ្វីទៅចោលបង? (Tears of Sorrow)"
                $titles += "ស្នាមរបួសក្នុងចិត្តដែលមិនចេះជា"
            }
            "mother" {
                $titles += "ម៉ែអើយកូននឹកម៉ែណាស់ (Mother's Love)"
                $titles += "ស្រណោះផ្ទះស្លឹកស្រុកកំណើត (Homeland Memories)"
                $titles += "គុណម៉ែធំធេងលើសមហាសាគរ [Khmer Flute Melody]"
                $titles += "កូនសូមទោសអ្នកម្តាយ (Forgive Me, Mother)"
                $titles += "ញើសម៉ែដើម្បីអនាគតកូន"
            }
            "motivational" {
                $titles += "ក្រោកឈរឡើង! ហោះហើរទៅលើមេឃា (Rise Above)"
                $titles += "យើងជាអ្នកចម្បាំង មិនចុះចាញ់ (Warrior Heart)"
                $titles += "ពន្លឺនៃក្តីសង្ឃឹម (New Hope 2026)"
                $titles += "កម្លាំងចិត្តក្នុងព្យុះជីវិត (Unstoppable)"
                $titles += "ជ័យជម្នះជារបស់យើង (Victory Calling)"
            }
            "cafe" {
                $titles += "កាហ្វេជូរចត់ និងការចងចាំ (Midnight Coffee)"
                $titles += "រាត្រីភ្លៀងធ្លាក់កណ្តាលហាងកាហ្វេ (Rainy Cafe Vibes)"
                $titles += "អង្គុយចាំមនុស្សដែលមិនមក (Waiting in the Rain)"
                $titles += "រសជាតិកាហ្វេ រសជាតិនៃស្នេហា"
                $titles += "រាត្រីស្ងប់ស្ងាត់ និងបេះដូងឯកា"
            }
            "party" {
                $titles += "រាំវង់ចូលឆ្នាំខ្មែរសប្បាយ (Khmer New Year Dance)"
                $titles += "សារ៉ាវ៉ាន់ស្រុកយើង (Village Saravan Party)"
                $titles += "ក្រមុំភូមិខ្ញុំស្អាតដាច់គេ (Pretty Village Girl)"
                $titles += "ចង្វាក់កន្ទ្រាក់អារម្មណ៍រាំកម្សាន្ត (Festive Beats)"
                $titles += "ជួបជុំបងប្អូនថ្ងៃចូលឆ្នាំ"
            }
            "wedding" {
                $titles += "ក្លិនផ្ការំដួលកណ្តាលព្រៃព្រឹក្សា (Eternal Romance)"
                $titles += "ផ្ការីកក្នុងចិត្ត (Eternal Bloom - Pleng Kar)"
                $titles += "សម្រស់ស្រីខ្មែរដួងចៃបង (My Cambodian Bride)"
                $titles += "ស្បថស្បែក្រោមពន្លឺព្រះចន្ទ (Wedding Vow)"
                $titles += "ថ្ងៃមង្គលសិរីសួស្តីប្តីប្រពន្ធ"
            }
            default {
                $titles += "ស្រមោលស្នេហ៍កណ្តាលរាត្រី (Love Acoustic Ballad)"
                $titles += "ផ្ញើស្នេហ៍តាមខ្យល់ (Whispering Wind)"
                $titles += "កែវភ្នែកមួយគូនោះ (Only You - My Destiny)"
                $titles += "ក្តីស្រឡាញ់ដែលមិនចេះរីងស្ងួត (Timeless Love)"
                $titles += "ចង្វាក់បេះដូងរាត្រី (Heartbeat Rhythm)"
            }
        }
    }

    # Music Style Prompt Generator
    $instruments = switch ($selectedGenre) {
        "traditional" { "resonant traditional khmer roneat ek, sweet tro sau violin, khmer kloy bamboo flute, soft acoustic rhythm guitar" }
        "phonk" { "aggressive memphis phonk drift bass, 808 sub bass drop, dark atmosphere, distorted cowbell, high energy trap drums" }
        "acoustic" { "intimate warm nylon acoustic guitar, melodic grand piano, mellow cello accents, gentle ambient room reverb" }
        "rnb" { "silky electric rhodes piano, smooth modern 808 bass, atmospheric synth pads, soulful snaps, crystal clear high fidelity" }
        "rock" { "powerful distorted electric guitar riffs, screaming melodic solo, epic live heavy drums, driving bassline, stadium reverb" }
        "lofi" { "vintage tape-warm lo-fi guitar, dusty vinyl crackle, mellow rhodes chords, relaxed downtempo hip-hop drums" }
        default { "melodic grand piano, pristine acoustic strums, atmospheric synth pads, crisp studio live drums, deep warm bass" }
    }

    $bpm = switch ($tempo) {
        "slow" { (Get-Random -Minimum 68 -Maximum 76) }
        "fast" { (Get-Random -Minimum 118 -Maximum 132) }
        default { (Get-Random -Minimum 82 -Maximum 94) }
    }

    $soundMix = "Dolby Atmos 3D spatial mix, pristine studio recording, ultra-clear 24-bit/192 kHz audio master, wide emotional stereo soundstage"
    $genreName = switch ($selectedGenre) {
        "traditional" { "Contemporary Khmer Pleng Kar Fusion" }
        "phonk" { "High-Energy Drift Phonk" }
        "acoustic" { "Romantic Acoustic Folk Ballad" }
        "rnb" { "Soulful Contemporary R&B" }
        "rock" { "Epic Cinematic Melodic Rock" }
        "lofi" { "Chill Lo-Fi Acoustic Beats" }
        default { "Contemporary Khmer Pop Ballad" }
    }

    $vocalProf = Get-VocalProfile $vocalType
    $baseStyle = "$genreName, $instruments, $bpm bpm, $soundMix"
    $stylePrompt = Format-VocalEnforcedPrompt $baseStyle $vocalProf

    # Full Khmer Lyrics Composition
    $lyrics = switch ($selectedTheme) {
        "mother" {
@"
[Intro - Emotional Kloy Flute & Soft Acoustic Guitar]
(សំឡេងខ្លុយខ្មែរស្រទន់... នឹកដល់អ្នកម្តាយ... នឹកភូមិកំណើត...)

[Verse 1]
ខ្យល់រំភើយបក់មកពីទិសខាងកើត នឹកស្រុកកំណើតធ្លាប់រស់នៅ
នឹកក្លិនបាយក្ដៅម្ដាយដាំ នឹកផ្ទះស្លឹកចាស់ម្លប់ជ្រៃ
កូនមកតស៊ូនៅទីក្រុង ឆ្ងាយស្រុកឆ្ងាយភូមិ
រាល់រាត្រីសម្លឹងមើលផ្កាយ នឹកម៉ែឪរាល់វេលា

[Pre-Chorus]
ឮសូរសំឡេងម៉ែតាមទូរស័ព្ទ សួរកូនថាញ៉ាំបាយហើយឬនៅ?
ទឹកភ្នែកកូនហូរដោយមិនដឹងខ្លួន នឹកម៉ែណាស់...

[Chorus]
ម៉ែអើយកូននឹកម៉ែណាស់ នឹកទាំងដំបូន្មាន
កូនខំតស៊ូធ្វើការងារ ដើម្បីអនាគតថ្លៃថ្លា
រង់ចាំកូនណាអ្នកម្ដាយ មិនយូរឡើយកូននឹងត្រឡប់
យកជោគជ័យទៅជូនម៉ែ ជួបជុំគ្រួសារ

[Verse 2]
ឃើញដៃម៉ែគគ្រើមព្រោះធ្វើការ ទឹកភ្នែកហូរស្រក់ស្រណោះ
ម៉ែរងទុក្ខវេទនាដើម្បីកូន មិនដែលរអ៊ូពាក្យហត់នឿយ
គុណម៉ែធំធេងដូចមហាសាគរ រកអ្វីប្រៀបផ្ទឹមគ្មាន
កូនសូមសំពះបួងសួង សូមឱ្យម៉ែមានសុខភាពល្អ

[Bridge - Resonant Tro Sau Violin Solo]
(សំឡេងទ្ររំជួលចិត្ត... ស្រណោះគុណអ្នកមានគុណ...)
គ្មានកន្លែងណា កក់ក្តៅដូចទ្រូងអ្នកម្តាយឡើយ...

[Chorus]
ម៉ែអើយកូននឹកម៉ែណាស់ នឹកទាំងដំបូន្មាន
កូនខំតស៊ូធ្វើការងារ ដើម្បីអនាគតថ្លៃថ្លា
រង់ចាំកូនណាអ្នកម្ដាយ មិនយូរឡើយកូននឹងត្រឡប់
យកជោគជ័យទៅជូនម៉ែ ជួបជុំគ្រួសារ

[Outro - Soft Flute Melody Fade Out]
កូនស្រឡាញ់ម៉ែ... ស្រឡាញ់រហូត...
(Music softly fades out with gentle acoustic guitar...)
"@
        }
        "motivational" {
@"
[Intro - Driving Acoustic Rhythm & Atmospheric Strings]
(ស្គរបន្លឺឡើង... កម្លាំងចិត្តពុះកញ្ជ្រោល...)

[Verse 1]
ទោះផ្លូវខាងមុខមានបន្លា ឧបសគ្គរាប់រយរាប់ពាន់
ដួលប៉ុន្មានដងត្រូវតែងើប មិនត្រូវចុះចាញ់ព្រហ្មលិខិត
ញើសហូរស្រក់ដើម្បីក្ដីស្រមៃ ខំប្រឹងតស៊ូឥតឈប់
ថ្ងៃស្អែកនឹងជាថ្ងៃរបស់យើង ជោគជ័យនឹងមកដល់

[Pre-Chorus]
ក្រោកឡើង! បោសធូលីដីចេញ
ហើយបន្តដំណើរឆ្ពោះទៅកាន់ជ័យជម្នះ!
យើងកើតមកដើម្បីឈ្នះ មិនមែនដើម្បីចុះចាញ់!

[Chorus]
ក្រោកឈរឡើង! ហោះហើរទៅលើមេឃាក្រឡាស់
បញ្ចេញពន្លឺក្នុងចិត្ត ឱ្យលោកដឹងថាយើងខ្លាំង
ទោះខ្យល់ព្យុះបក់បោក ក៏មិនរាថយ
យើងជាអ្នកចម្បាំង ក្តោបក្តាប់ជ័យជម្នះក្នុងដៃ!

[Verse 2]
ការរិះគន់រាប់ពាន់សម្តី ក្លាយជាកម្លាំងរុញច្រាន
ឱ្យយើងកាន់តែរឹងមាំ មិនទន់ជ្រាយដូចពីមុន
រាល់ដំណក់ញើសដែលបានស្រក់ នឹងក្លាយជាពេជ្រចាំងចែង
ស្មាមញញឹមនៃជ័យជម្នះ នឹងបំភ្លឺជីវិត

[Bridge - Powerful Electric Guitar Solo & Heavy Drums]
(ហ្គីតាវាយយ៉ាងកក្រើក... ស្គរបោកបន្លឺ...)
ស្រែកឱ្យអស់ពីចិត្ត! គ្មានអ្វីរារាំងយើងបានឡើយ!

[Chorus]
ក្រោកឈរឡើង! ហោះហើរទៅលើមេឃាក្រឡាស់
បញ្ចេញពន្លឺក្នុងចិត្ត ឱ្យលោកដឹងថាយើងខ្លាំង
ទោះខ្យល់ព្យុះបក់បោក ក៏មិនរាថយ
យើងជាអ្នកចម្បាំង ក្តោបក្តាប់ជ័យជម្នះក្នុងដៃ!

[Outro - Triumphant Big Crash]
ជ័យជម្នះជារបស់យើង! កុំចុះចាញ់!
(Epic final drum hit and ringing sustain)
"@
        }
        "sad" {
@"
[Intro - Mellow Rain Sounds & Soft Piano]
(សំឡេងតំណក់ទឹកភ្លៀង និងព្យាណូកំសត់...)

[Verse 1]
តំណក់ទឹកភ្លៀងស្រក់ស្រាលៗ បេះដូងរងាក្នុងរាត្រី
រូបអូនចាកចេញឆ្ងាយទៅ មិនស្តាយក្រោយមួយម៉ាត់ឡើយ
បន្សល់ទុកត្រឹមស្រមោលស្នេហ៍ និងអនុស្សាវរីយ៍ចាស់
ធ្លាប់កាន់ដៃគ្នាដើរកាត់ភ្លៀង ឥឡូវសល់ត្រឹមទឹកភ្នែក

[Pre-Chorus]
ហេតុអ្វីមនុស្សធ្លាប់ស្រឡាញ់ ក្លាយជាមនុស្សចម្លែក?
តើបងធ្វើខុសអ្វី ទើបអូនដាច់ចិត្តចោលបង...?

[Chorus]
ដំណក់ទឹកភ្នែកហូរស្រក់កណ្តាលរាត្រី
ស្រែកហៅឈ្មោះអូន តែគ្មានចម្លើយត្រឡប់
បេះដូងបែកបាក់ ឈឺផ្សាស្ទើរធ្លាយទ្រូង
លាហើយម្ចាស់ស្នេហ៍ លាហើយក្តីស្រឡាញ់

[Verse 2]
សម្លឹងមើលកៅអីទទេ ដែលអូនធ្លាប់អង្គុយក្បែរ
កែវកាហ្វេត្រជាក់ស្រេប ដូចចិត្តអូនដែលប្រែប្រួល
ព្យាយាមបំភ្លេចតែមិនបាន កាន់តែគិតកាន់តែឈឺ
ត្រូវរៀនរស់នៅម្នាក់ឯង ក្នុងលោកដែលគ្មានអូន

[Bridge - Crying Electric Guitar Solo]
(ហ្គីតាសូឡូសម្រក់ទឹកភ្នែក... ឈឺចាប់ខ្លោចផ្សា...)
បើសិនពេលវេលាអាចត្រឡប់... បងនឹងថែអូនឱ្យល្អជាងនេះ...

[Chorus]
ដំណក់ទឹកភ្នែកហូរស្រក់កណ្តាលរាត្រី
ស្រែកហៅឈ្មោះអូន តែគ្មានចម្លើយត្រឡប់
បេះដូងបែកបាក់ ឈឺផ្សាស្ទើរធ្លាយទ្រូង
លាហើយម្ចាស់ស្នេហ៍ លាហើយក្តីស្រឡាញ់

[Outro - Soft Piano Melody Fade Out]
ជូនពរអូនឱ្យជួបគេ... មនុស្សដែលអូនស្រឡាញ់...
(Piano softly plays the final melancholic chord)
"@
        }
        "party" {
@"
[Intro - Fast Roneat Ek & Drum Rhythm]
(ចង្វាក់រនាតឯក និងស្គរប្រពៃណីខ្មែរ... រាំវង់សប្បាយៗ...)

[Verse 1]
ចូលឆ្នាំមកដល់ហើយបងប្អូនអើយ មករាំលេងសប្បាយ
ស្រីៗប្រុសៗស្លៀកពាក់ស្អាតបាត នាំគ្នាទៅវត្ត
ឃើញក្រមុំភូមិខាងជើង ញញឹមស្រស់ដូចបុប្ផា
បងចង់តែចូលទៅសួរនាំ ចង់បាននាងជាគូ

[Pre-Chorus]
ទះដៃអបអរសាទរ តោះយើងរាំវង់!
បងប្អូនជួបជុំ ញញឹមរីករាយគ្រប់គ្នា!

[Chorus]
រាំវង់! រាំវង់! រាំវង់សប្បាយរីករាយ!
ចូលឆ្នាំថ្មីប្រពៃណីជាតិខ្មែរយើង
លើកដៃឡើងរាំ តាមចង្វាក់ភ្លេងខ្មែរ
ជម្រុះរឿងទុក្ខសោក ទទួលពរជ័យសិរីសួស្តី!

[Verse 2]
តោះរាំសារ៉ាវ៉ាន់ ឬក៏ចង់រាំក្បាច់
សប្បាយចិត្តឥតឧបមា ក្នុងភូមិមានពិធីបុណ្យ
លេងល្បែងប្រជាប្រិយ បោះអង្គញ់ទាញព្រ័ត្រ
ស្រែកហ៊ោលាន់លឺពេញស្រែ សាមគ្គីបងប្អូនខ្មែរ

[Bridge - Festive Tro and Drum Beats]
(សំឡេងស្គរវាយយ៉ាងកន្ត្រាក់... ហ៊ោកញ្ជ្រៀវសប្បាយ...)
តោះបងប្អូនអើយ រាំមួយជុំទៀត!

[Chorus]
រាំវង់! រាំវង់! រាំវង់សប្បាយរីករាយ!
ចូលឆ្នាំថ្មីប្រពៃណីជាតិខ្មែរយើង
លើកដៃឡើងរាំ តាមចង្វាក់ភ្លេងខ្មែរ
ជម្រុះរឿងទុក្ខសោក ទទួលពរជ័យសិរីសួស្តី!

[Outro - Big Celebratory Ending]
សួស្តីឆ្នាំថ្មី! ជ័យយោ! សប្បាយរីករាយទាំងអស់គ្នា!
(Festive cheer and big traditional drum finish)
"@
        }
        default {
@"
[Intro - Melodic Piano & Sweet Acoustic Nylon Guitar]
(សំនៀងព្យាណូស្រទន់... កក់ក្តៅដូចពន្លឺព្រះអាទិត្យពេលព្រឹក...)

[Verse 1]
ជួបអូនគ្រាដំបូង បេះដូងបងចាប់ផ្តើមញាប់ញ័រ
ស្នាមញញឹមដ៏ស្រស់បំព្រង ដូចផ្ការីកក្នុងចិន្តា
កែវភ្នែកមួយគូនោះ បំភ្លឺពិភពលោកបង
ធ្វើឱ្យបងដឹងថា ក្តីស្រឡាញ់ពិតមាននៅទីនេះ

[Pre-Chorus]
ទោះមានរឿងអ្វីកើតឡើង ក៏បងនៅក្បែរអូន
ចាប់ដៃអូនឆ្លងកាត់ រាល់ឧបសគ្គជីវិត

[Chorus]
ស្រមោលស្នេហ៍កណ្តាលរាត្រី មានតែអូនក្នុងចិត្ត
បេះដូងមួយនេះស្មោះត្រង់ គ្មានថ្ងៃប្រែប្រួលឡើយ
សូមផ្ញើក្តីស្រឡាញ់ តាមខ្យល់ត្រជាក់រាត្រី
ឱ្យអូនបានដឹងថា បងស្រឡាញ់អូនរហូត

[Verse 2]
រាល់ថ្ងៃដែលបាននៅក្បែរ ជាពេលវេលាដ៏មានតម្លៃ
អរគុណព្រហ្មលិខិត ដែលនាំយើងឱ្យមកជួបគ្នា
ទោះមេឃងងឹត ឬមានព្យុះបោកបក់
ស្នេហាយើងនឹងនៅតែរឹងមាំ មិនរង្គោះរង្គើ

[Bridge - Emotional Cello & Acoustic Guitar Harmony]
(ហ្គីតា និងសែលឡូដេញខ្សែសំនៀងផ្អែមល្ហែម...)
សន្យានឹងថែអូន... ជារៀងរហូតដល់ចាស់កោងខ្នង...

[Chorus]
ស្រមោលស្នេហ៍កណ្តាលរាត្រី មានតែអូនក្នុងចិត្ត
បេះដូងមួយនេះស្មោះត្រង់ គ្មានថ្ងៃប្រែប្រួលឡើយ
សូមផ្ញើក្តីស្រឡាញ់ តាមខ្យល់ត្រជាក់រាត្រី
ឱ្យអូនបានដឹងថា បងស្រឡាញ់អូនរហូត

[Outro - Soft Guitar Chords Fade Out]
មានតែអូនម្នាក់គត់... ដួងចិត្តបង...
(Acoustic guitar softly plays the final loving chord)
"@
        }
    }

    return @{
        title = $titles[0]
        alternativeTitles = $titles
        style = $stylePrompt
        lyrics = (Format-VocalEnforcedLyrics $lyrics $vocalProf)
    }
}

# --- GEMINI 3.1 ONLINE COMPOSER ENGINE ---
function Compose-WithGemini($apiKey, $model, $topic, $themeName, $genreName, $vocalType, $tempo, $langObj, $customLangName = "") {
    $vocalProf = Get-VocalProfile $vocalType
    $instRule = if ($vocalProf.IsInstrumental) { "- Pure instrumental cues only e.g. [Instrumental], [Main Theme]. NO singing words." } else { "- Structure with [Intro], [Verse 1], [Pre-Chorus], [Chorus], [Verse 2], [Bridge], [Chorus], [Outro]." }
    
    $langDirective = if ($langObj -and $langObj.Code -eq "custom" -and $customLangName) { "$customLangName language with culturally authentic, poetic, and native songwriting conventions" } elseif ($langObj) { $langObj.Directive } else { "Khmer language (ភាសាខ្មែរ) with beautiful poetic Khmer vocabulary, idioms, and natural rhyme schemes" }
    $titleRule = if ($langObj -and $langObj.Code -eq "custom" -and $customLangName) { "A creative, catchy song title in $customLangName language" } elseif ($langObj) { $langObj.TitleRule } else { 'A creative, catchy, and poetic song title in Khmer (can include English subtitle in parentheses, e.g. "ស្រមោលស្នេហ៍ (Shadow of Love)")' }
    $vocalTag = if ($langObj -and $langObj.Code -eq "custom" -and $customLangName) { "$customLangName vocals" } elseif ($langObj) { $langObj.VocalTag } else { "Khmer vocals" }

    $promptText = @"
You are a master hit-maker songwriter, poet, and music producer for Suno AI.
Generate a completely original, brand new, deeply emotional, and viral song written in $langDirective based on these details:
- Song Topic / Idea: "$topic"
- Theme / Mood: "$themeName"
- Music Genre / Vibe: "$genreName"
- Vocals: "$($vocalProf.Name)"
$($vocalProf.PromptInstruction)
- Tempo: "$tempo"

Requirements:
1. "title": $titleRule. MUST be completely unique and memorable.
2. "alternativeTitles": Exactly 4 additional creative alternative titles in an array of strings in $($langObj.Name).
3. "style": A rich, highly optimized Suno AI Music Style Prompt (in English).
   - CRITICAL VOCAL DIRECTIVE: "style" MUST start with "$($vocalProf.StylePrefix)" as the very first words at index 0. Include "$vocalTag" if vocals are enabled. Then append specific instruments, mood, bpm, audio production quality (e.g. "Dolby Atmos 3D mix, wide acoustic stereo, pristine studio detail").
4. "lyrics": Complete, fully-written, poetic song lyrics written in $langDirective with proper Suno structure tags:
   - Must begin with "$($vocalProf.LyricTag)" at the top.
   $instRule

Return ONLY a valid JSON object with keys "title", "alternativeTitles", "style", and "lyrics", with no markdown code blocks or extra text:
{
  "title": "...",
  "alternativeTitles": ["...", "...", "...", "..."],
  "style": "...",
  "lyrics": "..."
}
"@

    $targetModel = if ($model) { $model } else { "gemini-3.1-flash-lite" }
    $url = "https://generativelanguage.googleapis.com/v1beta/models/${targetModel}:generateContent?key=${apiKey}"
    $payload = @{
        contents = @(
            @{ parts = @( @{ text = $promptText } ) }
        )
        generationConfig = @{
            temperature = 0.88
            maxOutputTokens = 1500
        }
    } | ConvertTo-Json -Depth 5

    $resp = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Body $payload -TimeoutSec 10
    $text = $resp.candidates[0].content.parts[0].text
    $cleanJson = $text -replace '(?s)^.*?\{', '{' -replace '(?s)\}[^}]*$', '}'
    $parsed = $cleanJson | ConvertFrom-Json
    if ($parsed.title -and $parsed.lyrics -and $parsed.style) {
        $alt = @()
        if ($parsed.alternativeTitles) { $alt = $parsed.alternativeTitles }
        $enforcedStyle = Format-VocalEnforcedPrompt $parsed.style $vocalProf
        $enforcedLyrics = Format-VocalEnforcedLyrics $parsed.lyrics $vocalProf
        return @{
            title = $parsed.title
            alternativeTitles = @($parsed.title) + $alt
            style = $enforcedStyle
            lyrics = $enforcedLyrics
        }
    }
    throw "Incomplete song JSON from Gemini API"
}

# --- BUILD GUI WINDOW ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Suno AI - កម្មវិធីនិពន្ធបទចម្រៀង និង បទភ្លេងស្វ័យប្រវត្តិ (Auto Song & Music Composer)"
$form.Width = 1080
$form.Height = 820
$form.MinimumSize = New-Object System.Drawing.Size(960, 720)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 21)
$form.ForeColor = [System.Drawing.Color]::FromArgb(240, 240, 245)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

if (Test-Path $iconPath) {
    try { $form.Icon = New-Object System.Drawing.Icon($iconPath) } catch { }
}

# Dark Title Bar
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DwmComposer {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}
"@
$form.Add_HandleCreated({
    try {
        $val = 1
        [DwmComposer]::DwmSetWindowAttribute($form.Handle, 20, [ref]$val, [System.Runtime.InteropServices.Marshal]::SizeOf($val))
        [DwmComposer]::DwmSetWindowAttribute($form.Handle, 35, [ref]$val, [System.Runtime.InteropServices.Marshal]::SizeOf($val))
    } catch { }
})

# Root Table Layout
# --- Standard Studio Button Engine (ស្ទីលធម្មតា) ---
function Apply-StandardBtnStyle($btn, $normalBg, $hoverBg, $textColor = [System.Drawing.Color]::White, $borderCol = $null) {
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.BackColor = $normalBg
    $btn.ForeColor = $textColor
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    if ($null -ne $borderCol) {
        $btn.FlatAppearance.BorderSize = 1
        $btn.FlatAppearance.BorderColor = $borderCol
    } else {
        $btn.FlatAppearance.BorderSize = 0
    }
    $btn.Add_MouseEnter({
        $this.BackColor = $hoverBg
    })
    $btn.Add_MouseLeave({
        $this.BackColor = $normalBg
    })
}
function Apply-IOS27BtnStyle($btn, $normalBg, $hoverBg, $textColor = [System.Drawing.Color]::White, $borderCol = $null) {
    Apply-StandardBtnStyle $btn $normalBg $hoverBg $textColor $borderCol
}

$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock = [System.Windows.Forms.DockStyle]::Fill
$root.RowCount = 3
$root.ColumnCount = 1
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 68))) # Header
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) # Main Body Split
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 52))) # Footer Bar
$form.Controls.Add($root)

# 1. HEADER (STYLE iOS 27 Liquid Frosted Glass)
$header = New-Object System.Windows.Forms.Panel
$header.Dock = [System.Windows.Forms.DockStyle]::Fill
$header.BackColor = [System.Drawing.Color]::FromArgb(22, 20, 32)
$header.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)

$header.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $w = $s.ClientSize.Width
    $h = $s.ClientSize.Height
    if ($w -le 2 -or $h -le 2) { return }

    $bgRect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush ($bgRect), ([System.Drawing.Color]::FromArgb(28, 26, 40)), ([System.Drawing.Color]::FromArgb(18, 17, 26)), ([float]90.0)
    $g.FillRectangle($bgBrush, $bgRect)
    $bgBrush.Dispose()

    $penTop = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(45, 255, 255, 255), 1)
    $g.DrawLine($penTop, 0, 0, $w, 0)
    $penTop.Dispose()

    $penBottom = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(45, 42, 60), 1)
    $g.DrawLine($penBottom, 0, ($h - 1), $w, ($h - 1))
    $penBottom.Dispose()
})

$lblBrand = New-Object System.Windows.Forms.Label
$lblBrand.Text = "🎼 កម្មវិធីនិពន្ធបទចម្រៀង និង បទភ្លេងស្វ័យប្រវត្តិ (Suno AI Music Composer)"
$lblBrand.Font = New-Object System.Drawing.Font("Segoe UI", 13.5, [System.Drawing.FontStyle]::Bold)
$lblBrand.ForeColor = [System.Drawing.Color]::FromArgb(255, 120, 60)
$lblBrand.AutoSize = $true
$lblBrand.Location = New-Object System.Drawing.Point(18, 10)
$header.Controls.Add($lblBrand)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "✨ និពន្ធចំណងជើង ស្ទីលបទភ្លេង (Style Prompt) និងទំនុកច្រៀងខ្មែរស្វ័យប្រវត្តិ • បញ្ចូលត្រង់ទៅ Suno ដោយ 1-Click"
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(160, 160, 185)
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(20, 38)
$header.Controls.Add($lblSub)
$root.Controls.Add($header, 0, 0)

# 2. MAIN BODY (Split Left: Controls, Right: Outputs)
$bodySplit = New-Object System.Windows.Forms.SplitContainer
$bodySplit.Dock = [System.Windows.Forms.DockStyle]::Fill
$bodySplit.SplitterDistance = 410
$bodySplit.FixedPanel = [System.Windows.Forms.FixedPanel]::Panel1
$bodySplit.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 40)
$root.Controls.Add($bodySplit, 0, 1)

# LEFT PANEL: Parameters & Controls
$pnlLeft = New-Object System.Windows.Forms.Panel
$pnlLeft.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlLeft.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 26)
$pnlLeft.AutoScroll = $true
$pnlLeft.Padding = New-Object System.Windows.Forms.Padding(16)
$bodySplit.Panel1.Controls.Add($pnlLeft)

$y = 12

# Section: Song Topic
$lblTopic = New-Object System.Windows.Forms.Label
$lblTopic.Text = "💡 ប្រធានបទ ឬគំនិតចម្រៀង (Song Topic / Idea):"
$lblTopic.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblTopic.ForeColor = [System.Drawing.Color]::FromArgb(255, 175, 110)
$lblTopic.Location = New-Object System.Drawing.Point(16, $y)
$lblTopic.Size = New-Object System.Drawing.Size(360, 22)
$pnlLeft.Controls.Add($lblTopic)
$y += 24

$txtTopic = New-Object System.Windows.Forms.TextBox
$txtTopic.Location = New-Object System.Drawing.Point(16, $y)
$txtTopic.Size = New-Object System.Drawing.Size(360, 27)
$txtTopic.BackColor = [System.Drawing.Color]::FromArgb(26, 26, 38)
$txtTopic.ForeColor = [System.Drawing.Color]::White
$txtTopic.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtTopic.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$pnlLeft.Controls.Add($txtTopic)
$y += 34

# Topic Quick Preset Buttons Panel
$pnlPresets = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlPresets.Location = New-Object System.Drawing.Point(16, $y)
$pnlPresets.Size = New-Object System.Drawing.Size(360, 56)
$pnlPresets.BackColor = [System.Drawing.Color]::Transparent

$presets = @(
    @{ text = "💖 ស្នេហាផ្អែមល្ហែម"; topic = "ស្នេហាផ្អែមល្ហែម និងការជួបគ្នាដំបូង"; theme = "love" },
    @{ text = "💔 បែកបាក់/កំសត់"; topic = "ការបែកបាក់ និងដំណក់ទឹកភ្នែករាត្រី"; theme = "sad" },
    @{ text = "🌾 នឹកម៉ែ/ស្រុកស្រែ"; topic = "នឹកអ្នកមានគុណ និងផ្ទះស្រុកកំណើត"; theme = "mother" },
    @{ text = "🔥 តស៊ូ/កម្លាំងចិត្ត"; topic = "ការតស៊ូជំនះឧបសគ្គ និងជោគជ័យ"; theme = "motivational" },
    @{ text = "☕ កាហ្វេ/រាត្រី"; topic = "រសជាតិកាហ្វេ និងរាត្រីភ្លៀងធ្លាក់"; theme = "cafe" },
    @{ text = "💃 ចូលឆ្នាំ/រាំវង់"; topic = "រាំវង់ចូលឆ្នាំខ្មែរ សប្បាយរីករាយ"; theme = "party" }
)

foreach ($p in $presets) {
    $btnP = New-Object System.Windows.Forms.Button
    $btnP.Text = $p.text
    $btnP.Tag = $p
    $btnP.AutoSize = $true
    $btnP.Height = 25
    $btnP.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
    Apply-IOS27BtnStyle $btnP ([System.Drawing.Color]::FromArgb(32, 32, 48)) ([System.Drawing.Color]::FromArgb(50, 50, 75)) ([System.Drawing.Color]::FromArgb(220, 220, 240)) ([System.Drawing.Color]::FromArgb(60, 60, 85))
    $btnP.Add_Click({
        $tag = $this.Tag
        $txtTopic.Text = $tag.topic
        switch ($tag.theme) {
            "love" { $cmbTheme.SelectedIndex = 0 }
            "sad" { $cmbTheme.SelectedIndex = 1 }
            "mother" { $cmbTheme.SelectedIndex = 2 }
            "motivational" { $cmbTheme.SelectedIndex = 3 }
            "cafe" { $cmbTheme.SelectedIndex = 5 }
            "party" { $cmbTheme.SelectedIndex = 4 }
        }
    })
    $pnlPresets.Controls.Add($btnP)
}
$pnlLeft.Controls.Add($pnlPresets)
$y += 62

# Section: Theme / Mood
$lblTheme = New-Object System.Windows.Forms.Label
$lblTheme.Text = "🎭 ទម្រង់មនោសញ្ចេតនា (Theme / Mood):"
$lblTheme.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$lblTheme.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 220)
$lblTheme.Location = New-Object System.Drawing.Point(16, $y)
$lblTheme.Size = New-Object System.Drawing.Size(360, 20)
$pnlLeft.Controls.Add($lblTheme)
$y += 22

$cmbTheme = New-Object System.Windows.Forms.ComboBox
$cmbTheme.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbTheme.BackColor = [System.Drawing.Color]::FromArgb(26, 26, 38)
$cmbTheme.ForeColor = [System.Drawing.Color]::White
$cmbTheme.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbTheme.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$cmbTheme.Location = New-Object System.Drawing.Point(16, $y)
$cmbTheme.Size = New-Object System.Drawing.Size(360, 26)
$cmbTheme.Items.Add("💖 មនោសញ្ចេតនា ផ្អែមល្ហែម (Sweet Romance)") | Out-Null
$cmbTheme.Items.Add("💔 កំសត់ ស្រក់ទឹកភ្នែក បែកបាក់ (Heartbreak & Sad)") | Out-Null
$cmbTheme.Items.Add("🌾 នឹកម៉ែ នឹកផ្ទះ ស្រុកកំណើត (Mother & Homesick)") | Out-Null
$cmbTheme.Items.Add("🔥 លើកទឹកចិត្ត កម្លាំងចិត្តតស៊ូ (Motivational & Hope)") | Out-Null
$cmbTheme.Items.Add("💃 រាំកម្សាន្ត ចូលឆ្នាំខ្មែរ (Khmer New Year Party)") | Out-Null
$cmbTheme.Items.Add("☕ ស្ងប់ស្ងាត់ រសជាតិកាហ្វេរាត្រី (Midnight Cafe Mood)") | Out-Null
$cmbTheme.Items.Add("💍 ចម្រៀងមង្គលការ (Khmer Wedding & Pleng Kar)") | Out-Null
$cmbTheme.SelectedIndex = 0
$pnlLeft.Controls.Add($cmbTheme)
$y += 34

# Section: Genre & Style
$lblGenre = New-Object System.Windows.Forms.Label
$lblGenre.Text = "🎼 ចង្វាក់ និងស្ទីលបទភ្លេង (Music Genre):"
$lblGenre.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$lblGenre.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 220)
$lblGenre.Location = New-Object System.Drawing.Point(16, $y)
$lblGenre.Size = New-Object System.Drawing.Size(360, 20)
$pnlLeft.Controls.Add($lblGenre)
$y += 22

$cmbGenre = New-Object System.Windows.Forms.ComboBox
$cmbGenre.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbGenre.BackColor = [System.Drawing.Color]::FromArgb(26, 26, 38)
$cmbGenre.ForeColor = [System.Drawing.Color]::White
$cmbGenre.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbGenre.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$cmbGenre.Location = New-Object System.Drawing.Point(16, $y)
$cmbGenre.Size = New-Object System.Drawing.Size(360, 26)
$cmbGenre.Items.Add("🎵 Khmer Modern Pop (បទសម័យពេញនិយម)") | Out-Null
$cmbGenre.Items.Add("🎸 Romantic Acoustic Ballad (ហ្គីតា និងព្យាណូស្រទន់)") | Out-Null
$cmbGenre.Items.Add("🇰🇭 Traditional Fusion (ភ្លេងការ/រនាតឯក/ទ្រ/ខ្លុយ)") | Out-Null
$cmbGenre.Items.Add("⚡ High-Energy Drift Phonk (ចង្វាក់បាសធ្ងន់ កក្រើក)") | Out-Null
$cmbGenre.Items.Add("🎹 R&B Soul & Atmospheric Pads (បទអារម្មណ៍ជ្រៅ)") | Out-Null
$cmbGenre.Items.Add("☕ Chill Lo-Fi Acoustic Beats (ចង្វាក់ស្រាលស្រទន់)") | Out-Null
$cmbGenre.Items.Add("🥁 Epic Cinematic Rock (រ៉ក់ និងស្គរធំ)") | Out-Null
$cmbGenre.SelectedIndex = 0
$pnlLeft.Controls.Add($cmbGenre)
$y += 34

# Section: Vocal & Tempo row
$pnlVT = New-Object System.Windows.Forms.TableLayoutPanel
$pnlVT.Location = New-Object System.Drawing.Point(16, $y)
$pnlVT.Size = New-Object System.Drawing.Size(360, 52)
$pnlVT.RowCount = 2
$pnlVT.ColumnCount = 2
$pnlVT.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 55)))
$pnlVT.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 45)))

$lblVocal = New-Object System.Windows.Forms.Label
$lblVocal.Text = "🎤 សំឡេងច្រៀង (Vocals):"
$lblVocal.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$lblVocal.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 220)
$lblVocal.Dock = [System.Windows.Forms.DockStyle]::Fill

$lblTempo = New-Object System.Windows.Forms.Label
$lblTempo.Text = "⏱️ ល្បឿនភ្លេង (BPM):"
$lblTempo.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$lblTempo.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 220)
$lblTempo.Dock = [System.Windows.Forms.DockStyle]::Fill

$cmbVocal = New-Object System.Windows.Forms.ComboBox
$cmbVocal.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbVocal.BackColor = [System.Drawing.Color]::FromArgb(26, 26, 38)
$cmbVocal.ForeColor = [System.Drawing.Color]::White
$cmbVocal.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbVocal.Dock = [System.Windows.Forms.DockStyle]::Fill
$cmbVocal.Items.Add("ស្រី (Female Vocals)") | Out-Null
$cmbVocal.Items.Add("ប្រុស (Male Vocals)") | Out-Null
$cmbVocal.Items.Add("ឆ្លើយឆ្លង (Duet: Male & Female)") | Out-Null
$cmbVocal.Items.Add("ភ្លេងសុទ្ធ (Instrumental)") | Out-Null
$cmbVocal.SelectedIndex = 0

$cmbTempo = New-Object System.Windows.Forms.ComboBox
$cmbTempo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbTempo.BackColor = [System.Drawing.Color]::FromArgb(26, 26, 38)
$cmbTempo.ForeColor = [System.Drawing.Color]::White
$cmbTempo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbTempo.Dock = [System.Windows.Forms.DockStyle]::Fill
$cmbTempo.Items.Add("មធ្យម 88 BPM") | Out-Null
$cmbTempo.Items.Add("យឺត 72 BPM") | Out-Null
$cmbTempo.Items.Add("រហ័ស 124 BPM") | Out-Null
$cmbTempo.SelectedIndex = 0

$pnlVT.Controls.Add($lblVocal, 0, 0)
$pnlVT.Controls.Add($lblTempo, 1, 0)
$pnlVT.Controls.Add($cmbVocal, 0, 1)
$pnlVT.Controls.Add($cmbTempo, 1, 1)
$pnlLeft.Controls.Add($pnlVT)
$y += 58

# Section: Language Selector (ភាសានិពន្ធចម្រៀង គ្រប់ភាសាទាំងអស់)
$lblLang = New-Object System.Windows.Forms.Label
$lblLang.Text = "🌐 ភាសានិពន្ធអត្ថបទចម្រៀង (Song Language):"
$lblLang.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$lblLang.ForeColor = [System.Drawing.Color]::FromArgb(255, 170, 70)
$lblLang.Location = New-Object System.Drawing.Point(16, $y)
$lblLang.Size = New-Object System.Drawing.Size(360, 20)
$pnlLeft.Controls.Add($lblLang)
$y += 22

$cmbLang = New-Object System.Windows.Forms.ComboBox
$cmbLang.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbLang.BackColor = [System.Drawing.Color]::FromArgb(26, 26, 38)
$cmbLang.ForeColor = [System.Drawing.Color]::White
$cmbLang.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbLang.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$cmbLang.Location = New-Object System.Drawing.Point(16, $y)
$cmbLang.Size = New-Object System.Drawing.Size(360, 26)

$supportedLanguages = @(
    @{ Code = "km"; Name = "🇰🇭 ភាសាខ្មែរ (Khmer - Standard)"; Directive = "Khmer language (ភាសាខ្មែរ) with beautiful poetic Khmer vocabulary, idioms, and natural rhyme schemes"; TitleRule = 'A creative, catchy, and poetic song title in Khmer (can include English subtitle in parentheses, e.g. "ស្រមោលស្នេហ៍ (Shadow of Love)")'; VocalTag = "Khmer vocals" },
    @{ Code = "en"; Name = "🇬🇧 ភាសាអង់គ្លេស (English)"; Directive = "English language with catchy, natural, hit-maker English lyrics, memorable hooks, and deep emotion"; TitleRule = 'A creative, catchy, and hit-worthy song title in English'; VocalTag = "English vocals" },
    @{ Code = "zh"; Name = "🇨🇳 ភាសាចិន (Chinese - Mandarin)"; Directive = "Standard Mandarin Chinese (中文) with poetic, meaningful lyrics and beautiful phrasing"; TitleRule = 'A creative, poetic song title in Chinese (with English subtitle in parentheses)'; VocalTag = "Chinese vocals, Mandarin" },
    @{ Code = "ja"; Name = "🇯🇵 ភាសាជប៉ុន (Japanese)"; Directive = "Japanese language (日本語) with emotive, expressive J-Pop/Anime lyrical style with natural kanji/hiragana/katakana"; TitleRule = 'A creative, poetic song title in Japanese (with English or Romaji subtitle in parentheses)'; VocalTag = "Japanese vocals" },
    @{ Code = "ko"; Name = "🇰🇷 ភាសាកូរ៉េ (Korean)"; Directive = "Korean language (한국어) with catchy K-Pop / K-Ballad rhythm, style, and natural Hangul lyrics"; TitleRule = 'A creative, catchy song title in Korean (with English subtitle in parentheses)'; VocalTag = "Korean vocals" },
    @{ Code = "th"; Name = "🇹🇭 ភាសាថៃ (Thai)"; Directive = "Thai language (ภาษาไทย) with melodic and expressive Thai phrasing and natural rhyming"; TitleRule = 'A creative, melodic song title in Thai (with English subtitle in parentheses)'; VocalTag = "Thai vocals" },
    @{ Code = "vi"; Name = "🇻🇳 ភាសាវៀតណាម (Vietnamese)"; Directive = "Vietnamese language (Tiếng Việt) with poetic tones and expressive V-Pop songwriting"; TitleRule = 'A creative, poetic song title in Vietnamese (with English subtitle in parentheses)'; VocalTag = "Vietnamese vocals" },
    @{ Code = "fr"; Name = "🇫🇷 ភាសាបារាំង (French)"; Directive = "French language (Français) with romantic, poetic, and elegant French lyrics"; TitleRule = 'A creative, romantic song title in French'; VocalTag = "French vocals" },
    @{ Code = "es"; Name = "🇪🇸 ភាសាអេស្ប៉ាញ (Spanish)"; Directive = "Spanish language (Español) with passionate, rhythmic, and poetic Spanish lyrics"; TitleRule = 'A creative, passionate song title in Spanish'; VocalTag = "Spanish vocals" },
    @{ Code = "de"; Name = "🇩🇪 ភាសាអាល្លឺម៉ង់ (German)"; Directive = "German language (Deutsch) with expressive, rhythmic, and powerful German lyrical structure"; TitleRule = 'A creative, catchy song title in German'; VocalTag = "German vocals" },
    @{ Code = "it"; Name = "🇮🇹 ភាសាអ៊ីតាលី (Italian)"; Directive = "Italian language (Italiano) with melodic, passionate, and emotive Italian songwriting"; TitleRule = 'A creative, melodic song title in Italian'; VocalTag = "Italian vocals" },
    @{ Code = "ru"; Name = "🇷🇺 ភាសារុស្ស៊ី (Russian)"; Directive = "Russian language (Русский) with deep, atmospheric, and emotive Russian lyrics"; TitleRule = 'A creative, atmospheric song title in Russian'; VocalTag = "Russian vocals" },
    @{ Code = "hi"; Name = "🇮🇳 ភាសាហិណ្ឌូ (Hindi)"; Directive = "Hindi language (हिन्दी) with Bollywood / Indie melodic flair and emotive Hindi phrasing"; TitleRule = 'A creative, catchy song title in Hindi'; VocalTag = "Hindi vocals" },
    @{ Code = "km_en"; Name = "🌐 ខ្មែរ + អង់គ្លេស (Khmer & English Bilingual)"; Directive = "Bilingual Khmer & English mix (ភាសាខ្មែរលាយអង់គ្លេស) - blending catchy English chorus/hooks with emotional Khmer verses"; TitleRule = 'A bilingual Khmer & English title (e.g. "រាត្រីភ្នំពេញ (Phnom Penh Midnight)")'; VocalTag = "Khmer & English vocals" },
    @{ Code = "custom"; Name = "✏️ ភាសាផ្សេងៗ / ផ្ទាល់ខ្លួន (Custom Any Language...)"; Directive = "Custom language"; TitleRule = 'A creative song title in the specified language'; VocalTag = "Vocals" }
)

$selLangIdx = 0
for ($i = 0; $i -lt $supportedLanguages.Count; $i++) {
    [void]$cmbLang.Items.Add($supportedLanguages[$i].Name)
    if ($supportedLanguages[$i].Code -eq $config.language) {
        $selLangIdx = $i
    }
}
$cmbLang.SelectedIndex = $selLangIdx
$pnlLeft.Controls.Add($cmbLang)
$y += 30

$txtCustomLang = New-Object System.Windows.Forms.TextBox
$txtCustomLang.Location = New-Object System.Drawing.Point(16, $y)
$txtCustomLang.Size = New-Object System.Drawing.Size(360, 25)
$txtCustomLang.BackColor = [System.Drawing.Color]::FromArgb(26, 26, 38)
$txtCustomLang.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 100)
$txtCustomLang.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$txtCustomLang.Text = if ($config.customLanguage) { $config.customLanguage } else { "" }
$txtCustomLang.Visible = ($config.language -eq "custom")
$pnlLeft.Controls.Add($txtCustomLang)
if ($config.language -eq "custom") { $y += 30 }

$cmbLang.Add_SelectedIndexChanged({
    $curSel = $supportedLanguages[$cmbLang.SelectedIndex]
    $config.language = $curSel.Code
    if ($curSel.Code -eq "custom") {
        $txtCustomLang.Visible = $true
    } else {
        $txtCustomLang.Visible = $false
    }
    Save-Config
})

$txtCustomLang.Add_TextChanged({
    $config.customLanguage = $txtCustomLang.Text.Trim()
    Save-Config
})

# Section: AI Engine Selection
$geminiComposerModels = @(
    # ជំនាន់ ៣.x (Next-Gen & Flagship)
    @{ id = "gemini-3.1-flash-lite"; name = "Gemini 3.1 Flash-Lite (លឿនឆ្លាត សន្សំសំចៃ - ណែនាំ)" },
    @{ id = "gemini-3.1-pro-preview"; name = "Gemini 3.1 Pro Preview (កំពូលស្នាដៃតែងនិពន្ធ & កម្រិតច្នៃប្រឌិតខ្ពស់)" },
    @{ id = "gemini-3.5-flash"; name = "Gemini 3.5 Flash (ឆ្លាតវៃកម្រិតខ្ពស់ & ល្បឿនលឿន)" },
    @{ id = "gemini-3.0-flash"; name = "Gemini 3.0 Flash (Next-Gen Flash)" },

    # ជំនាន់ ២.៥ (Balanced & Production)
    @{ id = "gemini-2.5-flash"; name = "Gemini 2.5 Flash (រហ័សទាន់ចិត្ត និងមានតុល្យភាពល្អ)" },
    @{ id = "gemini-2.5-flash-lite"; name = "Gemini 2.5 Flash-Lite (ទម្ងន់ស្រាល និងរហ័សបំផុត)" },
    @{ id = "gemini-2.5-pro"; name = "Gemini 2.5 Pro (ជំនាញភាសាខ្មែរ និងតែងនិពន្ធស៊ីជម្រៅ)" },

    # ជំនាន់ ២.០ (Advanced Reasoning & Speed)
    @{ id = "gemini-2.0-flash"; name = "Gemini 2.0 Flash (ជំនាន់ឆ្លាតវៃល្បឿនលឿន)" },
    @{ id = "gemini-2.0-flash-lite"; name = "Gemini 2.0 Flash-Lite (កម្រិតស្រាល រហ័ស)" },
    @{ id = "gemini-2.0-flash-thinking-exp"; name = "Gemini 2.0 Flash Thinking (គិតស៊ីជម្រៅ)" },
    @{ id = "gemini-2.0-pro-exp-02-05"; name = "Gemini 2.0 Pro Experimental (កម្រិតសរសេរខ្ពស់)" },

    # ជំនាន់ ១.៥ & ១.០ (Classic & Foundation)
    @{ id = "gemini-1.5-flash"; name = "Gemini 1.5 Flash (រហ័សទាន់ចិត្ត Context ធំ)" },
    @{ id = "gemini-1.5-flash-8b"; name = "Gemini 1.5 Flash-8B (ខ្នាតតូច សន្សំសំចៃ)" },
    @{ id = "gemini-1.5-pro"; name = "Gemini 1.5 Pro (កម្លាំងគិតស៊ីជម្រៅ)" },
    @{ id = "gemini-1.0-pro"; name = "Gemini 1.0 Pro (ជំនាន់ដំបូងបង្អស់ Classic)" },

    # Local Engine
    @{ id = "smart_engine"; name = "⚡ Smart AI Engine (ដំណើរការ Offline គ្មាន Key)" }
)

$pnlEngine = New-Object System.Windows.Forms.Panel
$pnlEngine.Location = New-Object System.Drawing.Point(16, $y)
$pnlEngine.Size = New-Object System.Drawing.Size(360, 155)
$pnlEngine.BackColor = [System.Drawing.Color]::FromArgb(24, 22, 34)
$pnlEngine.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

$rbSmart = New-Object System.Windows.Forms.RadioButton
$rbSmart.Text = "⚡ Smart AI Engine (មិនបាច់ប្រើ API Key)"
$rbSmart.Checked = ($config.model -eq "smart_engine")
$rbSmart.Location = New-Object System.Drawing.Point(10, 6)
$rbSmart.Size = New-Object System.Drawing.Size(335, 20)
$rbSmart.ForeColor = [System.Drawing.Color]::FromArgb(110, 231, 183)
$rbSmart.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$pnlEngine.Controls.Add($rbSmart)

$rbGemini = New-Object System.Windows.Forms.RadioButton
$rbGemini.Text = "✨ Google Gemini AI (ជំនាន់ ១.០ ដល់ ៣.៥)"
$rbGemini.Checked = ($config.model -ne "smart_engine")
$rbGemini.Location = New-Object System.Drawing.Point(10, 28)
$rbGemini.Size = New-Object System.Drawing.Size(335, 20)
$rbGemini.ForeColor = [System.Drawing.Color]::FromArgb(196, 181, 253)
$rbGemini.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$pnlEngine.Controls.Add($rbGemini)

$lblModelTitle = New-Object System.Windows.Forms.Label
$lblModelTitle.Text = "🤖 ជំនាន់ Gemini (Auto-Bound):"
$lblModelTitle.ForeColor = [System.Drawing.Color]::FromArgb(167, 139, 250)
$lblModelTitle.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$lblModelTitle.Location = New-Object System.Drawing.Point(10, 52)
$lblModelTitle.Size = New-Object System.Drawing.Size(200, 18)
$pnlEngine.Controls.Add($lblModelTitle)

$cmbComposerModel = New-Object System.Windows.Forms.ComboBox
$cmbComposerModel.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbComposerModel.BackColor = [System.Drawing.Color]::FromArgb(32, 28, 44)
$cmbComposerModel.ForeColor = [System.Drawing.Color]::White
$cmbComposerModel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbComposerModel.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$cmbComposerModel.Location = New-Object System.Drawing.Point(10, 72)
$cmbComposerModel.Size = New-Object System.Drawing.Size(335, 24)
foreach ($m in $geminiComposerModels) {
    $cmbComposerModel.Items.Add($m.name) | Out-Null
}
$initCompIdx = 0
for ($i = 0; $i -lt $geminiComposerModels.Count; $i++) {
    if ($geminiComposerModels[$i].id -eq $config.model) {
        $initCompIdx = $i
        break
    }
}
$cmbComposerModel.SelectedIndex = $initCompIdx

$cmbComposerModel.Add_SelectedIndexChanged({
    $selIdx = $cmbComposerModel.SelectedIndex
    if ($selIdx -ge 0 -and $selIdx -lt $geminiComposerModels.Count) {
        $selectedCode = $geminiComposerModels[$selIdx].id
        $config.model = $selectedCode
        if ($selectedCode -eq "smart_engine") {
            $rbSmart.Checked = $true
        } else {
            $rbGemini.Checked = $true
        }
        Save-Config
        try {
            $qFile = Join-Path $sunoDir "song_queue.json"
            $qList = if (Test-Path $qFile) { Get-Content $qFile -Raw | ConvertFrom-Json } else { @() }
            if ($qList -isnot [System.Collections.IList]) { $qList = @($qList) }
            $qList += @{ action = "set_gemini_model"; model = $selectedCode; processed = $false }
            $qList | ConvertTo-Json -Depth 3 | Set-Content $qFile -Encoding UTF8
        } catch { }
    }
})
$pnlEngine.Controls.Add($cmbComposerModel)

$lblKeyHint = New-Object System.Windows.Forms.Label
$lblKeyHint.Text = "🔑 API Key:"
$lblKeyHint.ForeColor = [System.Drawing.Color]::FromArgb(156, 163, 175)
$lblKeyHint.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblKeyHint.Location = New-Object System.Drawing.Point(10, 102)
$lblKeyHint.Size = New-Object System.Drawing.Size(70, 18)
$pnlEngine.Controls.Add($lblKeyHint)

$txtApiKey = New-Object System.Windows.Forms.TextBox
$txtApiKey.Location = New-Object System.Drawing.Point(82, 100)
$txtApiKey.Size = New-Object System.Drawing.Size(263, 24)
$txtApiKey.BackColor = [System.Drawing.Color]::FromArgb(32, 28, 44)
$txtApiKey.ForeColor = [System.Drawing.Color]::White
$txtApiKey.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtApiKey.PasswordChar = '*'
if ($config.apiKey) {
    $txtApiKey.Text = $config.apiKey
} else {
    $txtApiKey.Text = ""
}
$pnlEngine.Controls.Add($txtApiKey)
$pnlLeft.Controls.Add($pnlEngine)
$y += 165

# Action Buttons (Style iOS 27)
$btnCompose = New-Object System.Windows.Forms.Button
$btnCompose.Text = "✨ បង្កើតបទចម្រៀង និង បទភ្លេងស្វ័យប្រវត្តិ (F5)"
$btnCompose.Location = New-Object System.Drawing.Point(16, $y)
$btnCompose.Size = New-Object System.Drawing.Size(360, 46)
$btnCompose.Font = New-Object System.Drawing.Font("Segoe UI", 11.5, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnCompose ([System.Drawing.Color]::FromArgb(255, 68, 51)) ([System.Drawing.Color]::FromArgb(255, 105, 85)) ([System.Drawing.Color]::White)
$pnlLeft.Controls.Add($btnCompose)
$y += 52

$btnAutoFill = New-Object System.Windows.Forms.Button
$btnAutoFill.Text = "⚡ បញ្ចូលទាំងអស់ទៅក្នុង Suno (Auto-Fill to Suno)"
$btnAutoFill.Location = New-Object System.Drawing.Point(16, $y)
$btnAutoFill.Size = New-Object System.Drawing.Size(360, 40)
$btnAutoFill.Font = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnAutoFill ([System.Drawing.Color]::FromArgb(16, 185, 129)) ([System.Drawing.Color]::FromArgb(52, 211, 153)) ([System.Drawing.Color]::White)
$pnlLeft.Controls.Add($btnAutoFill)
$y += 46

$btnOpenSuno = New-Object System.Windows.Forms.Button
$btnOpenSuno.Text = "🚀 បើកកម្មវិធី Suno Desktop"
$btnOpenSuno.Location = New-Object System.Drawing.Point(16, $y)
$btnOpenSuno.Size = New-Object System.Drawing.Size(360, 34)
$btnOpenSuno.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnOpenSuno ([System.Drawing.Color]::FromArgb(0, 122, 255)) ([System.Drawing.Color]::FromArgb(40, 145, 255)) ([System.Drawing.Color]::White)
$pnlLeft.Controls.Add($btnOpenSuno)
$y += 42

# 📁 PLAYLIST & BATCH SELECTION PANEL (10, 14, 18 Tracks)
$pnlPlaylist = New-Object System.Windows.Forms.Panel
$pnlPlaylist.Location = New-Object System.Drawing.Point(16, $y)
$pnlPlaylist.Size = New-Object System.Drawing.Size(360, 226)
$pnlPlaylist.BackColor = [System.Drawing.Color]::FromArgb(26, 20, 38)
$pnlPlaylist.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pnlPlaylist.Padding = New-Object System.Windows.Forms.Padding(10)

$lblPlTitle = New-Object System.Windows.Forms.Label
$lblPlTitle.Text = "📁 ជ្រើសរើសចម្រៀង & PLAYLIST:"
$lblPlTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblPlTitle.ForeColor = [System.Drawing.Color]::FromArgb(233, 213, 255)
$lblPlTitle.Location = New-Object System.Drawing.Point(8, 8)
$lblPlTitle.Size = New-Object System.Drawing.Size(240, 20)
$pnlPlaylist.Controls.Add($lblPlTitle)

$lblPlBadge = New-Object System.Windows.Forms.Label
$lblPlBadge.Text = "14 បទ"
$lblPlBadge.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$lblPlBadge.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
$lblPlBadge.Location = New-Object System.Drawing.Point(260, 8)
$lblPlBadge.Size = New-Object System.Drawing.Size(90, 18)
$lblPlBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$pnlPlaylist.Controls.Add($lblPlBadge)

# Preset buttons: 10, 14, 18, Clear (Style iOS 27)
$btnPl10 = New-Object System.Windows.Forms.Button
$btnPl10.Text = "☑️ 10 បទ"
$btnPl10.Location = New-Object System.Drawing.Point(8, 32)
$btnPl10.Size = New-Object System.Drawing.Size(80, 28)
$btnPl10.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnPl10 ([System.Drawing.Color]::FromArgb(40, 30, 65)) ([System.Drawing.Color]::FromArgb(70, 50, 110)) ([System.Drawing.Color]::FromArgb(196, 181, 253)) ([System.Drawing.Color]::FromArgb(80, 60, 130))
$pnlPlaylist.Controls.Add($btnPl10)

$btnPl14 = New-Object System.Windows.Forms.Button
$btnPl14.Text = "⭐ 14 បទ"
$btnPl14.Location = New-Object System.Drawing.Point(92, 32)
$btnPl14.Size = New-Object System.Drawing.Size(82, 28)
$btnPl14.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnPl14 ([System.Drawing.Color]::FromArgb(70, 30, 80)) ([System.Drawing.Color]::FromArgb(115, 45, 130)) ([System.Drawing.Color]::FromArgb(244, 114, 182)) ([System.Drawing.Color]::FromArgb(140, 60, 150))
$pnlPlaylist.Controls.Add($btnPl14)

$btnPl18 = New-Object System.Windows.Forms.Button
$btnPl18.Text = "☑️ 18 បទ"
$btnPl18.Location = New-Object System.Drawing.Point(178, 32)
$btnPl18.Size = New-Object System.Drawing.Size(80, 28)
$btnPl18.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnPl18 ([System.Drawing.Color]::FromArgb(30, 45, 75)) ([System.Drawing.Color]::FromArgb(45, 75, 130)) ([System.Drawing.Color]::FromArgb(147, 197, 253)) ([System.Drawing.Color]::FromArgb(60, 95, 160))
$pnlPlaylist.Controls.Add($btnPl18)

$btnPlClear = New-Object System.Windows.Forms.Button
$btnPlClear.Text = "🔄 ដោះ"
$btnPlClear.Location = New-Object System.Drawing.Point(262, 32)
$btnPlClear.Size = New-Object System.Drawing.Size(88, 28)
$btnPlClear.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
Apply-IOS27BtnStyle $btnPlClear ([System.Drawing.Color]::FromArgb(50, 25, 30)) ([System.Drawing.Color]::FromArgb(90, 35, 45)) ([System.Drawing.Color]::FromArgb(252, 165, 165)) ([System.Drawing.Color]::FromArgb(120, 45, 55))
$pnlPlaylist.Controls.Add($btnPlClear)

# Playlist Name Textbox + Smart Name Button
$txtPlName = New-Object System.Windows.Forms.TextBox
$txtPlName.Location = New-Object System.Drawing.Point(8, 68)
$txtPlName.Size = New-Object System.Drawing.Size(250, 25)
$txtPlName.Text = "Khmer Hits $(Get-Date -Format 'yyyy') (14 Tracks)"
$txtPlName.BackColor = [System.Drawing.Color]::FromArgb(16, 14, 24)
$txtPlName.ForeColor = [System.Drawing.Color]::White
$txtPlName.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pnlPlaylist.Controls.Add($txtPlName)

$btnPlSmart = New-Object System.Windows.Forms.Button
$btnPlSmart.Text = "✨ ថ្មី"
$btnPlSmart.Location = New-Object System.Drawing.Point(262, 67)
$btnPlSmart.Size = New-Object System.Drawing.Size(88, 26)
$btnPlSmart.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnPlSmart ([System.Drawing.Color]::FromArgb(124, 58, 237)) ([System.Drawing.Color]::FromArgb(167, 139, 250)) ([System.Drawing.Color]::White)
$pnlPlaylist.Controls.Add($btnPlSmart)

# Create & Add Button
$btnPlCreateAdd = New-Object System.Windows.Forms.Button
$btnPlCreateAdd.Text = "🚀 បង្កើត Playlist ថ្មី & Add ស្វ័យប្រវត្តិ"
$btnPlCreateAdd.Location = New-Object System.Drawing.Point(8, 102)
$btnPlCreateAdd.Size = New-Object System.Drawing.Size(342, 34)
$btnPlCreateAdd.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnPlCreateAdd ([System.Drawing.Color]::FromArgb(16, 185, 129)) ([System.Drawing.Color]::FromArgb(52, 211, 153)) ([System.Drawing.Color]::White)
$pnlPlaylist.Controls.Add($btnPlCreateAdd)

# Sibling Pair Cohesive Rename Button
$btnDedup = New-Object System.Windows.Forms.Button
$btnDedup.Text = "🪄 ប្តូរឈ្មោះបទភ្លោះ ដោយ AI"
$btnDedup.Location = New-Object System.Drawing.Point(8, 142)
$btnDedup.Size = New-Object System.Drawing.Size(342, 34)
$btnDedup.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnDedup ([System.Drawing.Color]::FromArgb(14, 116, 144)) ([System.Drawing.Color]::FromArgb(6, 182, 212)) ([System.Drawing.Color]::White)
$pnlPlaylist.Controls.Add($btnDedup)

# Playlist ZIP Downloader Button
$btnPlZipDl = New-Object System.Windows.Forms.Button
$btnPlZipDl.Text = "📦 ទាញយក Playlist ជា File ZIP"
$btnPlZipDl.Location = New-Object System.Drawing.Point(8, 182)
$btnPlZipDl.Size = New-Object System.Drawing.Size(342, 34)
$btnPlZipDl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnPlZipDl ([System.Drawing.Color]::FromArgb(234, 88, 12)) ([System.Drawing.Color]::FromArgb(251, 146, 60)) ([System.Drawing.Color]::White)
$btnPlZipDl.Add_Click({
    $plLauncher = Join-Path $sunoDir "SunoPlaylistDownloaderLauncher.vbs"
    Start-Process "wscript.exe" -ArgumentList "`"$plLauncher`""
})
$pnlPlaylist.Controls.Add($btnPlZipDl)

$pnlLeft.Controls.Add($pnlPlaylist)
$y += 236

# ⏱️ SONG DURATION PANEL (កំណត់នាទីចម្រៀង)
$pnlDuration = New-Object System.Windows.Forms.Panel
$pnlDuration.Location = New-Object System.Drawing.Point(16, $y)
$pnlDuration.Size = New-Object System.Drawing.Size(360, 108)
$pnlDuration.BackColor = [System.Drawing.Color]::FromArgb(26, 20, 38)
$pnlDuration.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pnlDuration.Padding = New-Object System.Windows.Forms.Padding(10)

$lblDurTitle = New-Object System.Windows.Forms.Label
$lblDurTitle.Text = "⏱️ កំណត់នាទីចម្រៀង (Song Duration):"
$lblDurTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblDurTitle.ForeColor = [System.Drawing.Color]::FromArgb(233, 213, 255)
$lblDurTitle.Location = New-Object System.Drawing.Point(8, 8)
$lblDurTitle.Size = New-Object System.Drawing.Size(240, 20)
$pnlDuration.Controls.Add($lblDurTitle)

$lblDurBadge = New-Object System.Windows.Forms.Label
$lblDurBadge.Text = "⚡ Auto"
$lblDurBadge.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$lblDurBadge.ForeColor = [System.Drawing.Color]::FromArgb(165, 180, 252)
$lblDurBadge.Location = New-Object System.Drawing.Point(250, 8)
$lblDurBadge.Size = New-Object System.Drawing.Size(100, 18)
$lblDurBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$pnlDuration.Controls.Add($lblDurBadge)

# Preset buttons: Auto, 2m, 3m, 4m, 5m, 6m (Style iOS 27)
$btnDurAuto = New-Object System.Windows.Forms.Button
$btnDurAuto.Text = "⚡ Auto"
$btnDurAuto.Location = New-Object System.Drawing.Point(8, 32)
$btnDurAuto.Size = New-Object System.Drawing.Size(54, 28)
$btnDurAuto.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnDurAuto ([System.Drawing.Color]::FromArgb(40, 40, 55)) ([System.Drawing.Color]::FromArgb(65, 65, 90)) ([System.Drawing.Color]::FromArgb(226, 232, 240)) ([System.Drawing.Color]::FromArgb(75, 75, 105))
$pnlDuration.Controls.Add($btnDurAuto)

$btnDur2m = New-Object System.Windows.Forms.Button
$btnDur2m.Text = "2 នាទី"
$btnDur2m.Location = New-Object System.Drawing.Point(65, 32)
$btnDur2m.Size = New-Object System.Drawing.Size(54, 28)
$btnDur2m.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnDur2m ([System.Drawing.Color]::FromArgb(40, 30, 65)) ([System.Drawing.Color]::FromArgb(70, 50, 110)) ([System.Drawing.Color]::FromArgb(196, 181, 253)) ([System.Drawing.Color]::FromArgb(80, 60, 130))
$pnlDuration.Controls.Add($btnDur2m)

$btnDur3m = New-Object System.Windows.Forms.Button
$btnDur3m.Text = "⭐ 3 នាទី"
$btnDur3m.Location = New-Object System.Drawing.Point(122, 32)
$btnDur3m.Size = New-Object System.Drawing.Size(58, 28)
$btnDur3m.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnDur3m ([System.Drawing.Color]::FromArgb(70, 30, 80)) ([System.Drawing.Color]::FromArgb(115, 45, 130)) ([System.Drawing.Color]::FromArgb(244, 114, 182)) ([System.Drawing.Color]::FromArgb(140, 60, 150))
$pnlDuration.Controls.Add($btnDur3m)

$btnDur4m = New-Object System.Windows.Forms.Button
$btnDur4m.Text = "4 នាទី"
$btnDur4m.Location = New-Object System.Drawing.Point(183, 32)
$btnDur4m.Size = New-Object System.Drawing.Size(54, 28)
$btnDur4m.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnDur4m ([System.Drawing.Color]::FromArgb(30, 45, 75)) ([System.Drawing.Color]::FromArgb(45, 75, 130)) ([System.Drawing.Color]::FromArgb(147, 197, 253)) ([System.Drawing.Color]::FromArgb(60, 95, 160))
$pnlDuration.Controls.Add($btnDur4m)

$btnDur5m = New-Object System.Windows.Forms.Button
$btnDur5m.Text = "5 នាទី"
$btnDur5m.Location = New-Object System.Drawing.Point(240, 32)
$btnDur5m.Size = New-Object System.Drawing.Size(54, 28)
$btnDur5m.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnDur5m ([System.Drawing.Color]::FromArgb(20, 50, 40)) ([System.Drawing.Color]::FromArgb(30, 85, 65)) ([System.Drawing.Color]::FromArgb(110, 231, 183)) ([System.Drawing.Color]::FromArgb(40, 110, 85))
$pnlDuration.Controls.Add($btnDur5m)

$btnDur6m = New-Object System.Windows.Forms.Button
$btnDur6m.Text = "🔥 6 នាទី"
$btnDur6m.Location = New-Object System.Drawing.Point(297, 32)
$btnDur6m.Size = New-Object System.Drawing.Size(55, 28)
$btnDur6m.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnDur6m ([System.Drawing.Color]::FromArgb(60, 20, 40)) ([System.Drawing.Color]::FromArgb(105, 30, 65)) ([System.Drawing.Color]::FromArgb(244, 114, 182)) ([System.Drawing.Color]::FromArgb(135, 40, 80))
$pnlDuration.Controls.Add($btnDur6m)

# Custom duration input row
$txtDurCustom = New-Object System.Windows.Forms.TextBox
$txtDurCustom.Location = New-Object System.Drawing.Point(8, 68)
$txtDurCustom.Size = New-Object System.Drawing.Size(220, 25)
$txtDurCustom.Text = "3:00"
$txtDurCustom.BackColor = [System.Drawing.Color]::FromArgb(16, 14, 24)
$txtDurCustom.ForeColor = [System.Drawing.Color]::White
$txtDurCustom.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$pnlDuration.Controls.Add($txtDurCustom)

$btnDurApply = New-Object System.Windows.Forms.Button
$btnDurApply.Text = "⏱️ កំណត់នាទី"
$btnDurApply.Location = New-Object System.Drawing.Point(232, 67)
$btnDurApply.Size = New-Object System.Drawing.Size(120, 26)
$btnDurApply.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnDurApply ([System.Drawing.Color]::FromArgb(147, 51, 234)) ([System.Drawing.Color]::FromArgb(168, 85, 247)) ([System.Drawing.Color]::White)
$pnlDuration.Controls.Add($btnDurApply)

$pnlLeft.Controls.Add($pnlDuration)
$y += 118

# RIGHT PANEL: Outputs (Title, Style, Lyrics)
$pnlRight = New-Object System.Windows.Forms.Panel
$pnlRight.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlRight.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 22)
$pnlRight.Padding = New-Object System.Windows.Forms.Padding(18, 14, 18, 14)
$bodySplit.Panel2.Controls.Add($pnlRight)

$ry = 10

# 1. Title Section
$lblOutTitle = New-Object System.Windows.Forms.Label
$lblOutTitle.Text = "🏷️ ចំណងជើងបទចម្រៀង (Song Title):"
$lblOutTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblOutTitle.ForeColor = [System.Drawing.Color]::FromArgb(196, 181, 253)
$lblOutTitle.Location = New-Object System.Drawing.Point(18, $ry)
$lblOutTitle.Size = New-Object System.Drawing.Size(300, 20)
$pnlRight.Controls.Add($lblOutTitle)

$btnCopyTitle = New-Object System.Windows.Forms.Button
$btnCopyTitle.Text = "📋 Copy Title"
$btnCopyTitle.Location = New-Object System.Drawing.Point(520, $ry - 2)
$btnCopyTitle.Size = New-Object System.Drawing.Size(95, 24)
$btnCopyTitle.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnCopyTitle.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
Apply-IOS27BtnStyle $btnCopyTitle ([System.Drawing.Color]::FromArgb(35, 30, 48)) ([System.Drawing.Color]::FromArgb(65, 55, 90)) ([System.Drawing.Color]::FromArgb(216, 180, 254)) ([System.Drawing.Color]::FromArgb(85, 70, 120))
$pnlRight.Controls.Add($btnCopyTitle)
$ry += 24

$txtOutTitle = New-Object System.Windows.Forms.TextBox
$txtOutTitle.Location = New-Object System.Drawing.Point(18, $ry)
$txtOutTitle.Size = New-Object System.Drawing.Size(595, 30)
$txtOutTitle.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$txtOutTitle.BackColor = [System.Drawing.Color]::FromArgb(24, 20, 36)
$txtOutTitle.ForeColor = [System.Drawing.Color]::FromArgb(250, 245, 255)
$txtOutTitle.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtOutTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12.0, [System.Drawing.FontStyle]::Bold)
$pnlRight.Controls.Add($txtOutTitle)
$ry += 38

# Alternative Titles Chip Panel
$pnlAltTitles = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlAltTitles.Location = New-Object System.Drawing.Point(18, $ry)
$pnlAltTitles.Size = New-Object System.Drawing.Size(595, 36)
$pnlAltTitles.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$pnlAltTitles.BackColor = [System.Drawing.Color]::Transparent
$pnlRight.Controls.Add($pnlAltTitles)
$ry += 42

# 2. Style Prompt Section
$lblOutStyle = New-Object System.Windows.Forms.Label
$lblOutStyle.Text = "🎼 ស្ទីលបទភ្លេង Suno (Style Prompt):"
$lblOutStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblOutStyle.ForeColor = [System.Drawing.Color]::FromArgb(147, 197, 253)
$lblOutStyle.Location = New-Object System.Drawing.Point(18, $ry)
$lblOutStyle.Size = New-Object System.Drawing.Size(300, 20)
$pnlRight.Controls.Add($lblOutStyle)

$btnCopyStyle = New-Object System.Windows.Forms.Button
$btnCopyStyle.Text = "📋 Copy Style"
$btnCopyStyle.Location = New-Object System.Drawing.Point(520, $ry - 2)
$btnCopyStyle.Size = New-Object System.Drawing.Size(95, 24)
$btnCopyStyle.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnCopyStyle.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
Apply-IOS27BtnStyle $btnCopyStyle ([System.Drawing.Color]::FromArgb(24, 34, 52)) ([System.Drawing.Color]::FromArgb(45, 65, 100)) ([System.Drawing.Color]::FromArgb(147, 197, 253)) ([System.Drawing.Color]::FromArgb(55, 80, 125))
$pnlRight.Controls.Add($btnCopyStyle)
$ry += 24

$txtOutStyle = New-Object System.Windows.Forms.TextBox
$txtOutStyle.Multiline = $true
$txtOutStyle.Location = New-Object System.Drawing.Point(18, $ry)
$txtOutStyle.Size = New-Object System.Drawing.Size(595, 52)
$txtOutStyle.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$txtOutStyle.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 36)
$txtOutStyle.ForeColor = [System.Drawing.Color]::FromArgb(224, 242, 254)
$txtOutStyle.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtOutStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$pnlRight.Controls.Add($txtOutStyle)
$ry += 60

# 3. Lyrics Section
$lblOutLyrics = New-Object System.Windows.Forms.Label
$lblOutLyrics.Text = "📝 ទំនុកច្រៀងពេញលេញ (Khmer Lyrics):"
$lblOutLyrics.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblOutLyrics.ForeColor = [System.Drawing.Color]::FromArgb(110, 231, 183)
$lblOutLyrics.Location = New-Object System.Drawing.Point(18, $ry)
$lblOutLyrics.Size = New-Object System.Drawing.Size(300, 20)
$pnlRight.Controls.Add($lblOutLyrics)

$btnCopyLyrics = New-Object System.Windows.Forms.Button
$btnCopyLyrics.Text = "📋 Copy Lyrics"
$btnCopyLyrics.Location = New-Object System.Drawing.Point(520, $ry - 2)
$btnCopyLyrics.Size = New-Object System.Drawing.Size(95, 24)
$btnCopyLyrics.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnCopyLyrics.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
Apply-IOS27BtnStyle $btnCopyLyrics ([System.Drawing.Color]::FromArgb(20, 40, 32)) ([System.Drawing.Color]::FromArgb(35, 75, 60)) ([System.Drawing.Color]::FromArgb(110, 231, 183)) ([System.Drawing.Color]::FromArgb(45, 95, 75))
$pnlRight.Controls.Add($btnCopyLyrics)
$ry += 24

$txtOutLyrics = New-Object System.Windows.Forms.TextBox
$txtOutLyrics.Multiline = $true
$txtOutLyrics.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtOutLyrics.Location = New-Object System.Drawing.Point(18, $ry)
$txtOutLyrics.Size = New-Object System.Drawing.Size(595, ($pnlRight.Height - $ry - 14))
$txtOutLyrics.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$txtOutLyrics.BackColor = [System.Drawing.Color]::FromArgb(18, 22, 28)
$txtOutLyrics.ForeColor = [System.Drawing.Color]::FromArgb(240, 253, 244)
$txtOutLyrics.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtOutLyrics.Font = New-Object System.Drawing.Font("Segoe UI", 10.5)
$pnlRight.Controls.Add($txtOutLyrics)

# 3. FOOTER
$footer = New-Object System.Windows.Forms.Panel
$footer.Dock = [System.Windows.Forms.DockStyle]::Fill
$footer.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 28)
$footer.Padding = New-Object System.Windows.Forms.Padding(20, 8, 20, 8)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "🟢 ត្រៀមរួចរាល់ (Ready)"
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblStatus.Location = New-Object System.Drawing.Point(20, 14)
$lblStatus.AutoSize = $true
$footer.Controls.Add($lblStatus)

$btnClearFields = New-Object System.Windows.Forms.Button
$btnClearFields.Text = "🗑️ លុប"
$btnClearFields.Location = New-Object System.Drawing.Point(420, 10)
$btnClearFields.Size = New-Object System.Drawing.Size(80, 32)
$btnClearFields.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
Apply-IOS27BtnStyle $btnClearFields ([System.Drawing.Color]::FromArgb(45, 25, 30)) ([System.Drawing.Color]::FromArgb(85, 35, 45)) ([System.Drawing.Color]::FromArgb(252, 165, 165)) ([System.Drawing.Color]::FromArgb(110, 45, 55))
$footer.Controls.Add($btnClearFields)

$btnAutoLoop = New-Object System.Windows.Forms.Button
$btnAutoLoop.Text = "🔁 វិលជុំស្វ័យប្រវត្តិ"
$btnAutoLoop.Location = New-Object System.Drawing.Point(510, 10)
$btnAutoLoop.Size = New-Object System.Drawing.Size(150, 32)
$btnAutoLoop.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnAutoLoop.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnAutoLoop ([System.Drawing.Color]::FromArgb(76, 29, 149)) ([System.Drawing.Color]::FromArgb(124, 58, 237)) ([System.Drawing.Color]::FromArgb(245, 243, 255))
$footer.Controls.Add($btnAutoLoop)

$btnSaveTxt = New-Object System.Windows.Forms.Button
$btnSaveTxt.Text = "💾 រក្សាទុក (.txt)"
$btnSaveTxt.Location = New-Object System.Drawing.Point(670, 10)
$btnSaveTxt.Size = New-Object System.Drawing.Size(110, 32)
$btnSaveTxt.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
Apply-IOS27BtnStyle $btnSaveTxt ([System.Drawing.Color]::FromArgb(35, 35, 48)) ([System.Drawing.Color]::FromArgb(65, 65, 88)) ([System.Drawing.Color]::White) ([System.Drawing.Color]::FromArgb(75, 75, 100))
$footer.Controls.Add($btnSaveTxt)

$btnCopyAll = New-Object System.Windows.Forms.Button
$btnCopyAll.Text = "📋 Copy ទាំងអស់"
$btnCopyAll.Location = New-Object System.Drawing.Point(790, 10)
$btnCopyAll.Size = New-Object System.Drawing.Size(115, 32)
$btnCopyAll.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
Apply-IOS27BtnStyle $btnCopyAll ([System.Drawing.Color]::FromArgb(40, 35, 60)) ([System.Drawing.Color]::FromArgb(75, 65, 115)) ([System.Drawing.Color]::FromArgb(216, 180, 254)) ([System.Drawing.Color]::FromArgb(90, 75, 135))
$footer.Controls.Add($btnCopyAll)

$btnSendBottom = New-Object System.Windows.Forms.Button
$btnSendBottom.Text = "⚡ បញ្ចូលទៅ Suno"
$btnSendBottom.Location = New-Object System.Drawing.Point(915, 10)
$btnSendBottom.Size = New-Object System.Drawing.Size(145, 32)
$btnSendBottom.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnSendBottom.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
Apply-IOS27BtnStyle $btnSendBottom ([System.Drawing.Color]::FromArgb(16, 185, 129)) ([System.Drawing.Color]::FromArgb(52, 211, 153)) ([System.Drawing.Color]::White)
$footer.Controls.Add($btnSendBottom)
$root.Controls.Add($footer, 0, 2)

# --- HELPER FUNCTIONS ---
function Render-AltTitleChips($titles) {
    $pnlAltTitles.Controls.Clear()
    foreach ($t in $titles) {
        $btnChip = New-Object System.Windows.Forms.Button
        $btnChip.Text = "💡 $t"
        $btnChip.Tag = $t
        $btnChip.AutoSize = $true
        $btnChip.Height = 26
        $btnChip.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
        Apply-IOS27BtnStyle $btnChip ([System.Drawing.Color]::FromArgb(32, 28, 46)) ([System.Drawing.Color]::FromArgb(65, 55, 95)) ([System.Drawing.Color]::FromArgb(220, 210, 245)) ([System.Drawing.Color]::FromArgb(70, 60, 95))
        $btnChip.Add_Click({
            $txtOutTitle.Text = $this.Tag
            $lblStatus.Text = "✓ បានប្តូរចំណងជើងជា៖ `"$($this.Tag)`""
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(196, 181, 253)
        })
        $pnlAltTitles.Controls.Add($btnChip)
    }
}

function Do-Compose {
    $lblStatus.Text = "⏳ កំពុងតែងនិពន្ធបទចម្រៀង និង បទភ្លេងថ្មី..."
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 50)
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    [System.Windows.Forms.Application]::DoEvents()

    $themeKeys = @("love", "sad", "mother", "motivational", "party", "cafe", "wedding")
    $genreKeys = @("pop", "acoustic", "traditional", "phonk", "rnb", "lofi", "rock")
    $vocalTexts = @("female", "male", "duet", "instrumental")
    $tempoKeys = @("moderate", "slow", "fast")

    $selTheme = $themeKeys[$cmbTheme.SelectedIndex]
    $selGenre = $genreKeys[$cmbGenre.SelectedIndex]
    $selVocal = $vocalTexts[$cmbVocal.SelectedIndex]
    $selTempo = $tempoKeys[$cmbTempo.SelectedIndex]
    $userTopic = $txtTopic.Text.Trim()

    $songResult = $null
    $apiKey = $txtApiKey.Text.Trim()
    $useGemini = $rbGemini.Checked -and $apiKey

    $selLangObj = $supportedLanguages[$cmbLang.SelectedIndex]
    $customLangName = $txtCustomLang.Text.Trim()

    if ($useGemini) {
        try {
            $config.apiKey = $apiKey
            Save-Config
            $songResult = Compose-WithGemini $apiKey $config.model $userTopic $cmbTheme.Text $cmbGenre.Text $selVocal $selTempo $selLangObj $customLangName
            $lblStatus.Text = "✨ Gemini 3.1 បាននិពន្ធបទចម្រៀង ($($selLangObj.Name)) រួចរាល់!"
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(196, 181, 253)
        } catch {
            $lblStatus.Text = "⚠️ Gemini API រវល់... កំពុងប្រើប្រាស់ Smart AI Engine..."
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(251, 146, 60)
            [System.Windows.Forms.Application]::DoEvents()
            $songResult = Get-SmartKhmerSong $userTopic $selTheme $selGenre $selVocal $selTempo
        }
    } else {
        $songResult = Get-SmartKhmerSong $userTopic $selTheme $selGenre $selVocal $selTempo
        $lblStatus.Text = "✓ Smart AI Engine បាននិពន្ធបទចម្រៀង ($($selLangObj.Name)) រួចរាល់!"
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
    }

    $form.Cursor = [System.Windows.Forms.Cursors]::Default

    if ($songResult) {
        $txtOutTitle.Text = $songResult.title
        $txtOutStyle.Text = $songResult.style
        $txtOutLyrics.Text = $songResult.lyrics
        Render-AltTitleChips $songResult.alternativeTitles
    }
}

function Do-AutoFillToSuno {
    $title = $txtOutTitle.Text.Trim()
    $style = $txtOutStyle.Text.Trim()
    $lyrics = Clean-DuplicateLyrics $txtOutLyrics.Text.Trim()

    if (-not $lyrics -or -not $style) {
        [System.Windows.Forms.MessageBox]::Show("សូមចុចបង្កើតបទចម្រៀងជាមុនសិន មុនពេលបញ្ចូលទៅ Suno!", "ព័ត៌មាន", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    # 1. Set Windows Clipboard
    try {
        [System.Windows.Forms.Clipboard]::SetText($lyrics)
    } catch { }

    # 2. Append to song_queue.json
    try {
        $qList = [System.Collections.Generic.List[object]]::new()
        if (Test-Path $songQueueFile) {
            $raw = Get-Content $songQueueFile -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                $parsed = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($parsed -is [System.Array]) {
                    foreach ($it in $parsed) { $qList.Add($it) }
                } elseif ($null -ne $parsed) {
                    $qList.Add($parsed)
                }
            }
        }
        $qList.Add(@{
            title = $title
            style = $style
            lyrics = $lyrics
            timestamp = [DateTime]::UtcNow.Ticks
            processed = $false
        })
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false); [System.IO.File]::WriteAllText($songQueueFile, (ConvertTo-JsonArray $qList), $utf8NoBom)
    } catch { }

    # 3. Check Suno window and bring to front
    $sunoHwnd = [Win32Composer]::FindSunoWindow()
    if ($sunoHwnd -ne [IntPtr]::Zero) {
        [Win32Composer]::ShowWindow($sunoHwnd, 9)
        [Win32Composer]::SetForegroundWindow($sunoHwnd)
        $lblStatus.Text = "⚡ បានបញ្ចូល Title, Style, Lyrics ទៅក្នុង Suno រួចរាល់!"
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
    } else {
        # Launch Suno
        $sunoBat = Join-Path $sunoDir "Suno.bat"
        if (Test-Path $sunoBat) {
            Start-Process $sunoBat
            $lblStatus.Text = "🚀 កំពុងបើក Suno Desktop... ទិន្នន័យនឹងត្រូវបញ្ចូលដោយស្វ័យប្រវត្តិ!"
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(147, 197, 253)
        } else {
            $lblStatus.Text = "⚡ បានរក្សាទុកក្នុង Queue (សូមបើក Suno ដើម្បីទទួល)"
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(250, 204, 21)
        }
    }
}

function Send-SongQueueAction($actionObj) {
    try {
        $qList = [System.Collections.Generic.List[object]]::new()
        if (Test-Path $songQueueFile) {
            $raw = Get-Content $songQueueFile -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                $parsed = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($parsed -is [System.Array]) {
                    foreach ($it in $parsed) { $qList.Add($it) }
                } elseif ($null -ne $parsed) {
                    $qList.Add($parsed)
                }
            }
        }
        $actionObj["timestamp"] = [DateTime]::UtcNow.Ticks
        $actionObj["processed"] = $false
        $qList.Add($actionObj)
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false); [System.IO.File]::WriteAllText($songQueueFile, (ConvertTo-JsonArray $qList), $utf8NoBom)
    } catch { }

    $sunoHwnd = [Win32Composer]::FindSunoWindow()
    if ($sunoHwnd -ne [IntPtr]::Zero) {
        [Win32Composer]::ShowWindow($sunoHwnd, 9)
        [Win32Composer]::SetForegroundWindow($sunoHwnd)
    } else {
        $sunoBat = Join-Path $sunoDir "Suno.bat"
        if (Test-Path $sunoBat) { Start-Process $sunoBat }
    }
}

# --- EVENT HANDLERS ---
$btnCompose.Add_Click({ Do-Compose })
$btnAutoFill.Add_Click({ Do-AutoFillToSuno })
$btnSendBottom.Add_Click({ Do-AutoFillToSuno })

$btnClearFields.Add_Click({
    $txtOutTitle.Text = ""
    $txtOutStyle.Text = ""
    $txtOutLyrics.Text = ""
    $pnlAltTitles.Controls.Clear()
    try {
        $qList = [System.Collections.Generic.List[object]]::new()
        if (Test-Path $songQueueFile) {
            $raw = Get-Content $songQueueFile -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                $parsed = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($parsed -is [System.Array]) {
                    foreach ($it in $parsed) { $qList.Add($it) }
                } elseif ($null -ne $parsed) {
                    $qList.Add($parsed)
                }
            }
        }
        $qList.Add(@{
            action = "clear"
            timestamp = [DateTime]::UtcNow.Ticks
            processed = $false
        })
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false); [System.IO.File]::WriteAllText($songQueueFile, (ConvertTo-JsonArray $qList), $utf8NoBom)
    } catch { }
    $lblStatus.Text = "🗑️ បានលុបសម្អាត Lyrics, Styles, និង Song Title រួចរាល់!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(252, 165, 165)
})

$btnAutoLoop.Add_Click({
    try {
        $qList = [System.Collections.Generic.List[object]]::new()
        if (Test-Path $songQueueFile) {
            $raw = Get-Content $songQueueFile -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                $parsed = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($parsed -is [System.Array]) {
                    foreach ($it in $parsed) { $qList.Add($it) }
                } elseif ($null -ne $parsed) {
                    $qList.Add($parsed)
                }
            }
        }
        $qList.Add(@{
            action = "toggle_auto_loop"
            timestamp = [DateTime]::UtcNow.Ticks
            processed = $false
        })
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false); [System.IO.File]::WriteAllText($songQueueFile, (ConvertTo-JsonArray $qList), $utf8NoBom)
    } catch { }

    $sunoHwnd = [Win32Composer]::FindSunoWindow()
    if ($sunoHwnd -ne [IntPtr]::Zero) {
        [Win32Composer]::ShowWindow($sunoHwnd, 9)
        [Win32Composer]::SetForegroundWindow($sunoHwnd)
    } else {
        $sunoBat = Join-Path $sunoDir "Suno.bat"
        if (Test-Path $sunoBat) { Start-Process $sunoBat }
    }
    $lblStatus.Text = "🔁 បានបើកដំណើរការ Auto-Loop Producer ក្នុង Suno Desktop!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(196, 181, 253)
})

# Playlist & Batch Selection Handlers
$global:targetPlaylistCount = 14

function Get-SmartPlaylistName([int]$count = 14) {
    $yr = (Get-Date).Year
    $mo = (Get-Date).ToString("MMM")
    $randNum = Get-Random -Minimum 1 -Maximum 99
    $volStr = "{0:D2}" -f $randNum
    $opts = @(
        "ស្នេហាក្នុងរាត្រីភ្នំពេញ (Phnom Penh Night Hits) [$count Tracks]",
        "បណ្តុំចម្រៀង Drift Phonk & Bass $yr (Vol. $volStr) [$count Tracks]",
        "អនុស្សាវរីយ៍ជ្រោះស្នេហ៍ (Acoustic Romance $yr) [$count Tracks]",
        "Suno Khmer Masterpiece · កម្រងចម្រៀងកំពូលស្នាដៃ [$count Tracks]",
        "ចង្វាក់រាំញាក់កន្ត្រាក់អារម្មណ៍ (EDM Club Festival) [$count Tracks]",
        "KH-Hits Master Collection (Vol. $volStr) [$count Tracks]",
        "មន្តស្នេហ៍តន្ត្រីសម័យថ្មី $yr (Khmer Wave) [$count Tracks]",
        "បំភ្លេចមិនបាន (Unforgettable Melodies $yr) [$count Tracks]",
        "រាត្រីស្រវឹងស្នេហ៍ (Late Night Chill R&B) [$count Tracks]",
        "មរតកសំនៀងថ្មី $yr · Suno Pro Edition [$count Tracks]",
        "បទចម្រៀងកំដរអារម្មណ៍ (Deep Soul & Coffee Vibes) [$count Tracks]",
        "សំឡេងរាត្រីកម្ពុជា (Cambodian Midnight Beats) [$count Tracks]",
        "ស្នេហ៍វ័យជំទង់ (Romantic Pop Melodies) [$count Tracks]",
        "បណ្តុំចម្រៀងពេញនិយមប្រចាំខែ $mo $yr [$count Tracks]",
        "បទភ្លេងកន្ត្រាក់បេះដូង (High Energy Phonk & Synth) [$count Tracks]",
        "ភ្លេងមនោសញ្ចេតនាស្នេហ៍ជ្រាលជ្រៅ (Deep Emotional Acoustic) [$count Tracks]",
        "សំនៀងពិរោះរណ្តំ (Khmer Golden Soul $yr) [$count Tracks]",
        "ដំណើរឆ្លងកាត់រាត្រី (Night Cruise Phonk) [$count Tracks]"
    )
    return $opts[(Get-Random -Maximum $opts.Length)]
}

$btnPl10.Add_Click({
    $global:targetPlaylistCount = 10
    $lblPlBadge.Text = "10 បទ"
    $lblPlBadge.ForeColor = [System.Drawing.Color]::FromArgb(196, 181, 253)
    $txtPlName.Text = Get-SmartPlaylistName 10
    $btnPlCreateAdd.Text = "🚀 Add ចូល Playlist តែម្តង (10 បទ)"
    Send-SongQueueAction @{ action = "select_batch_songs"; count = 10 }
    $lblStatus.Text = "☑️ កំពុងធិកជ្រើសរើសចម្រៀងឱ្យគ្រប់ 10 បទក្នុង Suno..."
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(196, 181, 253)
})

$btnPl14.Add_Click({
    $global:targetPlaylistCount = 14
    $lblPlBadge.Text = "14 បទ"
    $lblPlBadge.ForeColor = [System.Drawing.Color]::FromArgb(244, 114, 182)
    $txtPlName.Text = Get-SmartPlaylistName 14
    $btnPlCreateAdd.Text = "🚀 Add ចូល Playlist តែម្តង (14 បទ)"
    Send-SongQueueAction @{ action = "select_batch_songs"; count = 14 }
    $lblStatus.Text = "⭐ កំពុងធិកជ្រើសរើសចម្រៀងឱ្យគ្រប់ 14 បទ (ស្តង់ដារ) ក្នុង Suno..."
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(244, 114, 182)
})

$btnPl18.Add_Click({
    $global:targetPlaylistCount = 18
    $lblPlBadge.Text = "18 បទ"
    $lblPlBadge.ForeColor = [System.Drawing.Color]::FromArgb(147, 197, 253)
    $txtPlName.Text = Get-SmartPlaylistName 18
    $btnPlCreateAdd.Text = "🚀 Add ចូល Playlist តែម្តង (18 បទ)"
    Send-SongQueueAction @{ action = "select_batch_songs"; count = 18 }
    $lblStatus.Text = "☑️ កំពុងធិកជ្រើសរើសចម្រៀងឱ្យគ្រប់ 18 បទក្នុង Suno..."
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(147, 197, 253)
})

$btnPlClear.Add_Click({
    Send-SongQueueAction @{ action = "deselect_all_songs" }
    $lblPlBadge.Text = "0 បទ"
    $lblPlBadge.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
    $lblStatus.Text = "🔄 បានដោះការធិកទាំងអស់ក្នុង Suno!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(252, 165, 165)
})

$btnPlSmart.Add_Click({
    $txtPlName.Text = Get-SmartPlaylistName $global:targetPlaylistCount
})

$btnPlCreateAdd.Add_Click({
    $name = $txtPlName.Text.Trim()
    if (-not $name) {
        $name = Get-SmartPlaylistName $global:targetPlaylistCount
        $txtPlName.Text = $name
    }
    Send-SongQueueAction @{
        action = "create_playlist"
        name = $name
        count = $global:targetPlaylistCount
    }
    $lblStatus.Text = "🚀 បានបញ្ជាបង្កើត Playlist '$name' ($global:targetPlaylistCount បទ) & Add ស្វ័យប្រវត្តិ!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
})

$btnDedup.Add_Click({
    Send-SongQueueAction @{ action = "dedup_titles" }
    $lblStatus.Text = "🪄 បានបញ្ជាឱ្យ AI ស្កេន និងប្តូរឈ្មោះបទភ្លោះក្នុង Suno ភ្លាមៗ!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
})

# ⏱️ Duration Event Handlers
$btnDurAuto.Add_Click({
    $lblDurBadge.Text = "⚡ Auto"
    $lblDurBadge.ForeColor = [System.Drawing.Color]::FromArgb(165, 180, 252)
    $txtDurCustom.Text = "Auto"
    Send-SongQueueAction @{ action = "set_duration"; duration = "auto" }
    $lblStatus.Text = "⚡ បានកំណត់នាទីចម្រៀងជា Auto (ស្វ័យប្រវត្តិតាម Suno)!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(165, 180, 252)
})

$btnDur2m.Add_Click({
    $lblDurBadge.Text = "⏱️ 2:00"
    $lblDurBadge.ForeColor = [System.Drawing.Color]::FromArgb(196, 181, 253)
    $txtDurCustom.Text = "2:00"
    Send-SongQueueAction @{ action = "set_duration"; duration = 120 }
    $lblStatus.Text = "⏱️ បានកំណត់នាទីចម្រៀងត្រឹម 2 នាទី (2:00 / 120 វិនាទី)!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(196, 181, 253)
})

$btnDur3m.Add_Click({
    $lblDurBadge.Text = "⏱️ 3:00"
    $lblDurBadge.ForeColor = [System.Drawing.Color]::FromArgb(244, 114, 182)
    $txtDurCustom.Text = "3:00"
    Send-SongQueueAction @{ action = "set_duration"; duration = 180 }
    $lblStatus.Text = "⏱️ បានកំណត់នាទីចម្រៀងត្រឹម 3 នាទី (3:00 / 180 វិនាទី - ស្តង់ដារ)!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(244, 114, 182)
})

$btnDur4m.Add_Click({
    $lblDurBadge.Text = "⏱️ 4:00"
    $lblDurBadge.ForeColor = [System.Drawing.Color]::FromArgb(147, 197, 253)
    $txtDurCustom.Text = "4:00"
    Send-SongQueueAction @{ action = "set_duration"; duration = 240 }
    $lblStatus.Text = "⏱️ បានកំណត់នាទីចម្រៀងត្រឹម 4 នាទី (4:00 / 240 វិនាទី)!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(147, 197, 253)
})

$btnDur5m.Add_Click({
    $lblDurBadge.Text = "⏱️ 5:00"
    $lblDurBadge.ForeColor = [System.Drawing.Color]::FromArgb(110, 231, 183)
    $txtDurCustom.Text = "5:00"
    Send-SongQueueAction @{ action = "set_duration"; duration = 300 }
    $lblStatus.Text = "⏱️ បានកំណត់នាទីចម្រៀងត្រឹម 5 នាទី (5:00 / 300 វិនាទី)!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(110, 231, 183)
})

$btnDur6m.Add_Click({
    $lblDurBadge.Text = "⏱️ 6:00"
    $lblDurBadge.ForeColor = [System.Drawing.Color]::FromArgb(244, 114, 182)
    $txtDurCustom.Text = "6:00"
    Send-SongQueueAction @{ action = "set_duration"; duration = 360 }
    $lblStatus.Text = "🔥 បានកំណត់នាទីចម្រៀងត្រឹម 6 នាទី (6:00 / 360 វិនាទី - Max អតិបរមា)!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(244, 114, 182)
})

$btnDurApply.Add_Click({
    $customVal = $txtDurCustom.Text.Trim()
    if (-not $customVal) { $customVal = "3:00" }
    $lblDurBadge.Text = "⏱️ $customVal"
    $lblDurBadge.ForeColor = [System.Drawing.Color]::FromArgb(168, 85, 247)
    Send-SongQueueAction @{ action = "set_duration"; duration = $customVal }
    $lblStatus.Text = "⏱️ បានកំណត់នាទីចម្រៀងត្រឹម '$customVal' ក្នុង Suno!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(168, 85, 247)
})

$btnOpenSuno.Add_Click({
    $sunoHwnd = [Win32Composer]::FindSunoWindow()
    if ($sunoHwnd -ne [IntPtr]::Zero) {
        [Win32Composer]::ShowWindow($sunoHwnd, 9)
        [Win32Composer]::SetForegroundWindow($sunoHwnd)
    } else {
        $sunoBat = Join-Path $sunoDir "Suno.bat"
        if (Test-Path $sunoBat) { Start-Process $sunoBat }
    }
})

$btnCopyTitle.Add_Click({
    if ($txtOutTitle.Text) {
        [System.Windows.Forms.Clipboard]::SetText($txtOutTitle.Text)
        $lblStatus.Text = "✓ បានចម្លងចំណងជើង (Title) រួចរាល់!"
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
    }
})

$btnCopyStyle.Add_Click({
    if ($txtOutStyle.Text) {
        [System.Windows.Forms.Clipboard]::SetText($txtOutStyle.Text)
        $lblStatus.Text = "✓ បានចម្លងស្ទីលភ្លេង (Style Prompt) រួចរាល់!"
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
    }
})

$btnCopyLyrics.Add_Click({
    if ($txtOutLyrics.Text) {
        [System.Windows.Forms.Clipboard]::SetText($txtOutLyrics.Text)
        $lblStatus.Text = "✓ បានចម្លងទំនុកច្រៀង (Lyrics) រួចរាល់!"
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
    }
})

$btnCopyAll.Add_Click({
    $full = "[Title]: $($txtOutTitle.Text)`r`n[Style]: $($txtOutStyle.Text)`r`n`r`n[Lyrics]:`r`n$($txtOutLyrics.Text)"
    [System.Windows.Forms.Clipboard]::SetText($full)
    $lblStatus.Text = "✓ បានចម្លង Title + Style + Lyrics ទាំងអស់រួចរាល់!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
})

$btnSaveTxt.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
    $cleanTitle = ($txtOutTitle.Text -replace '[\\/:*?"<>|]', '_').Trim()
    if (-not $cleanTitle) { $cleanTitle = "Suno_Song" }
    $sfd.FileName = "$cleanTitle.txt"
    if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $content = "Title: $($txtOutTitle.Text)`r`nStyle: $($txtOutStyle.Text)`r`n`r`n$($txtOutLyrics.Text)"
        [System.IO.File]::WriteAllText($sfd.FileName, $content, [System.Text.Encoding]::UTF8)
        $lblStatus.Text = "✓ បានរក្សាទុកជាឯកសារ៖ $($sfd.FileName)"
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153)
    }
})

# Keyboard Shortcuts
$form.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
        Do-Compose
        $e.Handled = $true
    } elseif ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        Do-AutoFillToSuno
        $e.Handled = $true
    }
})

$form.Add_Load({
    if ($topic) { $txtTopic.Text = $topic }
    Do-Compose
})

$form.Add_Shown({
    try {
        $form.Activate()
        $form.BringToFront()
        [Win32Composer]::ShowWindow($form.Handle, 5) | Out-Null
        [Win32Composer]::SetForegroundWindow($form.Handle) | Out-Null
    } catch { }
})

$form.Add_FormClosing({
    param($s, $e)
    if ($appMutex) {
        try { $appMutex.ReleaseMutex() } catch { }
        $appMutex.Dispose()
    }
})

[System.Windows.Forms.Application]::EnableVisualStyles()
$null = $form.ShowDialog()
