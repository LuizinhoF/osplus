' Hidden launcher for the OSPlus sidecar exe.
' Invoked by the Lua mod via: wscript.exe launch_hidden.vbs OSPlus.exe
' Window state 0 = hidden, bWaitOnReturn = False = async.
' Run via wscript (NOT cscript) so no console is allocated for the launcher itself.
Set oShell = CreateObject("WScript.Shell")
Set oFSO   = CreateObject("Scripting.FileSystemObject")
sScriptDir = oFSO.GetParentFolderName(WScript.ScriptFullName)
sExe       = oFSO.BuildPath(sScriptDir, WScript.Arguments(0))
oShell.CurrentDirectory = sScriptDir
oShell.Run """" & sExe & """", 0, False
