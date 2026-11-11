param([Parameter(Mandatory=$true)][string]$Printer, [Parameter(Mandatory=$true)][string]$Destination, [ValidateSet('Portrait','Landscape')][string]$Orientation='Portrait')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName ReachFramework
Add-Type -AssemblyName System.Printing
$server = New-Object System.Printing.LocalPrintServer
$queue = $null
$converter = $null
function Assert-Settings($ticket) {
    if ($null -ne $ticket.PagesPerSheet -and $ticket.PagesPerSheet -ne 1) { throw 'Driver did not confirm PagesPerSheet=1. Printing stopped.' }
    if ($null -ne $ticket.Duplexing -and $ticket.Duplexing -ne [System.Printing.Duplexing]::OneSided) { throw 'Driver did not confirm one-sided printing. Printing stopped.' }
    # Grayscale and Monochrome are both valid black-and-white outputs.
    # Some legacy drivers report Color even for gray raster data; do not fail here.
    # The application renders every page to grayscale before spooling.
    if ($null -ne $ticket.CopyCount -and $ticket.CopyCount -ne 1) { throw 'Driver did not confirm CopyCount=1. Printing stopped.' }
}
try {
    $queue = $server.GetPrintQueue($Printer)
    $base = $queue.UserPrintTicket
    if ($null -eq $base) { $base = $queue.DefaultPrintTicket }
    if ($null -eq $base) { throw 'Printer has no PrintTicket provider.' }
    $delta = New-Object System.Printing.PrintTicket
    $delta.PagesPerSheet = 1
    $delta.Duplexing = [System.Printing.Duplexing]::OneSided
    $caps = $queue.GetPrintCapabilities($base)
    if ($caps.OutputColorCapability.Contains([System.Printing.OutputColor]::Grayscale)) {
        $delta.OutputColor = [System.Printing.OutputColor]::Grayscale
    } elseif ($caps.OutputColorCapability.Contains([System.Printing.OutputColor]::Monochrome)) {
        $delta.OutputColor = [System.Printing.OutputColor]::Monochrome
    }

    $delta.CopyCount = 1
    $delta.PageScalingFactor = 100
    $delta.PageOrientation = [System.Printing.PageOrientation]::$Orientation
    $validated = $queue.MergeAndValidatePrintTicket($base, $delta).ValidatedPrintTicket
    Assert-Settings $validated
    $converter = New-Object System.Printing.Interop.PrintTicketConverter($Printer, 1)
    $bytes = $converter.ConvertPrintTicketToDevMode($validated, [System.Printing.Interop.BaseDevModeType]::UserDefault, [System.Printing.PrintTicketScope]::JobScope)
    $roundtrip = $converter.ConvertDevModeToPrintTicket($bytes, [System.Printing.PrintTicketScope]::JobScope)
    Assert-Settings $roundtrip
    [IO.File]::WriteAllBytes($Destination, $bytes)
} finally {
    if ($null -ne $converter) { $converter.Dispose() }
    if ($null -ne $queue) { $queue.Dispose() }
    $server.Dispose()
}
