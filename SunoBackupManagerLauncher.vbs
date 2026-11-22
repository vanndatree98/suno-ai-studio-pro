Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\Users\PS\AppData\Local\Programs\Suno\SunoBackupManager.ps1""", 0, False
