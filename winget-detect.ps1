#Change app to detect [Application ID]
$AppToDetect = "Notepad++.Notepad++"


<# FUNCTIONS #>

Function Get-WingetCmd {

    #Get WinGet Path (if admin context)
    $ResolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" | Sort-Object { [version]($_.Path -replace '^[^\d]+_((\d+\.)*\d+)_.*', '$1') }
    if ($ResolveWingetPath) {
        #If multiple version, pick last one
        $WingetPath = $ResolveWingetPath[-1].Path
    }

    #Get Winget Location in User context
    $WingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($WingetCmd) {
        $Script:Winget = $WingetCmd.Source
    }
    #Get Winget Location in System context
    elseif (Test-Path "$WingetPath\winget.exe") {
        $Script:Winget = "$WingetPath\winget.exe"
    }
    else {
        break
    }
}

<# MAIN #>

#Get WinGet Location Function
Get-WingetCmd

#Get "Winget List AppID"
$InstalledApp = & $winget list --Id $AppToDetect --accept-source-agreements | Out-String

#Return if AppID existe in the list
if ($InstalledApp -match [regex]::Escape($AppToDetect)) {
    return "Installed!"
}