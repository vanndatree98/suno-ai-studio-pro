Set objFSO = CreateObject("Scripting.FileSystemObject")
strDir = objFSO.GetParentFolderName(WScript.ScriptFullName)
strPS1 = objFSO.BuildPath(strDir, "SunoPlaylistDownloader.ps1")

Dim args
args = ""
For i = 0 To WScript.Arguments.Count - 1
    args = args & " """ & WScript.Arguments(i) & """"
Next

strCommand = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & strPS1 & """" & args

Set objShell = CreateObject("WScript.Shell")
objShell.Run strCommand, 0, False
