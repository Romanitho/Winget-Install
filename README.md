# Winget-Install
Powershell scripts to install Winget Packages with SCCM/Intune (or similar) or even as standalone in system context (Inspired by [o-l-a-v](https://github.com/o-l-a-v) work)

## Install
### SCCM
- Create an application and put the "winget-install.ps1" script as sources
- For install command, put this command line:  
`powershell.exe -ExecutionPolicy bypass -File winget-install.ps1 -AppIDs Notepad++.Notepad++`

![image](https://user-images.githubusercontent.com/96626929/152222570-da527307-ecc9-4fc2-b83e-7891ffae36ee.png)

### Intune
- Create Intunewin with the "winget-install.ps1" script
- Create a Win32 application in Intune
- Put this command line as Install Cmd (Must call 64 bits powershell in order to work):  
`"%systemroot%\sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File winget-install.ps1 -AppIDs Notepad++.Notepad++`

> You can also use **WingetIntunePackager** tool to package apps from a GUI: https://github.com/Romanitho/WingetIntunePackager

### Use Winget native parameters
You can add custom parameter in your `AppIDs` argument. Don't forget to escape the quote:  
`powershell.exe -Executionpolicy Bypass -File winget-install.ps1 -AppIDs "Citrix.Workspace --override \"/silent /noreboot /includeSSON /forceinstall\""`  
Details: https://github.com/Romanitho/Winget-Install/discussions/20

### Multiple apps at once
- Run this command  
`powershell.exe -Executionpolicy Bypass -Command .\winget-install.ps1 -AppIDs "7zip.7zip, Notepad++.Notepad++"`

## Detection method
- Use the "winget-detect.ps1" with SCCM or Intune as detection method.
- Replace "$AppToDetect" value by your App ID  
`$AppToDetect = "Notepad++.Notepad++"`

## Updates
https://github.com/Romanitho/Winget-autoupdate

## Uninstall
- To uninstall an app, you can use:  
`powershell.exe -ExecutionPolicy bypass -File winget-install.ps1 -AppIDs Notepad++.Notepad++ -Uninstall`

but most of the time, winget does not manage silent uninstall correcty.
- I would suggest to use the original application uninstaller method, something like this:  
`C:\Program Files\Notepad++\uninstall.exe /S`

## Custom (Mods)

The **Mods feature** allows you to run additional scripts before/when/after installing or uninstalling an app.  
Just put the script with the **AppID** followed by the suffix to be considered in the **Mods directory**:  
**AppID**`-preinstall.ps1`, `-install.ps1`, `-installed-once.ps1`, `-installed.ps1`, `-preuninstall.ps1`, `-uninstall.ps1` or `-uninstalled.ps1`  

> Example:  
> Runs before install: `AppID-preinstall.ps1`  
> Runs during install (before install check): `AppID-install.ps1`  
> Runs after install has been confirmed (one time): `AppID-installed-once.ps1`  
> Runs after install has been confirmed: `AppID-installed.ps1`  
> Runs before uninstall: `AppID-preuninstall.ps1`  
> Runs during uninstall (before uninstall check): `AppID-uninstall.ps1`  
> Runs after uninstall has been confirmed: `AppID-uninstalled.ps1`  

If you're using [**WAU** (Winget-AutoUpdate)](https://github.com/Romanitho/Winget-AutoUpdate) they get copied to the **WAU mods** directory (except `-installed-once.ps1/-preuninstall.ps1/-uninstall.ps1/-uninstalled.ps1`) and also runs when upgrading apps in **WAU**.

`AppID-installed-once.ps1` runs instead of `AppID-installed.ps1` from **Winget-Install**.  

They are deleted from **WAU** on an uninstall (if deployed from **Winget-Install**)

## Other ideas and approaches
https://github.com/o-l-a-v/winget-intune-win32
