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
    [Parameter(Mandatory = $True, ParameterSetName = "AppIDs")] [String[]] $AppIDs,
    [Parameter(Mandatory = $False)] [Switch] $Uninstall,
    [Parameter(Mandatory = $False)] [String] $LogPath,
    [Parameter(Mandatory = $False)] [Switch] $WAUWhiteList
)


<# FUNCTIONS #>

#Initialization
function Start-Init {

    #Config console output encoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    #Get WAU Installed location (if installed)
    $WAURegKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Winget-AutoUpdate\"
    if (Test-Path $WAURegKey) {
        $Script:WAUInstallLocation = Get-ItemProperty $WAURegKey | Select-Object -ExpandProperty InstallLocation -ErrorAction SilentlyContinue
    }

    #LogPath initialisation
    if (!($LogPath)) {
        #If LogPath if null, get WAU log path from registry
        if ($WAUInstallLocation) {
            $LogPath = "$WAUInstallLocation\Logs"
        }
        else {
            #Else, set default one
            $LogPath = "$env:ProgramData\Winget-AutoUpdate\Logs"
        }
    }

    #Logs initialisation
    if (!(Test-Path $LogPath)) {
        New-Item -ItemType Directory -Force -Path $LogPath | Out-Null
    }

    #Log file
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        $Script:LogFile = "$LogPath\install.log"
    }
    else {
        $Script:LogFile = "$LogPath\install_$env:UserName.log"
    }

    #Log Header
    if ($Uninstall) {
        Write-Log "###   $(Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern) - NEW UNINSTALL REQUEST   ###" "Magenta"
    }
    else {
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
    $ResolveWingetPath = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe" | Sort-Object { [version]($_.Path -replace '^[^\d]+_((\d+\.)*\d+)_.*', '$1') }
    if ($ResolveWingetPath) {
        #If multiple versions, pick last one
        $WingetPath = $ResolveWingetPath[-1].Path
    }
    #Get WinGet Location in User context
    $WingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($WingetCmd) {
        $Script:Winget = $WingetCmd.Source
    }
    #Get Winget Location in System context
    elseif (Test-Path "$WingetPath\winget.exe") {
        $Script:Winget = "$WingetPath\winget.exe"
    }
    else {
        Write-Log "Winget not installed or detected !" "Red"
        break
    }
    Write-Log "Using following Winget Cmd: $winget`n"
}

#Function to configure prefered scope option as Machine
function Add-ScopeMachine {
    #Get Settings path for system or current user
    if ([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        $SettingsPath = "$Env:windir\System32\config\systemprofile\AppData\Local\Microsoft\WinGet\Settings\settings.json"
    }
    else {
        $SettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
    }

    #Check if setting file exist, if not create it
    if (Test-Path $SettingsPath) {
        $ConfigFile = Get-Content -Path $SettingsPath | Where-Object { $_ -notmatch '//' } | ConvertFrom-Json
    }

    if (!$ConfigFile) {
        $ConfigFile = @{}
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

#Check if app is installed
function Confirm-Install ($AppID) {
    #Get "Winget List AppID"
    $InstalledApp = & $winget list --Id $AppID -e --accept-source-agreements | Out-String

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
    $WingetApp = & $winget show --Id $AppID -e --accept-source-agreements | Out-String

    #Return if AppID exists
    if ($WingetApp -match [regex]::Escape($AppID)) {
        Write-Log "-> $AppID exists on Winget Repository." "Cyan"
        return $true
    }
    else {
        Write-Log "-> $AppID does not exist on Winget Repository! Check spelling." "Red"
        return $false
    }
}

#Check if modifications exist in "mods" directory
function Test-ModsInstall ($AppID) {

    #Takes care of a null situation
    $ModsPreInstall = $null
    $ModsInstallOnce = $null
    $ModsInstall = $null
    $ModsUpgrade = $null

    if (Test-Path "$PSScriptRoot\mods\$AppID-preinstall.ps1") {
        $ModsPreInstall = "$PSScriptRoot\mods\$AppID-preinstall.ps1"
    }

    if (Test-Path "$PSScriptRoot\mods\$AppID-install-once.ps1") {
        $ModsInstallOnce = "$PSScriptRoot\mods\$AppID-install-once.ps1"
        return $ModsPreInstall, $ModsInstallOnce
    }
    elseif (Test-Path "$PSScriptRoot\mods\$AppID-install.ps1") {
        $ModsInstall = "$PSScriptRoot\mods\$AppID-install.ps1"
        return $ModsPreInstall, $ModsInstall
    }
    elseif (Test-Path "$PSScriptRoot\mods\$AppID-upgrade.ps1") {
        $ModsUpgrade = "$PSScriptRoot\mods\$AppID-upgrade.ps1"
        return $ModsPreInstall, $ModsUpgrade
    }
    return $ModsPreInstall
}

function Test-ModsUninstall ($AppID) {
    if (Test-Path "$PSScriptRoot\mods\$AppID-uninstall.ps1") {
        $ModsUninstall = "$PSScriptRoot\mods\$AppID-uninstall.ps1"
    }
    if (Test-Path "$PSScriptRoot\mods\$AppID-uninstalled.ps1") {
        $ModsUninstalled = "$PSScriptRoot\mods\$AppID-uninstalled.ps1"
    }
    return $ModsUninstall, $ModsUninstalled
}

#Install function
function Install-App ($AppID, $AppArgs) {
    $IsInstalled = Confirm-Install $AppID
    if (!($IsInstalled)) {
        #Check if mods exist for preinstall/install/upgrade
        $ModsPreInstall, $ModsInstall = Test-ModsInstall $($AppID)

        #Check if an preinstall mod already exist
        if (!($ModsPreInstall) -and (Test-Path "$WAUInstallLocation\mods\$AppID-preinstall.ps1")) {
            $ModsPreInstall = "$WAUInstallLocation\mods\$AppID-preinstall.ps1"
        }

        #If PreInstall script exist
        if ($ModsPreInstall) {
            Write-Log "-> Modifications for $AppID before upgrade are being applied..." "Yellow"
            & "$ModsPreInstall"
        }

        #Install App
        Write-Log "-> Installing $AppID..." "Yellow"
        $WingetArgs = "install --id $AppID -e --accept-package-agreements --accept-source-agreements -h $AppArgs" -split " "
        Write-Log "-> Running: `"$Winget`" $WingetArgs"

        & "$Winget" $WingetArgs | Tee-Object -file $LogFile -Append

        #Check if install is ok
        $IsInstalled = Confirm-Install $AppID
        if ($IsInstalled) {
            Write-Log "-> $AppID successfully installed." "Green"
            #Check if an install/upgrade mod exist
            if (($ModsInstall -like "*$AppID-install*") -or ($ModsInstall -like "*$AppID-upgrade*")) {
                if ($ModsInstall -like "*$AppID-install*") {
                    Write-Log "-> Modifications for $AppID after install are being applied..." "Yellow"
                    & "$ModsInstall"
                }
                #Add mods if deployed from app install
                Add-WAUMods $AppID
            }
            else {
                #Check if an install mod already exist
                $ModsInstall = "$WAUInstallLocation\mods\$AppID-install.ps1"
                if (Test-Path "$ModsInstall") {
                    Write-Log "-> Modifications for $AppID after install are being applied..." "Yellow"
                    & "$ModsInstall"
                }
            }
            #Add to WAU White List if set
            if ($WAUWhiteList) {
                Add-WAUWhiteList $AppID
            }
        }
        else {
            Write-Log "-> $AppID installation failed!" "Red"
        }
    }
    else {
        Write-Log "-> $AppID is already installed." "Cyan"
    }
}

#Uninstall function
function Uninstall-App ($AppID, $AppArgs) {
    $IsInstalled = Confirm-Install $AppID
    if ($IsInstalled) {
        #Uninstall App
        Write-Log "-> Uninstalling $AppID..." "Yellow"
        $WingetArgs = "uninstall --id $AppID -e --accept-source-agreements -h" -split " "
        Write-Log "-> Running: `"$Winget`" $WingetArgs"
        & "$Winget" $WingetArgs | Tee-Object -file $LogFile -Append

        #Check if mods exist
        $ModsUninstall, $ModsUninstalled = Test-ModsUninstall $AppID
        if ($ModsUninstall) {
            Write-Log "-> Modifications for $AppID during uninstall are being applied..." "Yellow"
            & "$ModsUninstall"
        }
        else {
            #Check if an uninstall mod already exist
            $ModsUninstall = "$WAUInstallLocation\mods\$AppID-uninstall.ps1"
            if (Test-Path "$ModsUninstall") {
                Write-Log "-> Modifications for $AppID during uninstall are being applied..." "Yellow"
                & "$ModsUninstall"
            }
        }
        
        #Check if uninstall is ok
        $IsInstalled = Confirm-Install $AppID
        if (!($IsInstalled)) {
            Write-Log "-> $AppID successfully uninstalled." "Green"
            if ($ModsUninstalled) {
                Write-Log "-> Modifications for $AppID after uninstall are being applied..." "Yellow"
                & "$ModsUninstalled"
                #Remove mods if deployed from app install
                if ((Test-Path "$PSScriptRoot\mods\$AppID-install.ps1") -or (Test-Path "$PSScriptRoot\mods\$AppID-upgrade.ps1")) {
                    Remove-WAUMods $AppID
                }
            }
            else {
                #Check if an uninstalled mod already exist
                $ModsUninstalled = "$WAUInstallLocation\mods\$AppID-uninstalled.ps1"
                if (Test-Path "$ModsUninstalled") {
                    Write-Log "-> Modifications for $AppID after uninstall are being applied..." "Yellow"
                    & "$ModsUninstalled"
                }
                #Remove mods if deployed from app install
                if ((Test-Path "$PSScriptRoot\mods\$AppID-install.ps1") -or (Test-Path "$PSScriptRoot\mods\$AppID-upgrade.ps1")) {
                    Remove-WAUMods $AppID
                }
            }
            #Remove from WAU White List if set
            if ($WAUWhiteList) {
                Remove-WAUWhiteList $AppID
            }
        }
        else {
            Write-Log "-> $AppID uninstall failed!" "Red"
        }
    }
    else {
        Write-Log "-> $AppID is not installed." "Cyan"
    }
}

#Function to Add app to WAU white list
function Add-WAUWhiteList ($AppID) {
    #Check if WAU default intall path exists
    $WhiteList = "$WAUInstallLocation\included_apps.txt"
    if (Test-Path $WhiteList) {
        Write-Log "-> Add $AppID to WAU included_apps.txt"
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
        Write-Log "-> Remove $AppID from WAU included_apps.txt"
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
        if ((Test-Path "$PSScriptRoot\mods\$AppID-preinstall.ps1") -or (Test-Path "$PSScriptRoot\mods\$AppID-install.ps1") -or (Test-Path "$PSScriptRoot\mods\$AppID-upgrade.ps1")) {
            Write-Log "-> Add modifications for $AppID to WAU 'mods'"
            Copy-Item "$PSScriptRoot\mods\$AppID-*" -Destination "$Mods" -Exclude "*-install-once*", "*-uninstall*" -Force
        }
    }
}

#Function to Remove Mods from WAU "mods"
function Remove-WAUMods ($AppID) {
    #Check if WAU default install path exists
    $Mods = "$WAUInstallLocation\mods"
    if (Test-Path "$Mods\$AppID*") {
        Write-Log "-> Remove $AppID modifications from WAU 'mods'"
        #Remove mods
        Remove-Item -Path "$Mods\$AppID*" -Exclude "*-uninstall*"-Force
    }
}

<# MAIN #>

#If running as a 32-bit process on an x64 system, re-launch as a 64-bit process
if ("$env:PROCESSOR_ARCHITEW6432" -ne "ARM64") {
    if (Test-Path "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe") {
        Start-Process "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe" -Wait -NoNewWindow -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $($MyInvocation.line)"
        Exit $lastexitcode
    }
}

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
Write-Host "`t_________________________________________________________`n`n"

#Run Init Function
Start-Init

#Run Scope Machine funtion
Add-ScopeMachine

#Run WingetCmd Function
Get-WingetCmd

#Run install or uninstall for all apps
foreach ($App_Full in $AppIDs) {
    #Split AppID and Custom arguments
    $AppID, $AppArgs = ($App_Full.Trim().Split(" ", 2))

    #Log current App
    Write-Log "Start $AppID processing..." "Blue"

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
    Write-Log "$AppID processing finished!`n" "Blue"
    Start-Sleep 1

}

Write-Log "###   END REQUEST   ###`n" "Magenta"
Start-Sleep 3
