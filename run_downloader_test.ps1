$ErrorActionPreference = "Stop"

$sunoDir = "C:\Users\PS\AppData\Local\Programs\Suno"

[System.AppDomain]::CurrentDomain.add_AssemblyResolve({
    param($sender, $args)
    $name = $args.Name.Split(',')[0]
    $path = Join-Path "C:\Users\PS\AppData\Local\Programs\Suno" "$name.dll"
    if (Test-Path $path) {
        return [System.Reflection.Assembly]::LoadFrom($path)
    }
    return $null
})

$csPath = Join-Path $sunoDir "SunoDownloader.cs"

$refs = @(
    "System.dll",
    "System.Core.dll",
    "System.Drawing.dll",
    "System.Windows.Forms.dll",
    "System.Web.Extensions.dll",
    (Join-Path $sunoDir "Microsoft.Web.WebView2.Core.dll"),
    (Join-Path $sunoDir "Microsoft.Web.WebView2.WinForms.dll")
)

$code = Get-Content $csPath -Raw -Encoding UTF8

Add-Type -TypeDefinition $code -ReferencedAssemblies $refs

Write-Host "Success! SunoDownloader compiled and loaded into memory!"
