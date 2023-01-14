Pre/During/Post install/uninstall custom scripts should be placed here.  
A script **Template** and **Mods Functions** are included as **example** to get you started...  

Scripts that are considered:  
**AppID**`-preinstall.ps1`, `-install.ps1`, `-installed-once.ps1`, `-installed.ps1`, `-preuninstall.ps1`, `-uninstall.ps1` or `-uninstalled.ps1`  

If you're using [**WAU** (Winget-AutoUpdate)](https://github.com/Romanitho/Winget-AutoUpdate) they get copied to the **WAU mods** directory (except `-installed-once.ps1`  and `-uninstall.ps1`) and also runs when upgrading apps in **WAU**.

They are deleted from **WAU** on an uninstall (if deployed from **Winget-Install**)
