Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\Users\PS\AppData\Local\Programs\Suno\SunoNetworkDoctor.ps1""", 0, False
