$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = Join-Path $env:LOCALAPPDATA 'EunQuickPrint'
New-Item -ItemType Directory -Force -Path $root | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'app.py') $root -Force
Copy-Item (Join-Path $PSScriptRoot 'print-settings.ps1') $root -Force
Copy-Item (Join-Path $PSScriptRoot 'requirements.txt') $root -Force
$runtime = Join-Path $root 'runtime'
try {
    if (!(Test-Path (Join-Path $runtime 'python.exe'))) {
        Write-Host 'Downloading application runtime...'
        $archive = Join-Path $root 'runtime.zip'
        Invoke-WebRequest 'https://www.python.org/ftp/python/3.13.9/python-3.13.9-embed-amd64.zip' -OutFile $archive -UseBasicParsing
        Expand-Archive $archive -DestinationPath $runtime -Force
        Remove-Item $archive
    }
    $pth = Join-Path $runtime 'python313._pth'
    $text = Get-Content $pth -Raw
    $text = $text.Replace('#import site', 'import site')
    if (!$text.Contains('..')) { $text += "`r`n..`r`n" }
    Set-Content -Path $pth -Value $text -Encoding ASCII
    $python = Join-Path $runtime 'python.exe'
    if (!(Test-Path (Join-Path $runtime 'Lib\site-packages\pip'))) {
        Invoke-WebRequest 'https://bootstrap.pypa.io/get-pip.py' -OutFile (Join-Path $root 'get-pip.py') -UseBasicParsing
        & $python (Join-Path $root 'get-pip.py') --no-warn-script-location
        if ($LASTEXITCODE -ne 0) { throw 'pip installation failed.' }
    }
    & $python -m pip install --only-binary=:all: --no-warn-script-location -r (Join-Path $root 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
    & $python -c 'import PySide6.QtWidgets, pymupdf, PIL.ImageWin, win32print, win32com.client'
    if ($LASTEXITCODE -ne 0) { throw 'Application dependency check failed.' }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Quick Print.lnk'))
    $shortcut.TargetPath = Join-Path $runtime 'pythonw.exe'
    $shortcut.Arguments = '"' + (Join-Path $root 'app.py') + '"'
    $shortcut.WorkingDirectory = $root
    $shortcut.Save()
    $startup = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'Quick Print.lnk'))
    $startup.TargetPath = $shortcut.TargetPath
    $startup.Arguments = $shortcut.Arguments + ' --tray'
    $startup.WorkingDirectory = $root
    $startup.Save()
    Write-Host 'Installation complete. Quick Print starts in the system tray at Windows sign-in.' 
    Start-Process (Join-Path $runtime 'pythonw.exe') -ArgumentList ('"' + (Join-Path $root 'app.py') + '"')
} catch {
    Write-Host $_ -ForegroundColor Red
    Read-Host 'Installation failed. Press Enter to close'
    exit 1
}
