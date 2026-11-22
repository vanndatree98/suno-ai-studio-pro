Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\Users\PS\AppData\Local\Programs\Suno\SunoAudioStudio.ps1""", 0, False
