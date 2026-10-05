if($SelfTest){Invoke-VguiSelfTest; return}
if (-not $NoRun) {
    if ($Cli -or $GamePath -or $DefaultFont -or $Replace -or $ListFonts -or $DryRun -or $Diagnose -or $Size -or $DefaultSize -or $Factor) { Invoke-CliMode }
    else {
        $launchConsole=Hide-GuiLaunchConsole
        try{Show-VguiFontGui}catch{
            # Startup errors must remain visible instead of disappearing in a hidden console.
            if($launchConsole -ne [IntPtr]::Zero){$null=[VGUIFontChangerConsole]::ShowWindow($launchConsole,5)}
            throw
        }
    }
}
