function Invoke-SourceGameSelfTest {
    $testRoot=Join-Path ([IO.Path]::GetTempPath()) ('VGUIFontChanger-games-test-'+[guid]::NewGuid().ToString('N'))
    $oldSettingsFunction=(Get-Command Get-SettingsRoot).ScriptBlock
    $oldFindFunction=(Get-Command Find-SourceGames).ScriptBlock
    $oldSteamFunction=(Get-Command Get-SteamRoots).ScriptBlock
    $oldDefaultFunction=(Get-Command Find-DefaultGamePath).ScriptBlock
    $oldLibraryFunction=(Get-Command Get-SteamLibraries).ScriptBlock
    $script:SourceTestRoot=$testRoot
    try{
        Set-Item Function:Get-SettingsRoot {return Join-Path $script:SourceTestRoot 'settings'}
        Set-Item Function:Get-SteamRoots {return @()}
        if((Get-MaintainerProfileTarget) -ne 'https://steamcommunity.com/id/kawalain'){throw 'Missing Steam must use the web profile'}
        $script:ProfileTestSteamRoot=Join-Path $testRoot 'steam'
        $null=[IO.Directory]::CreateDirectory($script:ProfileTestSteamRoot)
        [IO.File]::WriteAllText((Join-Path $script:ProfileTestSteamRoot 'steam.exe'),'test sentinel; never executed')
        Set-Item Function:Get-SteamRoots {return $script:ProfileTestSteamRoot}
        if((Get-MaintainerProfileTarget) -ne 'steam://url/SteamIDPage/76561198436496102'){throw 'Installed Steam profile target failed'}
        $launches=New-StringList
        $mockLauncher={param($target);$launches.Add($target);if($target.StartsWith('steam:')){throw 'Simulated Steam launch failure'}}.GetNewClosure()
        Open-MaintainerProfile -Launcher $mockLauncher
        if($launches.Count -ne 2 -or $launches[1] -ne 'https://steamcommunity.com/id/kawalain'){throw 'Steam launch failure must fall back to the web profile'}
        Set-Item Function:Get-SteamRoots $oldSteamFunction
        $game=Join-Path $testRoot 'gameA';$second=Join-Path $testRoot 'gameB'
        foreach($directory in @($game,$second,(Join-Path $game 'custom/B-hud/resource'),(Join-Path $game 'custom/Z-hud/resource'),(Join-Path $game 'resource/ui'))){$null=[IO.Directory]::CreateDirectory($directory)}
        $info='"GameInfo" { "game" "Fixture" "FileSystem" { "SteamAppId" "440" "SearchPaths" { "game+mod" "|gameinfo_path|custom/*" "game+vgui" "|gameinfo_path|." } } }'
        [IO.File]::WriteAllText((Join-Path $game 'gameinfo.txt'),$info);[IO.File]::WriteAllText((Join-Path $second 'gameinfo.txt'),$info.Replace('440','441'))
        $script:SourceTestGames=@($second,$game)
        $script:DiscoveryCalls=0
        Set-Item Function:Find-SourceGames {$script:DiscoveryCalls++;return $script:SourceTestGames}
        Set-Item Function:Find-DefaultGamePath {return $script:SourceTestGames[1]}
        if((Resolve-GamePath '') -ne $game){throw 'Default game must prefer Steam application 440'}
        $layout=Read-LayoutPreferences;$layout.GamePath=$second;Save-GuiPreferences $layout
        if((Resolve-GamePath '') -ne $second){throw 'Last opened game was not restored'}
        $layout.GamePath=Join-Path $testRoot 'missing';Save-GuiPreferences $layout
        if((Resolve-GamePath '') -ne $game){throw 'Missing last game must fall back to application 440'}
        if($script:DiscoveryCalls -ne 0){throw 'Known last/default game must not enumerate all games'}
        Set-Item Function:Find-DefaultGamePath {return $null}
        if((Resolve-GamePath '') -ne $game -or $script:DiscoveryCalls -ne 1){throw 'Full discovery must run only once as the final fallback'}
        $script:FastTestLibrary=Join-Path $testRoot 'library'
        $fastGame=Join-Path $script:FastTestLibrary 'steamapps/common/RenamedTF/tf'
        $null=[IO.Directory]::CreateDirectory($fastGame)
        [IO.File]::WriteAllText((Join-Path $fastGame 'gameinfo.txt'),$info)
        $manifest=Join-Path $script:FastTestLibrary 'steamapps/appmanifest_440.acf'
        [IO.File]::WriteAllText($manifest,'"AppState" { "installdir" "RenamedTF" }')
        Set-Item Function:Get-SteamLibraries {return $script:FastTestLibrary}
        Set-Item Function:Find-DefaultGamePath $oldDefaultFunction
        if((Find-DefaultGamePath) -ne $fastGame){throw 'Fast default lookup must use appmanifest_440.acf'}
        [IO.File]::WriteAllText($manifest,'"AppState" { "installdir" "Missing" }')
        $fallbackGame=Join-Path $script:FastTestLibrary 'steamapps/common/Team Fortress 2/tf'
        $null=[IO.Directory]::CreateDirectory($fallbackGame)
        [IO.File]::WriteAllText((Join-Path $fallbackGame 'gameinfo.txt'),$info)
        if((Find-DefaultGamePath) -ne $fallbackGame){throw 'Fast default lookup must support the traditional TF2 directory'}
        $script:FastTestLibrary=Join-Path $testRoot 'empty-library'
        if(Find-DefaultGamePath){throw 'Missing default game must allow discovery fallback'}
        Set-Item Function:Get-SteamLibraries $oldLibraryFunction
        Set-Item Function:Find-SourceGames $oldFindFunction
        $scheme='"Scheme" { "Fonts" { "Text" { "1" { "name" "Verdana" "tall" "13" } } } }'
        [IO.File]::WriteAllText((Join-Path $game 'custom/B-hud/resource/ClientScheme.res'),$scheme)
        [IO.File]::WriteAllText((Join-Path $game 'custom/Z-hud/resource/ClientScheme.res'),$scheme.Replace('13','99'))
        [IO.File]::WriteAllText((Join-Path $game 'resource/ui/ConsoleScheme.res'),$scheme)
        if((Resolve-GamePath $game) -ne $game -or (Resolve-GamePath (Join-Path $second 'gameinfo.txt')) -ne $second){throw 'Generic game path resolution failed'}
        $ambiguous=$false;try{$null=Resolve-GamePath $testRoot}catch{$ambiguous=$true};if(-not $ambiguous){throw 'Ambiguous game folder must require selection'}
        $sources=@(Get-SearchSources $game '!fonts');$winner=Read-VirtualFile $sources 'resource/ClientScheme.res'
        if($winner.Source -notlike '*B-hud*'){throw 'Gameinfo/custom first-hit ordering failed'}
        $resolved=Get-ResolvedSchemes $game '!fonts'
        if($resolved.Documents.Count -ne 2 -or -not (@($resolved.Documents.VirtualPath) -contains 'resource/ui/ConsoleScheme.res')){throw 'Nested scheme discovery failed'}
        $output=Join-Path $game 'custom/!fonts';$fonts=Get-GeneratedFontDirectory $output
        $null=[IO.Directory]::CreateDirectory($fonts);[IO.File]::WriteAllText((Join-Path $fonts 'stale.ttf'),'old generated asset')
        $result=Invoke-FontBuild $game '!fonts' (ConvertTo-ReplacementMap @('Verdana=Tahoma')) $null
        if(Test-Path -LiteralPath (Join-Path $fonts 'stale.ttf')){throw 'Stale generated font was not cleaned'}
        if(-not (Test-Path -LiteralPath (Join-Path $output 'resource/ui/ConsoleScheme.res'))){throw 'Nested scheme output failed'}
        if(-not @(Get-ChildItem -LiteralPath (Join-Path $testRoot 'settings/backups') -Filter '*.tar.zst').Count){throw 'Compressed font backup is missing'}
        $result=Invoke-FontBuild $game '!fonts' (ConvertTo-ReplacementMap @()) $null
        $originalHash=Get-ContentSha256 ([IO.File]::ReadAllBytes((Get-FontFile 'Verdana')))
        $remaining=@(Get-ChildItem -LiteralPath $fonts -File)
        if($remaining.Count -ne 1 -or $remaining[0].BaseName -cne $originalHash){throw 'Only the effective original portable font should remain after clearing the replacement'}
        $null=[IO.Directory]::CreateDirectory($fonts);[IO.File]::WriteAllText((Join-Path $fonts 'rollback.ttf'),'preserve on failure')
        Set-Item Function:Copy-Item {throw 'Injected copy failure'}
        $failed=$false;try{$null=Invoke-FontBuild $game '!fonts' (ConvertTo-ReplacementMap @('Verdana=Tahoma')) $null}catch{$failed=$true}finally{Remove-Item Function:Copy-Item}
        if(-not $failed -or -not (Test-Path -LiteralPath (Join-Path $fonts 'rollback.ttf'))){throw 'Font cleanup rollback failed'}
        # Worker functions must carry a literal test root, not this test's scope.
        $settingsRoot=Join-Path $testRoot 'settings'
        Set-Item Function:Get-SettingsRoot ([scriptblock]::Create("return '"+$settingsRoot.Replace("'","''")+"'"))
        $workerState=@{Pipeline=$null;Handle=$null;Work=$null;Task=''}
        $profile=@{Version=2;Nodes=@{'group|Verdana'=@{Font='Tahoma';Factor=1.2}}}
        try{
            Start-GuiTask $workerState 'Save' $game @{} @{} $profile
            $savedResults=$workerState.Pipeline.EndInvoke($workerState.Handle)
            if($workerState.Pipeline.Streams.Error.Count){throw $workerState.Pipeline.Streams.Error[0]}
            if(-not $savedResults[$savedResults.Count-1].Saved -or $workerState.Work.CanCancel){throw 'Background save result/commit state failed'}
            $saved=ConvertTo-PlainValue (Read-FontProfile $game)
            if($saved.Nodes['group|Verdana'].Factor -ne 1.2){throw 'Background save profile round-trip failed'}
            if(@(Get-ChildItem -LiteralPath $settingsRoot -Filter '.settings-*.tmp').Count){throw 'Atomic settings save left temporary files'}
        }finally{if($workerState.Pipeline){$workerState.Pipeline.Dispose()}}
        $exportFile=Join-Path $testRoot 'export.json'
        foreach($task in @('Export','Import')){
            $workerState=@{Pipeline=$null;Handle=$null;Work=$null;Task=''}
            try{
                Start-GuiTask $workerState $task $exportFile @{} @{} $profile
                $results=$workerState.Pipeline.EndInvoke($workerState.Handle)
                if($workerState.Pipeline.Streams.Error.Count){throw $workerState.Pipeline.Streams.Error[0]}
                $result=$results[$results.Count-1]
                if($task -eq 'Export' -and (-not $result.Exported -or -not [IO.File]::Exists($exportFile))){throw 'Background export failed'}
                if($task -eq 'Import' -and $result.Settings['group|Verdana'].Font -ne 'Tahoma'){throw 'Background import failed'}
            }finally{if($workerState.Pipeline){$workerState.Pipeline.Dispose()}}
        }
        # Independent ASTs and deterministic merge/output order must survive
        # pooling. File bytes stay in a source snapshot; ASTs also have a disk cache.
        foreach($name in @('OneScheme.res','TwoScheme.res','ThreeScheme.res','FourScheme.res')){
            [IO.File]::WriteAllText((Join-Path $game ('resource/ui/'+$name)),('#base "../ui/ConsoleScheme.res"'+[Environment]::NewLine+'"Scheme" { "Colors" { "Accent" "1 2 3 255" } }'))
        }
        $parallel=Get-ResolvedSchemes $game '!fonts';$serial=Get-ResolvedSchemes $game '!fonts' -Sequential
        if($parallel.Documents.Count -ne $serial.Documents.Count){throw 'Parallel Scheme document count differs'}
        for($i=0;$i -lt $serial.Documents.Count;$i++){
            if((ConvertTo-KeyValuesText $parallel.Documents[$i] @{}) -cne (ConvertTo-KeyValuesText $serial.Documents[$i] @{})){throw 'Parallel Scheme order/base merge differs from sequential'}
        }
        $reused=Get-ResolvedSchemes $game '!fonts'
        if($reused.CacheHits -ne 6 -or $reused.CacheMisses -ne 0){throw 'Unchanged Scheme files must reuse persistent SHA256 cache'}
        for($i=0;$i -lt $serial.Documents.Count;$i++){
            if((ConvertTo-KeyValuesText $reused.Documents[$i] @{}) -cne (ConvertTo-KeyValuesText $serial.Documents[$i] @{})){throw 'Persistent cache changed resolved Scheme/source metadata'}
        }
        $parallelRecords=@(Get-FontRecords $parallel.Documents.ToArray())
        $parallelRecords[0].Node.Value='modified AST only'
        if(@($parallelRecords | Where-Object {$_.Node.Value -eq 'modified AST only'}).Count -ne 1){throw 'Parallel Scheme ASTs must not share mutable nodes'}
        $snapshot=@(Get-SearchSources $game '!fonts')
        $cached=Read-VirtualFile $snapshot 'resource/ui/ConsoleScheme.res'
        [IO.File]::WriteAllText((Join-Path $game 'resource/ui/ConsoleScheme.res'),$scheme.Replace('13','42'))
        if((Read-VirtualFile $snapshot 'resource/ui/ConsoleScheme.res').Text -cne $cached.Text){throw 'File cache snapshot changed while resolving dependencies'}
        $fresh=@(Get-SearchSources $game '!fonts')
        if((Read-VirtualFile $fresh 'resource/ui/ConsoleScheme.res').Text -ceq $cached.Text){throw 'New scan must invalidate old file contents'}
        $changedCache=Get-ResolvedSchemes $game '!fonts'
        if($changedCache.CacheHits -ne 1 -or $changedCache.CacheMisses -ne 5){throw 'Changed dependency must invalidate its roots but preserve unrelated cache entries'}
        $onePath=Join-Path $game 'resource/ui/OneScheme.res'
        [IO.File]::WriteAllText($onePath,('#base "MissingOptional.res"'+[Environment]::NewLine+$scheme))
        $null=Get-ResolvedSchemes $game '!fonts'
        $unchangedMissing=Get-ResolvedSchemes $game '!fonts'
        if($unchangedMissing.CacheHits -ne 6){throw 'Absent optional dependency must be fingerprinted'}
        [IO.File]::WriteAllText((Join-Path $game 'resource/ui/MissingOptional.res'),'"Scheme" { "Colors" { "AddedLater" "1 2 3 255" } }')
        $newDependency=Get-ResolvedSchemes $game '!fonts'
        if($newDependency.CacheHits -ne 5 -or $newDependency.CacheMisses -ne 1){throw 'Newly added optional dependency must invalidate the affected cache entry'}
        $cacheDirectory=Get-ScanCacheDirectory $game '!fonts'
        $cacheIndex=ConvertTo-PlainValue ([IO.File]::ReadAllText((Join-Path $cacheDirectory 'index.json'))|ConvertFrom-Json)
        $damagedAst=Join-Path $cacheDirectory ($cacheIndex.Documents['resource/ui/OneScheme.res'].AstHash+'.json')
        [IO.File]::WriteAllText($damagedAst,'damaged test cache')
        $repaired=Get-ResolvedSchemes $game '!fonts'
        if($repaired.CacheHits -ne 5 -or $repaired.CacheMisses -ne 1){throw 'Damaged cached AST must be rebuilt'}
        if((Get-ResolvedSchemes $game '!fonts').CacheHits -ne 6){throw 'Repaired cached AST must be reusable'}
        Set-Item Function:Find-SourceGames {throw 'Unexpected full discovery for an explicit game path'}
        Set-Item Function:Find-DefaultGamePath {throw 'Unexpected default lookup for an explicit game path'}
        $workerState=@{Pipeline=$null;Handle=$null;Work=$null;Task=''}
        try{
            Start-GuiTask $workerState 'Scan' $game @{} @{}
            $results=$workerState.Pipeline.EndInvoke($workerState.Handle)
            if($workerState.Pipeline.Streams.Error.Count){throw $workerState.Pipeline.Streams.Error[0]}
            if($results[$results.Count-1].Game -ne $game){throw 'Explicit scan must use the selected game directly'}
            $scanSnapshot=$results[$results.Count-1].ScanSnapshot
        }finally{if($workerState.Pipeline){$workerState.Pipeline.Dispose()}}
        $baseline=ConvertTo-KeyValuesText $scanSnapshot.Resolved.Documents[0] @{}
        $resolveFunction=(Get-Command Get-ResolvedSchemes).ScriptBlock
        try{
            Set-Item Function:Get-ResolvedSchemes {throw 'Cached Apply must not rescan'}
            $first=Invoke-FontBuild $game $scanSnapshot.Mod (ConvertTo-ReplacementMap @()) $null -WhatIf -FactorMap @{Verdana=1.2} -ScanSnapshot $scanSnapshot
            $second=Invoke-FontBuild $game $scanSnapshot.Mod (ConvertTo-ReplacementMap @()) $null -WhatIf -FactorMap @{Verdana=1.2} -ScanSnapshot $scanSnapshot
            if((ConvertTo-KeyValuesText $first.Documents[0] @{}) -cne (ConvertTo-KeyValuesText $second.Documents[0] @{})){throw 'Repeated cached Apply must not compound factors'}
            if((ConvertTo-KeyValuesText $scanSnapshot.Resolved.Documents[0] @{}) -cne $baseline){throw 'Cached Apply must preserve the scan baseline'}
            $workerState=@{Pipeline=$null;Handle=$null;Work=$null;Task='';ScanSnapshot=$scanSnapshot}
            try{
                Start-GuiTask $workerState 'Build' $game @{} @{} @{Version=2;Nodes=@{'group|Verdana'=@{Factor=1.2}}}
                $buildResults=$workerState.Pipeline.EndInvoke($workerState.Handle)
                if($workerState.Pipeline.Streams.Error.Count){throw $workerState.Pipeline.Streams.Error[0]}
                if($buildResults[$buildResults.Count-1].Total -ne $first.Total){throw 'Background cached Apply changed the input definition count'}
                if((ConvertTo-KeyValuesText $scanSnapshot.Resolved.Documents[0] @{}) -cne $baseline){throw 'Background cached Apply changed the shared baseline'}
            }finally{if($workerState.Pipeline){$workerState.Pipeline.Dispose()}}
        }finally{Set-Item Function:Get-ResolvedSchemes $resolveFunction}
        'Source game tests passed: parallel/serial equivalence, SHA256 cache reuse/dependency invalidation, cached Apply without cumulative scaling, font rollback and background tasks.'
    }finally{
        Set-Item Function:Get-SettingsRoot $oldSettingsFunction
        Set-Item Function:Find-SourceGames $oldFindFunction
        Set-Item Function:Get-SteamRoots $oldSteamFunction
        Set-Item Function:Find-DefaultGamePath $oldDefaultFunction
        Set-Item Function:Get-SteamLibraries $oldLibraryFunction
        $resolvedTestRoot=[IO.Path]::GetFullPath($testRoot)
        if(-not $resolvedTestRoot.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolvedTestRoot -Leaf) -notlike 'VGUIFontChanger-games-test-*'){throw 'Unsafe test cleanup path'}
        if(Test-Path -LiteralPath $resolvedTestRoot){Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force}
    }
}
