$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
function Confirm-InstallKey {
 $dialog=New-Object Windows.Forms.Form
 $dialog.Text='스캔 문서 이름 정리 · 설치 키 확인'
 $dialog.ClientSize=New-Object Drawing.Size(460,185)
 $dialog.StartPosition='CenterScreen'; $dialog.FormBorderStyle='FixedDialog'
 $dialog.MaximizeBox=$false; $dialog.MinimizeBox=$false
 $dialog.Font=New-Object Drawing.Font('맑은 고딕',10)
 $label=New-Object Windows.Forms.Label
 $label.Text='전달받은 영문·숫자 16자리 설치 키를 입력하세요.'
 $label.SetBounds(20,20,420,30); $dialog.Controls.Add($label)
 $inputBox=New-Object Windows.Forms.TextBox
 $inputBox.SetBounds(20,57,420,30); $inputBox.MaxLength=16
 $inputBox.UseSystemPasswordChar=$true; $dialog.Controls.Add($inputBox)
 $hint=New-Object Windows.Forms.Label
 $hint.Text='대소문자를 구분합니다.'; $hint.SetBounds(20,94,420,24)
 $dialog.Controls.Add($hint)
 $ok=New-Object Windows.Forms.Button
 $ok.Text='설치'; $ok.SetBounds(244,136,92,32); $dialog.Controls.Add($ok)
 $cancel=New-Object Windows.Forms.Button
 $cancel.Text='취소'; $cancel.SetBounds(348,136,92,32)
 $cancel.DialogResult=[Windows.Forms.DialogResult]::Cancel
 $dialog.Controls.Add($cancel); $dialog.AcceptButton=$ok; $dialog.CancelButton=$cancel
 $ok.Add_Click({
  $entered=$inputBox.Text
  if($entered -cnotmatch '^[A-Za-z0-9]{16}$'){
   $hint.Text='영문·숫자 16자리 키를 입력하세요.'; $hint.ForeColor=[Drawing.Color]::Firebrick
   $inputBox.Focus(); return
  }
  $sha=[Security.Cryptography.SHA256]::Create()
  try {
   $bytes=[Text.Encoding]::UTF8.GetBytes('804268179a3764389e4d3a2354aea5a2'+':'+$entered)
   $actual=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
  }finally{$sha.Dispose()}
  if($actual -ceq 'e8ad6486aad2c8bcdf1a0e129926a0fd8565474740722cb0b8a497017528cbeb'){
   $dialog.DialogResult=[Windows.Forms.DialogResult]::OK; $dialog.Close()
  }else{
   $hint.Text='설치 키가 일치하지 않습니다.'; $hint.ForeColor=[Drawing.Color]::Firebrick
   $inputBox.SelectAll(); $inputBox.Focus()
  }
 })
 try {return ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK)}
 finally {$inputBox.Clear(); $dialog.Dispose()}
}
if(!(Confirm-InstallKey)){exit 0}
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
