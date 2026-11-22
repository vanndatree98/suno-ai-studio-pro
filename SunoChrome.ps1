# ==============================================================================
# Suno AI Studio Pro - Modern Google Chrome Runner (SunoChrome.ps1)
# Launches 100% Native Google Chrome with Suno Studio Extension & Real-Time IPC
# Solves Cloudflare Turnstile, CSP blocks, and anti-bot challenges natively!
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$sunoDir = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Programs\Suno" } else { "C:\Users\PS\AppData\Local\Programs\Suno" }
$extDir = Join-Path $sunoDir "chrome_extension"
$dataDir = Join-Path $sunoDir "Data"
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
}
$chromeUserData = Join-Path $dataDir "ChromeUserData"

if (-not (Test-Path $chromeUserData)) {
    New-Item -ItemType Directory -Force -Path $chromeUserData | Out-Null
}

# 1. Sync latest studio.js to extension folder
$srcStudio = Join-Path $sunoDir "studio.js"
$destStudio = Join-Path $extDir "studio.js"
if (Test-Path $srcStudio) {
    Copy-Item $srcStudio $destStudio -Force
}

# 2. Find Google Chrome binary
$chromePaths = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
)

$chromeExe = $null
foreach ($p in $chromePaths) {
    if (Test-Path $p) {
        $chromeExe = $p
        break
    }
}

if (-not $chromeExe) {
    # Fallback to Edge if Chrome is missing
    $edgePaths = @(
        "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
    )
    foreach ($p in $edgePaths) {
        if (Test-Path $p) {
            $chromeExe = $p
            break
        }
    }
}

if (-not $chromeExe) {
    Write-Error "រកមិនឃើញ Google Chrome ឬ Microsoft Edge នៅលើកុំព្យូទ័រឡើយ!"
    exit 1
}

Write-Host "🚀 កំពុងបើកដំណើរការ Suno Studio លើ Browser ថ្មី (Google Chrome): $chromeExe" -ForegroundColor Cyan

# 3. Start local HTTP Queue Bridge for Chrome on http://127.0.0.1:48999/
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:48999/")
try {
    $listener.Start()
    Write-Host "✓ បានបើកដំណើរការ Local Queue Bridge (Port 48999) ជោគជ័យ!" -ForegroundColor Green
} catch {
    Write-Host "⚠️ Warning: Listener failed or already running: $_" -ForegroundColor Yellow
}

# 4. Launch Chrome in App Mode with the extension loaded
$chromeArgs = @(
    "--app=https://suno.com/create",
    "--load-extension=`"$extDir`"",
    "--user-data-dir=`"$chromeUserData`"",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-features=Translate"
)

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $chromeExe
$psi.Arguments = [string]::Join(" ", $chromeArgs)
$psi.UseShellExecute = $false
$chromeProc = [System.Diagnostics.Process]::Start($psi)

# 5. Background Queue Service Loop
$songQueuePath = Join-Path $sunoDir "song_queue.json"
$queueInputPath = Join-Path $sunoDir "queue_input.json"

try {
    while ($listener.IsListening -and ($chromeProc -and -not $chromeProc.HasExited)) {
        $contextAsync = $listener.BeginGetContext($null, $null)
        $waitHandle = $contextAsync.AsyncWaitHandle
        if ($waitHandle.WaitOne(600)) {
            $context = $listener.EndGetContext($contextAsync)
            $req = $context.Request
            $resp = $context.Response
            $resp.AddHeader("Access-Control-Allow-Origin", "*")
            $resp.AddHeader("Access-Control-Allow-Headers", "*")
            $resp.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")

            if ($req.HttpMethod -eq "OPTIONS") {
                $resp.StatusCode = 200
                $resp.Close()
                continue
            }

            $rawPath = $req.Url.AbsolutePath
            if ($rawPath -eq "/poll") {
                $pendingItems = [System.Collections.Generic.List[PSObject]]::new()

                # Read song_queue.json
                if (Test-Path $songQueuePath) {
                    try {
                        $content = Get-Content $songQueuePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                        if ($content -and $content.Trim() -ne "[]") {
                            $parsed = $content | ConvertFrom-Json
                            if ($parsed -is [System.Array]) {
                                foreach ($it in $parsed) { $pendingItems.Add($it) }
                            } elseif ($parsed) {
                                $pendingItems.Add($parsed)
                            }
                            Set-Content $songQueuePath "[]" -Encoding UTF8
                        }
                    } catch { }
                }

                # Read queue_input.json
                if (Test-Path $queueInputPath) {
                    try {
                        $content = Get-Content $queueInputPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                        if ($content -and $content.Trim() -ne "[]") {
                            $parsed = $content | ConvertFrom-Json
                            if ($parsed -is [System.Array]) {
                                foreach ($it in $parsed) { $pendingItems.Add($it) }
                            } elseif ($parsed) {
                                $pendingItems.Add($parsed)
                            }
                            Remove-Item $queueInputPath -Force -ErrorAction SilentlyContinue
                        }
                    } catch { }
                }

                $jsonPayload = [PSCustomObject]@{ items = $pendingItems } | ConvertTo-Json -Depth 5 -Compress
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)
                $resp.ContentType = "application/json; charset=utf-8"
                $resp.ContentLength64 = $buffer.Length
                $resp.OutputStream.Write($buffer, 0, $buffer.Length)
                $resp.Close()
            } else {
                $statusPayload = '{"status":"ok","engine":"Google Chrome Native Suno Studio"}'
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($statusPayload)
                $resp.ContentType = "application/json; charset=utf-8"
                $resp.ContentLength64 = $buffer.Length
                $resp.OutputStream.Write($buffer, 0, $buffer.Length)
                $resp.Close()
            }
        }
    }
} finally {
    if ($listener.IsListening) {
        $listener.Stop()
        $listener.Close()
    }
}
