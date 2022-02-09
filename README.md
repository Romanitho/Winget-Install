# Winget-Install
Powershell scripts to install Winget Packages with SCCM/Intune (or similar) or even as standalone (Inspired by [o-l-a-v](https://github.com/o-l-a-v) work)

## Install
### SCCM
- Create an application and put the "winget-install.ps1" script as sources
- For install command, put this command line:
>powershell.exe -ExecutionPolicy bypass -File winget-install.ps1 -AppIDs Notepad++.Notepad++

![image](https://user-images.githubusercontent.com/96626929/152222570-da527307-ecc9-4fc2-b83e-7891ffae36ee.png)

### Intune
- Create Intunewin with the "winget-install.ps1" script
- Create an Win32 application in Intune
- Put this command line as Install Cmd
>powershell.exe -ExecutionPolicy Bypass -File winget-install.ps1 -AppIDs Notepad++.Notepad++

### Multiple apps at once
- Run this command
> powershell.exe -Executionpolicy Bypass -Command .\winget-install.ps1 -AppIDs 7zip.7zip,Notepad++.Notepad++

## Detection method
- Use the "winget-detect.ps1" with SCCM or Intune as detection method.
- Replace "$AppToDetect" value by your App ID
>$AppToDetect = "Notepad++.Notepad++"

## Updates
https://github.com/Romanitho/Winget-autoupdate

## Uninstall
- To uninstall an app, you can use:
>powershell.exe -ExecutionPolicy bypass -File winget-install.ps1 -AppIDs Notepad++.Notepad++ -Uninstall

but most of the time, winget does not manage silent uninstall correcty.
- I would suggest to use the original application uninstaller method, something like this:
>‪C:\Program Files\Notepad++\uninstall.exe /S

## Other ideas and approaches
https://github.com/o-l-a-v/winget-intune-win32
