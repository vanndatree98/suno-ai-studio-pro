# ==============================================================================
# Suno AI Studio Pro - Network & Cloudflare Diagnostic Doctor (SunoNetworkDoctor.ps1)
# Ping, latency, DNS health check and Cloudflare Turnstile reachability suite
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# High DPI Awareness
$win32Dpi = @"
using System;
using System.Runtime.InteropServices;
public class SunoNetDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
try {
    Add-Type -TypeDefinition $win32Dpi -ErrorAction SilentlyContinue
    [SunoNetDpi]::SetProcessDPIAware() | Out-Null
} catch { }

$sunoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $sunoDir -or -not (Test-Path $sunoDir)) {
    $sunoDir = "C:\Users\PS\AppData\Local\Programs\Suno"
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "🌐 Suno AI Studio Pro - Network & Cloudflare Diagnostic Doctor"
$form.Size = New-Object System.Drawing.Size 940, 680
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
$lblTitle.Text = "🌐 Suno Network & Cloudflare Turnstile Diagnostic Doctor"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 13.0, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
$lblTitle.AutoSize = $true
$lblTitle.Location = New-Object System.Drawing.Point(18, 14)
$pnlHeader.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "ត្រួតពិនិត្យល្បឿន Ping, ការតភ្ជាប់ទៅកាន់ Suno Servers, Cloudflare Gateways, និងដោះស្រាយបញ្ហារាំងស្ទះ"
$lblSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.8)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(160, 175, 200)
$lblSub.AutoSize = $true
$lblSub.Location = New-Object System.Drawing.Point(20, 48)
$pnlHeader.Controls.Add($lblSub)

# DataGridView Results
$gridNet = New-Object System.Windows.Forms.DataGridView
$gridNet.Location = New-Object System.Drawing.Point(20, 105)
$gridNet.Size = New-Object System.Drawing.Size 885, 380
$gridNet.BackgroundColor = [System.Drawing.Color]::FromArgb(18, 21, 30)
$gridNet.ForeColor = [System.Drawing.Color]::FromArgb(230, 235, 245)
$gridNet.GridColor = [System.Drawing.Color]::FromArgb(30, 36, 50)
$gridNet.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$gridNet.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$gridNet.MultiSelect = $false
$gridNet.ReadOnly = $true
$gridNet.AllowUserToAddRows = $false
$gridNet.RowHeadersVisible = $false
$gridNet.EnableHeadersVisualStyles = $false
$gridNet.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(26, 32, 46)
$gridNet.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(56, 189, 248)
$gridNet.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9.2, [System.Drawing.FontStyle]::Bold)
$gridNet.ColumnHeadersHeight = 34
$gridNet.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(18, 21, 30)
$gridNet.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$gridNet.RowTemplate.Height = 32
$form.Controls.Add($gridNet)

$colStatus = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colStatus.HeaderText = "ស្ថានភាព"
$colStatus.Width = 110
$gridNet.Columns.Add($colStatus) | Out-Null

$colHost = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colHost.HeaderText = "Endpoint / Server"
$colHost.Width = 260
$gridNet.Columns.Add($colHost) | Out-Null

$colLatency = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colLatency.HeaderText = "Latency (ms)"
$colLatency.Width = 120
$gridNet.Columns.Add($colLatency) | Out-Null

$colRole = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colRole.HeaderText = "តួនាទីក្នុងប្រព័ន្ធ (Role)"
$colRole.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
$gridNet.Columns.Add($colRole) | Out-Null

# Bottom Actions Panel
$pnlBottom = New-Object System.Windows.Forms.Panel
$pnlBottom.Dock = [System.Windows.Forms.DockStyle]::Bottom
$pnlBottom.Height = 85
$pnlBottom.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 34)
$pnlBottom.Padding = New-Object System.Windows.Forms.Padding(20, 14, 20, 14)
$form.Controls.Add($pnlBottom)

$btnPingAll = New-Object System.Windows.Forms.Button
$btnPingAll.Text = "🔍 ស្កេនបណ្តាញឡើងវិញ (Test All)"
$btnPingAll.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnPingAll.Size = New-Object System.Drawing.Size 230, 42
$btnPingAll.Location = New-Object System.Drawing.Point(20, 16)
$btnPingAll.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$btnPingAll.ForeColor = [System.Drawing.Color]::White
$btnPingAll.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnPingAll.FlatAppearance.BorderSize = 0
$btnPingAll.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlBottom.Controls.Add($btnPingAll)

$btnFlushDNS = New-Object System.Windows.Forms.Button
$btnFlushDNS.Text = "🧹 សម្អាត DNS (Flush DNS)"
$btnFlushDNS.Font = New-Object System.Drawing.Font("Segoe UI", 9.2, [System.Drawing.FontStyle]::Bold)
$btnFlushDNS.Size = New-Object System.Drawing.Size 210, 42
$btnFlushDNS.Location = New-Object System.Drawing.Point(260, 16)
$btnFlushDNS.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$btnFlushDNS.ForeColor = [System.Drawing.Color]::White
$btnFlushDNS.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnFlushDNS.FlatAppearance.BorderSize = 0
$btnFlushDNS.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlBottom.Controls.Add($btnFlushDNS)

$btnRestartChrome = New-Object System.Windows.Forms.Button
$btnRestartChrome.Text = "🌐 បើក Suno Chrome Engine"
$btnRestartChrome.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnRestartChrome.Size = New-Object System.Drawing.Size 230, 42
$btnRestartChrome.Location = New-Object System.Drawing.Point(480, 16)
$btnRestartChrome.BackColor = [System.Drawing.Color]::FromArgb(45, 52, 70)
$btnRestartChrome.ForeColor = [System.Drawing.Color]::White
$btnRestartChrome.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRestartChrome.FlatAppearance.BorderSize = 0
$btnRestartChrome.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlBottom.Controls.Add($btnRestartChrome)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "✕ បិទ"
$btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
$btnClose.Size = New-Object System.Drawing.Size 95, 42
$btnClose.Location = New-Object System.Drawing.Point(805, 16)
$btnClose.BackColor = [System.Drawing.Color]::FromArgb(35, 40, 52)
$btnClose.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 215)
$btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.FlatAppearance.BorderSize = 0
$btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClose.Add_Click({ $form.Close() })
$pnlBottom.Controls.Add($btnClose)

function Run-NetworkAudit {
    $gridNet.Rows.Clear()
    $endpoints = @(
        @{ Url = "https://suno.com"; Role = "Suno Main Web Studio" },
        @{ Url = "https://studio-api.suno.ai"; Role = "Generation & Metadata API" },
        @{ Url = "https://audiopipe.suno.ai"; Role = "Real-Time Audio Streaming Pipeline" },
        @{ Url = "https://cdn1.suno.ai"; Role = "Song Media & MP3 Audio CDN" },
        @{ Url = "https://challenges.cloudflare.com"; Role = "Cloudflare Turnstile Verification Gate" },
        @{ Url = "http://127.0.0.1:48999"; Role = "Local IPC Bridge Port (Chrome Extension)" }
    )

    foreach ($ep in $endpoints) {
        $u = $ep.Url
        $role = $ep.Role
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $statusStr = ""
        $latStr = ""

        try {
            $req = [System.Net.HttpWebRequest]::Create($u)
            $req.Timeout = 4000
            $req.Method = "HEAD"
            $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) SunoDoctor/3.8"
            $resp = $req.GetResponse()
            $sw.Stop()
            $lat = $sw.ElapsedMilliseconds
            $resp.Close()

            $statusStr = "🟢 ល្អឥតខ្ចោះ"
            $latStr = "$lat ms"
        } catch {
            $sw.Stop()
            if ($_.Exception.Response) {
                # Got HTTP response (e.g. 403 or 404 is still reachable)
                $statusStr = "🟢 ភ្ជាប់បាន"
                $latStr = "$($sw.ElapsedMilliseconds) ms"
            } elseif ($u -like "*127.0.0.1*") {
                $statusStr = "ℹ️ ទំនេរ (Standby)"
                $latStr = "Ready"
            } else {
                $statusStr = "🔴 រាំងស្ទះ / យឺត"
                $latStr = "Timeout"
            }
        }

        $gridNet.Rows.Add($statusStr, $u, $latStr, $role) | Out-Null
    }
}

$btnPingAll.Add_Click({ Run-NetworkAudit })

$btnFlushDNS.Add_Click({
    $out = & ipconfig /flushdns 2>&1
    [System.Windows.Forms.MessageBox]::Show("បានសម្អាត DNS Resolver Cache ដោយជោគជ័យ!`n`n$out", "ជោគជ័យ", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Run-NetworkAudit
})

$btnRestartChrome.Add_Click({
    $launcher = Join-Path $sunoDir "SunoChrome.bat"
    if (Test-Path $launcher) {
        Start-Process "cmd.exe" "/c `"$launcher`"" -WindowStyle Hidden
    }
})

$form.Add_Shown({
    Run-NetworkAudit
})

[System.Windows.Forms.Application]::Run($form)
