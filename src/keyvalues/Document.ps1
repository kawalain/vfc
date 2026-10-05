function Find-KvChild {
    param($Node, [string]$Name)
    foreach ($child in $Node.Children) { if ($child.Key -ieq $Name) { return $child } }
    return $null
}

function Find-KvRoot {
    param($Document, [string]$Name)
    foreach ($root in $Document.Nodes) { if ($root.Key -ieq $Name) { return $root } }
    return $null
}

function Get-FontRecords {
    param([object[]]$Documents)
    $records = New-ObjectList; $occurrences=@{}
    foreach ($document in $Documents) {
        $scheme = Find-KvRoot $document 'Scheme'
        if ($null -eq $scheme) { continue }
        $fonts = Find-KvChild $scheme 'Fonts'
        if ($null -eq $fonts) { continue }
        foreach ($alias in $fonts.Children) {
            $glyphSets = if ($alias.Children.Count -gt 0) { $alias.Children.ToArray() } else { @($alias) }
            foreach ($glyphSet in $glyphSets) {
                foreach ($property in $glyphSet.Children) {
                    if ($property.Key -ieq 'name' -and $property.HasValue) {
                        $kind = if ($property.Value -match $script:SymbolFontPattern -or $alias.Key -match $script:SymbolAliasPattern) { 'Symbol' } else { 'Text' }
                        $tall = Find-KvChild $glyphSet 'tall'
                        $groupId='group|'+[Uri]::EscapeDataString($property.Value)
                        $aliasId=$groupId+'|alias|'+[Uri]::EscapeDataString($document.VirtualPath)+'|'+[Uri]::EscapeDataString($alias.Key)
                        $baseId=$aliasId+'|glyphset|'+[Uri]::EscapeDataString($glyphSet.Key)
                        if(-not $occurrences.ContainsKey($baseId)){$occurrences[$baseId]=0}; $occurrences[$baseId]++
                        $id=$baseId+'|'+$occurrences[$baseId]
                        $yres=Find-KvChild $glyphSet 'yres'; $condition=($glyphSet.Condition+' '+$property.Condition).Trim()
                        if($yres){$condition=('yres '+$yres.Value+' '+$condition).Trim()}
                        $null = $records.Add([pscustomobject]@{ Id=$id;GroupId=$groupId;AliasId=$aliasId;Condition=$condition; Scheme=$document.VirtualPath; Alias=$alias.Key; GlyphSet=$glyphSet.Key; Font=$property.Value; Kind=$kind; Node=$property; GlyphSetNode=$glyphSet; Tall=if($tall){$tall.Value}else{''}; Source=$property.Source; Line=$property.Line })
                    }
                }
            }
        }
    }
    return $records.ToArray()
}

function Select-EffectiveAliasRecords {
    # Engine behaviour (verified against the published engine source and live
    # game files): every scheme file becomes its own scheme with a private
    # alias table, so definitions in different files never shadow each other;
    # the binding that matters is the one in the scheme the drawing panel
    # uses. The HUD and most game UI load ClientScheme.res. The engine's own
    # panels (console, loading screens, dialogs) use the default scheme, the
    # first one loaded, SourceScheme.res, which is also the fallback for any
    # panel without an explicit scheme. Dedicated schemes such as
    # itemtest_scheme.res only apply to the specific panels that load them.
    # Within one file a duplicated alias name keeps its first definition: the
    # alias dictionary allows duplicate keys but lookup and glyph setup both
    # read the first entry. Rank ClientScheme first, the engine default
    # SourceScheme second, and niche dedicated schemes last.
    param([object[]]$Records)
    if(-not $Records -or @($Records).Count -eq 0){return $Records}
    $winner=@{}
    foreach($record in @($Records)){
        $base=[IO.Path]::GetFileNameWithoutExtension([string]$record.Scheme).ToLowerInvariant()
        $priority=if($base -eq 'clientscheme'){0}elseif($base -eq 'sourcescheme'){1}else{2}
        $key=([string]$record.Alias).ToLowerInvariant()
        $current=$winner[$key]
        $replace=$true
        if($current){
            if($priority -gt $current.Priority){$replace=$false}
            elseif($priority -eq $current.Priority){
                if([string]$record.Scheme -ieq $current.Scheme){$replace=([int]$record.Line -lt [int]$current.Line)}else{$replace=$false}
            }
        }
        if($replace){$winner[$key]=@{Priority=$priority;Scheme=[string]$record.Scheme;Line=[int]$record.Line}}
    }
    $result=New-ObjectList
    foreach($record in @($Records)){
        $current=$winner[([string]$record.Alias).ToLowerInvariant()]
        if($current -and [string]$record.Scheme -ieq $current.Scheme){$null=$result.Add($record)}
    }
    return $result.ToArray()
}
function Get-FontSummary {
    param([object[]]$Records,[switch]$All)
    $records=if($All){@($Records)}else{@(Select-EffectiveAliasRecords $Records)}
    $groups = @($records | Group-Object Font | Sort-Object Name)
    foreach ($group in $groups) {
        # A text family can also be used by ButtonText/IconLabel aliases. Hide
        # the whole family only when every use is classified as a symbol.
        $kind = if (@($group.Group | Where-Object Kind -eq 'Text').Count -eq 0) { 'Symbol' } else { 'Text' }
        $locations=@($group.Group | ForEach-Object {[pscustomobject]@{Id=$_.Id;AliasId=$_.AliasId;GroupId=$_.GroupId;Condition=$_.Condition;Source=$_.Source;Line=$_.Line;Alias=$_.Alias;GlyphSet=$_.GlyphSet;Scheme=$_.Scheme;Tall=$_.Tall}})
        [pscustomobject]@{ Font=$group.Name; Kind=$kind; Count=$group.Count; Sizes=(@($group.Group | ForEach-Object Tall | Sort-Object -Unique) -join ', '); Locations=$locations }
    }
}

function Add-FontUsageContext {
    param([object[]]$Summary,[object[]]$Sources)
    $cache=@{}
    foreach($item in $Summary){
        foreach($location in $item.Locations){
            Test-WorkCancellation
            if(-not $cache.ContainsKey($location.Source)){
                $sourceText=$null
                if($location.Source -match '^(.*\.vpk):(.+)$'){
                    $container=$Matches[1]; $virtual=$Matches[2]
                    $source=@($Sources | Where-Object {$_.Type -eq 'Vpk' -and $_.Path -eq $container})
                    $file=Read-VirtualFile $source $virtual
                    if($file){$sourceText=$file.Text}
                }elseif(Test-Path -LiteralPath $location.Source -PathType Leaf){$sourceText=Convert-BytesToText ([IO.File]::ReadAllBytes($location.Source))}
                $cache[$location.Source]=$sourceText
            }
            $context=Get-NumberedContext $cache[$location.Source] $location.Line
            $location | Add-Member NoteProperty Context $context
        }
    }
}
function Get-NumberedContext {
    param([string]$Text,[int]$Line,[int]$Radius=10)
    if($null -eq $Text -or $Text.Length -eq 0){return [pscustomobject]@{Text='';Offset=0;Length=0}}
    $lines=[regex]::Split($Text,'\r\n|\n|\r'); $builder=New-Object Text.StringBuilder
    $offset=0; $length=0
    for($index=[Math]::Max(1,$Line-$Radius);$index -le [Math]::Min($lines.Length,$Line+$Radius);$index++){
        $row=('{0,6}  {1}' -f $index,$lines[$index-1])
        if($index -eq $Line){$offset=$builder.Length; $length=$row.Length}
        $null=$builder.AppendLine($row)
    }
    return [pscustomobject]@{Text=$builder.ToString();Offset=$offset;Length=$length}
}

function ConvertTo-KvQuoted {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Write-KvNodeText {
    param($Node, [Text.StringBuilder]$Builder, [int]$Depth)
    $indent = "`t" * $Depth
    if (-not $Node.HasValue) {
        $null = $Builder.AppendLine($indent + (ConvertTo-KvQuoted $Node.Key))
        $null = $Builder.AppendLine($indent + '{')
        foreach ($child in $Node.Children) { Write-KvNodeText $child $Builder ($Depth + 1) }
        $null = $Builder.AppendLine($indent + '}')
    } elseif ($Node.Children.Count -gt 0) {
        $null = $Builder.AppendLine($indent + (ConvertTo-KvQuoted $Node.Key))
        $null = $Builder.AppendLine($indent + '{')
        foreach ($child in $Node.Children) { Write-KvNodeText $child $Builder ($Depth + 1) }
        $null = $Builder.AppendLine($indent + '}')
    } else {
        $null = $Builder.AppendLine($indent + (ConvertTo-KvQuoted $Node.Key) + "`t" + (ConvertTo-KvQuoted $Node.Value))
    }
}

function ConvertTo-KeyValuesText {
    param($Document, [hashtable]$Metadata)
    $builder = New-Object Text.StringBuilder
    $null = $builder.AppendLine('// AUTO-GENERATED by VGUIFontChanger')
    $null = $builder.AppendLine('// Entry: ' + $Document.Entry)
    if ($Metadata.ContainsKey('Generated')) { $null = $builder.AppendLine('// Generated: ' + $Metadata.Generated) }
    $null = $builder.AppendLine('// Do not edit manually; regenerate this file instead.')
    foreach ($dependency in $Document.Dependencies) { $null = $builder.AppendLine('// Dependency: ' + $dependency) }
    $null = $builder.AppendLine()
    foreach ($root in $Document.Nodes) { Write-KvNodeText $root $builder 0 }
    return $builder.ToString()
}
