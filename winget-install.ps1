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
.\winget-install.ps1 -AppIDs 7zip.7zip -WAUWhiteList

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
function Start-Init {

    #Config console output encoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

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
    #Get WinGet Path (if admin context)
    $ResolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe"
    if ($ResolveWingetPath){
        #If multiple version, pick last one
        $WingetPath = $ResolveWingetPath[-1].Path
    }
    #Get WinGet Location in User context
    $WingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($WingetCmd){
        $Script:Winget = $WingetCmd.Source
    }
    #Get Winget Location in System context (WinGet < 1.17)
    elseif (Test-Path "$WingetPath\AppInstallerCLI.exe"){
        $Script:Winget = "$WingetPath\AppInstallerCLI.exe"
    }
    #Get Winget Location in System context (WinGet > 1.17)
    elseif (Test-Path "$WingetPath\winget.exe"){
        $Script:Winget = "$WingetPath\winget.exe"
    }
    else{
        Write-Log "Winget not installed !" "Red"
        break
    }
    Write-Log "Using following Winget Cmd: $winget"
}

#Function to configure prefered scope option as Machine
function Add-ScopeMachine ($path) {
    if (Test-Path $path){
        $ConfigFile = Get-Content -Path $path | Where-Object {$_ -notmatch '//'} | ConvertFrom-Json
    }
    if (!$ConfigFile){
        $ConfigFile = @{}
    }
    if ($ConfigFile.installBehavior.preferences.scope){
        $ConfigFile.installBehavior.preferences.scope = "Machine"
    }
    else {
        Add-Member -InputObject $ConfigFile -MemberType NoteProperty -Name 'installBehavior' -Value $(
            New-Object PSObject -Property $(@{preferences = $(
                    New-Object PSObject -Property $(@{scope = "Machine"}))
            })
        ) -Force
    }
    $ConfigFile | ConvertTo-Json | Out-File $path -Encoding utf8 -Force
}

#Check if app is installed
function Confirm-Install ($AppID){
    #Get "Winget List AppID"
    $InstalledApp = & $winget list --Id $AppID --accept-source-agreements | Out-String

    #Return if AppID exists in the list
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

#Check if modifications exist in "mods" directory
function Test-ModsInstall ($AppID){
    if (Test-Path "$PSScriptRoot\mods\$AppID-install-once.ps1"){
        $ModsInstallOnce = "$PSScriptRoot\mods\$AppID-install-once.ps1"
        return $ModsInstallOnce
    }
    elseif (Test-Path "$PSScriptRoot\mods\$AppID-install.ps1"){
        $ModsInstall = "$PSScriptRoot\mods\$AppID-install.ps1"
        return $ModsInstall
    }
    elseif (Test-Path "$PSScriptRoot\mods\$AppID-upgrade.ps1"){
        $ModsUpgrade = "$PSScriptRoot\mods\$AppID-upgrade.ps1"
        return $ModsUpgrade
    }
    else{
        return 0
    }
}

function Test-ModsUninstall ($AppID){
    if (Test-Path "$PSScriptRoot\mods\$AppID-uninstall.ps1"){
        $ModsUninstall = "$PSScriptRoot\mods\$AppID-uninstall.ps1"
        return $ModsUninstall
    }
    else {
        return 0
    }
}

#Install function
function Install-App ($AppID,$AppArgs){
    $IsInstalled = Confirm-Install $AppID
    if (!($IsInstalled)){
        #Install App
        Write-Log "Installing $AppID..." "Yellow"
        $WingetArgs = "install --id $AppID --accept-package-agreements --accept-source-agreements -h $AppArgs" -split " "
        Write-Log "Running: `"$Winget`" $WingetArgs"
        & "$Winget" $WingetArgs | Tee-Object -file $LogFile -Append
        
        #Check if install is ok
        $IsInstalled = Confirm-Install $AppID
        if ($IsInstalled){
            Write-Log "$AppID successfully installed." "Green"
            #Check if mods exist
            $ModsInstall = Test-ModsInstall $AppID
            if ($ModsInstall -like "*$AppID-install*"){
                Write-Log "Modifications for $AppID after install are being applied..." "Yellow"
                & "$ModsInstall"
            }
            #Add to WAU mods if exists
            if (($ModsInstall -like "*$AppID-install*") -or ($ModsInstall -like "*$AppID-upgrade*")){
                Add-WAUMods $AppID
            }
            #Add to WAU White List if set
            if ($WAUWhiteList){
                Add-WAUWhiteList $AppID
            }
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
function Uninstall-App ($AppID,$AppArgs){
    $IsInstalled = Confirm-Install $AppID
    if ($IsInstalled){
        #Uninstall App
        Write-Log "Uninstalling $AppID..." "Yellow"
        $WingetArgs = "uninstall --id $AppID --accept-package-agreements --accept-source-agreements -h" -split " "
        Write-Log "Running: `"$Winget`" $WingetArgs"
        & "$Winget" $WingetArgs | Tee-Object -file $LogFile -Append


        #Check if mods exist
        $ModsUninstall = Test-ModsUninstall $AppID
        if ($ModsUninstall){
            Write-Log "Modifications for $AppID during uninstall are being applied..." "Yellow"
            & "$ModsUninstall"
        }
        #Check if uninstall is ok
        $IsInstalled = Confirm-Install $AppID
        if (!($IsInstalled)){
            Write-Log "$AppID successfully uninstalled." "Green"
            #Remove from WAU mods (always)
            Remove-WAUMods $AppID
            #Remove from WAU White List if set
            if ($WAUWhiteList){
                Remove-WAUWhiteList $AppID
            }
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
        Write-Log "Remove $AppID from WAU included_apps.txt"
        #Remove app from list
        $file = Get-Content $WhiteList | Where-Object {$_ -ne "$AppID"}
        $file | Out-File $WhiteList
    }
}

#Function to Add Mods to WAU "mods"
function Add-WAUMods ($AppID){
    #Check if WAU default install path exists
    $Mods = "$env:ProgramData\Winget-AutoUpdate\mods"
    if (Test-Path $Mods){
        #Add mods
        if ((Test-Path "$PSScriptRoot\mods\$AppID-install.ps1") -or (Test-Path "$PSScriptRoot\mods\$AppID-upgrade.ps1")){
            Write-Log "Add modifications for $AppID to WAU 'mods'"
            Copy-Item "$PSScriptRoot\mods\$AppID-*" -Destination "$Mods" -Exclude "*-install-once*","*-uninstall*" -Force
        }
    }
}

#Function to Remove Mods from WAU "mods"
function Remove-WAUMods ($AppID){
    #Check if WAU default install path exists
    $Mods = "$env:ProgramData\Winget-AutoUpdate\mods"
    if (Test-Path "$Mods\$AppID*"){
        Write-Log "Remove $AppID modifications from WAU 'mods'"
        #Remove mods
        Remove-Item -Path "$Mods\$AppID*" -Force
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
Start-Init

#Run Scope Machine funtion
if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
    $SettingsPath = "$Env:windir\system32\config\systemprofile\AppData\Local\Microsoft\WinGet\Settings\settings.json"
}
else{
    $SettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
}
Add-ScopeMachine $SettingsPath

#Run WingetCmd Function
Get-WingetCmd

#Run install or uninstall for all apps
foreach ($App_Full in $AppIDs){
    #Split AppID and Custom arguments
    $AppID, $AppArgs = ($App_Full.Trim().Split(" ",2))

    #Check if app exists on Winget Repo
    $Exists = Confirm-Exist $AppID
    if ($Exists){
        #Install or Uninstall command
        if ($Uninstall){
            Uninstall-App $AppID $AppArgs
        }
        else{
            Install-App $AppID $AppArgs
        }
    }
    Start-Sleep 2
}

Write-Log "###   END REQUEST   ###" "Magenta"
Start-Sleep 2
