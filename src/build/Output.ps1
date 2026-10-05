function Remove-FontOverride {
    param([string]$Game,[string]$Mod)
    $root=Get-ManagedOutputRoot $Game $Mod
    if(-not [IO.Directory]::Exists($root)){return [pscustomobject]@{Removed=$false;Output=$root}}
    if(-not [IO.File]::Exists((Join-Path $root 'VGUIFontChanger-info.json'))){throw 'Output folder has no VGUIFontChanger ownership manifest.'}
    $manifest=[IO.File]::ReadAllText((Join-Path $root 'VGUIFontChanger-info.json'))|ConvertFrom-Json
    if($manifest.Application -cne 'VGUIFontChanger'){throw 'Output folder ownership manifest does not match this application.'}
    Test-WorkCancellation
    $backup=New-OutputBackup $root $Game
    Test-WorkCancellation
    if($script:Work){$script:Work.CanCancel=$false}
    Remove-Item -LiteralPath $root -Recurse -Force
    Write-VfcLog 'INFO' "Override removed: folder=$root; recovery=$backup"
    return [pscustomobject]@{Removed=$true;Output=$root;Backup=$backup}
}
