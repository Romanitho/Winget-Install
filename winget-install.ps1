<#
.SYNOPSIS
Install apps with Winget through Intune or SCCM.
Can be used standalone.

.DESCRIPTION
Allow to run Winget in System Context to install your apps.
https://github.com/Romanitho/Winget-Install

.PARAMETER AppIDs
Forward Winget App ID to install. For multiple apps, separate with ",". Case sensitive.

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
.\winget-install.ps1 -AppIDs 7zip.7zip,Notepad++.Notepad++ -LogPath "C:\temp\logs"

.EXAMPLE
.\winget-install.ps1 -AppIDs "7zip.7zip -v 22.00", "Notepad++.Notepad++"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $True, ParameterSetName = "AppIDs")] [String[]] $AppIDs,
    [Parameter(Mandatory = $False)] [Switch] $Uninstall,
    [Parameter(Mandatory = $False)] [String] $LogPath,
    [Parameter(Mandatory = $False)] [Switch] $WAUWhiteList
)


<# FUNCTIONS #>

#Log Function
function Write-ToLog ($LogMsg, $LogColor = "White") {
    #Get log
    $Log = "$(Get-Date -UFormat "%T") - $LogMsg"
    #Echo log
    $Log | Write-host -ForegroundColor $LogColor
    #Write log to file
    $Log | out-file -filepath $LogFile -Append
}

#Get WinGet Location Function
function Get-WingetCmd {

    $WingetCmd = $null

    #Get WinGet Path
    try {
        #Get Admin Context Winget Location
        $WingetInfo = (Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe").VersionInfo | Sort-Object -Property FileVersionRaw
        #If multiple versions, pick most recent one
        $WingetCmd = $WingetInfo[-1].FileName
    }
    catch {
        #Get User context Winget Location
        if (Test-Path "$env:LocalAppData\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe") {
            $WingetCmd = "$env:LocalAppData\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe"
        }
    }

    return $WingetCmd
}

#Function to configure prefered scope option as Machine
function Add-ScopeMachine {
    #Function to configure prefered scope option as Machine
    function Add-ScopeMachine {
        #Get Settings path for system or current user
        if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
            $SettingsPath = "$Env:windir\System32\config\systemprofile\AppData\Local\Microsoft\WinGet\Settings\settings.json"
        }
        else {
            $SettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
        }

        $ConfigFile = @{}

        #Check if setting file exist, if not create it
        if (Test-Path $SettingsPath) {
            $ConfigFile = Get-Content -Path $SettingsPath | Where-Object { $_ -notmatch '//' } | ConvertFrom-Json
        }
        else {
            New-Item -Path $SettingsPath
        }

        if ($ConfigFile.installBehavior.preferences) {
            Add-Member -InputObject $ConfigFile.installBehavior.preferences -MemberType NoteProperty -Name 'scope' -Value 'Machine' -Force
        }
        else {
            $Scope = New-Object PSObject -Property $(@{scope = 'Machine' })
            $Preference = New-Object PSObject -Property $(@{preferences = $Scope })
            Add-Member -InputObject $ConfigFile -MemberType NoteProperty -Name 'installBehavior' -Value $Preference -Force
        }

        $ConfigFile | ConvertTo-Json | Out-File $SettingsPath -Encoding utf8 -Force
    }
}

function Install-Prerequisites {

    Write-ToLog "Checking prerequisites..." "Cyan"

    #Check if Visual C++ 2019 or 2022 installed
    $Visual2019 = "Microsoft Visual C++ 2015-2019 Redistributable*"
    $Visual2022 = "Microsoft Visual C++ 2015-2022 Redistributable*"
    $path = Get-Item HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object { $_.GetValue("DisplayName") -like $Visual2019 -or $_.GetValue("DisplayName") -like $Visual2022 }

    #If not installed, download and install
    if (!($path)) {

        Write-ToLog "Microsoft Visual C++ 2015-2022 is not installed." "Red"

        try {
            #Get proc architecture
            if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
                $OSArch = "arm64"
            }
            elseif ($env:PROCESSOR_ARCHITECTURE -like "*64*") {
                $OSArch = "x64"
            }
            else {
                $OSArch = "x86"
            }

            #Download and install
            $SourceURL = "https://aka.ms/vs/17/release/VC_redist.$OSArch.exe"
            $Installer = ".\VC_redist.$OSArch.exe"
            Write-ToLog "-> Downloading $SourceURL..."
            Invoke-WebRequest $SourceURL -UseBasicParsing -OutFile $Installer
            Write-ToLog "-> Installing VC_redist.$OSArch.exe..."
            Start-Process -FilePath $Installer -Args "/quiet /norestart" -Wait
            Start-Sleep 3
            Remove-Item $Installer -ErrorAction Ignore
            Write-ToLog "-> MS Visual C++ 2015-2022 installed successfully." "Green"
        }
        catch {
            Write-ToLog "-> MS Visual C++ 2015-2022 installation failed." "Red"
        }

    }

    #Check if Microsoft.VCLibs.140.00.UWPDesktop is installed
    if (!(Get-AppxPackage -Name 'Microsoft.VCLibs.140.00.UWPDesktop' -AllUsers)) {
        Write-ToLog "Microsoft.VCLibs.140.00.UWPDesktop is not installed" "Red"
        $VCLibsUrl = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        $VCLibsFile = ".\Microsoft.VCLibs.x64.14.00.Desktop.appx"
        Write-ToLog "-> Downloading $VCLibsUrl..."
        Invoke-RestMethod -Uri $VCLibsUrl -OutFile $VCLibsFile
        try {
            Write-ToLog "-> Installing Microsoft.VCLibs.140.00.UWPDesktop..."
            Add-AppxProvisionedPackage -Online -PackagePath $VCLibsFile -SkipLicense | Out-Null
            Write-ToLog "-> Microsoft.VCLibs.140.00.UWPDesktop installed successfully." "Green"
        }
        catch {
            Write-ToLog "-> Failed to intall Microsoft.VCLibs.140.00.UWPDesktop..." "Red"
        }
        Remove-Item -Path $VCLibsFile -Force
    }

    #Check available WinGet version, if fail set version to the latest version as of 2023-10-08
    $WingetURL = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
    try {
        $WinGetAvailableVersion = ((Invoke-WebRequest $WingetURL -UseBasicParsing | ConvertFrom-Json)[0].tag_name).Replace("v", "")
    }
    catch {
        $WinGetAvailableVersion = "1.6.2771"
    }

    #Get installed Winget version
    try {
        $WingetInstalledVersionCmd = & $Winget -v
        $WinGetInstalledVersion = (($WingetInstalledVersionCmd).Replace("-preview", "")).Replace("v", "")
        Write-ToLog "Installed Winget version: $WingetInstalledVersionCmd"
    }
    catch {
        Write-ToLog "WinGet is not installed" "Red"
    }

    #Check if the available WinGet is newer than the installed
    if ($WinGetAvailableVersion -gt $WinGetInstalledVersion) {

        Write-ToLog "-> Downloading Winget v$WinGetAvailableVersion"
        $WingetURL = "https://github.com/microsoft/winget-cli/releases/download/v$WinGetAvailableVersion/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $WingetInstaller = ".\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        Invoke-RestMethod -Uri $WingetURL -OutFile $WingetInstaller
        try {
            Write-ToLog "-> Installing Winget v$WinGetAvailableVersion"
            Add-AppxProvisionedPackage -Online -PackagePath $WingetInstaller -SkipLicense | Out-Null
            Write-ToLog "-> Winget installed." "Green"
        }
        catch {
            Write-ToLog "-> Failed to install Winget!" "Red"
        }
        Remove-Item -Path $WingetInstaller -Force
    }

    Write-ToLog "Checking prerequisites ended.`n" "Cyan"

}

#Check if app is installed
function Confirm-Install ($AppID) {
    #Get "Winget List AppID"
    $InstalledApp = & $winget list --Id $AppID -e --accept-source-agreements -s winget | Out-String

    #Return if AppID exists in the list
    if ($InstalledApp -match [regex]::Escape($AppID)) {
        return $true
    }
    else {
        return $false
    }
}

#Check if App exists in Winget Repository
function Confirm-Exist ($AppID) {
    #Check is app exists in the winget repository
    $WingetApp = & $winget show --Id $AppID -e --accept-source-agreements -s winget | Out-String

    #Return if AppID exists
    if ($WingetApp -match [regex]::Escape($AppID)) {
        Write-ToLog "-> $AppID exists on Winget Repository." "Cyan"
        return $true
    }
    else {
        Write-ToLog "-> $AppID does not exist on Winget Repository! Check spelling." "Red"
        return $false
    }
}

#Check if install modifications exist in "mods" directory
function Test-ModsInstall ($AppID) {
    if (Test-Path "$PSScriptRoot\mods\$AppID-preinstall.ps1") {
        $ModsPreInstall = "$PSScriptRoot\mods\$AppID-preinstall.ps1"
    }
    elseif (($WAUInstallLocation) -and (Test-Path "$WAUInstallLocation\mods\$AppID-preinstall.ps1")) {
        $ModsPreInstall = "$WAUInstallLocation\mods\$AppID-preinstall.ps1"
    }

    if (Test-Path "$PSScriptRoot\mods\$AppID-install.ps1") {
        $ModsInstall = "$PSScriptRoot\mods\$AppID-install.ps1"
    }
    elseif (($WAUInstallLocation) -and (Test-Path "$WAUInstallLocation\mods\$AppID-install.ps1")) {
        $ModsInstall = "$WAUInstallLocation\mods\$AppID-install.ps1"
    }

    if (Test-Path "$PSScriptRoot\mods\$AppID-installed-once.ps1") {
        $ModsInstalledOnce = "$PSScriptRoot\mods\$AppID-installed-once.ps1"
    }

    if (Test-Path "$PSScriptRoot\mods\$AppID-installed.ps1") {
        $ModsInstalled = "$PSScriptRoot\mods\$AppID-installed.ps1"
    }
    elseif (($WAUInstallLocation) -and (Test-Path "$WAUInstallLocation\mods\$AppID-installed.ps1")) {
        $ModsInstalled = "$WAUInstallLocation\mods\$AppID-installed.ps1"
    }

    return $ModsPreInstall, $ModsInstall, $ModsInstalledOnce, $ModsInstalled
}

#Check if uninstall modifications exist in "mods" directory
function Test-ModsUninstall ($AppID) {
    if (Test-Path "$PSScriptRoot\mods\$AppID-preuninstall.ps1") {
        $ModsPreUninstall = "$PSScriptRoot\mods\$AppID-preuninstall.ps1"
    }
    elseif (($WAUInstallLocation) -and (Test-Path "$WAUInstallLocation\mods\$AppID-preuninstall.ps1")) {
        $ModsPreUninstall = "$WAUInstallLocation\mods\$AppID-preuninstall.ps1"
    }

    if (Test-Path "$PSScriptRoot\mods\$AppID-uninstall.ps1") {
        $ModsUninstall = "$PSScriptRoot\mods\$AppID-uninstall.ps1"
    }
    elseif (($WAUInstallLocation) -and (Test-Path "$WAUInstallLocation\mods\$AppID-uninstall.ps1")) {
        $ModsUninstall = "$WAUInstallLocation\mods\$AppID-uninstall.ps1"
    }

    if (Test-Path "$PSScriptRoot\mods\$AppID-uninstalled.ps1") {
        $ModsUninstalled = "$PSScriptRoot\mods\$AppID-uninstalled.ps1"
    }
    elseif (($WAUInstallLocation) -and (Test-Path "$WAUInstallLocation\mods\$AppID-uninstalled.ps1")) {
        $ModsUninstalled = "$WAUInstallLocation\mods\$AppID-uninstalled.ps1"
    }

    return $ModsPreUninstall, $ModsUninstall, $ModsUninstalled
}

#Install function
function Install-App ($AppID, $AppArgs) {
    $IsInstalled = Confirm-Install $AppID
    if (!($IsInstalled)) {
        #Check if mods exist (or already exist) for preinstall/install/installedonce/installed
        $ModsPreInstall, $ModsInstall, $ModsInstalledOnce, $ModsInstalled = Test-ModsInstall $($AppID)

        #If PreInstall script exist
        if ($ModsPreInstall) {
            Write-ToLog "-> Modifications for $AppID before install are being applied..." "Yellow"
            & "$ModsPreInstall"
        }

        #Install App
        Write-ToLog "-> Installing $AppID..." "Yellow"
        $WingetArgs = "install --id $AppID -e --accept-package-agreements --accept-source-agreements -s winget -h $AppArgs" -split " "
        Write-ToLog "-> Running: `"$Winget`" $WingetArgs"
        & "$Winget" $WingetArgs | Where-Object { $_ -notlike "   *" } | Tee-Object -file $LogFile -Append

        if ($ModsInstall) {
            Write-ToLog "-> Modifications for $AppID during install are being applied..." "Yellow"
            & "$ModsInstall"
        }

        #Check if install is ok
        $IsInstalled = Confirm-Install $AppID
        if ($IsInstalled) {
            Write-ToLog "-> $AppID successfully installed." "Green"

            if ($ModsInstalledOnce) {
                Write-ToLog "-> Modifications for $AppID after install (one time) are being applied..." "Yellow"
                & "$ModsInstalledOnce"
            }
            elseif ($ModsInstalled) {
                Write-ToLog "-> Modifications for $AppID after install are being applied..." "Yellow"
                & "$ModsInstalled"
            }

            #Add mods if deployed from Winget-Install
            if ((Test-Path "$PSScriptRoot\mods\$AppID-preinstall.ps1") -or (Test-Path "$PSScriptRoot\mods\$AppID-upgrade.ps1") -or (Test-Path "$PSScriptRoot\mods\$AppID-install.ps1") -or (Test-Path "$PSScriptRoot\mods\$AppID-installed.ps1")) {
                Add-WAUMods $AppID
            }

            #Add to WAU White List if set
            if ($WAUWhiteList) {
                Add-WAUWhiteList $AppID
            }
        }
        else {
            Write-ToLog "-> $AppID installation failed!" "Red"
        }
    }
    else {
        Write-ToLog "-> $AppID is already installed." "Cyan"
    }
}

#Uninstall function
function Uninstall-App ($AppID, $AppArgs) {
    $IsInstalled = Confirm-Install $AppID
    if ($IsInstalled) {
        #Check if mods exist (or already exist) for preuninstall/uninstall/uninstalled
        $ModsPreUninstall, $ModsUninstall, $ModsUninstalled = Test-ModsUninstall $AppID

        #If PreUninstall script exist
        if ($ModsPreUninstall) {
            Write-ToLog "-> Modifications for $AppID before uninstall are being applied..." "Yellow"
            & "$ModsPreUninstall"
        }

        #Uninstall App
        Write-ToLog "-> Uninstalling $AppID..." "Yellow"
        $WingetArgs = "uninstall --id $AppID -e --accept-source-agreements -h" -split " "
        Write-ToLog "-> Running: `"$Winget`" $WingetArgs"
        & "$Winget" $WingetArgs | Where-Object { $_ -notlike "   *" } | Tee-Object -file $LogFile -Append

        if ($ModsUninstall) {
            Write-ToLog "-> Modifications for $AppID during uninstall are being applied..." "Yellow"
            & "$ModsUninstall"
        }

        #Check if uninstall is ok
        $IsInstalled = Confirm-Install $AppID
        if (!($IsInstalled)) {
            Write-ToLog "-> $AppID successfully uninstalled." "Green"
            if ($ModsUninstalled) {
                Write-ToLog "-> Modifications for $AppID after uninstall are being applied..." "Yellow"
                & "$ModsUninstalled"
            }

            #Remove mods if deployed from Winget-Install
            if ((Test-Path "$PSScriptRoot\mods\$AppID-preinstall.ps1") -or (Test-Path "$PSScriptRoot\mods\$AppID-upgrade.ps1") -or (Test-Path "$PSScriptRoot\mods\$AppID-install.ps1") -or (Test-Path "$PSScriptRoot\mods\$AppID-installed.ps1")) {
                Remove-WAUMods $AppID
            }

            #Remove from WAU White List if set
            if ($WAUWhiteList) {
                Remove-WAUWhiteList $AppID
            }
        }
        else {
            Write-ToLog "-> $AppID uninstall failed!" "Red"
        }
    }
    else {
        Write-ToLog "-> $AppID is not installed." "Cyan"
    }
}

#Function to Add app to WAU white list
function Add-WAUWhiteList ($AppID) {
    #Check if WAU default intall path exists
    $WhiteList = "$WAUInstallLocation\included_apps.txt"
    if (Test-Path $WhiteList) {
        Write-ToLog "-> Add $AppID to WAU included_apps.txt"
        #Add App to "included_apps.txt"
        Add-Content -path $WhiteList -Value "`n$AppID" -Force
        #Remove duplicate and blank lines
        $file = Get-Content $WhiteList | Select-Object -Unique | Where-Object { $_.trim() -ne "" } | Sort-Object
        $file | Out-File $WhiteList
    }
}

#Function to Remove app from WAU white list
function Remove-WAUWhiteList ($AppID) {
    #Check if WAU default intall path exists
    $WhiteList = "$WAUInstallLocation\included_apps.txt"
    if (Test-Path $WhiteList) {
        Write-ToLog "-> Remove $AppID from WAU included_apps.txt"
        #Remove app from list
        $file = Get-Content $WhiteList | Where-Object { $_ -ne "$AppID" }
        $file | Out-File $WhiteList
    }
}

#Function to Add Mods to WAU "mods"
function Add-WAUMods ($AppID) {
    #Check if WAU default install path exists
    $Mods = "$WAUInstallLocation\mods"
    if (Test-Path $Mods) {
        #Add mods
        Write-ToLog "-> Add modifications for $AppID to WAU 'mods'"
        Copy-Item "$PSScriptRoot\mods\$AppID-*" -Destination "$Mods" -Exclude "*installed-once*", "*uninstall*" -Force
    }
}

#Function to Remove Mods from WAU "mods"
function Remove-WAUMods ($AppID) {
    #Check if WAU default install path exists
    $Mods = "$WAUInstallLocation\mods"
    if (Test-Path "$Mods\$AppID*") {
        Write-ToLog "-> Remove $AppID modifications from WAU 'mods'"
        #Remove mods
        Remove-Item -Path "$Mods\$AppID-*" -Exclude "*uninstall*" -Force
    }
}



<# MAIN #>

#If running as a 32-bit process on an x64 system, re-launch as a 64-bit process
if ("$env:PROCESSOR_ARCHITEW6432" -ne "ARM64") {
    if (Test-Path "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe") {
        Start-Process "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe" -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $($MyInvocation.line)"
        Exit $lastexitcode
    }
}

#Config console output encoding
$null = cmd /c '' #Tip for ISE
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:ProgressPreference = 'SilentlyContinue'

#Check if current process is elevated (System or admin user)
$CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$Script:IsElevated = $CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

#Get potential WAU Installed location
$WAURegKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate\"
if (Test-Path $WAURegKey) {
    $Script:WAUInstallLocation = Get-ItemProperty $WAURegKey | Select-Object -ExpandProperty InstallLocation -ErrorAction SilentlyContinue
}

#LogPath initialisation
if (!($LogPath)) {
    #If LogPath is not set, get WAU log path
    if ($WAUInstallLocation) {
        $LogPath = "$WAUInstallLocation\Logs"
    }
    else {
        #Else, set a default one
        $LogPath = "$env:ProgramData\Winget-AutoUpdate\Logs"
    }
}

#Logs initialisation
if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Force -Path $LogPath | Out-Null
}

#Log file
if ($IsElevated) {
    $Script:LogFile = "$LogPath\install.log"
}
else {
    $Script:LogFile = "$LogPath\install_$env:UserName.log"
}

#Header (not logged)
Write-Host "`n"
Write-Host "`t        888       888 d8b  .d8888b.           d8b" -ForegroundColor Cyan
Write-Host "`t        888   o   888 Y8P d88P  Y88b          Y8P" -ForegroundColor Cyan
Write-Host "`t        888  d8b  888     888    888" -ForegroundColor Cyan
Write-Host "`t        888 d888b 888 888 888        888  888 888" -ForegroundColor Cyan
Write-Host "`t        888d88888b888 888 888  88888 888  888 888" -ForegroundColor Cyan
Write-Host "`t        88888P Y88888 888 888    888 888  888 888" -ForegroundColor Magenta
Write-Host "`t        8888P   Y8888 888 Y88b  d88P Y88b 888 888" -ForegroundColor Cyan
Write-Host "`t        888P     Y888 888  `"Y8888P88  `"Y88888 888`n" -ForegroundColor Cyan
Write-Host "`t       https://github.com/Romanitho/Winget-Install" -ForegroundColor Magenta
Write-Host "`t     https://github.com/Romanitho/Winget-Install-GUI`n" -ForegroundColor Cyan
Write-Host "`t_________________________________________________________`n `n "

#Log Header
if ($Uninstall) {
    Write-ToLog "###   $(Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern) - NEW UNINSTALL REQUEST   ###`n " "Magenta"
}
else {
    Write-ToLog "###   $(Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern) - NEW INSTALL REQUEST   ###`n " "Magenta"
}

#Get Winget command
$Script:Winget = Get-WingetCmd

if ($IsElevated -eq $True) {
    Write-ToLog "Running with admin rights.`n "
    #Check/install prerequisites
    Install-Prerequisites
    #Reload Winget command
    $Script:Winget = Get-WingetCmd
    #Run Scope Machine funtion
    Add-ScopeMachine
}
else {
    Write-ToLog "Running without admin rights.`n "
}

if ($Winget) {
    #Run install or uninstall for all apps
    foreach ($App_Full in $AppIDs) {
        #Split AppID and Custom arguments
        $AppID, $AppArgs = ($App_Full.Trim().Split(" ", 2))

        #Log current App
        Write-ToLog "Start $AppID processing..." "Blue"

        #Install or Uninstall command
        if ($Uninstall) {
            Uninstall-App $AppID $AppArgs
        }
        else {
            #Check if app exists on Winget Repo
            $Exists = Confirm-Exist $AppID
            if ($Exists) {
                #Install
                Install-App $AppID $AppArgs
            }
        }

        #Log current App
        Write-ToLog "$AppID processing finished!`n" "Blue"
        Start-Sleep 1
    }
}

Write-ToLog "###   END REQUEST   ###`n" "Magenta"
Start-Sleep 3
