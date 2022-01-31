# Winget-Install
Powershell scripts to install Winget Packages with SCCM/Intune or other tools and even standalone.

## Install
### SCCM
- Create an application and put the "winget-install.ps1" script as sources
- For install command, put this command line:
>powershell.exe -ExecutionPolicy bypass -File winget-install.ps1 -AppIDs Notepad++.Notepad++

### Intune
- Create Intunewin with the "winget-install.ps1" script
- Create an Win32 application in Intune
- Put this command line as Install Cmd
>powershell.exe -ExecutionPolicy bypass -File winget-install.ps1 -AppIDs Notepad++.Notepad++

## Detection method
- Use the "winget-detect.ps1" with SCCM or Intune as detection method.
- Replace "$AppToDetect" value by your App ID
>$AppToDetect = "Notepad++.Notepad++"

## Updates
https://github.com/Romanitho/Winget-autoupdate

## Other ideas and approaches
https://github.com/o-l-a-v/winget-intune-win32
