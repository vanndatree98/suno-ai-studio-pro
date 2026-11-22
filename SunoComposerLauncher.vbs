Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\Users\PS\AppData\Local\Programs\Suno\SunoComposerApp.ps1""", 0, False
