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

The Mods feature allows you to run additional scripts when installing, upgrading or uninstalling an app.  
Just put the script with the App ID followed by the suffix to be considered (`AppID-install-once.ps1`, `AppID-install.ps1`, `AppID-upgrade.ps1`, `AppID-uninstall.ps1` or `AppID-uninstalled.ps1`) in the Mods directory.  
`AppID-install-once.ps1` overrides `AppID-install.ps1` overrides `AppID-upgrade.ps1`
> Example:  
> If you want to run a script during uninstall (wait for process etc.), name your script like this: `AppID-uninstall.ps1`  
> If you want to run a script after the uninstall has been confirmed, name your script like this: `AppID-uninstalled.ps1`  

If your using WAU (Winget-AutoUpdate) `AppID-install.ps1` and `AppID-upgrade.ps1` gets copied to the WAU mods directory and runs when upgrading apps.
They are deleted on an uninstall (if not externally managed).

## Other ideas and approaches
https://github.com/o-l-a-v/winget-intune-win32
