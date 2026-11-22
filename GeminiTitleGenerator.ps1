param(
    [string]$topic = "",
    [string]$style = "",
    [string]$lyrics = ""
)

$ErrorActionPreference = "SilentlyContinue"

# Check single instance
$mutexName = "Local\GeminiTitleGenerator_App_Mutex_65432"
$isNew = $false
$appMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$isNew)

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

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Win32Title {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public static IntPtr FindTitleWindow() {
        IntPtr found = IntPtr.Zero;
        EnumWindows((hWnd, lParam) => {
            if (IsWindowVisible(hWnd)) {
                var sb = new StringBuilder(256);
                GetWindowText(hWnd, sb, 256);
                string title = sb.ToString();
                if (title.Contains("Gemini 3.1 - Auto Song Title") || title.Contains("បង្កើតចំណងជើងចម្រៀង")) {
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
    $cWnd = [Win32Title]::GetConsoleWindow()
    if ($cWnd -ne [IntPtr]::Zero) { [Win32Title]::ShowWindow($cWnd, 0) | Out-Null }
} catch { }

if (-not $isNew) {
    $existingHwnd = [Win32Title]::FindTitleWindow()
    if ($existingHwnd -ne [IntPtr]::Zero) {
        [Win32Title]::ShowWindow($existingHwnd, 9)
        [Win32Title]::SetForegroundWindow($existingHwnd)
        exit 0
    } else {
        Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*GeminiTitleGenerator.ps1*" -and $_.ProcessId -ne $PID } | ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
        }
        Start-Sleep -Milliseconds 400
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$sunoDir = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Programs\Suno" } else { "C:\Users\PS\AppData\Local\Programs\Suno" }
$configFile = Join-Path $sunoDir "gemini_config.json"
$titleQueueFile = Join-Path $sunoDir "title_queue.json"
$iconPath = Join-Path $sunoDir "app.ico"

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
        if ($null -ne $rawConfig.autoFillSuno) { $config.autoFillSuno = [bool]$rawConfig.autoFillSuno }
        if ($rawConfig.language) { $config.language = $rawConfig.language }
        if ($rawConfig.customLanguage) { $config.customLanguage = $rawConfig.customLanguage }
    } catch { }
}

function Save-Config {
    try {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false); [System.IO.File]::WriteAllText($configFile, ($config | ConvertTo-Json -Depth 3), $utf8NoBom)
    } catch { }
}

# Main Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Gemini 3.1 - Auto Song Title Generator for Suno"
$form.Width = 920
$form.Height = 780
$form.MinimumSize = New-Object System.Drawing.Size(820, 680)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

if (Test-Path $iconPath) {
    try { $form.Icon = New-Object System.Drawing.Icon($iconPath) } catch { }
}

# Dark Titlebar API
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DwmHelperTitle {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}
"@
$form.Add_HandleCreated({
    try {
        $val = 1
        [DwmHelperTitle]::DwmSetWindowAttribute($form.Handle, 20, [ref]$val, [System.Runtime.InteropServices.Marshal]::SizeOf($val))
        [DwmHelperTitle]::DwmSetWindowAttribute($form.Handle, 35, [ref]$val, [System.Runtime.InteropServices.Marshal]::SizeOf($val))
    } catch { }
})

# Root Layout
$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock = [System.Windows.Forms.DockStyle]::Fill
$root.RowCount = 5
$root.ColumnCount = 1
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 70)))  # Header
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 45)))  # API Key Bar
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 190))) # Inputs
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))  # Results
$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 55)))  # Footer
$form.Controls.Add($root)

# 1. Header Panel
$header = New-Object System.Windows.Forms.Panel
$header.Dock = [System.Windows.Forms.DockStyle]::Fill
$header.BackColor = [System.Drawing.Color]::FromArgb(26, 22, 38)
$header.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "✨ កម្មវិធីបង្កើតចំណងជើងបទចម្រៀង AI ដោយ Gemini 3.1"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(196, 181, 253)
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(20, 12)
$header.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "ស្វ័យប្រវត្តិតាមបច្ចេកវិទ្យា Google Gemini 3.1 • បញ្ចូលដោយផ្ទាល់ទៅក្នុង Suno Song Title (Optional)"
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(160, 150, 185)
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(22, 40)
$header.Controls.Add($lblSub)
$root.Controls.Add($header, 0, 0)

# 2. API Key & Model Bar
$apiBar = New-Object System.Windows.Forms.Panel
$apiBar.Dock = [System.Windows.Forms.DockStyle]::Fill
$apiBar.BackColor = [System.Drawing.Color]::FromArgb(22, 20, 30)
$apiBar.Padding = New-Object System.Windows.Forms.Padding(20, 6, 20, 6)

$lblModel = New-Object System.Windows.Forms.Label
$lblModel.Text = "Model:"
$lblModel.ForeColor = [System.Drawing.Color]::FromArgb(167, 139, 250)
$lblModel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblModel.Location = New-Object System.Drawing.Point(20, 12)
$lblModel.Size = New-Object System.Drawing.Size(55, 20)
$apiBar.Controls.Add($lblModel)

$geminiModels = @(
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

$cmbModel = New-Object System.Windows.Forms.ComboBox
$cmbModel.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbModel.BackColor = [System.Drawing.Color]::FromArgb(35, 30, 48)
$cmbModel.ForeColor = [System.Drawing.Color]::White
$cmbModel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
foreach ($m in $geminiModels) {
    $cmbModel.Items.Add($m.name) | Out-Null
}
$initIdx = 0
for ($i = 0; $i -lt $geminiModels.Count; $i++) {
    if ($geminiModels[$i].id -eq $config.model) {
        $initIdx = $i
        break
    }
}
$cmbModel.SelectedIndex = $initIdx
$cmbModel.Location = New-Object System.Drawing.Point(75, 9)
$cmbModel.Size = New-Object System.Drawing.Size(260, 26)

# Auto-Bind across the entire system when selected
$cmbModel.Add_SelectedIndexChanged({
    $selIdx = $cmbModel.SelectedIndex
    if ($selIdx -ge 0 -and $selIdx -lt $geminiModels.Count) {
        $selectedCode = $geminiModels[$selIdx].id
        $config.model = $selectedCode
        Save-Config
        # Broadcast to SunoApp / studio.js via song_queue.json
        try {
            $qFile = Join-Path $sunoDir "song_queue.json"
            $qList = if (Test-Path $qFile) { Get-Content $qFile -Raw | ConvertFrom-Json } else { @() }
            if ($qList -isnot [System.Collections.IList]) { $qList = @($qList) }
            $qList += @{ action = "set_gemini_model"; model = $selectedCode; processed = $false }
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false); [System.IO.File]::WriteAllText($qFile, ($qList | ConvertTo-Json -Depth 3), $utf8NoBom)
        } catch { }
    }
})
$apiBar.Controls.Add($cmbModel)

$lblKey = New-Object System.Windows.Forms.Label
$lblKey.Text = "Gemini Key:"
$lblKey.ForeColor = [System.Drawing.Color]::FromArgb(167, 139, 250)
$lblKey.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblKey.Location = New-Object System.Drawing.Point(350, 12)
$lblKey.Size = New-Object System.Drawing.Size(85, 20)
$apiBar.Controls.Add($lblKey)

$txtApiKey = New-Object System.Windows.Forms.TextBox
$txtApiKey.PasswordChar = '*'
$txtApiKey.BackColor = [System.Drawing.Color]::FromArgb(35, 30, 48)
$txtApiKey.ForeColor = [System.Drawing.Color]::White
$txtApiKey.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtApiKey.Location = New-Object System.Drawing.Point(435, 10)
$txtApiKey.Size = New-Object System.Drawing.Size(270, 24)
$txtApiKey.Text = $config.apiKey
$apiBar.Controls.Add($txtApiKey)

$btnSaveKey = New-Object System.Windows.Forms.Button
$btnSaveKey.Text = "រក្សាទុក Key"
$btnSaveKey.BackColor = [System.Drawing.Color]::FromArgb(139, 92, 246)
$btnSaveKey.ForeColor = [System.Drawing.Color]::White
$btnSaveKey.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSaveKey.FlatAppearance.BorderSize = 0
$btnSaveKey.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$btnSaveKey.Location = New-Object System.Drawing.Point(715, 9)
$btnSaveKey.Size = New-Object System.Drawing.Size(95, 26)
$btnSaveKey.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnSaveKey.Add_Click({
    $config.apiKey = $txtApiKey.Text.Trim()
    Save-Config
    [System.Windows.Forms.MessageBox]::Show("បានរក្សាទុក Gemini API Key ដោយជោគជ័យ!", "Gemini 3.1", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
})
$apiBar.Controls.Add($btnSaveKey)

$root.Controls.Add($apiBar, 0, 1)

# 3. Inputs Area
$inputPanel = New-Object System.Windows.Forms.Panel
$inputPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$inputPanel.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
$inputPanel.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)

# Field 1: Topic / Concept
$lblTopic = New-Object System.Windows.Forms.Label
$lblTopic.Text = "១. គំនិត ឬប្រធានបទបទចម្រៀង (Song Topic / Idea):"
$lblTopic.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 160)
$lblTopic.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblTopic.Location = New-Object System.Drawing.Point(20, 10)
$lblTopic.Size = New-Object System.Drawing.Size(380, 20)
$inputPanel.Controls.Add($lblTopic)

$txtTopic = New-Object System.Windows.Forms.TextBox
$txtTopic.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 36)
$txtTopic.ForeColor = [System.Drawing.Color]::White
$txtTopic.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtTopic.Location = New-Object System.Drawing.Point(20, 32)
$txtTopic.Size = New-Object System.Drawing.Size(410, 26)
$txtTopic.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$txtTopic.Text = if ($topic) { $topic } else { "ស្នេហាចម្ងាយ, រាត្រីកាហ្វេ, ដើរលេងមាត់សមុទ្រ" }
$inputPanel.Controls.Add($txtTopic)

# Field 2: Style / Genre
$lblStyle = New-Object System.Windows.Forms.Label
$lblStyle.Text = "២. រចនាបថភ្លេង / ស្ទីល (Music Style / Genre):"
$lblStyle.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 160)
$lblStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblStyle.Location = New-Object System.Drawing.Point(450, 10)
$lblStyle.Size = New-Object System.Drawing.Size(380, 20)
$inputPanel.Controls.Add($lblStyle)

$txtStyle = New-Object System.Windows.Forms.TextBox
$txtStyle.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 36)
$txtStyle.ForeColor = [System.Drawing.Color]::White
$txtStyle.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtStyle.Location = New-Object System.Drawing.Point(450, 32)
$txtStyle.Size = New-Object System.Drawing.Size(430, 26)
$txtStyle.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$txtStyle.Text = if ($style) { $style } else { "Khmer Acoustic Guitar, soft melodic vocals, emotional ballad, 82 bpm" }
$inputPanel.Controls.Add($txtStyle)

# Field 3: Lyrics snippet
$lblLyrics = New-Object System.Windows.Forms.Label
$lblLyrics.Text = "៣. ទំនុកច្រៀងសង្ខេប ឬឃ្លាគន្លឹះ (Lyrics Excerpt / Keywords) [ជាជម្រើស]:"
$lblLyrics.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 200)
$lblLyrics.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblLyrics.Location = New-Object System.Drawing.Point(20, 68)
$lblLyrics.Size = New-Object System.Drawing.Size(500, 18)
$inputPanel.Controls.Add($lblLyrics)

$txtLyrics = New-Object System.Windows.Forms.TextBox
$txtLyrics.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 36)
$txtLyrics.ForeColor = [System.Drawing.Color]::FromArgb(210, 210, 225)
$txtLyrics.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtLyrics.Location = New-Object System.Drawing.Point(20, 88)
$txtLyrics.Size = New-Object System.Drawing.Size(860, 42)
$txtLyrics.Multiline = $true
$txtLyrics.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$txtLyrics.Text = if ($lyrics) { $lyrics } else { "នឹកឃើញគ្រាដំបូងដែលជួបគ្នា កែវភ្នែកស្រទន់សម្លឹងមើលមកបង..." }
$inputPanel.Controls.Add($txtLyrics)

# Big Generate Button
$btnGenerate = New-Object System.Windows.Forms.Button
$btnGenerate.Text = "✨ បង្កើតចំណងជើងដោយ Gemini 3.1 (Generate 5 Titles)"
$btnGenerate.BackColor = [System.Drawing.Color]::FromArgb(139, 92, 246)
$btnGenerate.ForeColor = [System.Drawing.Color]::White
$btnGenerate.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnGenerate.FlatAppearance.BorderSize = 0
$btnGenerate.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$btnGenerate.Location = New-Object System.Drawing.Point(20, 138)
$btnGenerate.Size = New-Object System.Drawing.Size(860, 40)
$btnGenerate.Cursor = [System.Windows.Forms.Cursors]::Hand
$inputPanel.Controls.Add($btnGenerate)

$root.Controls.Add($inputPanel, 0, 2)

# 4. Results Area (Scrollable FlowLayoutPanel)
$resultsGroup = New-Object System.Windows.Forms.GroupBox
$resultsGroup.Text = "💡 ជម្រើសចំណងជើងបង្កើតដោយ Gemini 3.1 (ចុច '⚡ បញ្ចូលក្នុង Suno' ឬ '📋 Copy')"
$resultsGroup.ForeColor = [System.Drawing.Color]::FromArgb(196, 181, 253)
$resultsGroup.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$resultsGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
$resultsGroup.Padding = New-Object System.Windows.Forms.Padding(15, 10, 15, 10)

$flowResults = New-Object System.Windows.Forms.FlowLayoutPanel
$flowResults.Dock = [System.Windows.Forms.DockStyle]::Fill
$flowResults.AutoScroll = $true
$flowResults.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
$flowResults.WrapContents = $false
$flowResults.Padding = New-Object System.Windows.Forms.Padding(5)
$resultsGroup.Controls.Add($flowResults)

$root.Controls.Add($resultsGroup, 0, 3)

# 5. Footer Panel
$footer = New-Object System.Windows.Forms.Panel
$footer.Dock = [System.Windows.Forms.DockStyle]::Fill
$footer.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 20)
$footer.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "🟢 រួចរាល់សម្រាប់ការបង្កើតចំណងជើង"
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblStatus.Location = New-Object System.Drawing.Point(20, 16)
$lblStatus.Size = New-Object System.Drawing.Size(400, 22)
$footer.Controls.Add($lblStatus)

$btnOpenSuno = New-Object System.Windows.Forms.Button
$btnOpenSuno.Text = "🚀 បើកកម្មវិធី Suno Desktop"
$btnOpenSuno.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 48)
$btnOpenSuno.ForeColor = [System.Drawing.Color]::White
$btnOpenSuno.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOpenSuno.FlatAppearance.BorderSize = 1
$btnOpenSuno.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60, 60, 80)
$btnOpenSuno.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnOpenSuno.Location = New-Object System.Drawing.Point(670, 12)
$btnOpenSuno.Size = New-Object System.Drawing.Size(210, 32)
$btnOpenSuno.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnOpenSuno.Add_Click({
    $sunoScript = Join-Path $sunoDir "SunoApp.ps1"
    Start-Process "powershell.exe" -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$sunoScript`""
})
$footer.Controls.Add($btnOpenSuno)

$root.Controls.Add($footer, 0, 4)

# --- SEND TO SUNO FUNCTION ---
function Send-TitleToSuno([string]$chosenTitle) {
    if (-not $chosenTitle) { return }
    
    # 1. Copy to clipboard
    [System.Windows.Forms.Clipboard]::SetText($chosenTitle)

    # 2. Write to title_queue.json
    try {
        $qList = [System.Collections.Generic.List[object]]::new()
        if (Test-Path $titleQueueFile) {
            $raw = Get-Content $titleQueueFile -Raw -ErrorAction SilentlyContinue
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
            title = $chosenTitle
            timestamp = [DateTime]::UtcNow.Ticks
            processed = $false
        })
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false); [System.IO.File]::WriteAllText($titleQueueFile, (ConvertTo-JsonArray $qList), $utf8NoBom)
    } catch { }

    # 3. Bring Suno to front
    $proc = Get-Process -ErrorAction SilentlyContinue | Where-Object { ($_.ProcessName -match "Suno AI Music|powershell|electron") -and ($_.MainWindowTitle -like "*Suno*") } | Select-Object -First 1
    if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
        [Win32Title]::ShowWindow($proc.MainWindowHandle, 9)
        [Win32Title]::SetForegroundWindow($proc.MainWindowHandle)
    }

    $lblStatus.Text = "✓ បានបញ្ជូនចំណងជើង `"$chosenTitle`" ចូលទៅក្នុង Suno រួចរាល់!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
}

# --- SMART AI FALLBACK TITLE ENGINE (DYNAMIC & UNIQUE) ---
function Generate-SmartFallbackTitles([string]$inTopic, [string]$inStyle, [string]$inLyrics) {
    $clean = $inTopic.Trim() -replace '^(បទ|ចម្រៀង|បទចម្រៀង)[\s៖:]*', ''
    $prefixes = @('ស្រមោល', 'រាត្រី', 'អនុស្សាវរីយ៍', 'ចង្វាក់', 'ដំណក់', 'សំឡេង', 'រលក', 'ក្លិន', 'បេះដូង', 'ក្តីសង្ឃឹម', 'វេលា', 'ផ្កាយ', 'ជំនោរ', 'រដូវ', 'ពន្លឺ', 'ទឹកភ្នែក', 'ស្នាមញញឹម', 'សុបិន', 'ចម្រៀង', 'ដួងចិត្ត', 'ដានជើង', 'ខ្យល់បក់', 'ចម្លើយ', 'សន្យា', 'មន្តស្នេហ៍', 'ក្តីស្រមៃ')
    $themes = @('ស្នេហ៍ស្មោះ', 'នឹកមនុស្សម្នាក់', 'កោះរ៉ុង', 'ភ្នំពេញរាត្រី', 'សៀមរាបអង្គរ', 'កាហ្វេរាត្រី', 'មាត់សមុទ្រ', 'ខ្យល់ត្រជាក់', 'ចាកចេញឆ្ងាយ', 'ការចងចាំ', 'ផ្ការំដួល', 'ស្នេហ៍កណ្តាលភ្លៀង', 'ព្រះចន្ទពេញវង់', 'ពន្លឺថ្ងៃថ្មី', 'បេះដូងឯកា', 'ផ្លូវឆ្ងាយ', 'ស្រុកកំណើត', 'ម្លប់ជ្រៃចាស់', 'ស្នេហ៍គ្រាដំបូង', 'មនុស្សក្នុងសុបិន')
    $suffixes = @('(Acoustic Melody)', '(Midnight Mix)', '(Heartbeat Ballad)', '(Emotional Version)', '(Drift Phonk Vibe)', '[Lo-Fi Dream]', '(Deep Emotion)', '[Classic Khmer Pop]', '(Lost in Thought)', '[Soulful R&B]', '(Endless Love)', '[Pristine Studio Mix]', '(Whisper of Night)', '[Romantic Chill]', '(Sunset Acoustic)', '[Echo of Love]')

    $list = @()
    $used = New-Object 'System.Collections.Generic.HashSet[string]'
    $attempts = 0
    while ($list.Count -lt 5 -and $attempts -lt 80) {
        $attempts++
        $p = $prefixes[(Get-Random -Maximum $prefixes.Count)]
        $t = $themes[(Get-Random -Maximum $themes.Count)]
        $s = $suffixes[(Get-Random -Maximum $suffixes.Count)]

        $title = if ($clean -and $attempts -le 25) {
            $r = Get-Random -Maximum 3
            if ($r -eq 0) { "$clean $s" }
            elseif ($r -eq 1) { "$p$clean $s" }
            else { "រឿងរ៉ាវ `"$clean`" $s" }
        } else {
            "$p$t $s"
        }

        if (-not $used.Contains($title)) {
            $used.Add($title) | Out-Null
            $list += $title
        }
    }
    return $list | Select-Object -First 5
}

# --- GENERATE HANDLER ---
$btnGenerate.Add_Click({
    $top = $txtTopic.Text.Trim()
    $sty = $txtStyle.Text.Trim()
    $lyr = $txtLyrics.Text.Trim()
    $key = $txtApiKey.Text.Trim()
    $modelIdx = $cmbModel.SelectedIndex
    $modelCode = if ($modelIdx -ge 0 -and $modelIdx -lt $geminiModels.Count) { $geminiModels[$modelIdx].id } else { "gemini-3.1-flash-lite" }

    $btnGenerate.Enabled = $false
    $btnGenerate.Text = "⏳ Gemini 3.1 កំពុងបង្កើតចំណងជើង..."
    $lblStatus.Text = "⏳ កំពុងដំណើរការបង្កើតចំណងជើង..."
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(236, 72, 153)
    $form.Update()

    $generatedTitles = @()
    $usedApi = $false

    if ($key -and $modelCode -ne "smart_engine") {
        try {
            $langDirectives = @{
                "km" = "Khmer language (ភាសាខ្មែរ) with poetic Khmer vocabulary, idioms, and natural rhythm"
                "en" = "English language with catchy, hit-worthy English phrasing"
                "zh" = "Chinese Mandarin (中文) with poetic phrasing"
                "ja" = "Japanese language (日本語) with emotive J-Pop/Anime lyrical style"
                "ko" = "Korean language (한국어) with catchy K-Pop / K-Ballad rhythm"
                "th" = "Thai language (ภาษาไทย) with melodic Thai phrasing"
                "vi" = "Vietnamese language (Tiếng Việt) with poetic tones"
                "fr" = "French language (Français) with romantic, elegant French phrasing"
                "es" = "Spanish language (Español) with passionate, rhythmic Spanish style"
                "de" = "German language (Deutsch) with expressive, rhythmic structure"
                "it" = "Italian language (Italiano) with melodic, emotive songwriting"
                "ru" = "Russian language (Русский) with atmospheric, emotive Russian lyrics"
                "hi" = "Hindi language (हिन्दी) with Bollywood / Indie pop melodic flair"
                "km_en" = "Bilingual Khmer & English mix"
            }
            $curLangDir = if ($config.language -eq "custom" -and $config.customLanguage) { "$($config.customLanguage) language" } elseif ($langDirectives.ContainsKey($config.language)) { $langDirectives[$config.language] } else { "Khmer language (ភាសាខ្មែរ)" }

            $prompt = @"
You are a professional hit songwriter and song title specialist for Suno AI music creation.
Generate 5 catchy, viral, poetic, and creative song titles written in $curLangDir for Suno based on these details:
- Song Theme/Idea: "$top"
- Music Style: "$sty"
- Lyrics Excerpt: "$lyr"

Guidelines:
1. Provide creative titles written in $curLangDir that are memorable and hit-worthy.
2. Titles must be diverse in mood: from poetic to energetic and emotional.
3. Return ONLY a valid JSON array of exactly 5 strings:
["Title 1", "Title 2", "Title 3", "Title 4", "Title 5"]
"@

            $reqBody = @{
                contents = @(
                    @{ parts = @( @{ text = $prompt } ) }
                )
                generationConfig = @{
                    temperature = 0.85
                    maxOutputTokens = 350
                }
            } | ConvertTo-Json -Depth 5

            $url = "https://generativelanguage.googleapis.com/v1beta/models/${modelCode}:generateContent?key=${key}"
            $res = Invoke-RestMethod -Uri $url -Method Post -Body $reqBody -ContentType "application/json; charset=utf-8" -TimeoutSec 15
            
            $rawText = $res.candidates[0].content.parts[0].text
            if ($rawText) {
                $cleanJson = $rawText -replace '(?s)```json\s*', '' -replace '```', ''
                $cleanJson = $cleanJson.Trim()
                $parsed = $cleanJson | ConvertFrom-Json
                if ($parsed -is [System.Array] -and $parsed.Count -gt 0) {
                    $generatedTitles = @($parsed | ForEach-Object { $_.ToString().Trim() })
                    $usedApi = $true
                }
            }
        } catch {
            # Fallback
        }
    }

    if ($generatedTitles.Count -eq 0) {
        $generatedTitles = Generate-SmartFallbackTitles $top $sty $lyr
    }

    # Populate Results Cards
    $flowResults.Controls.Clear()
    $cardWidth = 830

    for ($i = 0; $i -lt $generatedTitles.Count; $i++) {
        $t = $generatedTitles[$i]
        $isTop = ($i -eq 0)

        $card = New-Object System.Windows.Forms.Panel
        $card.Width = $cardWidth
        $card.Height = 56
        $card.BackColor = if ($isTop) { [System.Drawing.Color]::FromArgb(38, 30, 58) } else { [System.Drawing.Color]::FromArgb(25, 23, 34) }
        $card.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)

        $lblBadge = New-Object System.Windows.Forms.Label
        $lblBadge.Text = if ($isTop) { "⭐ #1" } else { "💡 #$($i+1)" }
        $lblBadge.ForeColor = if ($isTop) { [System.Drawing.Color]::FromArgb(251, 191, 36) } else { [System.Drawing.Color]::FromArgb(167, 139, 250) }
        $lblBadge.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
        $lblBadge.Location = New-Object System.Drawing.Point(12, 17)
        $lblBadge.Size = New-Object System.Drawing.Size(55, 22)
        $card.Controls.Add($lblBadge)

        $txtBox = New-Object System.Windows.Forms.TextBox
        $txtBox.Text = $t
        $txtBox.BackColor = if ($isTop) { [System.Drawing.Color]::FromArgb(26, 20, 42) } else { [System.Drawing.Color]::FromArgb(20, 18, 28) }
        $txtBox.ForeColor = if ($isTop) { [System.Drawing.Color]::FromArgb(255, 225, 170) } else { [System.Drawing.Color]::White }
        $txtBox.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
        $txtBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $txtBox.Location = New-Object System.Drawing.Point(70, 14)
        $txtBox.Size = New-Object System.Drawing.Size(520, 28)
        $card.Controls.Add($txtBox)

        # Copy Button
        $btnCopy = New-Object System.Windows.Forms.Button
        $btnCopy.Text = "📋 Copy"
        $btnCopy.BackColor = [System.Drawing.Color]::FromArgb(45, 42, 60)
        $btnCopy.ForeColor = [System.Drawing.Color]::FromArgb(220, 215, 240)
        $btnCopy.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btnCopy.FlatAppearance.BorderSize = 0
        $btnCopy.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $btnCopy.Location = New-Object System.Drawing.Point(600, 13)
        $btnCopy.Size = New-Object System.Drawing.Size(80, 28)
        $btnCopy.Cursor = [System.Windows.Forms.Cursors]::Hand
        $titleToCopy = $t
        $btnCopy.Add_Click({
            [System.Windows.Forms.Clipboard]::SetText($titleToCopy)
            $lblStatus.Text = "✓ បានចម្លង `"$titleToCopy`" ទៅក្នុង Clipboard!"
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
        })
        $card.Controls.Add($btnCopy)

        # Send to Suno Button
        $btnSend = New-Object System.Windows.Forms.Button
        $btnSend.Text = "⚡ បញ្ចូលក្នុង Suno"
        $btnSend.BackColor = if ($isTop) { [System.Drawing.Color]::FromArgb(16, 185, 129) } else { [System.Drawing.Color]::FromArgb(139, 92, 246) }
        $btnSend.ForeColor = [System.Drawing.Color]::White
        $btnSend.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btnSend.FlatAppearance.BorderSize = 0
        $btnSend.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $btnSend.Location = New-Object System.Drawing.Point(688, 13)
        $btnSend.Size = New-Object System.Drawing.Size(130, 28)
        $btnSend.Cursor = [System.Windows.Forms.Cursors]::Hand
        $titleToSend = $t
        $btnSend.Add_Click({
            Send-TitleToSuno $titleToSend
        })
        $card.Controls.Add($btnSend)

        $flowResults.Controls.Add($card)
    }

    $btnGenerate.Enabled = $true
    $btnGenerate.Text = "✨ បង្កើតចំណងជើងដោយ Gemini 3.1 (Generate 5 Titles)"
    $sourceNote = if ($usedApi) { "Gemini 3.1 API ($modelCode)" } else { "Smart AI Title Engine" }
    $lblStatus.Text = "✅ បានបង្កើតចំណងជើង ៥ ជម្រើសដោយជោគជ័យតាម $sourceNote!"
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
})

# Initial Generation on load
$form.Add_Shown({
    $btnGenerate.PerformClick()
})

$form.Add_FormClosing({
    param($s, $e)
    if ($appMutex) {
        try { $appMutex.ReleaseMutex() } catch { }
        $appMutex.Dispose()
    }
})

[System.Windows.Forms.Application]::Run($form)
