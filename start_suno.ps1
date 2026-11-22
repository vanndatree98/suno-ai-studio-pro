$ErrorActionPreference = "SilentlyContinue"

# Check if an existing Suno window is open
$existing = Get-Process -Name "powershell" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*Suno*" }
if ($existing) {
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class WinApi {
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    }
"@
    [WinApi]::ShowWindow($existing.MainWindowHandle, 9)
    [WinApi]::SetForegroundWindow($existing.MainWindowHandle)
    exit 0
}

# Launch SunoApp.ps1 completely silent
Start-Process "powershell.exe" -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"C:\Users\PS\AppData\Local\Programs\Suno\SunoApp.ps1`"" -NoNewWindow
