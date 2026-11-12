$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
try {
 $dest=Join-Path $env:LOCALAPPDATA 'HallaScanRenamer'
 New-Item -ItemType Directory -Force $dest | Out-Null
 Copy-Item -LiteralPath "$PSScriptRoot\App.ps1" -Destination $dest -Force
 # Draw a local icon, with no downloads.
 $b=New-Object Drawing.Bitmap(64,64); $g=[Drawing.Graphics]::FromImage($b); $g.Clear([Drawing.Color]::FromArgb(26,85,165)); $g.FillRectangle([Drawing.Brushes]::White,16,9,32,45); $pen=New-Object Drawing.Pen([Drawing.Color]::FromArgb(26,85,165),3); foreach($y in @(21,29,37)){$g.DrawLine($pen,22,$y,42,$y)}
 $icon=[Drawing.Icon]::FromHandle($b.GetHicon()); $s=[IO.File]::Create("$dest\App.ico");$icon.Save($s);$s.Dispose();$g.Dispose();$b.Dispose()
 $source=@'
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
class ScanRenamer {
 [STAThread] static void Main() {
  try {
   string root=AppDomain.CurrentDomain.BaseDirectory;
   string ps=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),@"System32\WindowsPowerShell\v1.0\powershell.exe");
   Process.Start(new ProcessStartInfo(ps,"-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \""+Path.Combine(root,"App.ps1")+"\""){UseShellExecute=false,CreateNoWindow=true});
  } catch(Exception e){MessageBox.Show(e.Message,"스캔 문서 이름 정리");}
 }
}
'@
 $exe=Join-Path $dest 'ScanRenamer.exe'
 if(Test-Path $exe){Remove-Item -LiteralPath $exe -Force}
 # Use one Add-Type parameter set; CompilerParameters conflicts with ReferencedAssemblies.
 Add-Type -TypeDefinition $source -Language CSharp -ReferencedAssemblies System.Windows.Forms -OutputAssembly $exe -OutputType WindowsApplication
 $shell=New-Object -ComObject WScript.Shell
 foreach($base in @([Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('Programs'))){
  $link=$shell.CreateShortcut((Join-Path $base '스캔 문서 이름 정리.lnk'));$link.TargetPath=$exe;$link.WorkingDirectory=$dest;$link.IconLocation="$dest\App.ico";$link.Save()
 }
 [void][Windows.Forms.MessageBox]::Show("설치 완료!`n바탕화면 아이콘으로 실행하세요.`n실행 후 작업표시줄 아이콘을 오른쪽 클릭해 '작업 표시줄에 고정'을 누르세요.",'스캔 문서 이름 정리')
 Start-Process -FilePath $exe
} catch {[void][Windows.Forms.MessageBox]::Show($_.Exception.ToString(),'설치 오류');exit 1}
