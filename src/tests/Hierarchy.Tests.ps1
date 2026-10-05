function Invoke-HierarchySelfTest {
    $mixed=ConvertFrom-KeyValuesText '"Scheme" { "Fonts" { "Chat" { "1" { "name" "tf2secondary_fix" "tall" "12" } } "ButtonText" { "1" { "name" "tf2secondary_fix" "tall" "12" } } "Icon" { "1" { "name" "Marlett" "tall" "12" } } } }' 'mixed-family-fixture'
    $mixed | Add-Member NoteProperty VirtualPath 'resource/ClientScheme.res'
    $mixedSummary=@(Get-FontSummary @(Get-FontRecords @($mixed)))
    $mixedModel=New-FontHierarchy $mixedSummary @{}
    $mixedVisible=@(Get-VisibleFontNodes $mixedModel)
    if($mixedVisible -notcontains 'group|tf2secondary_fix' -or $mixedVisible -contains 'group|Marlett'){throw 'Mixed text/button family must be visible while symbol-only families remain hidden'}
    $clientDoc=ConvertFrom-KeyValuesText '"Scheme" { "Fonts" { "Default" { "1" { "name" "Tahoma" "tall" "12" } } } }' 'dedupe-client'
    $clientDoc | Add-Member NoteProperty VirtualPath 'resource/ClientScheme.res'
    $sourceDoc=ConvertFrom-KeyValuesText '"Scheme" { "Fonts" { "Default" { "1" { "name" "Verdana" "tall" "10" } } "EngineOnly" { "1" { "name" "Wingdings" "tall" "10" } } "ConsoleText" { "1" { "name" "Courier New" "tall" "10" } } } }' 'dedupe-source'
    $sourceDoc | Add-Member NoteProperty VirtualPath 'resource/SourceScheme.res'
    $dedicatedDoc=ConvertFrom-KeyValuesText '"Scheme" { "Fonts" { "ConsoleText" { "1" { "name" "Lucida Console" "tall" "10" } } } }' 'dedupe-dedicated'
    $dedicatedDoc | Add-Member NoteProperty VirtualPath 'resource/itemtest_scheme.res'
    $dedupeSummary=@(Get-FontSummary @(Get-FontRecords @($clientDoc,$sourceDoc,$dedicatedDoc)))
    if(@($dedupeSummary | Where-Object Font -eq 'Verdana').Count -ne 0){throw 'ClientScheme definition must shadow the engine default scheme definition'}
    if(@($dedupeSummary | Where-Object Font -eq 'Lucida Console').Count -ne 0){throw 'The engine default scheme definition must shadow niche dedicated scheme definitions'}
    if(@($dedupeSummary | Where-Object Font -eq 'Wingdings').Count -ne 1){throw 'Engine default scheme aliases must remain visible when unique'}
    $clientAlias=@($dedupeSummary | Where-Object Font -eq 'Tahoma')
    if($clientAlias.Count -ne 1 -or @($clientAlias[0].Locations).Count -ne 1){throw 'Effective alias selection failed'}
    $allSummary=@(Get-FontSummary @(Get-FontRecords @($clientDoc,$sourceDoc,$dedicatedDoc)) -All)
    if(@($allSummary | Where-Object Font -eq 'Verdana').Count -ne 1 -or @($allSummary | Where-Object Font -eq 'Lucida Console').Count -ne 1){throw 'Summary -All must list every definition'}
    $fixture=ConvertFrom-KeyValuesText '"Scheme" { "Fonts" { "Chat" { "1" { "name" "Verdana" [!$OSX] "tall" "10" "yres" "720 1080" } "2" { "name" "Verdana" "tall" "20" "yres" "1081 2160" } } "Console" { "1" { "name" "Verdana" "tall" "12" } } } }' 'hierarchy-fixture'
    $fixture | Add-Member NoteProperty VirtualPath 'resource/ClientScheme.res'
    $fixture | Add-Member NoteProperty Entry 'hierarchy-fixture'
    $fixture | Add-Member NoteProperty Dependencies @('hierarchy-fixture')
    $records=@(Get-FontRecords @($fixture));$summary=@(Get-FontSummary $records)
    $model=New-FontHierarchy $summary @{Fonts=@{Verdana='Tahoma'};Factors=@{Verdana=1.2}} 'en-US' 'System'
    $root=$model.Nodes[$model.Roots[0]]
    $chat=$model.Nodes[($records | Where-Object Alias -eq 'Chat' | Select-Object -First 1).AliasId]
    $leaf=$model.Nodes[$chat.Children[0]]
    $console=$model.Nodes[($records | Where-Object Alias -eq 'Console').AliasId]
    if((Get-NodeValue $model $leaf.Id 'Font') -ne 'Tahoma' -or (Get-NodeValue $model $leaf.Id 'Factor') -ne 1.2){throw 'Hierarchy legacy migration failed'}
    if($records[0].Condition -notmatch 'yres' -or $records[0].Condition -notmatch 'OSX'){throw 'Conditional variant metadata failed'}
    $before=Get-ModelSnapshot $model
    Set-NodeValue $model $chat.Id 'Font' 'Arial';Set-NodeValue $model $leaf.Id 'Font' 'Verdana';Set-NodeValue $model $leaf.Id 'Factor' 1.5
    $null=Complete-ModelChange $model $before
    $before=Get-ModelSnapshot $model
    Set-NodeValue $model $root.Id 'Factor' 2.0;$model.Preferences.Theme='AMOLED';$model.Preferences.Locale='ko-KR'
    $null=Complete-ModelChange $model $before
    if((Get-NodeValue $model $leaf.Id 'Font') -ne 'Verdana' -or (Get-NodeValue $model $leaf.Id 'Factor') -ne 1.5 -or (Get-NodeValue $model $console.Id 'Factor') -ne 2.0){throw 'Independent field inheritance failed'}
    if(-not (Invoke-ModelHistory $model 'Undo') -or $model.Preferences.Theme -ne 'System' -or (Get-NodeValue $model $console.Id 'Factor') -ne 1.2){throw 'Hierarchy undo failed'}
    if(-not (Invoke-ModelHistory $model 'Redo') -or $model.Preferences.Locale -ne 'ko-KR'){throw 'Hierarchy redo failed'}
    $profile=Get-HierarchyProfile $model;$settings=ConvertTo-NodeSettings (($profile|ConvertTo-Json -Depth 12)|ConvertFrom-Json)
    if($settings[$leaf.Id].Font -ne 'Verdana' -or $settings[$leaf.Id].Factor -ne 1.5){throw 'Nested profile round-trip failed'}
    foreach($badProfile in @(@{Version=99;Nodes=@{}},@{Nodes=@{'group|Verdana'=@{Factor=[double]::NaN}}},@{Nodes=@{'group|Verdana'=@{Factor=5}}},@{Nodes=@{'group|Verdana'=@{Size=20}}},@{Nodes=@{($leaf.Id)=@{Size=513}}},@{Nodes=@{($leaf.Id)=@{Size=1.5}}})){
        $rejected=$false;try{$null=ConvertTo-NodeSettings $badProfile}catch{$rejected=$true};if(-not $rejected){throw 'Malformed profile validation failed'}
    }
    $oldFunction=(Get-Command Get-ResolvedSchemes).ScriptBlock;$script:HierarchyFixture=$fixture
    $fixtureText=ConvertTo-KeyValuesText $fixture @{}
    try{
        Set-Item Function:Get-ResolvedSchemes {param($game,$mod);$list=New-ObjectList;$list.Add($script:HierarchyFixture);[pscustomobject]@{Documents=$list;Sources=@()}}
        $r=Invoke-FontBuild '.' '!fonts' (ConvertTo-ReplacementMap @()) $null -WhatIf -NodeSettings $settings
        foreach($record in $r.Records){
            if($record.Id -eq $leaf.Id){if($record.Node.Value -ne 'Verdana' -or $record.Tall -ne '15'){throw 'Leaf compilation failed'}}
            elseif($record.Alias -eq 'Chat'){if($record.Node.Value -ne 'Arial' -or $record.Tall -ne '40'){throw 'Alias compilation failed'}}
            elseif($record.Node.Value -ne 'Tahoma' -or $record.Tall -ne '24'){throw 'Group compilation failed'}
        }
        Set-NodeValue $model $leaf.Id 'Size' 27
        $before=Get-ModelSnapshot $model;Set-NodeValue $model $root.Id 'Factor' 3.0;$null=Complete-ModelChange $model $before
        if((Get-NodeValue $model $leaf.Id 'Size') -ne 27 -or $model.Settings[$leaf.Id].ContainsKey('Factor')){throw 'Absolute size must stay fixed on parent factor changes'}
        $script:HierarchyFixture=ConvertFrom-KeyValuesText $fixtureText 'hierarchy-fixture'
        $script:HierarchyFixture|Add-Member NoteProperty VirtualPath 'resource/ClientScheme.res'
        $script:HierarchyFixture|Add-Member NoteProperty Entry 'hierarchy-fixture'
        $script:HierarchyFixture|Add-Member NoteProperty Dependencies @('hierarchy-fixture')
        $low=Find-KvChild (Find-KvChild (Find-KvChild (Find-KvRoot $script:HierarchyFixture 'Scheme') 'Fonts') 'Chat') '1'
        $low.Children.Add((New-KvNode 'tall_lodef' $true '12' @() 'hierarchy-fixture' 1))
        $sizeSettings=ConvertTo-NodeSettings (Get-HierarchyProfile $model)
        $r=Invoke-FontBuild '.' '!fonts' (ConvertTo-ReplacementMap @()) $null -WhatIf -NodeSettings $sizeSettings
        $sizeRecord=$r.Records|Where-Object Id -eq $leaf.Id|Select-Object -First 1
        if($sizeRecord.Tall -ne '27' -or (Find-KvChild $sizeRecord.VariantNode 'tall_lodef').Value -ne '32'){throw 'Absolute size compiler and resolution-specific size test failed'}
    }finally{Set-Item Function:Get-ResolvedSchemes $oldFunction}
    $model.Settings[$leaf.Id].Remove('Font')
    if((Get-NodeValue $model $leaf.Id 'Font') -ne 'Arial'){throw 'Reset-to-inherited failed'}
    $before=Get-ModelSnapshot $model;$model.Settings=@{};$null=Complete-ModelChange $model $before
    if($model.Redo.Count -ne 0 -or -not (Invoke-ModelHistory $model 'Undo')){throw 'Import/reset history failed'}
    'Hierarchy settings migration, independent overrides, reset, conditional variants, validation and compiler tests passed.'
}
