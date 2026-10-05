function Invoke-FontBuild {
    param(
        [string]$GamePath,
        [string]$OutputModName,
        [System.Collections.Generic.IDictionary[string,string]]$ReplacementMap,
        [string]$DefaultTextFont,
        [switch]$WhatIf,
        [System.Collections.Generic.IDictionary[string,string]]$SizeMap,
        [int]$TextSize,
        [hashtable]$FactorMap,
        [hashtable]$NodeSettings,
        $HierarchyProfile,
        $ScanSnapshot
    )
    if ($OutputModName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $OutputModName -in @('.', '..')) { throw 'Invalid output mod name.' }
    if($ScanSnapshot){
        if($ScanSnapshot.Game -ine $GamePath -or $ScanSnapshot.Mod -ine $OutputModName){throw 'Scan snapshot does not match the selected game.'}
        Set-WorkStatus 'Preparing settings'
        $resolved=Copy-ResolvedSchemes $ScanSnapshot.Resolved
    }else{$resolved = Get-ResolvedSchemes $GamePath $OutputModName}
    if ($resolved.Documents.Count -eq 0) { throw 'No VGUI scheme files were found.' }
    $records = @(Get-FontRecords $resolved.Documents.ToArray())
    $changed = 0
    $sizeChanged = 0
    $assets = @{}
    $registrations=@{}
    $script:FontAssetCache = @{}
    $script:GameFontPaths = @{}
    $gameAssets=if($ScanSnapshot){$ScanSnapshot.GameFonts}else{@(Get-GameFontAssets $resolved)}
    foreach($asset in $gameAssets){
        foreach($family in $asset.Names){$script:GameFontPaths[$family]=$asset.Path}
    }
    foreach ($record in $records) {
        $initialTall=$record.Tall
        $replacement = $null
        if ($ReplacementMap -and $ReplacementMap.ContainsKey($record.Font)) { $replacement = $ReplacementMap[$record.Font] }
        elseif ($DefaultTextFont -and $record.Kind -eq 'Text') { $replacement = $DefaultTextFont }
        $factorValue=1.0; $hasFactor=$false; $nodeSize=0
        if($FactorMap -and $FactorMap.ContainsKey($record.Font)){$factorValue=[double]$FactorMap[$record.Font];$hasFactor=$true}
        foreach($settingId in @($record.GroupId,$record.AliasId,$record.Id)){
            if($NodeSettings -and $NodeSettings.ContainsKey($settingId)){
                $setting=$NodeSettings[$settingId]
                if($setting.ContainsKey('Font')){$replacement=[string]$setting.Font}
                if($setting.ContainsKey('Factor')){$factorValue=[double]$setting.Factor;$hasFactor=$true}
                if($setting.ContainsKey('Size')){$nodeSize=[int]$setting.Size}
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($replacement)) {
            # Use the English SFNT family name in engine files; localized Windows
            # aliases can resolve in GDI+ but fail the engine's narrow-string lookup.
            $record.Node.Value = Get-CanonicalFontName $replacement
            if($record.Node.Value -cne $record.Font){$changed++}
            if ($replacement) {
                # Do not force FONTFLAG_CUSTOM: disabling compatibility fallback
                # caused missing Hangul despite Windows GDI glyph success.
                $customFlag=Find-KvChild $record.GlyphSetNode 'custom'
                if($customFlag){$customFlag.Value='0'}
                else{$record.GlyphSetNode.Children.Add((New-KvNode 'custom' $true '0' @() 'generated' 0))}
                $bitmapFlag=Find-KvChild $record.GlyphSetNode 'bitmap'
                if($bitmapFlag){$bitmapFlag.Value='0'}
            }
        }
        Test-WorkCancellation
        if ($replacement) {
            $registrationKey=$record.Scheme+'|'+$record.Node.Value
            if(-not $registrations.ContainsKey($registrationKey)){
                Add-SchemeFontRegistration $resolved.Documents.ToArray() $record.Scheme $record.Node.Value $assets -Required
                $registrations[$registrationKey]=$true
            }
        }
        if($nodeSize -gt 0){
            $originalTall=Find-KvChild $record.GlyphSetNode 'tall'
            if($originalTall -and $originalTall.Value -match '^\d+$' -and [int]$originalTall.Value -gt 0){$factorValue=$nodeSize/[double]$originalTall.Value;$hasFactor=$true}
        }
        if ($hasFactor) {
            if ($nodeSize -eq 0 -and ($factorValue -lt 0.1 -or $factorValue -gt 4 -or [Math]::Abs($factorValue*10-[Math]::Round($factorValue*10)) -gt 0.0001)) { throw 'Factor must be 0.1..4.0 in steps of 0.1.' }
            foreach($property in $record.GlyphSetNode.Children) {
                if($property.Key -in @('tall','tall_lodef','tall_hidef') -and $property.Value -match '^\d+$' -and [int]$property.Value -gt 0) {
                    $property.Value=[string][Math]::Max(1,[Math]::Round([double]$property.Value*$factorValue,0,[MidpointRounding]::AwayFromZero))
                }
            }
            $bitmap=Find-KvChild $record.GlyphSetNode 'bitmap'
            if($bitmap -and $bitmap.Value -eq '1'){
                foreach($scaleKey in @('scalex','scaley')){
                    $property=Find-KvChild $record.GlyphSetNode $scaleKey
                    $originalScale=1.0; if($property){$originalScale=[double]::Parse($property.Value,[Globalization.CultureInfo]::InvariantCulture)}
                    $scaled=($originalScale*$factorValue).ToString('0.######',[Globalization.CultureInfo]::InvariantCulture)
                    if($property){$property.Value=$scaled}else{$record.GlyphSetNode.Children.Add((New-KvNode $scaleKey $true $scaled @() 'generated' 0))}
                }
            }
            $tall=Find-KvChild $record.GlyphSetNode 'tall'; if($tall){$record.Tall=$tall.Value}
            if($factorValue -ne 1){$sizeChanged++}
        }
        $newSize = 0
        if ($SizeMap -and $SizeMap.ContainsKey($record.Font)) { $newSize = [int]$SizeMap[$record.Font] }
        elseif ($TextSize -gt 0 -and $record.Kind -eq 'Text') { $newSize = $TextSize }
        if($nodeSize -gt 0){$newSize=$nodeSize}
        if ($newSize -gt 0) {
            if ($newSize -gt 512) { throw 'Font size must be 1..512 VGUI pixels.' }
            $tall = Find-KvChild $record.GlyphSetNode 'tall'
            if (-not $tall) { $tall = New-KvNode 'tall' $true ([string]$newSize) @() $record.Source $record.Line; $record.GlyphSetNode.Children.Add($tall) }
            else { $tall.Value = [string]$newSize }
            $record.Tall=[string]$newSize
            $sizeChanged++
        }
        $properties=New-StringList;foreach($property in $record.GlyphSetNode.Children){if($property.HasValue){$properties.Add($property.Key+'='+$property.Value)}}
        Write-VfcLog 'DEBUG' ('Font definition: scheme={0}; alias={1}; glyphset={2}; source={3}:{4}; original={5}; effective={6}; originalTall={7}; finalTall={8}; factor={9}; selected={10}; kind={11}; condition={12}; properties={13}' -f $record.Scheme,$record.Alias,$record.GlyphSet,$record.Source,$record.Line,$record.Font,$record.Node.Value,$initialTall,$record.Tall,$factorValue,[bool]$replacement,$record.Kind,$record.Condition,([string]::Join(';',$properties.ToArray())))
    }
    # Bundle effective original families too, without broadening their existing
    # language ranges. A portable override must not depend on local installations.
    foreach($record in $records){
        $key=$record.Scheme+'|'+$record.Node.Value
        if(-not $registrations.ContainsKey($key)){
            Add-SchemeFontRegistration $resolved.Documents.ToArray() $record.Scheme $record.Node.Value $assets -PreserveRanges
            $registrations[$key]=$true
        }
    }
    ConvertTo-PortableGameFonts $resolved.Documents.ToArray() $gameAssets $assets

    if($OutputModName -match '[\\/]' -or $OutputModName -in @('.','..') -or [string]::IsNullOrWhiteSpace($OutputModName)){throw 'OutputModName must be a single custom directory name.'}
    $gameDirectory=$GamePath;if($resolved.PSObject.Properties['GameDirectory']){$gameDirectory=$resolved.GameDirectory}
    $outputRoot = Join-Path (Join-Path $gameDirectory 'custom') $OutputModName
    $resourceRoot = Join-Path $outputRoot 'resource'
    $backendDocument=New-FontBackendDocument $resolved.Sources $script:FontAssetCache -RestoreBaseline:(Test-Path -LiteralPath (Join-Path $resourceRoot 'FontInfo.kv'))
    if($backendDocument){$resolved.Documents.Add($backendDocument)}
    if (-not $WhatIf) {
        $payloads=@{}
        foreach($document in $resolved.Documents){
            Set-WorkStatus ('Verifying '+$document.VirtualPath)
            $text=ConvertTo-KeyValuesText $document @{Generated=[DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss zzz')}
            $check=ConvertFrom-KeyValuesText $text 'generated'
            $check | Add-Member NoteProperty VirtualPath $document.VirtualPath
            $expected=@(Get-FontRecords @($document)); $actual=@(Get-FontRecords @($check))
            Test-GeneratedFontRanges $check $script:FontAssetCache
            if($expected.Count -ne $actual.Count){throw 'Generated scheme validation failed.'}
            for($i=0;$i -lt $actual.Count;$i++){if($actual[$i].Font -cne $expected[$i].Node.Value -or $actual[$i].Tall -ne $expected[$i].Tall){throw 'Generated font/size validation failed.'}}
            if($document.VirtualPath -eq 'resource/FontInfo.kv'){
                $expectedRoot=Find-KvRoot $document 'FontInfo'; $actualRoot=Find-KvRoot $check 'FontInfo'
                foreach($setting in $expectedRoot.Children){
                    $actualSetting=Find-KvChild $actualRoot $setting.Key
                    if(-not $actualSetting -or $actualSetting.Value -cne $setting.Value){throw 'Generated font backend validation failed.'}
                }
            }
            if($document.VirtualPath -notlike 'resource/*' -or $document.VirtualPath -match '(^|/)\.\.(/|$)'){throw 'Unsafe generated scheme path.'}
            $payloads[$document.VirtualPath.Substring(9)]=$text
        }
        Test-WorkCancellation
        # The short file-commit section cannot be interrupted. Cancellation before it writes nothing.
        if($script:Work){$script:Work.CanCancel=$false}
        Set-WorkStatus 'Saving verified schemes'
        $backupArchive=New-OutputBackup $outputRoot $gameDirectory
        $null=[IO.Directory]::CreateDirectory($resourceRoot)
        $backupRoot=Join-Path ([IO.Path]::GetTempPath()) ('VGUIFontChanger-commit-'+[guid]::NewGuid().ToString('N'))
        $prior=@{}
        foreach($name in $payloads.Keys){
            $target=Join-Path $resourceRoot $name
            $prior[$name]=$null
            if(Test-Path -LiteralPath $target){
                $prior[$name]=[IO.File]::ReadAllBytes($target)
                $null=[IO.Directory]::CreateDirectory($backupRoot)
                $null=[IO.Directory]::CreateDirectory((Split-Path (Join-Path $backupRoot $name) -Parent))
                [IO.File]::WriteAllBytes((Join-Path $backupRoot $name),$prior[$name])
            }
        }
        $fontDirectory=Get-GeneratedFontDirectory $outputRoot
        $fontBackup=Join-Path $backupRoot 'fonts/vguifontchanger';$fontsMoved=$false
        try{
            if(Test-Path -LiteralPath $fontDirectory){
                $null=[IO.Directory]::CreateDirectory((Split-Path $fontBackup -Parent))
                Move-Item -LiteralPath $fontDirectory -Destination $fontBackup;$fontsMoved=$true
            }
            foreach($virtual in $assets.Keys){
                if($virtual -notlike 'resource/fonts/vguifontchanger/*' -or $virtual -match '(^|/)\.\.(/|$)'){throw 'Unsafe generated font asset path.'}
                $target=Join-Path $outputRoot $virtual
                $null=[IO.Directory]::CreateDirectory((Split-Path $target -Parent))
                if(-not (Test-Path -LiteralPath $target)){Copy-Item -LiteralPath $assets[$virtual] -Destination $target}
                $copiedHash=Get-ContentSha256 ([IO.File]::ReadAllBytes($target))
                if($copiedHash -cne [IO.Path]::GetFileNameWithoutExtension($target)){throw "Copied font hash verification failed: $target"}
                Write-VfcLog 'DEBUG' "Font copied and verified: source=$($assets[$virtual]); target=$target; sha256=$copiedHash"
            }
            foreach($name in $payloads.Keys){$target=Join-Path $resourceRoot $name;$null=[IO.Directory]::CreateDirectory((Split-Path $target -Parent));[IO.File]::WriteAllText($target,$payloads[$name],(New-Object Text.UTF8Encoding($false)));Write-VfcLog 'DEBUG' "Scheme written: file=$target; sha256=$(Get-ContentSha256 ([IO.File]::ReadAllBytes($target)))"}
        } catch {
            # Only the exact validated generated folder is removed on rollback;
            # original font files were moved to the recovery backup, not deleted.
            if(Test-Path -LiteralPath $fontDirectory){$null=Get-GeneratedFontDirectory $outputRoot;Remove-Item -LiteralPath $fontDirectory -Recurse -Force}
            if($fontsMoved){Move-Item -LiteralPath $fontBackup -Destination $fontDirectory}
            foreach($name in $prior.Keys){
                $target=Join-Path $resourceRoot $name
                if($null -ne $prior[$name]){[IO.File]::WriteAllBytes($target,$prior[$name])}
                elseif(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target -Force}
            }
            Write-VfcLog 'ERROR' ('Commit failed; rollback completed. '+$_.Exception.ToString())
            Remove-CommitStage $backupRoot
            throw
        }
        $profile=@{Fonts=@{};Factors=@{}}
        foreach($record in $records){if($record.Node.Value -cne $record.Font){$profile.Fonts[$record.Font]=$record.Node.Value}}
        if($ReplacementMap){foreach($key in $ReplacementMap.Keys){$profile.Fonts[$key]=$ReplacementMap[$key]}}
        if($FactorMap){$profile.Factors=$FactorMap}
        if($HierarchyProfile){$profile=$HierarchyProfile}
        Save-FontProfile $GamePath $profile
        $changes=@($records | Where-Object {$_.Node.Value -cne $_.Font} | ForEach-Object {[pscustomobject]@{Scheme=$_.Scheme;Alias=$_.Alias;GlyphSet=$_.GlyphSet;Original=$_.Font;Replacement=$_.Node.Value;Size=$_.Tall}})
        $info=@{Application='VGUIFontChanger';Version=1;AppliedAt=[DateTimeOffset]::Now.ToString('o');GameCode=[IO.Path]::GetFileName($gameDirectory);Changes=$changes;Assets=@($assets.Keys);SchemeFiles=@($payloads.Keys);Uninstall="Exit the game, then delete custom/$OutputModName (or use File > Remove override).";Backup=$backupArchive}
        Write-SettingsFile (Join-Path $outputRoot 'VGUIFontChanger-info.json') $info
        [IO.File]::WriteAllText((Join-Path $outputRoot 'README.txt'),("VGUIFontChanger portable font override"+[Environment]::NewLine+"Applied: "+$info.AppliedAt+[Environment]::NewLine+"Copy this whole folder to the same game's custom folder on another Windows PC."+[Environment]::NewLine+$info.Uninstall+[Environment]::NewLine+"See VGUIFontChanger-info.json for changes and asset hashes."),(New-Object Text.UTF8Encoding($false)))
        if($OutputModName -ieq '!VGUIFontChanger'){Disable-LegacyFontOverride $gameDirectory}
        Remove-CommitStage $backupRoot
        Write-VfcLog 'INFO' "Apply completed: schemes=$($payloads.Count); assets=$($assets.Count); changedFonts=$changed; changedSizes=$sizeChanged; output=$outputRoot"
    }
    return [pscustomobject]@{ Changed=$changed; SizeChanged=$sizeChanged; Total=$records.Count;FileCount=($resolved.Documents.Count+$assets.Count+2); Output=$resourceRoot; Documents=$resolved.Documents; Records=$records }
}
function Test-GeneratedFontRanges {
    param($Document,[hashtable]$FontAssets)
    $scheme=Find-KvRoot $Document 'Scheme';if(-not $scheme){return}
    $custom=Find-KvChild $scheme 'CustomFontFiles'
    $verified=@{}
    foreach($record in @(Get-FontRecords @($Document))){
        if(-not $FontAssets.ContainsKey($record.Font) -or -not $FontAssets[$record.Font] -or -not $FontAssets[$record.Font].RangeSchemes.ContainsKey($Document.VirtualPath)){continue}
        if($verified.ContainsKey($record.Font)){continue}
        $matched=$false
        if($custom){foreach($entry in $custom.Children){
            if($entry.HasValue){continue}
            $name=Find-KvChild $entry 'name';if(-not $name -or $name.Value -ine $record.Font){continue}
            $font=Find-KvChild $entry 'font';if(-not $font -or $font.Value -cne $FontAssets[$record.Font].Virtual){continue}
            foreach($language in @('koreana','english','japanese','schinese','tchinese','russian','polish')){
                $languageNode=Find-KvChild $entry $language
                $range=if($languageNode){Find-KvChild $languageNode 'range'}else{$null}
                if(-not $range -or $range.Value -cne '0x0000 0xFFFF'){throw "Missing Unicode BMP registration: family=$($record.Font); language=$language; scheme=$($Document.VirtualPath)"}
            }
            $matched=$true;break
        }}
        if(-not $matched){throw "Missing portable font registration: family=$($record.Font); scheme=$($Document.VirtualPath)"}
        $verified[$record.Font]=$true
    }
}
function Disable-LegacyFontOverride {
    param([string]$Game)
    $root=Get-ManagedOutputRoot $Game '!fonts';$resource=Join-Path $root 'resource'
    if(-not [IO.Directory]::Exists($resource)){return}
    $generated=New-StringList
    foreach($file in @(Get-ChildItem -LiteralPath $resource -Recurse -File)){
        if($file.Extension -notin @('.res','.kv')){continue}
        if([IO.File]::ReadAllText($file.FullName).StartsWith('// AUTO-GENERATED by VGUIFontChanger')){$generated.Add($file.FullName)}
    }
    if(-not $generated.Count){return}
    $backup=New-OutputBackup $root $Game
    foreach($path in $generated){Remove-Item -LiteralPath $path -Force;Write-VfcLog 'INFO' "Legacy generated Scheme disabled: file=$path; recovery=$backup"}
}
function Remove-CommitStage {
    param([string]$Path)
    $resolved=[IO.Path]::GetFullPath($Path)
    $temporary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
    if((Split-Path $resolved -Parent) -ine $temporary -or (Split-Path $resolved -Leaf) -notmatch '^VGUIFontChanger-commit-[a-f0-9]{32}$'){throw 'Unsafe commit staging cleanup path.'}
    if([IO.Directory]::Exists($resolved)){
        if((Get-Item -LiteralPath $resolved).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Commit staging cleanup refuses a reparse point.'}
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
