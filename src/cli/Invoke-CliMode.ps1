function Invoke-CliMode {
    $script:LogPath=New-OperationLog 'CLI' $GamePath
    try{
    $resolvedPath = Resolve-GamePath $GamePath
    if($Diagnose){Invoke-FontDiagnosis $resolvedPath $TestFont; return}
    if ($ListFonts) {
        $resolved = Get-ResolvedSchemes $resolvedPath $OutputModName
        $records = @(Get-FontRecords $resolved.Documents.ToArray())
        $explicitMap=ConvertTo-ReplacementMap $Replace
        Get-FontSummary $records -All:$AllAliases | Where-Object { $ShowSymbols -or $_.Kind -ne 'Symbol' -or $explicitMap.ContainsKey($_.Font) } | Format-Table Font, Sizes, Count -AutoSize
        return
    }
    $map = ConvertTo-ReplacementMap $Replace
    if (-not $DefaultFont -and $map.Count -eq 0 -and -not $DefaultSize -and -not $Size -and -not $Factor) { throw 'Specify -DefaultFont, -Replace, -DefaultSize or -Size.' }
    $sizes=ConvertTo-ReplacementMap $Size
    $factors=@{}
    foreach($pair in @($Factor)){
        if(-not $pair){continue}
        $split=$pair.IndexOf('=')
        if($split -le 0){throw 'Use -Factor Original=1.2'}
        $factors[$pair.Substring(0,$split)]=[double]::Parse($pair.Substring($split+1),[Globalization.CultureInfo]::InvariantCulture)
    }
    # Preserve child overrides when CLI edits group defaults in a v2 profile.
    $savedProfile=ConvertTo-PlainValue (Read-FontProfile $resolvedPath)
    $nodeSettings=$null; $hierarchyProfile=$null
    if($savedProfile.ContainsKey('Nodes')){
        $nodeSettings=ConvertTo-NodeSettings $savedProfile
        foreach($key in $map.Keys){
            $id='group|'+[Uri]::EscapeDataString($key)
            if(-not $nodeSettings.ContainsKey($id)){$nodeSettings[$id]=@{}}
            $nodeSettings[$id].Font=$map[$key]
        }
        foreach($key in $factors.Keys){
            $id='group|'+[Uri]::EscapeDataString($key)
            if(-not $nodeSettings.ContainsKey($id)){$nodeSettings[$id]=@{}}
            $nodeSettings[$id].Factor=$factors[$key]
        }
        if($DefaultFont){
            $resolved=Get-ResolvedSchemes $resolvedPath $OutputModName
            foreach($record in @(Get-FontRecords $resolved.Documents.ToArray() | Where-Object Kind -eq 'Text')){
                if($map.ContainsKey($record.Font)){continue}
                if(-not $nodeSettings.ContainsKey($record.GroupId)){$nodeSettings[$record.GroupId]=@{}}
                $nodeSettings[$record.GroupId].Font=$DefaultFont
            }
        }
        $hierarchyProfile=$savedProfile;$hierarchyProfile.Remove('Preferences');$hierarchyProfile.Nodes=$nodeSettings
    }
    $result = Invoke-FontBuild $resolvedPath $OutputModName $map $DefaultFont -WhatIf:$DryRun -SizeMap $sizes -TextSize $DefaultSize -FactorMap $factors -NodeSettings $nodeSettings -HierarchyProfile $hierarchyProfile
    if ($DryRun) { Write-Host 'Dry run complete.' } else {
        Write-Host 'Override created.'
        if($LaunchGame){Restart-GameProcess $resolvedPath}
    }
    Write-Host "Changed: $($result.Changed) / $($result.Total) definitions"
    Write-Host "Size changes: $($result.SizeChanged)"
    Write-Host "Output:  $($result.Output)"
    }catch{Write-VfcLog 'ERROR' ($_.Exception.ToString()+[Environment]::NewLine+$_.ScriptStackTrace);throw}
    finally{Write-VfcLog 'INFO' 'CLI operation ended.'}
}
