' 无窗口启动 dsh-pet（路径按自身目录算，插件装到哪都能用）
' 注意：有些机器上 FSO 被组策略/安全软件禁用，CreateObject 会失败，
' 这里全程容错：拿不到 FSO 就用字符串截路径，拿不到 WScript.Shell 就静默退出，绝不弹窗。
On Error Resume Next
Dim fso, sh, dir, cmd

Set fso = CreateObject("Scripting.FileSystemObject")
If Err.Number <> 0 Then
  Err.Clear
  dir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\") - 1)
Else
  dir = fso.GetParentFolderName(WScript.ScriptFullName)
  Set fso = Nothing
End If

Set sh = CreateObject("WScript.Shell")
If Err.Number <> 0 Then WScript.Quit 1

cmd = "powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\pet.ps1"""
sh.Run cmd, 0, False
If Err.Number <> 0 Then WScript.Quit 1
