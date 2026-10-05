function Get-WorkerLibrary {
    $parts=New-StringList
    $parts.Add('$script:LogPath=""; $script:VfcLogLevel="INFO"')
    $parts.Add('$ErrorActionPreference="Stop"; Set-StrictMode -Version 2.0; $script:VpkIndexCache=@{}; $script:VpkToolIndexCache=@{}; $script:Work=$null; $script:SchemeNames=@("ClientScheme.res","SourceScheme.res","ChatScheme.res"); $script:SymbolFontPattern="(?i)(marlett|webdings|wingdings|symbol|icons?|glyph|buttons?|crosshairs?|halflife2)"; $script:SymbolAliasPattern="(?i)(icon|glyph|button|crosshair)"')
    foreach($name in $script:WorkerFunctionNames){$command=Get-Command $name -CommandType Function; $parts.Add("function $name {"+$command.Definition+[Environment]::NewLine+"}")}
    return [string]::Join([Environment]::NewLine,$parts.ToArray())
}
function Start-GuiTask {
    param($State,[string]$Task,[string]$Game,[hashtable]$Fonts,[hashtable]$Factors,$HierarchyProfile)
    if($State.Pipeline){return}
    $State.Work=[hashtable]::Synchronized(@{Cancel=$false;CanCancel=$true;Message='Starting...'})
    $model=if($State.ContainsKey('Model')){$State['Model']}else{$null}
    $State.Work.LogLevel='INFO'
    if($model -and $model.Preferences.ContainsKey('LogLevel') -and $model.Preferences['LogLevel']){$State.Work.LogLevel=[string]$model.Preferences['LogLevel']}
    $State.Work.LaunchGame=($Task -eq 'Build' -and $model -and $model.Preferences.ContainsKey('LaunchGame') -and $model.Preferences['LaunchGame'])
    $State.Work.ShowDuplicates=$false
    if($model -and $model.Preferences.ContainsKey('ShowDuplicates')){$State.Work.ShowDuplicates=[bool]$model.Preferences['ShowDuplicates']}
    $State.Work.LogPath=New-OperationLog $Task $Game
    $State.CurrentLogPath=$State.Work.LogPath
    $State.Task=$Task
    $State.Pipeline=[PowerShell]::Create()
    $worker={
        param($library,$task,$game,$fonts,$factors,$operationState,$mod,$hierarchyProfile,$scanSnapshot)
        . ([scriptblock]::Create($library))
        $script:Work=$operationState
        try{
        Test-WorkCancellation
        if($task -eq 'Scan'){
            Set-WorkStatus 'Locating game folder'
            $game=Resolve-GamePath $game
            $resolved=Get-ResolvedSchemes $game $mod
            $records=@(Get-FontRecords $resolved.Documents.ToArray())
            $gameFonts=@(Get-GameFontAssets $resolved)
            Set-WorkStatus 'Loading Windows font previews'
            $families=@(Get-InstalledFontFamilies)
            Test-WorkCancellation
            $summary=@(Get-FontSummary $records -All:($operationState.ShowDuplicates -eq $true))
            Set-WorkStatus 'Loading source locations'
            Add-FontUsageContext $summary $resolved.Sources
            # Keep the immutable baseline and indexes alive across GUI workers.
            # Build clones the AST before changing font names/heights.
            $null=Read-VirtualFile $resolved.Sources 'resource/FontInfo.kv'
            $snapshot=[pscustomobject]@{Game=$game;Mod=$mod;Resolved=$resolved;GameFonts=$gameFonts;Indexes=$script:VpkIndexCache}
            [pscustomobject]@{Game=$game;Summary=$summary;Families=$families;GameFonts=$gameFonts;Profile=(Read-FontProfile $game);ScanSnapshot=$snapshot}
        }elseif($task -eq 'RemoveOverride'){
            Remove-FontOverride $game $mod
        }elseif($task -eq 'Save'){
            Set-WorkStatus 'Preparing settings'
            $profile=ConvertTo-PlainValue $hierarchyProfile
            Test-WorkCancellation
            Set-WorkStatus 'Saving settings'
            $script:Work.CanCancel=$false
            Save-FontProfile $game $profile
            [pscustomobject]@{Saved=$true}
        }elseif($task -eq 'Import'){
            Set-WorkStatus 'Loading settings'
            if((Get-Item -LiteralPath $game).Length -gt 5MB){throw 'Settings file exceeds 5 MB.'}
            $profile=ConvertTo-PlainValue ([IO.File]::ReadAllText($game)|ConvertFrom-Json)
            $settings=ConvertTo-NodeSettings $profile
            Test-WorkCancellation
            [pscustomobject]@{Settings=$settings}
        }elseif($task -eq 'Export'){
            Set-WorkStatus 'Preparing settings'
            $profile=ConvertTo-PlainValue $hierarchyProfile
            Test-WorkCancellation
            Set-WorkStatus 'Exporting settings'
            $script:Work.CanCancel=$false
            Write-SettingsFile $game $profile
            [pscustomobject]@{Exported=$true}
        }else{
            $map=New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach($key in $fonts.Keys){$map[$key]=[string]$fonts[$key]}
            $settings=$null; if($hierarchyProfile){$settings=ConvertTo-NodeSettings $hierarchyProfile}
            if($scanSnapshot){$script:VpkIndexCache=$scanSnapshot.Indexes}
            Invoke-FontBuild $game $mod $map $null -FactorMap $factors -NodeSettings $settings -HierarchyProfile $hierarchyProfile -ScanSnapshot $scanSnapshot
            if($operationState.LaunchGame){Restart-GameProcess $game}
        }
        Write-VfcLog 'INFO' "Operation finished: task=$task"
        }catch{Write-VfcLog 'ERROR' ($_.ToString()+[Environment]::NewLine+$_.Exception.ToString()+[Environment]::NewLine+$_.ScriptStackTrace);throw}
    }
    $snapshot=$null;if($State.ContainsKey('ScanSnapshot')){$snapshot=$State.ScanSnapshot}
    $null=$State.Pipeline.AddScript($worker.ToString()).AddArgument((Get-WorkerLibrary)).AddArgument($Task).AddArgument($Game).AddArgument($Fonts).AddArgument($Factors).AddArgument($State.Work).AddArgument($OutputModName).AddArgument($HierarchyProfile).AddArgument($snapshot)
    $State.Handle=$State.Pipeline.BeginInvoke()
}
