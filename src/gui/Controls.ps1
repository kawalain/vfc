function Set-PreviewCombo {
    param($Combo,$Cache,[hashtable]$PrivateFamilies)
    $Combo.DropDownStyle='DropDownList'; $Combo.DrawMode='OwnerDrawFixed'; $Combo.ItemHeight=27; $Combo.DropDownHeight=330
    # GetNewClosure creates a dynamic module; script-local functions are not
    # reliably visible there. Capture the implementation, not just its name.
    $previewFontFactory=${function:Get-PreviewFont}
    $handler={
        param($sender,$e)
        if($e.Index -lt 0){return}
        $e.DrawBackground()
        $name=[string]$sender.Items[$e.Index]
        $font=& $previewFontFactory $Cache $name $PrivateFamilies 1.0 ([single]$sender.Font.Size)
        $brush=New-Object Drawing.SolidBrush($e.ForeColor)
        try{$e.Graphics.DrawString($name,$font,$brush,[single]($e.Bounds.X+3),[single]($e.Bounds.Y+3))}finally{$brush.Dispose()}
        $e.DrawFocusRectangle()
    }.GetNewClosure()
    $Combo.Add_DrawItem($handler)
}

function Test-DedicatedGuiLaunch {
    param([string[]]$LaunchArguments)
    if($LaunchArguments -contains '-NoExit'){return $false}
    for($i=1;$i -lt $LaunchArguments.Count;$i++){
        if($LaunchArguments[$i] -ieq '-File' -and $i+1 -lt $LaunchArguments.Count){
            return ([IO.Path]::GetFileName($LaunchArguments[$i+1]) -ieq 'VGUIFontChanger.ps1')
        }
        if($LaunchArguments[$i] -ieq '-Command' -and $i+1 -lt $LaunchArguments.Count){
            $commandText=[string]::Join(' ', $LaunchArguments[($i+1)..($LaunchArguments.Count-1)])
            return ($commandText -match '(?i)\bVGUIFontChanger\.ps1\b')
        }
    }
    return $false
}
function Hide-GuiLaunchConsole {
    # Do not hide an existing interactive terminal, a shared console or -NoExit host.
    if(-not (Test-DedicatedGuiLaunch ([Environment]::GetCommandLineArgs()))){return [IntPtr]::Zero}
    if(-not ('VGUIFontChangerConsole' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class VGUIFontChangerConsole {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("kernel32.dll")] public static extern uint GetConsoleProcessList([Out] uint[] processes, uint count);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
}
'@
    }
    $processIds=New-Object uint32[] 2
    $count=[VGUIFontChangerConsole]::GetConsoleProcessList($processIds,2)
    if($count -ne 1 -or $processIds[0] -ne $PID){return [IntPtr]::Zero}
    $window=[VGUIFontChangerConsole]::GetConsoleWindow()
    if($window -ne [IntPtr]::Zero){$null=[VGUIFontChangerConsole]::ShowWindow($window,0)}
    return $window
}
