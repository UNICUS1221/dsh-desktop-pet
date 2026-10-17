' 无窗口启动 dsh-pet（路径按自身目录算，插件装到哪都能用）
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\pet.ps1"""
sh.Run cmd, 0, False
