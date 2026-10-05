function Invoke-PortableSelfTest {
    $root=Join-Path ([IO.Path]::GetTempPath()) ('VGUIFontChanger-portable-test-'+[Guid]::NewGuid().ToString('N'))
    $oldRoot=(Get-Command Get-SettingsRoot).ScriptBlock;$oldFile=(Get-Command Get-FontFile).ScriptBlock
    $script:PortableTestFontPath=Get-FontFile 'Tahoma'
    try{
        $game=Join-Path $root 'tf';$settings=Join-Path $root 'settings'
        $null=[IO.Directory]::CreateDirectory((Join-Path $game 'resource'))
        Set-Item Function:Get-SettingsRoot ([scriptblock]::Create("return '"+$settings.Replace("'","''")+"'"))
        Set-Item Function:Get-FontFile {param($Name);if($Name -eq '__missing_font__'){return $null};return $script:PortableTestFontPath}
        $script:FontAssetCache=@{}
        $document=ConvertFrom-KeyValuesText '"Scheme" { "Fonts" { "A" { "1" { "name" "Family A" "tall" "12" } } "B" { "1" { "name" "Family B" "tall" "12" } } } "CustomFontFiles" { "Old" { "name" "Family A" "font" "old.ttf" "english" { "range" "0x0000 0x00FF" } } } }' 'portable-fixture'
        $document | Add-Member NoteProperty VirtualPath 'resource/ClientScheme.res'
        $assets=@{}
        Add-SchemeFontRegistration @($document) $document.VirtualPath 'Family A' $assets -Required
        Add-SchemeFontRegistration @($document) $document.VirtualPath 'Family B' $assets -Required
        $custom=Find-KvChild (Find-KvRoot $document 'Scheme') 'CustomFontFiles'
        if($custom.Children.Count -ne 2 -or $assets.Count -ne 1){throw 'Shared TTC/file families require separate registrations and one copied asset'}
        Test-GeneratedFontRanges $document $script:FontAssetCache
        $failed=$false;try{Add-SchemeFontRegistration @($document) $document.VirtualPath '__missing_font__' $assets -Required}catch{$failed=$true}
        if(-not $failed){throw 'An unresolved selected font must stop Apply'}
        Set-Item Function:Get-FontFile $oldFile
        [IO.File]::WriteAllText((Join-Path $game 'gameinfo.txt'),'"GameInfo" { "game" "Fixture" "FileSystem" { "SearchPaths" { "game+vgui" "|gameinfo_path|custom/*" "game" "|gameinfo_path|." } } }')
        [IO.File]::WriteAllText((Join-Path $game 'resource/ClientScheme.res'),'"Scheme" { "Fonts" { "Chat" { "1" { "name" "Tahoma" "tall" "12" "custom" "1" } } } }')
        $result=Invoke-FontBuild $game '!VGUIFontChanger' (ConvertTo-ReplacementMap @('Tahoma=Tahoma')) $null
        $generated=Join-Path $game 'custom/!VGUIFontChanger'
        if(-not [IO.File]::Exists((Join-Path $generated 'VGUIFontChanger-info.json'))){throw 'Portable output ownership/information manifest is missing'}
        $copied=@(Get-ChildItem -LiteralPath (Join-Path $generated 'resource/fonts/vguifontchanger') -File)
        if($copied.Count -ne 1 -or $copied[0].BaseName -notmatch '^[A-F0-9]{64}$'){throw 'Selecting the original family must still copy its full SHA256-named font file'}
        $node=($result.Records|Select-Object -First 1).VariantNode
        if((Find-KvChild $node 'custom').Value -ne '0'){throw 'Explicit original-family selection must also restore Asian fallback'}
        $relocated=Join-Path $root 'relocated';Copy-Item -LiteralPath $generated -Destination $relocated -Recurse
        foreach($entry in (Find-KvChild (Find-KvRoot $result.Documents[0] 'Scheme') 'CustomFontFiles').Children){
            $font=Find-KvChild $entry 'font'
            if([IO.Path]::IsPathRooted($font.Value) -or -not [IO.File]::Exists((Join-Path $relocated $font.Value))){throw 'Relocated output must resolve all generated font paths locally'}
        }
        $removed=Remove-FontOverride $game '!VGUIFontChanger'
        if(-not $removed.Removed -or [IO.Directory]::Exists($generated) -or -not [IO.File]::Exists($removed.Backup)){throw 'Remove override must delete only the generated folder and retain a compressed recovery backup'}
        $bytes=[IO.File]::ReadAllBytes($removed.Backup)
        if([BitConverter]::ToString($bytes,0,4) -ne '28-B5-2F-FD'){throw 'Backup must have a Zstandard frame header'}
        'Portable tests passed: shared-file family ranges, required fonts, SHA256 assets, relocation, ownership manifest and compressed uninstall backup.'
    }finally{
        Set-Item Function:Get-SettingsRoot $oldRoot;Set-Item Function:Get-FontFile $oldFile
        $resolved=[IO.Path]::GetFullPath($root)
        if((Split-Path $resolved -Parent) -ine [IO.Path]::GetTempPath().TrimEnd('\','/') -or (Split-Path $resolved -Leaf) -notlike 'VGUIFontChanger-portable-test-*'){throw 'Unsafe portable test cleanup path'}
        if([IO.Directory]::Exists($resolved)){Remove-Item -LiteralPath $resolved -Recurse -Force}
    }
}
