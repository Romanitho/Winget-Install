<#
.SYNOPSIS
Install apps with Winget through Intune or SCCM.
Can be used standalone.

.DESCRIPTION
Allow to run Winget in System Context to install your apps.
https://github.com/Romanitho/Winget-Install

.PARAMETER AppIDs
Forward Winget App ID to install. For multiple apps, separate with ","

.PARAMETER Uninstall
To uninstall app. Works with AppIDs

.PARAMETER LogPath
Used to specify logpath. Default is same folder as Winget-Autoupdate project

.PARAMETER WAUWhiteList
Adds the app to the Winget-AutoUpdate White List. More info: https://github.com/Romanitho/Winget-AutoUpdate
If '-Uninstall' is used, it removes the app from WAU White List.

.EXAMPLE
.\winget-install.ps1 -AppIDs 7zip.7zip

.EXAMPLE
.\winget-install.ps1 -AppIDs 7zip.7zip -Uninstall

.EXAMPLE
.\winget-install.ps1 -AppIDs 7zip.7zip,notepad++.notepad++ -LogPath "C:\temp\logs"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$True,ParameterSetName="AppIDs")] [String[]] $AppIDs,
    [Parameter(Mandatory=$False)] [Switch] $Uninstall,
    [Parameter(Mandatory=$False)] [String] $LogPath = "$env:ProgramData\Winget-AutoUpdate\logs",
    [Parameter(Mandatory=$False)] [Switch] $WAUWhiteList
)


<# FUNCTIONS #>

#Initialization
function Init {
    #Logs initialisation
    if (!(Test-Path $LogPath)){
        New-Item -ItemType Directory -Force -Path $LogPath | Out-Null
    }

    #Log file
    $Script:LogFile = "$LogPath\install.log"
    Write-Host "Log path is: $LogFile"

    #Log Header
    if ($Uninstall){
        Write-Log "###   $(Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern) - NEW UNINSTALL REQUEST   ###" "Magenta"
    }
    else{
        Write-Log "###   $(Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern) - NEW INSTALL REQUEST   ###" "Magenta"
    }
}

#Log Function
function Write-Log ($LogMsg, $LogColor = "White") {
    #Get log
    $Log = "$(Get-Date -UFormat "%T") - $LogMsg"
    #Echo log
    $Log | Write-host -ForegroundColor $LogColor
    #Write log to file
    $Log | out-file -filepath $LogFile -Append
}

#Get WinGet Location Function
function Get-WingetCmd {
    #Get WinGet Location in User context
    $WingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($WingetCmd){
        $Script:winget = $WingetCmd.Source
    }
    #Get WinGet Location in System context (WinGet < 1.17)
    elseif (Test-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\AppInstallerCLI.exe"){
        $Script:winget = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\AppInstallerCLI.exe" | Select-Object -ExpandProperty Path
    }
    #Get WinGet Location in System context (WinGet > 1.17)
    elseif (Test-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"){
        $Script:winget = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" | Select-Object -ExpandProperty Path
    }
    else{
        Write-Log "Winget not installed !" "Red"
        break
    }
    Write-Log "Using following Winget Cmd: $winget"
}

#Check if app is installed
function Confirm-Install ($AppID){
    #Get "Winget List AppID"
    $InstalledApp = & $winget list --Id $AppID --accept-source-agreements | Out-String

    #Return if AppID existe in the list
    if ($InstalledApp -match [regex]::Escape($AppID)){
        return $true
    }
    else{
        return $false
    }
}

#Check if App exists in Winget Repository
function Confirm-Exist ($AppID){
    #Check is app exists in the winget repository
    $WingetApp = & $winget show --Id $AppID --accept-source-agreements | Out-String

    #Return if AppID exists
    if ($WingetApp -match [regex]::Escape($AppID)){
        Write-Log "$AppID exists on Winget Repository." "Cyan"
        return $true
    }
    else{
        Write-Log "$AppID does not exist on Winget Repository! Check spelling." "Red"
        return $false
    }
}

#Install function
function Install-App ($AppID){
    $IsInstalled = Confirm-Install $AppID
    if (!($IsInstalled)){
        #Install App
        Write-Log "Installing $AppID..." "Yellow"
        & $winget install --id $AppID --silent --accept-package-agreements --accept-source-agreements
        #Check if install is ok
        $IsInstalled = Confirm-Install $AppID
        if ($IsInstalled){
            Write-Log "$AppID successfully installed." "Green"
        }
        else{
            Write-Log "$AppID installation failed!" "Red"
        }
    }
    else{
        Write-Log "$AppID is already installed." "Cyan"
    }
}

#Uninstall function
function Uninstall-App ($AppID){
    $IsInstalled = Confirm-Install $AppID
    if ($IsInstalled){
        #Install App
        Write-Log "Uninstalling $AppID..." "Yellow"
        & $winget uninstall --id $AppID --silent --accept-source-agreements
        #Check if install is ok
        $IsInstalled = Confirm-Install $AppID
        if (!($IsInstalled)){
            Write-Log "$AppID successfully uninstalled." "Green"
        }
        else{
            Write-Log "$AppID uninstall failed!" "Red"
        }
    }
    else{
        Write-Log "$AppID is not installed." "Cyan"
    }
}

#Function to Add app to WAU white list
function Add-WAUWhiteList ($AppID){
    #Check if WAU default intall path exists
    $WhiteList = "$env:ProgramData\Winget-AutoUpdate\included_apps.txt"
    if (Test-Path $WhiteList){
        Write-Log "Add $AppID to WAU included_apps.txt"
        #Add App to "included_apps.txt"
        Add-Content -path $WhiteList -Value "`n$AppID" -Force
        #Remove duplicate and blank lines
        $file = Get-Content $WhiteList | Select-Object -Unique | Where-Object {$_.trim() -ne ""} | Sort-Object
        $file | Out-File $WhiteList
    }
}

#Function to Remove app from WAU white list
function Remove-WAUWhiteList ($AppID){
    #Check if WAU default intall path exists
    $WhiteList = "$env:ProgramData\Winget-AutoUpdate\included_apps.txt"
    if (Test-Path $WhiteList){
        Write-Log "Remove $AppID to WAU included_apps.txt"
        #Remove app from list
        $file = Get-Content $WhiteList | Where-Object {$_ -notmatch "$AppID"}
        $file | Out-File $WhiteList
    }
}

<# MAIN #>

Write-host "`n"
Write-host "`t###################################"
Write-host "`t#                                 #"
Write-host "`t#         Winget Install          #"
Write-host "`t#                                 #"
Write-host "`t###################################"
Write-Host "`n"

#Run Init Function
Init

#Run WingetCmd Function
Get-WingetCmd

#Run install or uninstall for all apps
foreach ($AppID in $AppIDs){
    #Check if app exists
    $Exists = Confirm-Exist $AppID
    if ($Exists){
        #Install or Uninstall command
        if ($Uninstall){
            Uninstall-App $AppID
            #Add to WAU White List if set
            if ($WAUWhiteList){
                Remove-WAUWhiteList $AppID
            }
        }
        else{
            Install-App $AppID
            #Remove from WAU White List if set
            if ($WAUWhiteList){
                Add-WAUWhiteList $AppID
            }
        }
    }
    Start-Sleep 3
}

Write-Log "###   END REQUEST   ###" "Magenta"
Start-Sleep 3