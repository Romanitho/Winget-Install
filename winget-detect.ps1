# Change app to detect [Application ID] (case sensitive!)
$AppToDetect = "Notepad++.Notepad++"


<# FUNCTIONS #>

Function Get-WinGetCmd {

    $WinGetCmd = $null

    # Get WinGet Path
    try {
        # Get System Context WinGet Location
        $WinGetInfo = (Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe").VersionInfo | Sort-Object -Property FileVersionRaw
        # If multiple versions, pick most recent one
        $WinGetCmd = $WinGetInfo[-1].FileName
    }
    catch {
        # Get User context WinGet Location
        if (Test-Path "$env:LocalAppData\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe") {
            $WinGetCmd = "$env:LocalAppData\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe"
        }
    }

    return $WinGetCmd
}

<# MAIN #>

# Get WinGet Location Function
$WinGet = Get-WinGetCmd

# Check if the app is installed
$output = & $WinGet list --Id $AppToDetect -e --accept-source-agreements -s winget

# Check if the output contains "-----" (which means WinGet got a positive response with a header)
if ($output -match "-----") {
    # Extract the second-to-last word from the output (which is the Application ID)
    $outputArray = $output -split ' '
    $outputArrayId = $outputArray[-2]

    # Checks if the value of $outputArrayId is case-sensitively equal to the value of $AppToDetect
    if ($outputArrayId -ceq $AppToDetect) {
        return "Installed!"
    }
}
