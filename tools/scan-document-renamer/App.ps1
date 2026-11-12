$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.Runtime.WindowsRuntime
try {
# Use Windows Runtime projection directly. No C# compilation or WinMD file loading.
[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime] > $null
[Windows.Data.Pdf.PdfDocument,Windows.Data.Pdf,ContentType=WindowsRuntime] > $null
[Windows.Data.Pdf.PdfPageRenderOptions,Windows.Data.Pdf,ContentType=WindowsRuntime] > $null
[Windows.Graphics.Imaging.BitmapDecoder,Windows.Foundation,ContentType=WindowsRuntime] > $null
[Windows.Graphics.Imaging.BitmapTransform,Windows.Foundation,ContentType=WindowsRuntime] > $null
[Windows.Graphics.Imaging.SoftwareBitmap,Windows.Foundation,ContentType=WindowsRuntime] > $null
[Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime] > $null
[Windows.Media.Ocr.OcrResult,Windows.Foundation,ContentType=WindowsRuntime] > $null
[Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime] > $null
[Windows.Storage.Streams.InMemoryRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime] > $null
[Windows.Storage.Streams.IRandomAccessStream,Windows.Storage.Streams,ContentType=WindowsRuntime] > $null
[Windows.Foundation.IAsyncAction,Windows.Foundation,ContentType=WindowsRuntime] > $null
$script:awaitMethod=[System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {$_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'} | Select-Object -First 1
$script:actionMethod=[System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {$_.Name -eq 'AsTask' -and !$_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.FullName -eq 'Windows.Foundation.IAsyncAction'} | Select-Object -First 1
function Await-Result($operation,[Type]$resultType) {
 $arguments=New-Object object[] 1; $arguments[0]=$operation
 $task=$script:awaitMethod.MakeGenericMethod($resultType).Invoke($null,$arguments)
 return ,($task.GetAwaiter().GetResult())
}
function Await-Action($operation) {
 $arguments=New-Object object[] 1; $arguments[0]=$operation
 $task=$script:actionMethod.Invoke($null,$arguments)
 [void]$task.GetAwaiter().GetResult()
}
function Read-Page($path) {
 $file=Await-Result ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
 $stream=$null; $page=$null; $bitmap=$null
 try {
  if([IO.Path]::GetExtension($path) -ieq '.pdf') {
   $pdf=Await-Result ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($file)) ([Windows.Data.Pdf.PdfDocument])
   if(!$pdf.PageCount){throw 'PDF에 페이지가 없습니다.'}
   $page=$pdf.GetPage(0)
   $stream=New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
   $options=New-Object Windows.Data.Pdf.PdfPageRenderOptions; $options.DestinationWidth=2200
   Await-Action ($page.RenderToStreamAsync($stream,$options)); $stream.Seek(0)
  }else{
   $stream=Await-Result ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  }
  $decoder=Await-Result ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $transform=New-Object Windows.Graphics.Imaging.BitmapTransform
  $scale=[Math]::Min(1.0,2200.0/[Math]::Max($decoder.PixelWidth,$decoder.PixelHeight))
  $transform.ScaledWidth=[uint32][Math]::Max(1,$decoder.PixelWidth*$scale)
  $transform.ScaledHeight=[uint32][Math]::Max(1,$decoder.PixelHeight*$scale)
  $bitmap=Await-Result ($decoder.GetSoftwareBitmapAsync([Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8,[Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied,$transform,[Windows.Graphics.Imaging.ExifOrientationMode]::RespectExifOrientation,[Windows.Graphics.Imaging.ColorManagementMode]::DoNotColorManage)) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $engine=[Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language 'ko-KR'))
  if(!$engine){throw 'Windows 한국어 OCR이 설치되어 있지 않습니다.'}
  $result=Await-Result ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
  # Rebuild physical rows so the first title line precedes its continuation.
  $words=@(foreach($line in $result.Lines){foreach($word in $line.Words){
   [pscustomobject]@{Text=$word.Text;X=$word.BoundingRect.X;Y=($word.BoundingRect.Y+$word.BoundingRect.Height/2);Height=$word.BoundingRect.Height}
  }})
  if(!$words.Count){return @()}
  $heights=@($words.Height | Sort-Object); $tolerance=[Math]::Max(3,$heights[[int][Math]::Floor($heights.Count/2)]*0.55)
  $rows=New-Object System.Collections.ArrayList
  foreach($word in ($words | Sort-Object Y)){
   $nearest=$rows | Sort-Object { [Math]::Abs($_.Y-$word.Y) } | Select-Object -First 1
   if(!$nearest -or [Math]::Abs($nearest.Y-$word.Y) -gt $tolerance){
    $nearest=[pscustomobject]@{Y=$word.Y;Words=(New-Object System.Collections.ArrayList)}; [void]$rows.Add($nearest)
   }
   $nearest.Y=($nearest.Y*$nearest.Words.Count+$word.Y)/($nearest.Words.Count+1)
   [void]$nearest.Words.Add($word)
  }
  return @($rows | Sort-Object Y | ForEach-Object {($_.Words | Sort-Object X | ForEach-Object {$_.Text}) -join ' '})
 }finally{if($bitmap){$bitmap.Dispose()};if($page){$page.Dispose()};if($stream){$stream.Dispose()}}
}
function Find-Title($lines) {
 for($i=0;$i -lt $lines.Count;$i++) {
  if($lines[$i] -match '^\s*제\s*목\s*[:：]?\s*(.*)$') {
   $parts=New-Object 'System.Collections.Generic.List[string]'
   if($Matches[1].Trim()){$parts.Add($Matches[1].Trim())}
   if($parts.Count -gt 0 -and $parts[$parts.Count-1] -match '(알림|안내|요청|통보|계획|보고|개최|제출|송부|협조|결과|지급)\s*$'){return ($parts -join ' ').Trim()}
   for($j=$i+1;$j -lt [Math]::Min($i+6,$lines.Count);$j++) {
    $s=$lines[$j].Trim()
    if($s -match '^(\d+[.)、]|가[.)]|수신|참조|붙임|첨부|담당|시행|접수|우\s*\d|귀\s|1\s*\.)'){break}
    if($s){$parts.Add($s)}
    if($s -match '(알림|안내|요청|통보|계획|보고|개최|제출|송부|협조|결과|지급)\s*$'){break}
   }
   return ($parts -join ' ').Trim()
  }
 }
 return ''
}
function Clean-Name($name) {
 $s=($name -replace '[<>:"/\\|?*\x00-\x1F]',' ') -replace '\s+',' '
 $s=$s.Trim().TrimEnd([char[]]' .')
 if($s -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\.)'){$s='문서 '+$s}
 if($s.Length -gt 150){$s=$s.Substring(0,150).TrimEnd()}; return $s
}
$form=New-Object Windows.Forms.Form
$form.Text='스캔 문서 이름 정리 v1.9'; $form.Size=New-Object Drawing.Size(1080,680); $form.MinimumSize=New-Object Drawing.Size(850,550); $form.StartPosition='CenterScreen'; $form.Font=New-Object Drawing.Font('맑은 고딕',10)
if(Test-Path "$PSScriptRoot\App.ico"){$form.Icon=New-Object Drawing.Icon("$PSScriptRoot\App.ico")}
$header=New-Object Windows.Forms.Label; $header.Text='스캔 문서 이름 정리'; $header.Font=New-Object Drawing.Font('맑은 고딕',20,[Drawing.FontStyle]::Bold); $header.SetBounds(24,20,800,45); $form.Controls.Add($header)
$desc=New-Object Windows.Forms.Label; $desc.Text='SCAN_ 파일 불러오기 → 변경할 파일 체크 → 파일명 확인 → 변경'; $desc.SetBounds(26,73,990,28); $form.Controls.Add($desc)
$folder=New-Object Windows.Forms.TextBox; $folder.SetBounds(26,114,760,30); $folder.Text='C:\Users\user\Documents\Scan'; $form.Controls.Add($folder)
$choose=New-Object Windows.Forms.Button; $choose.Text='폴더 선택'; $choose.SetBounds(800,112,110,34); $form.Controls.Add($choose)
$scan=New-Object Windows.Forms.Button; $scan.Text='파일 불러오기'; $scan.SetBounds(922,112,110,34); $form.Controls.Add($scan)
$grid=New-Object Windows.Forms.DataGridView; $grid.SetBounds(26,165,1006,365); $grid.Anchor='Top,Bottom,Left,Right'; $grid.AllowUserToAddRows=$false; $grid.AllowUserToDeleteRows=$false; $grid.RowHeadersVisible=$false; $grid.AutoSizeColumnsMode='Fill'; $grid.SelectionMode='FullRowSelect'; $grid.BackgroundColor=[Drawing.Color]::White; $form.Controls.Add($grid)
$check=New-Object Windows.Forms.DataGridViewCheckBoxColumn; $check.Name='선택'; $check.FillWeight=12; [void]$grid.Columns.Add($check)
foreach($n in @('기존 파일명','변경할 제목','생성일자','상태')){[void]$grid.Columns.Add($n,$n)}
$grid.EditMode=[Windows.Forms.DataGridViewEditMode]::EditOnKeystrokeOrF2
$grid.Columns[2].ReadOnly=$false
$grid.Add_CellDoubleClick({
 param($sender,$event)
 if(!$script:busy -and $event.RowIndex -ge 0 -and $event.ColumnIndex -eq 2){
  $grid.CurrentCell=$grid.Rows[$event.RowIndex].Cells[2]
  [void]$grid.BeginEdit($true)
 }
})
$grid.Add_CurrentCellDirtyStateChanged({
 if($grid.IsCurrentCellDirty -and $grid.CurrentCell.ColumnIndex -eq 0){
  [void]$grid.CommitEdit([Windows.Forms.DataGridViewDataErrorContexts]::Commit)
 }
})
$grid.Columns[1].ReadOnly=$true; $grid.Columns[3].DefaultCellStyle.Format='yyyy-MM-dd HH:mm:ss'; $grid.Columns[3].ReadOnly=$true; $grid.Columns[3].FillWeight=65; $grid.Columns[4].ReadOnly=$true; $grid.Columns[4].FillWeight=65
$status=New-Object Windows.Forms.Label; $status.Text='SCAN_ 파일을 불러온 뒤 변경할 파일을 체크하고 파일명 확인을 누르세요.'; $status.SetBounds(26,545,1000,38); $status.Anchor='Bottom,Left,Right'; $form.Controls.Add($status)
$open=New-Object Windows.Forms.Button; $open.Text='선택 문서 열기'; $open.SetBounds(26,590,150,36); $open.Anchor='Bottom,Left'; $form.Controls.Add($open)
$rename=New-Object Windows.Forms.Button; $rename.Text='변경'; $rename.SetBounds(852,585,180,43); $rename.Anchor='Bottom,Right'; $rename.BackColor=[Drawing.Color]::FromArgb(26,85,165); $rename.ForeColor=[Drawing.Color]::White; $form.Controls.Add($rename)
$choose.Add_Click({$d=New-Object Windows.Forms.FolderBrowserDialog; $d.SelectedPath=$folder.Text; if($d.ShowDialog() -eq 'OK'){$folder.Text=$d.SelectedPath}; $d.Dispose()})
$open.Add_Click({if($grid.CurrentRow -and $grid.CurrentRow.Tag){Start-Process -FilePath $grid.CurrentRow.Tag.Path}})
$preview=New-Object Windows.Forms.Button; $preview.Text='파일명 확인'; $preview.SetBounds(490,585,160,43); $preview.Anchor='Bottom,Right'; $form.Controls.Add($preview)
$stop=New-Object Windows.Forms.Button; $stop.Text='변경 중단'; $stop.SetBounds(670,585,160,43); $stop.Anchor='Bottom,Right'; $stop.Enabled=$false; $form.Controls.Add($stop)
$script:busy=$false
$script:timer=New-Object Windows.Forms.Timer
$script:timer.Interval=200
function Set-Busy([bool]$value) {
 $script:busy=$value
 foreach($control in @($scan,$choose,$folder,$preview,$rename,$open,$grid)){ $control.Enabled=!$value }
}
function Finish-Rename([bool]$stopped) {
 $script:timer.Stop(); $stop.Enabled=$false; Set-Busy $false
 $remaining=$script:queue.Count-$script:next
 $status.Text="변경 완료 $script:done 개 / 오류 $script:errors 개 / 미처리 $remaining 개"
 if($stopped){$status.Text+=' · 중단됨 (이미 변경한 파일은 유지)'}
}
$scan.Add_Click({
 if($script:busy){return}
 if(!(Test-Path -LiteralPath $folder.Text -PathType Container)){[void][Windows.Forms.MessageBox]::Show('스캔 폴더를 먼저 선택하세요.');return}
 $grid.Rows.Clear()
 try {
  $files=@(Get-ChildItem -LiteralPath $folder.Text -File | Where-Object {$_.Name -like 'SCAN_*' -and $_.Extension -match '^\.(pdf|jpg|jpeg|png|tif|tiff|bmp)$'} | Sort-Object CreationTime)
  foreach($f in $files){
   $idx=$grid.Rows.Add($true,$f.Name,'',$f.CreationTime,'미확인')
   $grid.Rows[$idx].Tag=@{Path=$f.FullName;Length=$f.Length;Ticks=$f.LastWriteTimeUtc.Ticks;Eligible=$true;ConfirmedTitle=$null;AutoTitle=$null}
  }
  $status.Text="$($files.Count)개 불러옴 · 변경할 파일 체크 → 파일명 확인"
 }catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message)}
})
$preview.Add_Click({
 if($script:busy){return}
 [void]$grid.EndEdit()
 $rows=@($grid.Rows | Where-Object {$_.Cells[0].Value -and $_.Tag.Eligible})
 if(!$rows.Count){[void][Windows.Forms.MessageBox]::Show('파일명 확인할 파일을 체크하세요.');return}
 Set-Busy $true
 try {
  foreach($row in $rows){
   $row.Tag.ConfirmedTitle=$null
   $status.Text='파일명 확인 중: '+$row.Cells[1].Value
   [Windows.Forms.Application]::DoEvents()
   try {
    $f=Get-Item -LiteralPath $row.Tag.Path
    if(((Get-Date)-$f.LastWriteTime).TotalSeconds -lt 5){throw '저장 중일 수 있습니다. 잠시 후 다시 확인하세요.'}
    $probe=[IO.File]::Open($f.FullName,'Open','Read','None'); $probe.Dispose()
    $name=Clean-Name ([string]$row.Cells[2].Value)
    if(!$name -or $name -ceq $row.Tag.AutoTitle){
     $lines=@(Read-Page $f.FullName); $name=Clean-Name (Find-Title $lines); $row.Tag.AutoTitle=$name
    }
    if(!$name){throw '제목을 찾지 못했습니다. 변경할 제목을 더블클릭해서 직접 입력하세요.'}
    $row.Cells[2].Value=$name
    $row.Tag.Length=$f.Length; $row.Tag.Ticks=$f.LastWriteTimeUtc.Ticks
    $row.Tag.ConfirmedTitle=$name
    $row.Cells[4].Value='확인 완료: '+$name+$f.Extension
   }catch{$row.Cells[4].Value=$_.Exception.Message}
  }
  $status.Text='파일명 확인 완료 · 제목을 더블클릭해 수정할 수 있습니다. 변경을 누르면 현재 입력한 제목을 사용합니다.'
 }finally{Set-Busy $false}
})
$rename.Add_Click({
 if($script:busy){return}
 [void]$grid.EndEdit()
 $rows=@($grid.Rows | Where-Object {$_.Cells[0].Value -and $_.Tag.Eligible})
 if(!$rows.Count){[void][Windows.Forms.MessageBox]::Show('변경할 파일을 체크하세요.');return}
 foreach($row in $rows){
  $name=Clean-Name ([string]$row.Cells[2].Value)
  if(!$name){
   [void][Windows.Forms.MessageBox]::Show('체크한 파일의 변경할 제목을 입력하세요. 제목이 비어 있으면 변경할 수 없습니다.'); return
  }
 }
 $answer=[Windows.Forms.MessageBox]::Show($form,"선택한 $($rows.Count)개 파일의 이름을 변경하시겠습니까?",'파일명 변경 확인',[Windows.Forms.MessageBoxButtons]::OKCancel,[Windows.Forms.MessageBoxIcon]::Question,[Windows.Forms.MessageBoxDefaultButton]::Button2)
 if($answer -ne [Windows.Forms.DialogResult]::OK){$status.Text='취소됨 · 파일명은 변경하지 않았습니다.';return}
 $script:queue=@($rows | ForEach-Object { @{Row=$_;Name=(Clean-Name ([string]$_.Cells[2].Value))} })
 $script:next=0; $script:done=0; $script:errors=0
 Set-Busy $true; $stop.Enabled=$true; $status.Text='변경 시작 · 변경 중단 버튼으로 다음 파일부터 멈출 수 있습니다.'
 $script:timer.Start()
})
$script:timer.Add_Tick({
 if($script:next -ge $script:queue.Count){Finish-Rename $false;return}
 $item=$script:queue[$script:next]; $row=$item.Row
 try {
  $src=Get-Item -LiteralPath $row.Tag.Path
  if($src.Length -ne $row.Tag.Length -or $src.LastWriteTimeUtc.Ticks -ne $row.Tag.Ticks){throw '파일이 변경되었습니다. 다시 불러오세요.'}
  $name=$item.Name; $dest=Join-Path $src.DirectoryName ($name+$src.Extension); $i=2
  while(Test-Path -LiteralPath $dest){$dest=Join-Path $src.DirectoryName ($name+' ('+$i+')'+$src.Extension);$i++}
  [IO.File]::Move($src.FullName,$dest)
  $row.Tag.Path=$dest; $row.Tag.Eligible=$false; $row.Cells[0].Value=$false
  $row.Cells[1].Value=[IO.Path]::GetFileName($dest); $row.Cells[4].Value='변경 완료'; $script:done++
 }catch{$row.Cells[4].Value=$_.Exception.Message; $script:errors++}
 $script:next++
 $status.Text="$script:next / $($script:queue.Count) 처리 · 완료 $script:done 개 · 변경 중단 가능"
 if($script:next -ge $script:queue.Count){Finish-Rename $false}
})
$stop.Add_Click({if($script:busy -and $script:timer.Enabled){Finish-Rename $true}})
$form.Add_FormClosing({$script:timer.Stop()})
[void]$form.ShowDialog()
$script:timer.Dispose()

} catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.ToString(),'실행 오류') }
