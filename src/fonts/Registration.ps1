function Get-FontFile {
    param([string]$Family)
    if($script:GameFontPaths.ContainsKey($Family)){return $script:GameFontPaths[$Family]}
    $registrations=New-ObjectList
    foreach($key in @('HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts','HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts')){
        if(-not (Test-Path $key)){continue}
        foreach($prop in (Get-ItemProperty $key).PSObject.Properties){
            $registeredFamilies=($prop.Name -replace '\s+\((TrueType|OpenType)\)$','') -split '\s+&\s+'
            if($prop.Name -like 'PS*'){continue}
            $path=[string]$prop.Value
            if(-not [IO.Path]::IsPathRooted($path)){$path=Join-Path "$env:WINDIR/Fonts" $path}
            if(-not (Test-Path -LiteralPath $path -PathType Leaf)){continue}
            if($registeredFamilies -contains $Family){return $path}
            $registrations.Add([pscustomobject]@{Families=$registeredFamilies;Path=$path})
        }
    }
    # Registry names may be localized while the font picker uses English names.
    # Keep direct lookup first, then compare canonical names for each TTC family.
    $canonical=Get-CanonicalFontName $Family
    foreach($registration in $registrations){
        foreach($name in $registration.Families){
            if((Get-CanonicalFontName $name) -eq $canonical){return $registration.Path}
        }
    }
    # Some registry labels include a style (e.g. "Family Regular") that is not
    # part of the internal family name. Verify file metadata rather than guess.
    $ordered=@($registrations | Sort-Object @{Expression={if($_.Families -contains ($Family+' Regular')){0}else{1}}})
    foreach($registration in $ordered){
        $collection=New-Object Drawing.Text.PrivateFontCollection
        try{
            $collection.AddFontFile($registration.Path)
            foreach($font in $collection.Families){
                try{
                    if($font.Name -eq $Family -or $font.GetName(1033) -eq $canonical){return $registration.Path}
                }finally{$font.Dispose()}
            }
        }catch{
            # Bitmap/unsupported files are not usable as private outline fonts.
        }finally{$collection.Dispose()}
    }
    return $null
}
function Get-CanonicalFontName {
    param([string]$Name)
    Add-Type -AssemblyName System.Drawing
    try{
        $family=New-Object Drawing.FontFamily($Name)
        try{return $family.GetName(1033)}finally{$family.Dispose()}
    }catch{return $Name}
}
function Add-SchemeFontRegistration {
    param([object[]]$Documents,[string]$SchemePath,[string]$Family,[hashtable]$Assets,[switch]$Required,[switch]$PreserveRanges)
    if(-not $script:FontAssetCache.ContainsKey($Family)){
        $path=Get-FontFile $Family
        if(-not $path){if($Required){throw "Cannot locate the font file for selected family: $Family"};Write-VfcLog 'WARN' "Original family has no separately resolvable file; retain game font aliases/fallback: family=$Family";$script:FontAssetCache[$Family]=$null; return}
        $hash=[Security.Cryptography.SHA256]::Create(); $stream=[IO.File]::OpenRead($path)
        try{$id=([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','')}finally{$stream.Dispose();$hash.Dispose()}
        $script:FontAssetCache[$Family]=[pscustomobject]@{Path=$path;Id=$id;Virtual=("resource/fonts/vguifontchanger/$id"+[IO.Path]::GetExtension($path).ToLowerInvariant());RangeSchemes=@{}}
        if($Required -and ($script:LogPath -or ($script:Work -and $script:Work.ContainsKey('LogPath') -and $script:Work.LogPath))){
            $probe=Test-WindowsFont $Family
            Write-VfcLog 'DEBUG' "Pre-registration Windows glyph probe: requested=$Family; canonical=$($probe.CanonicalFamily); actualFace=$($probe.GdiFace); exactMatch=$($probe.ExactMatch); missingSampleGlyphs=$($probe.MissingGlyphs); variable=$(Test-VariableFontFile $path)"
        }
    }
    $asset=$script:FontAssetCache[$Family]; if(-not $asset){if($Required){throw "Cannot locate the font file for selected family: $Family"};return}
    $path=$asset.Path; $id=$asset.Id; $virtual=$asset.Virtual
    $Assets[$virtual]=$path
    foreach($document in $Documents){
        if($document.VirtualPath -ne $SchemePath){continue}
        $scheme=Find-KvRoot $document 'Scheme'
        $custom=Find-KvChild $scheme 'CustomFontFiles'
        if(-not $custom){$custom=New-KvNode 'CustomFontFiles' $false $null @() 'generated' 0; $scheme.Children.Add($custom)}
        # A TTC may contain several families; file identity alone is not a
        # registration identity. Every selected family needs its own ranges.
        $familyId=(Get-ContentSha256 ([Text.Encoding]::UTF8.GetBytes($Family.ToLowerInvariant()))).Substring(0,16)
        $key="VGUIFontChanger_${id}_$familyId"
        if(Find-KvChild $custom $key){continue}
        for($index=$custom.Children.Count-1;$index -ge 0;$index--){
            $old=$custom.Children[$index];if($old.HasValue){continue}
            $oldName=Find-KvChild $old 'name'
            if(-not $PreserveRanges -and $oldName -and $oldName.Value -ieq $Family){$custom.Children.RemoveAt($index)}
        }
        $entry=New-KvNode $key $false $null @() 'generated' 0
        $entry.Children.Add((New-KvNode 'font' $true $virtual @() 'generated' 0))
        $entry.Children.Add((New-KvNode 'name' $true $Family @() 'generated' 0))
        if(-not $PreserveRanges){foreach($language in @('koreana','english','japanese','schinese','tchinese','russian','polish','arabic','bulgarian','czech','danish','dutch','finnish','french','german','greek','hungarian','indonesian','italian','norwegian','portuguese','brazilian','romanian','spanish','latam','swedish','thai','turkish','ukrainian','vietnamese')){
            $node=New-KvNode $language $false $null @() 'generated' 0
            $node.Children.Add((New-KvNode 'range' $true '0x0000 0xFFFF' @() 'generated' 0))
            $entry.Children.Add($node)
        };$asset.RangeSchemes[$SchemePath]=$true}
        $custom.Children.Add($entry)
        Write-VfcLog 'DEBUG' "Font registration: scheme=$SchemePath; family=$Family; source=$path; asset=$virtual; preserveOriginalRanges=$PreserveRanges; overrideBMP=$(-not $PreserveRanges)"
        if(-not $PreserveRanges){foreach($node in $entry.Children){if(-not $node.HasValue){Write-VfcLog 'TRACE' "Language range: scheme=$SchemePath; family=$Family; language=$($node.Key); range=0x0000 0xFFFF"}}}
    }
}
function ConvertTo-PortableGameFonts {
    param([object[]]$Documents,$GameAssets,[hashtable]$Assets)
    $mapping=@{}
    foreach($asset in $GameAssets){
        Test-WorkCancellation
        $hash=Get-ContentSha256 ([IO.File]::ReadAllBytes($asset.Path))
        $virtual='resource/fonts/vguifontchanger/'+$hash+[IO.Path]::GetExtension($asset.Path).ToLowerInvariant()
        $Assets[$virtual]=$asset.Path;$mapping[$asset.VirtualPath]=$virtual
        Write-VfcLog 'DEBUG' "Portable game font: source=$($asset.Source); asset=$virtual; sha256=$hash"
    }
    foreach($document in $Documents){
        $root=Find-KvRoot $document 'Scheme';if(-not $root){continue}
        $custom=Find-KvChild $root 'CustomFontFiles';if(-not $custom){continue}
        foreach($entry in $custom.Children){
            $font=if($entry.HasValue){$entry}else{Find-KvChild $entry 'font'}
            if($font -and $mapping.ContainsKey($font.Value)){$font.Value=$mapping[$font.Value]}
            elseif($font -and $font.Value -match '(?i)\.(ttf|otf|ttc|vbf)$' -and $font.Value -notlike 'resource/fonts/vguifontchanger/*'){
                throw "Cannot resolve a game/HUD font file required for portability: $($font.Value)"
            }
        }
    }
}
function Test-VariableFontFile {
    param([string]$Path)
    $bytes=[IO.File]::ReadAllBytes($Path)
    if($bytes.Length -lt 12){return $false}
    $tableCount=$bytes[4]*256+$bytes[5]
    if(12+16*$tableCount -gt $bytes.Length){return $false}
    for($index=0;$index -lt $tableCount;$index++){
        if([Text.Encoding]::ASCII.GetString($bytes,12+16*$index,4) -eq 'fvar'){return $true}
    }
    return $false
}
function New-FontBackendDocument {
    param([object[]]$Sources,[hashtable]$FontAssets,[switch]$RestoreBaseline)
    $families=@($FontAssets.Keys | Where-Object {$FontAssets[$_] -and (Test-VariableFontFile $FontAssets[$_].Path)})
    if($families.Count -eq 0 -and -not $RestoreBaseline){return $null}
    $virtual='resource/FontInfo.kv'
    $file=Read-VirtualFile $Sources $virtual
    if($file){$document=ConvertFrom-KeyValuesText $file.Text $file.Source; $entrySource=$file.Source}
    else{$document=ConvertFrom-KeyValuesText '"FontInfo" {}' 'generated'; $entrySource='generated'}
    $root=Find-KvRoot $document 'FontInfo'
    if(-not $root){throw 'FontInfo.kv has no FontInfo root; refusing to replace its configuration.'}
    foreach($family in $families){
        $setting=Find-KvChild $root $family
        if($setting){$setting.Value='freetype2'}
        else{$root.Children.Add((New-KvNode $family $true 'freetype2' @() 'generated' 0))}
    }
    $document | Add-Member NoteProperty VirtualPath $virtual
    $document | Add-Member NoteProperty Entry $entrySource
    $document | Add-Member NoteProperty Dependencies @($entrySource)
    return $document
}
function Get-GameFontAssets {
    param($Resolved)
    Add-Type -AssemblyName System.Drawing
    $assets=@{}
    foreach($document in $Resolved.Documents){
        $custom=Find-KvChild (Find-KvRoot $document 'Scheme') 'CustomFontFiles'
        if(-not $custom){continue}
        foreach($entry in $custom.Children){
            Test-WorkCancellation
            $virtual=$null; $declared=$null
            if($entry.HasValue){$virtual=$entry.Value}
            else{
                $font=Find-KvChild $entry 'font'; if($font){$virtual=$font.Value}
                $name=Find-KvChild $entry 'name'; if($name){$declared=$name.Value}
            }
            if(-not $virtual -or $virtual -notmatch '(?i)\.(ttf|otf|ttc|vbf)$'){continue}
            if(-not $assets.ContainsKey($virtual)){
                $file=Read-VirtualFile $Resolved.Sources $virtual -Binary
                if(-not $file){Write-Warning "Missing font file: $virtual";continue}
                $path=$file.Source
                if(-not (Test-Path -LiteralPath $path -PathType Leaf)){
                    $sha=[Security.Cryptography.SHA256]::Create()
                    try{$id=([BitConverter]::ToString($sha.ComputeHash([byte[]]$file.Bytes))).Replace('-','')}finally{$sha.Dispose()}
                    $root=Join-Path (Get-SettingsRoot) 'font-cache'
                    $null=[IO.Directory]::CreateDirectory($root)
                    $path=Join-Path $root ($id+[IO.Path]::GetExtension($virtual))
                    if(-not (Test-Path -LiteralPath $path)){[IO.File]::WriteAllBytes($path,[byte[]]$file.Bytes)}
                }
                $names=New-StringList
                $collection=New-Object Drawing.Text.PrivateFontCollection
                try{
                    if([IO.Path]::GetExtension($path) -ine '.vbf'){
                        $collection.AddFontFile($path)
                        foreach($family in $collection.Families){if(-not $names.Contains($family.Name)){$names.Add($family.Name)}}
                    }
                }catch{Write-Warning "Unable to preview font '$virtual': $($_.Exception.Message)"}
                finally{$collection.Dispose()}
                $assets[$virtual]=[pscustomobject]@{Path=$path;VirtualPath=$virtual;Source=$file.Source;Names=$names}
            }
            if($declared -and -not $assets[$virtual].Names.Contains($declared)){$assets[$virtual].Names.Add($declared)}
        }
    }
    return @($assets.Values)
}
function Initialize-PrivateFontPreview {
    Add-Type -AssemblyName System.Drawing
}
function New-PrivateFontStore {
    Initialize-PrivateFontPreview
    $store=[pscustomobject]@{Collection=(New-Object Drawing.Text.PrivateFontCollection)}
    $store | Add-Member ScriptMethod Add {param([string]$Path); $this.Collection.AddFontFile($Path)}
    $store | Add-Member ScriptMethod Dispose {$this.Collection.Dispose()}
    return $store
}
