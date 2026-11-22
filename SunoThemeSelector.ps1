# ==============================================================================
# SunoThemeSelector.ps1 - កម្មវិធីជ្រើសរើស Theme & ស្ទីលតន្ត្រី (10 Styles & 10 Themes)
# Suno AI Studio Pro Edition - Native Suno Dark Studio Interface (ស្ទីលធម្មតា)
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# High DPI Awareness
$win32Dpi = @"
using System;
using System.Runtime.InteropServices;
public class SunoThemeDpi {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
try {
    Add-Type -TypeDefinition $win32Dpi -ErrorAction SilentlyContinue
    $cWnd = [SunoThemeDpi]::GetConsoleWindow()
    if ($cWnd -ne [IntPtr]::Zero) { [SunoThemeDpi]::ShowWindow($cWnd, 0) | Out-Null }
    [SunoThemeDpi]::SetProcessDPIAware() | Out-Null
} catch {}

$appDir = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Programs\Suno" } else { "C:\Users\PS\AppData\Local\Programs\Suno" }
$queueInputFile = Join-Path $appDir "queue_input.json"

# ==============================================================================
# 1. THE 10 MASTER STYLES (ស្ទីលតន្ត្រីអាជីពទាំង ១០)
# ==============================================================================
$script:styles = @(
    [PSCustomObject]@{
        Id = "khmer_modern_pop"
        Name = "១. ខ្មែរ Modern Pop (ពីរោះ រំជួលចិត្ត)"
        Style = "Contemporary Khmer Pop, melodic piano, acoustic guitar, soft khmer kloy flute, emotional female vocal, 82 bpm, pristine production, warm acoustic reverb, radio hit"
        Icon = "🎹"
    },
    [PSCustomObject]@{
        Id = "romantic_ballad"
        Name = "២. បទមនោសញ្ចេតនា (Romantic Acoustic Ballad)"
        Style = "Sentimental acoustic ballad, warm grand piano, nylon acoustic guitar, ambient orchestral strings, heartfelt male vocals, 72 bpm, melancholic, intimate, slow tempo, soulful"
        Icon = "🎸"
    },
    [PSCustomObject]@{
        Id = "khmer_romvong"
        Name = "៣. ចង្វាក់ប្រជាប្រិយទំនើប (Romvong / Saravan)"
        Style = "Modern Khmer Romvong dance pop, tro, roneat, joyful melodic synthesizer, upbeat live drums, festive male and female choir, 118 bpm, happy celebration, khmer festival"
        Icon = "🥁"
    },
    [PSCustomObject]@{
        Id = "edm_dance"
        Name = "៤. EDM Festival & Club Dance (រាំញាក់ កន្ត្រាក់អារម្មណ៍)"
        Style = "Modern dance pop EDM, bright synth chords, punchy four-on-the-floor kick, euphoric festival drop, vocal chops, heavy bassline, 128 bpm, high energy party anthem"
        Icon = "🎆"
    },
    [PSCustomObject]@{
        Id = "drift_phonk"
        Name = "៥. Drift Phonk & Heavy 808 (Bass កក្រើក)"
        Style = "Aggressive drift phonk, distorted cowbells, heavy 808 sub-bass, rapid hi-hat rolls, dark atmospheric reverb, energetic street racing vibe, Memphis vocal samples, 140 bpm"
        Icon = "🚗"
    },
    [PSCustomObject]@{
        Id = "rnb_soul"
        Name = "៦. R&B / Soul សម័យថ្មី (ស្រទន់ រាត្រីកាល)"
        Style = "Modern R&B soul, lush Rhodes electric piano, smooth 808 bass, soulful vocal runs, sensual groove, 85 bpm, chill atmospheric reverb, late night vibing"
        Icon = "🎷"
    },
    [PSCustomObject]@{
        Id = "acoustic_lofi"
        Name = "៧. Acoustic / Lo-fi ស្ងប់ស្ងាត់ (លំហែចិត្ត)"
        Style = "Lo-fi acoustic chillhop, mellow fingerstyle acoustic guitar, vinyl crackle, gentle jazz drums, soft whispery vocal, 75 bpm, cozy relaxing study vibe, warm tape saturation"
        Icon = "☕"
    },
    [PSCustomObject]@{
        Id = "pop_rock"
        Name = "៨. Pop Rock & Arena Anthem (ស្វាហាប់ កម្លាំងចិត្ត)"
        Style = "Energetic pop rock anthem, driving distorted electric guitar riffs, punchy drums, powerful melodic chorus, passionate male vocal, 130 bpm, stadium rock, uplifting"
        Icon = "⚡"
    },
    [PSCustomObject]@{
        Id = "hiphop_trap"
        Name = "៩. Khmer Hip-Hop & Rap Beat (ចង្វាក់ញាក់ទាន់សម័យ)"
        Style = "Modern Khmer Hip-Hop, melodic trap synth, deep sliding 808 bass, crisp percussion, rhythmic flow, catchy hook, urban street beat, 95 bpm"
        Icon = "🎤"
    },
    [PSCustomObject]@{
        Id = "orchestral_epic"
        Name = "១០. Orchestral Cinematic Epic (ចង្វាក់ភាពយន្ត អធិកអធម)"
        Style = "Cinematic orchestral film score, thunderous taiko percussion, sweeping dramatic strings, epic brass fanfare, heroic choir, emotional climax, 90 bpm, Hans Zimmer style"
        Icon = "🎻"
    }
)

# ==============================================================================
# 2. THE 10 MASTER THEMES (ប្រធានបទចម្រៀងទាំង ១០ ភ្ជាប់ទំនុកច្រៀងពេញលេញ)
# ==============================================================================
$script:themes = @(
    [PSCustomObject]@{
        Id = "love_sweet"
        Name = "១. ក្ដីស្រឡាញ់ផ្អែមល្ហែម (Sweet Romance)"
        DefaultTitle = "ម្ចាស់បេះដូងអូន"
        DefaultStyleIndex = 0
        Icon = "💖"
        Lyrics = @"
[Intro - Soft Acoustic Guitar & Piano Melody]
(អូ... ហូ... ជួបអូនគ្រាដំបូង...)

[Verse 1]
រាល់ពេលឃើញស្នាមញញឹមថ្លៃ បេះដូងរំភើបឥតឧបមា
កែវភ្នែកស្រទន់ដូចតារា បំភ្លឺចិន្តាឱ្យភ្លឺថ្លា
ដើរកាត់ខ្យល់ត្រជាក់រាត្រី មានរូបថ្លៃក្បែរប្រាណ
ក្ដីសុខសាមញ្ញតែមានន័យ គ្មានអ្វីផ្ទឹមបាន

[Pre-Chorus]
ទោះបីថ្ងៃស្អែកទៅជាយ៉ាងណា
ចិត្តមួយនេះសន្យា ស្រឡាញ់តែអូន

[Chorus]
អូនជាដង្ហើម ជាក្ដីសុខក្នុងជីវិត
ស្រឡាញ់ស្មោះពិត គ្មានថ្ងៃប្រែប្រួលឡើយ
កាន់ដៃបងឆ្លងកាត់រាល់ឧបសគ្គកន្លង
មានតែរូបអូន ជាម្ចាស់បេះដូងបងរហូត

[Verse 2]
ពេលមានទុក្ខកង្វល់ក្នុងចិត្ត ស្នាមញញឹមអូនលួងលោម
រាល់ពាក្យផ្អែមល្ហែមដូចទឹកឃ្មុំ ថ្នាក់ថ្នមចិត្តកាយ
សូមអរគុណមេឃដែលប្រទានអូនមកឱ្យបង
មិនឱ្យរបូតបាត់បង់ ស្នេហ៍ដ៏មានន័យ

[Bridge - Traditional Flute & Strings Solo]
(ភ្លេងខ្លុយ និង ហ្គីតារំជួលចិត្ត...)
ទោះមេឃរលាយ ផ្កាយរលត់អស់ពីដួងចិត្ត
ក្ដីស្រឡាញ់ពិត នៅតែមានសម្រាប់អូន

[Chorus]
អូនជាដង្ហើម ជាក្ដីសុខក្នុងជីវិត
ស្រឡាញ់ស្មោះពិត គ្មានថ្ងៃប្រែប្រួលឡើយ
កាន់ដៃបងឆ្លងកាត់រាល់ឧបសគ្គកន្លង
មានតែរូបអូន ជាម្ចាស់បេះដូងបងរហូត

[Outro - Fade Out with Gentle Piano]
ស្រឡាញ់អូន... ជារៀងរហូត...
(Music fades out softly...)
"@
    },
    [PSCustomObject]@{
        Id = "heartbreak_sad"
        Name = "២. ស្នេហាបែកបាក់ ទឹកភ្នែកក្រោមភ្លៀង (Sad Heartbreak)"
        DefaultTitle = "ទឹកភ្នែកក្រោមតំណក់ភ្លៀង"
        DefaultStyleIndex = 1
        Icon = "🌧️"
        Lyrics = @"
[Intro - Melancholic Piano & Rain Sound Effect]
(តំណក់ទឹកភ្លៀង... ស្រក់កាត់បេះដូង...)

[Verse 1]
ភ្លៀងធ្លាក់ស្រក់កាត់បង្អួចចាស់ ដូចទឹកភ្នែកហូរមិនឈប់
ការចងចាំរឿងរ៉ាវគ្រប់យ៉ាង នៅតែដិតជាប់រាល់យប់
ធ្លាប់ដើរកាត់ភ្លៀងជាមួយគ្នា ឥឡូវនៅសល់តែបង
ពាក្យថាស្នេហ៍ដែលអូនធ្លាប់ផ្ដល់ រសាត់បាត់អស់ហើយថ្លៃ

[Pre-Chorus]
តើបងធ្វើខុសអ្វី ទើបអូនចាកចេញគ្មានស្ដាយ?
ទុកឱ្យបេះដូងមួយនេះ រងាវខ្លោចផ្សា

[Chorus]
ទឹកភ្នែកហូរស្រក់កាត់ថ្ពាល់ លាយឡំនឹងទឹកភ្លៀង
ឈឺចាប់ឥតល្ហែ ពេលស្នេហ៍ត្រូវប្រេះឆា
ជូនពរឱ្យអូនបានសុខ ជាមួយអ្នកថ្មីថ្លៃថ្លា
ទុកការឈឺផ្សា ឱ្យបងជាអ្នករ៉ាប់រង

[Verse 2]
អង្គុយមើលរូបថតចាស់ៗ ដែលយើងធ្លាប់សើចជាមួយគ្នា
ពេលនេះក្លាយជារឿងអតីត ដែលគ្មានថ្ងៃវិលត្រឡប់
ខំប្រាប់បេះដូងឱ្យបំភ្លេច តែចិត្តមិនព្រមស្ដាប់
នៅតែនឹក នៅតែស្រឡាញ់ ទោះអូនក្បត់ចិត្ត

[Bridge - Crying Guitar Solo]
(ហ្គីតាទួញសោក... យ៉ាងឈឺចាប់...)
បើសិនពេលវេលាអាចថយក្រោយ...
បងនឹងមិនជ្រើសរើសឱ្យយើងស្គាល់គ្នា...

[Chorus]
ទឹកភ្នែកហូរស្រក់កាត់ថ្ពាល់ លាយឡំនឹងទឹកភ្លៀង
ឈឺចាប់ឥតល្ហែ ពេលស្នេហ៍ត្រូវប្រេះឆា
ជូនពរឱ្យអូនបានសុខ ជាមួយអ្នកថ្មីថ្លៃថ្លា
ទុកការឈឺផ្សា ឱ្យបងជាអ្នករ៉ាប់រង

[Outro - Slow Piano]
លាហើយស្នេហា... លាហើយមនុស្សដែលបងស្រឡាញ់...
(Fade Out)
"@
    },
    [PSCustomObject]@{
        Id = "homesick_mother"
        Name = "៣. នឹកផ្ទះ នឹកម៉ែ ស្រុកកំណើត (Homesick & Mother)"
        DefaultTitle = "នឹកម៉ែស្រុកស្រែ"
        DefaultStyleIndex = 0
        Icon = "🏡"
        Lyrics = @"
[Intro - Traditional Khmer Kloy Flute & Acoustic Guitar]
(សំឡេងខ្លុយស្រុកស្រែ... នឹកដល់អ្នកម្ដាយ...)

[Verse 1]
ខ្យល់រំភើយបក់មកពីទិសខាងកើត នឹកស្រុកកំណើតធ្លាប់រស់នៅ
នឹកក្លិនបាយក្ដៅម្ដាយដាំ នឹកផ្ទះស្លឹកចាស់ម្លប់ជ្រៃ
កូនមកតស៊ូនៅទីក្រុង ឆ្ងាយស្រុកឆ្ងាយភូមិ
រាល់រាត្រីសម្លឹងមើលផ្កាយ នឹកម៉ែឪរាល់វេលា

[Pre-Chorus]
ឮសូរសំឡេងម៉ែតាមទូរស័ព្ទ សួរកូនថាញ៉ាំបាយហើយឬនៅ?
ទឹកភ្នែកកូនហូរដោយមិនដឹងខ្លួន នឹកម៉ែណាស់

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

[Bridge - Emotional Tro & Flute Harmony]
(សំឡេងទ្រ និង ខ្លុយរំជួលចិត្ត... នឹកភូមិកំណើត...)
កូននឹងវិលទៅរកផ្ទះយើងវិញ ម៉ែរង់ចាំកូនណា...

[Chorus]
ម៉ែអើយកូននឹកម៉ែណាស់ នឹកទាំងដំបូន្មាន
កូនខំតស៊ូធ្វើការងារ ដើម្បីអនាគតថ្លៃថ្លា
រង់ចាំកូនណាអ្នកម្ដាយ មិនយូរឡើយកូននឹងត្រឡប់
យកជោគជ័យទៅជូនម៉ែ ជួបជុំគ្រួសារ

[Outro - Soft Flute Melody]
កូនស្រឡាញ់ម៉ែ... ស្រឡាញ់រហូត...
(Fade Out)
"@
    },
    [PSCustomObject]@{
        Id = "motivational_rise"
        Name = "៤. លើកទឹកចិត្ត កុំចុះចាញ់ (Motivational / Rise Up)"
        DefaultTitle = "អ្នកចម្បាំងជីវិត"
        DefaultStyleIndex = 7
        Icon = "⚡"
        Lyrics = @"
[Intro - Building Drum Beats & Electric Guitar]
(បោះជំហានទៅមុខ... គ្មានអ្វីរារាំងយើងបាន...)

[Verse 1]
ទោះផ្លូវខាងមុខមានបន្លា ឧបសគ្គរាប់រយរាប់ពាន់
ដួលប៉ុន្មានដងត្រូវតែងើប មិនត្រូវចុះចាញ់ព្រហ្មលិខិត
ញើសហូរស្រក់ដើម្បីក្ដីស្រមៃ ខំប្រឹងតស៊ូឥតឈប់
ថ្ងៃស្អែកនឹងជាថ្ងៃរបស់យើង ជោគជ័យនឹងមកដល់

[Pre-Chorus]
ជឿជាក់លើខ្លួនឯង ជឿលើកម្លាំងចិត្ត
គ្មានអ្វីដែលថាមិនអាចធ្វើបាន បើយើងមិនបោះបង់

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

[Bridge - Powerful Rock Guitar Solo & Heavy Drums]
(ហ្គីតាវាយយ៉ាងកក្រើក... បង្ហាញភាពក្លាហាន...)
ស្រែកឱ្យអស់ពីចិត្ត! នេះជាពេលវេលារបស់យើង!

[Chorus]
ក្រោកឈរឡើង! ហោះហើរទៅលើមេឃាក្រឡាស់
បញ្ចេញពន្លឺក្នុងចិត្ត ឱ្យលោកដឹងថាយើងខ្លាំង
ទោះខ្យល់ព្យុះបក់បោក ក៏មិនរាថយ
យើងជាអ្នកចម្បាំង ក្តោបក្តាប់ជ័យជម្នះក្នុងដៃ!

[Outro - Triumphant Ending]
ជ័យជម្នះជារបស់យើង! កុំចុះចាញ់!
(Big Final Drum Hit)
"@
    },
    [PSCustomObject]@{
        Id = "khmer_party_dance"
        Name = "៥. រាំកម្សាន្តចូលឆ្នាំ សប្បាយរីករាយ (Khmer Party Dance)"
        DefaultTitle = "រាំកម្សាន្តចូលឆ្នាំថ្មី"
        DefaultStyleIndex = 2
        Icon = "🎊"
        Lyrics = @"
[Intro - Lively Roneat, Tro & Modern Dance Beat]
(អេវ៉ា... រាំលេងសប្បាយ... ចូលឆ្នាំថ្មីប្រពៃណីខ្មែរ!)

[Verse 1]
សូរស័ព្ទស្គរដៃបន្លឺកងរំពង បងប្អូនជួបជុំភូមិផងរបងជាមួយ
ផ្កាឈូកផ្ការំដួលរីកស្គុសស្គាយ ស្រីស្រស់ប្រិមប្រិយញញឹមស្រស់ថ្លា
តោះនាំគ្នារាំកម្សាន្ត ចង្វាក់រាំវង់សារ៉ាវ៉ាន់
ភ្លេចទុក្ខកង្វល់ឱ្យអស់ រីករាយគ្រប់គ្នា

[Pre-Chorus]
តោះរាំ! តោះរាំ! កុំនៅឈរស្ងៀម
តាក់ទែនទែនតាក់ រាំលេងសប្បាយ!

[Chorus]
រាំទៅៗ កុំនៅអៀនខ្មាស
ចូលឆ្នាំថ្មីហើយ សប្បាយណាស់ណា
ជូនពរពុកម៉ែ បងប្អូនជិតឆ្ងាយ
សុខសប្បាយ រកស៊ីមានបានគ្រប់គ្នា!

[Verse 2]
យុវជនយុវតីស្លៀកពាក់ចម្រុះពណ៌ រាំបណ្ដាក់គ្នាជារង្វង់មូល
លេងល្បែងប្រជាប្រិយចោលឈូង បោះអង្គញ់ និងទាញព្រ័ត្រ
សើចសប្បាយក្អាកក្អាយ ពេញភូមិកំណើត
មោទនភាពជាតិខ្មែរ ប្រពៃណីថ្លៃថ្លា

[Bridge - Festive Percussion & Cheering]
(ហោរ... ជយោ! រាំកន្ត្រាក់អារម្មណ៍!)

[Chorus]
រាំទៅៗ កុំនៅអៀនខ្មាស
ចូលឆ្នាំថ្មីហើយ សប្បាយណាស់ណា
ជូនពរពុកម៉ែ បងប្អូនជិតឆ្ងាយ
សុខសប្បាយ រកស៊ីមានបានគ្រប់គ្នា!

[Outro - Fast Upbeat Finish]
ជយោចូលឆ្នាំថ្មី! សប្បាយៗ!
(Drum Roll & Cymbal Crash)
"@
    },
    [PSCustomObject]@{
        Id = "drift_racing"
        Name = "៦. ចង្វាក់រថយន្តប្រណាំង រាត្រីកាល (Midnight Drift Racing)"
        DefaultTitle = "រាត្រីរថយន្តហោះហើរ (Tokyo Drift)"
        DefaultStyleIndex = 4
        Icon = "🏎️"
        Lyrics = @"
[Intro - Distorted Cowbells & Engine Revving]
(សូរសំឡេងម៉ាស៊ីន... ផ្សែងកង់កកិតលើថ្នល់...)

[Verse 1]
រាត្រីកណ្តាលអាធ្រាត្រ ភ្លើងនេអុងចាំងផ្លេកបន្ទោរ
សំឡេងកង់កកិតថ្នល់ បត់បែនតាមគំនូសកោង
គ្មានការភ័យខ្លាច គ្មានការរាថយ
ល្បឿនជាជីវិត ឆ្ពោះទៅកាន់ជើងមេឃ

[Chorus]
Drift កាត់កណ្តាលរាត្រី! សំឡេងបាសកក្រើកដី!
បេះដូងលោតញាប់ តាមចង្វាក់ Phonk ក្តៅគគុក
យើងជាស្តេចផ្លូវល្បឿន គ្មានអ្នកណាបញ្ឈប់បាន!
(Bass Drop - Heavy 808 Sub-Bass Rumble)

[Verse 2]
ក្រឡេកមើលកញ្ចក់ក្រោយ ឃើញតែផ្សែងកង់សក្បុស
គូប្រកួតដេញតាម តែមិនទាន់ស្រមោលយើង
នេះជាពិភពរបស់យើង ពិភពនៃល្បឿននិងកម្លាំង
ស្រែកឱ្យអស់សំឡេង កណ្តាលរាត្រីគ្មានព្រំដែន!

[Outro - Echoing Exhaust & Screeching Tires]
ល្បឿន... និងសេរីភាព... (Fade Out)
"@
    },
    [PSCustomObject]@{
        Id = "rnb_night"
        Name = "៧. កាហ្វេជូរចត់ និងរាត្រីឯកា (Midnight Coffee & Chill)"
        DefaultTitle = "កាហ្វេជូរចត់ និងរាត្រីស្ងប់ស្ងាត់"
        DefaultStyleIndex = 5
        Icon = "☕"
        Lyrics = @"
[Intro - Smooth Electric Rhodes Piano & Finger Snaps]
(កាហ្វេមួយកែវ... កណ្តាលរាត្រីស្ងាត់...)

[Verse 1]
អង្គុយក្បែរបង្អួច កែវកាហ្វេក្តៅឧណ្ហៗ
សម្លឹងមើលតំណក់ភ្លៀង គិតដល់រឿងរ៉ាវកន្លង
ក្លិនឈ្ងុយនៃកាហ្វេ លាយឡំនឹងការចងចាំ
មនុស្សធ្លាប់ក្បែរប្រាណ ពេលនេះនៅឯណា?

[Chorus]
រសជាតិជូរចត់នៃកាហ្វេ ដូចជាបេះដូងឯកា
ផឹកដើម្បីបំភ្លេច តែរឹតតែចងចាំថ្លៃថ្លា
រាត្រីស្ងាត់ជ្រងំ មានតែភ្លេង R&B លួងលោម
រង់ចាំថ្ងៃថ្មី មកស្រោចស្រង់ដួងចិត្ត

[Verse 2]
ទូរស័ព្ទស្ងាត់ច្រៀប គ្មានសារផ្ញើមកដូចមុន
តែមិនអីទេ បេះដូងរៀនរស់នៅម្នាក់ឯង
រាល់បទពិសោធន៍ បង្រៀនឱ្យយើងរឹងមាំ
ញញឹមទទួលយកការពិត ដើរទៅមុខបន្ត

[Outro - Soft Saxophone & Fading Piano]
រាត្រីដ៏ស្ងប់ស្ងាត់... Goodnight... (Fade Out)
"@
    },
    [PSCustomObject]@{
        Id = "lofi_peace"
        Name = "៨. ទេសភាពស្រុកស្រែ លំហែអារម្មណ៍ (Peaceful Countryside)"
        DefaultTitle = "ខ្យល់បក់រំភើយវាលស្រែ"
        DefaultStyleIndex = 6
        Icon = "🌾"
        Lyrics = @"
[Intro - Acoustic Fingerstyle Guitar & Birds Chirping]
(ខ្យល់បក់រំភើយ... ក្លិនស្រូវទុំក្រអូប...)

[Verse 1]
វាលស្រែខៀវស្រងាត់ លាតសន្ធឹងដល់ជើងមេឃ
សត្វចាបហើរច្រៀង លើមែកអំពិលទុំ
សម្រស់ធម្មជាតិ ស្រស់ថ្លាឥតកន្លែងផ្ទឹម
រំសាយទុក្ខកង្វល់ ចាកឆ្ងាយពីភាពអ៊ូអរ

[Chorus]
ស្រុកស្រែកំណើតអើយ ស្រស់ស្អាតម្ល៉េះទេ
ទឹកដីមាតុភូមិ ផ្តល់ក្តីសុខគ្រប់ពេលវេលា
អង្គុយក្រោមម្លប់ជ្រៃ ស្រូបយកខ្យល់អាកាសបរិសុទ្ធ
នេះហើយសេចក្តីសុខពិត ក្នុងជីវិតមនុស្សយើង

[Verse 2]
ពេលថ្ងៃរៀបលិច ពន្លឺពណ៌មាសចាំងលើទឹកស្ទឹង
កូនក្របីដើរត្រឡប់ ចូលក្រោលក្បែរផ្ទះ
ផ្សែងភ្លើងដាំបាយ ហុយត្រសែតលើដំបូលស្លឹក
ភាពកក់ក្តៅគ្រួសារ គ្មានអ្វីអាចទិញបាន

[Outro - Gentle Kloy Flute & Vinyl Crackle]
ស្រុកកំណើតដ៏កក់ក្តៅ... (Fade Out)
"@
    },
    [PSCustomObject]@{
        Id = "hiphop_street"
        Name = "៩. ក្មេងផ្លូវលំ ឆ្ពោះទៅក្ដីស្រមៃ (Street Flow & Dream)"
        DefaultTitle = "ក្មេងផ្លូវលំឆ្ពោះទៅក្ដីស្រមៃ"
        DefaultStyleIndex = 8
        Icon = "🎤"
        Lyrics = @"
[Intro - Heavy 808 Beat & Trap Hi-Hats]
(Yo! Check this out... ចេញពីបាតដៃទទេ...)

[Verse 1]
កើតនៅផ្លូវលំ គ្មានទ្រព្យសម្បត្តិស្តុកស្តម្ភ
មានតែក្តីស្រមៃ និងការតស៊ូក្នុងទ្រូង
គេមើលងាយសម្តី ថាយើងមិនអាចធ្វើបាន
តែការឈឺចាប់ទាំងនោះ ក្លាយជាភ្លើងដុតកម្លាំងចិត្ត

[Chorus]
យើងជាក្មេងផ្លូវលំ! ឆ្ពោះទៅកាន់កំពូលតារា!
ទោះលំបាកប៉ុនណា ក៏មិនដែលបោះបង់!
ឈរលើឆាកតន្ត្រី ស្រែកប្រាប់ពិភពលោកថា
ការប្រឹងប្រែងរបស់យើង មិនឥតប្រយោជន៍ឡើយ!

[Verse 2]
រាល់យប់សរសេរចម្រៀង ក្រោមពន្លឺភ្លើងចង្កៀង
ចង្វាក់បេះដូងលោត ស្របតាមចង្វាក់ Hip-Hop
មិនត្រូវការសំណាង ត្រូវការតែញើសនិងឈាម
បោះជំហានទៅមុខ យកពានរង្វាន់ជីវិត!

[Outro - Scratching Turntable & Heavy Bass Finish]
Real talk... Never back down! (Mic Drop)
"@
    },
    [PSCustomObject]@{
        Id = "epic_angkor"
        Name = "១០. មហានគរអង្គរដ៏រុងរឿង (Angkor Legend & Heritage)"
        DefaultTitle = "មហានគរអង្គរដ៏រុងរឿង"
        DefaultStyleIndex = 9
        Icon = "🏛️"
        Lyrics = @"
[Intro - Epic Taiko Drums, Kong Vong & Sweeping Orchestral Strings]
(មហានគរខ្មែរ... អរិយធម៌រុងរឿងរាប់ពាន់ឆ្នាំ...)

[Verse 1]
ប្រាសាទបុរាណសន្លឹម ឈរយ៉ាងអង់អាចកណ្តាលព្រៃ
ថ្មឆ្លាក់រឿងរ៉ាវ ប្រវត្តិសាស្ត្រមហស្ចារ្យ
ដូនតាខ្មែរខ្លាំងពូកែ កសាងស្នាដៃបន្សល់ទុក
មរតកដួងព្រលឹង ស្ថិតស្ថេររាប់ពាន់ឆ្នាំ

[Chorus]
អង្គរវត្តអើយ! មោទនភាពជាតិនៃយើង!
ទង់ជាតិខ្មែរបក់រវិច លើកំពូលប្រាសាទមាស
កូនខ្មែររួបរួមគ្នា ថែរក្សាការពារទឹកដី
ឱ្យកេរ្តិ៍ឈ្មោះខ្មែរ ល្បីល្បាញពេញសកលលោក!

[Verse 2]
ស្នាមញញឹមបាយ័ន បង្ហាញភាពស្ងប់និងមេត្តា
កម្លាំងសាមគ្គី នាំមកនូវជ័យជម្នះ
ឈាមជ័រអ្នកចម្បាំង ហូរនៅក្នុងខ្លួនយើង
ប្តេជ្ញាអភិវឌ្ឍជាតិ ឱ្យរុងរឿងជានិរន្តរ៍

[Outro - Grand Triumphant Brass Fanfare & Choral Finale]
ជយោព្រះរាជាណាចក្រកម្ពុជា! រុងរឿងជារៀងរហូត!
(Massive Orchestral Cymbal Crash)
"@
    }
)

# ==============================================================================
# 3. BUILD GUI WINDOW (Suno Obsidian Glassmorphism)
# ==============================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Suno AI - កម្មវិធីជ្រើសរើស Theme & ស្ទីលតន្ត្រី (10 Styles & 10 Themes)"
$form.Size = New-Object System.Drawing.Size 1060, 760
$form.MinimumSize = New-Object System.Drawing.Size 950, 680
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = [System.Drawing.Color]::FromArgb(9, 9, 11)
$form.ForeColor = [System.Drawing.Color]::White

# Try setting icon
$iconPath = Join-Path $appDir "suno_icon.ico"
if (Test-Path $iconPath) {
    try { $form.Icon = New-Object System.Drawing.Icon($iconPath) } catch {}
}

# Top Header Bar
$header = New-Object System.Windows.Forms.Panel
$header.Dock = [System.Windows.Forms.DockStyle]::Top
$header.Height = 70
$header.BackColor = [System.Drawing.Color]::FromArgb(14, 15, 20)
$header.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "✦ កម្មវិធីជ្រើសរើស Theme & ស្ទីលតន្ត្រី (Suno Theme & Style Studio)"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12.0, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(18, 12)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "ជ្រើសរើស Theme ទាំង ១០ និង Music Style ទាំង ១០ ដើម្បីបញ្ចូលទៅក្នុង Suno ដោយស្វ័យប្រវត្តិ"
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(161, 161, 170)
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(20, 40)

$header.Controls.AddRange(@($lblTitle, $lblSub))
$form.Controls.Add($header)

# Bottom Action Bar
$bottomBar = New-Object System.Windows.Forms.Panel
$bottomBar.Dock = [System.Windows.Forms.DockStyle]::Bottom
$bottomBar.Height = 65
$bottomBar.BackColor = [System.Drawing.Color]::FromArgb(14, 15, 20)
$bottomBar.Padding = New-Object System.Windows.Forms.Padding(20, 12, 20, 12)
$form.Controls.Add($bottomBar)

# Main Split Container
$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = [System.Windows.Forms.DockStyle]::Fill
$split.BackColor = [System.Drawing.Color]::FromArgb(28, 29, 36)
$split.Panel1.BackColor = [System.Drawing.Color]::FromArgb(11, 12, 16)
$split.Panel2.BackColor = [System.Drawing.Color]::FromArgb(14, 15, 20)
$split.FixedPanel = [System.Windows.Forms.FixedPanel]::Panel1
$form.Controls.Add($split)
$split.BringToFront()

# ==============================================================================
# LEFT PANEL: 10 THEMES LIST
# ==============================================================================
$lblLeftTitle = New-Object System.Windows.Forms.Label
$lblLeftTitle.Text = "★ បញ្ជីប្រធានបទ Theme (ជ្រើសរើសមួយ):"
$lblLeftTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10.0, [System.Drawing.FontStyle]::Bold)
$lblLeftTitle.ForeColor = [System.Drawing.Color]::FromArgb(240, 240, 250)
$lblLeftTitle.Location = New-Object System.Drawing.Point(16, 12)
$lblLeftTitle.Size = New-Object System.Drawing.Size 370, 25
$split.Panel1.Controls.Add($lblLeftTitle)

$themeListBox = New-Object System.Windows.Forms.ListBox
$themeListBox.Location = New-Object System.Drawing.Point(16, 42)
$themeListBox.Size = New-Object System.Drawing.Size 370, 500
$themeListBox.BackColor = [System.Drawing.Color]::FromArgb(18, 19, 26)
$themeListBox.ForeColor = [System.Drawing.Color]::White
$themeListBox.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$themeListBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$themeListBox.ItemHeight = 32

foreach ($t in $script:themes) {
    $themeListBox.Items.Add("$($t.Name)") | Out-Null
}
$split.Panel1.Controls.Add($themeListBox)

function Resize-LeftPanel {
    $pW = $split.Panel1.ClientSize.Width
    $pH = $split.Panel1.ClientSize.Height
    $themeListBox.Width = [Math]::Max(100, $pW - 32)
    $themeListBox.Height = [Math]::Max(100, $pH - 56)
}
$split.Panel1.Add_Resize({ Resize-LeftPanel })

# ==============================================================================
# RIGHT PANEL: 10 STYLES & LIVE PREVIEW
# ==============================================================================
$lblRightTitle = New-Object System.Windows.Forms.Label
$lblRightTitle.Text = "♫ ស្ទីលតន្ត្រី (Style of Music):"
$lblRightTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblRightTitle.ForeColor = [System.Drawing.Color]::FromArgb(240, 240, 250)
$lblRightTitle.Location = New-Object System.Drawing.Point(18, 12)
$lblRightTitle.AutoSize = $true
$split.Panel2.Controls.Add($lblRightTitle)

$styleCombo = New-Object System.Windows.Forms.ComboBox
$styleCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$styleCombo.Location = New-Object System.Drawing.Point(18, 38)
$styleCombo.Size = New-Object System.Drawing.Size 580, 32
$styleCombo.BackColor = [System.Drawing.Color]::FromArgb(22, 23, 32)
$styleCombo.ForeColor = [System.Drawing.Color]::White
$styleCombo.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$styleCombo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

foreach ($s in $script:styles) {
    $styleCombo.Items.Add("$($s.Name)") | Out-Null
}
$split.Panel2.Controls.Add($styleCombo)

# Title Label & Input
$lblSongTitle = New-Object System.Windows.Forms.Label
$lblSongTitle.Text = "● ចំណងជើងចម្រៀង (Song Title):"
$lblSongTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$lblSongTitle.ForeColor = [System.Drawing.Color]::FromArgb(200, 205, 220)
$lblSongTitle.Location = New-Object System.Drawing.Point(18, 78)
$lblSongTitle.AutoSize = $true
$split.Panel2.Controls.Add($lblSongTitle)

$txtTitle = New-Object System.Windows.Forms.TextBox
$txtTitle.Location = New-Object System.Drawing.Point(18, 102)
$txtTitle.Size = New-Object System.Drawing.Size 580, 28
$txtTitle.BackColor = [System.Drawing.Color]::FromArgb(22, 23, 32)
$txtTitle.ForeColor = [System.Drawing.Color]::White
$txtTitle.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$txtTitle.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$split.Panel2.Controls.Add($txtTitle)

# Style Prompt Label & Input
$lblStylePrompt = New-Object System.Windows.Forms.Label
$lblStylePrompt.Text = "⚡ Music Style Prompt (សម្រាប់ប្រអប់ Style ក្នុង Suno):"
$lblStylePrompt.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$lblStylePrompt.ForeColor = [System.Drawing.Color]::FromArgb(200, 205, 220)
$lblStylePrompt.Location = New-Object System.Drawing.Point(18, 138)
$lblStylePrompt.AutoSize = $true
$split.Panel2.Controls.Add($lblStylePrompt)

$txtStylePrompt = New-Object System.Windows.Forms.TextBox
$txtStylePrompt.Location = New-Object System.Drawing.Point(18, 162)
$txtStylePrompt.Size = New-Object System.Drawing.Size 580, 55
$txtStylePrompt.Multiline = $true
$txtStylePrompt.BackColor = [System.Drawing.Color]::FromArgb(22, 23, 32)
$txtStylePrompt.ForeColor = [System.Drawing.Color]::FromArgb(125, 211, 252)
$txtStylePrompt.Font = New-Object System.Drawing.Font("Consolas", 8.8)
$txtStylePrompt.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$split.Panel2.Controls.Add($txtStylePrompt)

# Lyrics Label & Input
$lblLyrics = New-Object System.Windows.Forms.Label
$lblLyrics.Text = "★ ទំនុកច្រៀងពេញលេញ (Lyrics Preview):"
$lblLyrics.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$lblLyrics.ForeColor = [System.Drawing.Color]::FromArgb(200, 205, 220)
$lblLyrics.Location = New-Object System.Drawing.Point(18, 228)
$lblLyrics.AutoSize = $true
$split.Panel2.Controls.Add($lblLyrics)

$txtLyrics = New-Object System.Windows.Forms.TextBox
$txtLyrics.Location = New-Object System.Drawing.Point(18, 252)
$txtLyrics.Size = New-Object System.Drawing.Size 580, 290
$txtLyrics.Multiline = $true
$txtLyrics.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtLyrics.BackColor = [System.Drawing.Color]::FromArgb(18, 19, 26)
$txtLyrics.ForeColor = [System.Drawing.Color]::FromArgb(240, 240, 250)
$txtLyrics.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$txtLyrics.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$split.Panel2.Controls.Add($txtLyrics)

function Resize-RightPanel {
    $pW = $split.Panel2.ClientSize.Width
    $pH = $split.Panel2.ClientSize.Height
    $targetW = [Math]::Max(100, $pW - 36)
    $styleCombo.Width = $targetW
    $txtTitle.Width = $targetW
    $txtStylePrompt.Width = $targetW
    $txtLyrics.Width = $targetW
    $txtLyrics.Height = [Math]::Max(100, $pH - 265)
}
$split.Panel2.Add_Resize({ Resize-RightPanel })

# Selection Changed Events
$script:selectedThemeIndex = 0
$script:selectedStyleIndex = 0

function Update-Preview {
    $tIdx = $script:selectedThemeIndex
    $sIdx = $script:selectedStyleIndex
    if ($tIdx -ge 0 -and $tIdx -lt $script:themes.Count) {
        $curTheme = $script:themes[$tIdx]
        $txtTitle.Text = $curTheme.DefaultTitle
        $txtLyrics.Text = $curTheme.Lyrics
    }
    if ($sIdx -ge 0 -and $sIdx -lt $script:styles.Count) {
        $curStyle = $script:styles[$sIdx]
        $txtStylePrompt.Text = $curStyle.Style
    }
}

$themeListBox.Add_SelectedIndexChanged({
    if ($themeListBox.SelectedIndex -ge 0) {
        $script:selectedThemeIndex = $themeListBox.SelectedIndex
        $t = $script:themes[$script:selectedThemeIndex]
        if ($t.DefaultStyleIndex -ge 0 -and $t.DefaultStyleIndex -lt $script:styles.Count) {
            $styleCombo.SelectedIndex = $t.DefaultStyleIndex
        }
        Update-Preview
    }
})

$styleCombo.Add_SelectedIndexChanged({
    if ($styleCombo.SelectedIndex -ge 0) {
        $script:selectedStyleIndex = $styleCombo.SelectedIndex
        Update-Preview
    }
})

# ==============================================================================
# BOTTOM ACTION BUTTONS
# ==============================================================================
function Send-DataToSuno($autoGenerate = $false) {
    $curTitle = $txtTitle.Text.Trim()
    $curStyle = $txtStylePrompt.Text.Trim()
    $curLyrics = $txtLyrics.Text.Trim()

    if (-not $curTitle) { $curTitle = "Suno Master Song" }
    if (-not $curStyle) { $curStyle = $script:styles[0].Style }

    # Write command payload to queue_input.json
    $payload = [PSCustomObject]@{
        action = if ($autoGenerate) { "generate_with_data" } else { "set_song_data" }
        title = $curTitle
        style = $curStyle
        lyrics = $curLyrics
        timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    }

    try {
        $json = $payload | ConvertTo-Json -Depth 4
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false); [System.IO.File]::WriteAllText($queueInputFile, $json, $utf8NoBom)

        # Also append to song_queue.json for dual-redundancy IPC
        $songQueueFile = Join-Path $appDir "song_queue.json"
        try {
            $existing = @()
            if (Test-Path $songQueueFile) {
                $rawSq = Get-Content $songQueueFile -Raw -ErrorAction SilentlyContinue
                if ($rawSq -and $rawSq.Trim() -ne "[]") {
                    $parsed = $rawSq | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($parsed -is [System.Array]) {
                        foreach ($it in $parsed) {
                            if ($it -and $it.PSObject -and $it.PSObject.Properties['value']) {
                                foreach ($sub in $it.value) { $existing += $sub }
                            } elseif ($it) {
                                $existing += $it
                            }
                        }
                    } elseif ($parsed) {
                        $existing += $parsed
                    }
                }
            }
            $existing += $payload
            $sqJson = $existing | ConvertTo-Json -Depth 4
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false); [System.IO.File]::WriteAllText($songQueueFile, $sqJson, $utf8NoBom)
        } catch { }

        $actionText = if ($autoGenerate) { "បង្កើតចម្រៀងភ្លាមៗ" } else { "បញ្ចូលទិន្នន័យទៅក្នុង Suno" }
        [System.Windows.Forms.MessageBox]::Show(
            "✓ បាន$actionTextជោគជ័យ!`n`nចំណងជើង: $curTitle`nស្ទីល: $($script:styles[$script:selectedStyleIndex].Name)",
            "Suno Studio Success",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "⚠️ បរាជ័យក្នុងការផ្ញើទិន្នន័យ៖ $($_.Exception.Message)",
            "Suno Studio Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    }
}

# 1. Apply to Suno Button
$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = "⚡ បញ្ចូលទៅ Suno (Apply)"
$btnApply.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnApply.Size = New-Object System.Drawing.Size 210, 40
$btnApply.Location = New-Object System.Drawing.Point(18, 12)
$btnApply.BackColor = [System.Drawing.Color]::FromArgb(5, 150, 105)
$btnApply.ForeColor = [System.Drawing.Color]::White
$btnApply.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnApply.FlatAppearance.BorderSize = 0
$btnApply.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnApply.Add_Click({ Send-DataToSuno $false })
$bottomBar.Controls.Add($btnApply)

# 2. Generate Now Button
$btnGen = New-Object System.Windows.Forms.Button
$btnGen.Text = "✨ បង្កើតចម្រៀង (Generate)"
$btnGen.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnGen.Size = New-Object System.Drawing.Size 210, 40
$btnGen.Location = New-Object System.Drawing.Point(236, 12)
$btnGen.BackColor = [System.Drawing.Color]::FromArgb(234, 88, 12)
$btnGen.ForeColor = [System.Drawing.Color]::White
$btnGen.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnGen.FlatAppearance.BorderSize = 0
$btnGen.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnGen.Add_Click({ Send-DataToSuno $true })
$bottomBar.Controls.Add($btnGen)

# 3. Copy Style Button
$btnCopyStyle = New-Object System.Windows.Forms.Button
$btnCopyStyle.Text = "ចម្លង Style"
$btnCopyStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnCopyStyle.Size = New-Object System.Drawing.Size 95, 40
$btnCopyStyle.Location = New-Object System.Drawing.Point(454, 12)
$btnCopyStyle.BackColor = [System.Drawing.Color]::FromArgb(38, 40, 52)
$btnCopyStyle.ForeColor = [System.Drawing.Color]::White
$btnCopyStyle.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCopyStyle.FlatAppearance.BorderSize = 0
$btnCopyStyle.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnCopyStyle.Add_Click({
    if ($txtStylePrompt.Text) {
        [System.Windows.Forms.Clipboard]::SetText($txtStylePrompt.Text)
        [System.Windows.Forms.MessageBox]::Show("✓ បានចម្លង Style រួចរាល់!", "Suno Studio", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})
$bottomBar.Controls.Add($btnCopyStyle)

# 4. Copy Lyrics Button
$btnCopyLyrics = New-Object System.Windows.Forms.Button
$btnCopyLyrics.Text = "ចម្លង Lyrics"
$btnCopyLyrics.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnCopyLyrics.Size = New-Object System.Drawing.Size 95, 40
$btnCopyLyrics.Location = New-Object System.Drawing.Point(556, 12)
$btnCopyLyrics.BackColor = [System.Drawing.Color]::FromArgb(38, 40, 52)
$btnCopyLyrics.ForeColor = [System.Drawing.Color]::White
$btnCopyLyrics.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCopyLyrics.FlatAppearance.BorderSize = 0
$btnCopyLyrics.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnCopyLyrics.Add_Click({
    if ($txtLyrics.Text) {
        [System.Windows.Forms.Clipboard]::SetText($txtLyrics.Text)
        [System.Windows.Forms.MessageBox]::Show("✓ បានចម្លង Lyrics រួចរាល់!", "Suno Studio", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})
$bottomBar.Controls.Add($btnCopyLyrics)

# 4b. Open in Google Chrome (New Browser Engine) Button
$btnOpenChrome = New-Object System.Windows.Forms.Button
$btnOpenChrome.Text = "🌐 បើក Browser ថ្មី (Chrome)"
$btnOpenChrome.Font = New-Object System.Drawing.Font("Segoe UI", 9.0, [System.Drawing.FontStyle]::Bold)
$btnOpenChrome.Size = New-Object System.Drawing.Size 195, 40
$btnOpenChrome.Location = New-Object System.Drawing.Point(658, 12)
$btnOpenChrome.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$btnOpenChrome.ForeColor = [System.Drawing.Color]::White
$btnOpenChrome.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenChrome.FlatAppearance.BorderSize = 0
$btnOpenChrome.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnOpenChrome.Add_Click({
    $chromeBat = Join-Path $appDir "SunoChrome.bat"
    if (Test-Path $chromeBat) {
        Start-Process $chromeBat
    }
})
$bottomBar.Controls.Add($btnOpenChrome)

# 5. Close Button
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "✕ បិទ (Close)"
$btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnClose.Size = New-Object System.Drawing.Size 110, 40
$btnClose.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnClose.Location = New-Object System.Drawing.Point(920, 12)
$btnClose.BackColor = [System.Drawing.Color]::FromArgb(28, 29, 36)
$btnClose.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 210)
$btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.FlatAppearance.BorderSize = 0
$btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClose.Add_Click({ $form.Close() })
$bottomBar.Controls.Add($btnClose)

# Form Load Event (Guarantee perfect split distance and initial selections)
$form.Add_Load({
    try {
        $split.SplitterDistance = 400
    } catch { }
    Resize-LeftPanel
    Resize-RightPanel
    $themeListBox.SelectedIndex = 0
    $styleCombo.SelectedIndex = 0
    Update-Preview
})

# ESC key to close
$form.KeyPreview = $true
$form.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $form.Close()
    }
})

# Show Dialog or Run
[System.Windows.Forms.Application]::Run($form)
