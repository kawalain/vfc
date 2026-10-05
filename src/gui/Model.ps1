function ConvertTo-PlainValue {
    param($Value)
    if($null -eq $Value){return $null}
    # PowerShell may wrap a scalar in PSObject after parameter binding. Do not
    # treat that wrapper as an empty JSON object when cloning profiles/history.
    if($Value -is [string] -or $Value -is [ValueType]){return $Value}
    if($Value -is [Collections.IDictionary]){$map=@{};foreach($key in $Value.Keys){$map[[string]$key]=ConvertTo-PlainValue $Value[$key]};return $map}
    if($Value -is [pscustomobject]){$map=@{};foreach($property in $Value.PSObject.Properties){$map[$property.Name]=ConvertTo-PlainValue $property.Value};return $map}
    if($Value -is [Collections.IEnumerable] -and $Value -isnot [string]){return ,@($Value | ForEach-Object {ConvertTo-PlainValue $_})}
    return $Value
}
function ConvertTo-NodeSettings {
    param($Profile)
    $profileMap=ConvertTo-PlainValue $Profile; $settings=@{}
    if($profileMap.ContainsKey('Version') -and [int]$profileMap.Version -gt 2){throw 'Unsupported settings version.'}
    if($profileMap.ContainsKey('Nodes')){
        if($profileMap.Nodes -isnot [hashtable]){throw 'Invalid Nodes settings object.'}
        foreach($id in $profileMap.Nodes.Keys){
            $entry=$profileMap.Nodes[$id]
            if($id -notlike 'group|*' -or $entry -isnot [hashtable]){throw 'Invalid node settings.'}
            $setting=@{}
            foreach($key in $entry.Keys){
                if($key -eq 'Font'){
                    if($entry[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($entry[$key])){throw 'Font must be a non-empty family name.'}
                    $setting.Font=$entry[$key]
                }elseif($key -eq 'Factor'){
                    $factor=[double]$entry[$key]
                    if([double]::IsNaN($factor) -or [double]::IsInfinity($factor) -or $factor -lt 0.1 -or $factor -gt 4.0 -or [Math]::Abs($factor*10-[Math]::Round($factor*10)) -gt 0.0001){throw 'Factor must be 0.1..4.0 in steps of 0.1.'}
                    $setting.Factor=$factor
                }elseif($key -eq 'Size'){
                    $size=[double]$entry[$key]
                    if($id -notlike '*|variant|*' -or [double]::IsNaN($size) -or [double]::IsInfinity($size) -or $size -lt 1 -or $size -gt 512 -or $size -ne [Math]::Round($size)){throw 'Variant size must be 1..512 whole VGUI pixels.'}
                    $setting.Size=[int]$size
                }else{throw ('Unknown setting: '+$key)}
            }
            if($setting.Count){$settings[$id]=$setting}
        }
    }else{
        foreach($key in @('Fonts','Factors')){
            if(-not $profileMap.ContainsKey($key)){continue}
            foreach($font in $profileMap[$key].Keys){
                $id='group|'+[Uri]::EscapeDataString($font)
                if(-not $settings.ContainsKey($id)){$settings[$id]=@{}}
                if($key -eq 'Fonts' -and $profileMap[$key][$font] -cne $font){$settings[$id].Font=[string]$profileMap[$key][$font]}
                if($key -eq 'Factors' -and [double]$profileMap[$key][$font] -ne 1.0){$settings[$id].Factor=[double]$profileMap[$key][$font]}
                if(-not $settings[$id].Count){$settings.Remove($id)}
            }
        }
        return ConvertTo-NodeSettings @{Nodes=$settings}
    }
    return $settings
}
function New-FontHierarchy {
    param([object[]]$Summary,$Profile,[string]$Language='en-US',[string]$Theme='System')
    $model=@{Nodes=@{};Roots=(New-StringList);Settings=(ConvertTo-NodeSettings $Profile);Undo=(New-StringList);Redo=(New-StringList);Preferences=@{Locale=$Language;Theme=$Theme;Symbols=$false;ListZoom=1.0;GamePath='';LogLevel='INFO'}}
    foreach($group in $Summary){
        $groupId='group|'+[Uri]::EscapeDataString($group.Font)
        $root=@{Id=$groupId;Parent='';Depth=0;Label=$group.Font;Original=$group.Font;Kind=$group.Kind;Children=(New-StringList);Locations=@($group.Locations);Sizes=$group.Sizes;Expanded=$false}
        $model.Nodes[$groupId]=$root; $model.Roots.Add($groupId)
        foreach($location in $group.Locations){
            if(-not $model.Nodes.ContainsKey($location.AliasId)){
                $alias=@{Id=$location.AliasId;Parent=$groupId;Depth=1;Label=($location.Alias+' ('+[IO.Path]::GetFileName($location.Scheme)+')');Original=$group.Font;Kind=$group.Kind;Children=(New-StringList);Locations=(New-ObjectList);Sizes=$group.Sizes;Expanded=$false}
                $model.Nodes[$alias.Id]=$alias; $root.Children.Add($alias.Id)
            }
            $alias=$model.Nodes[$location.AliasId]; $alias.Locations.Add($location)
            $label=$location.Variant; if($location.Condition){$label+='  ['+$location.Condition+']'}
            $variant=@{Id=$location.Id;Parent=$alias.Id;Depth=2;Label=$label;Original=$group.Font;Kind=$group.Kind;Children=(New-StringList);Locations=@($location);Sizes=$location.Tall;Expanded=$false}
            $model.Nodes[$variant.Id]=$variant; $alias.Children.Add($variant.Id)
        }
    }
    return $model
}
function Get-NodeValue {
    param($Model,[string]$Id,[string]$Property)
    $node=$Model.Nodes[$Id]
    if($Model.Settings.ContainsKey($Id) -and $Model.Settings[$Id].ContainsKey($Property)){return $Model.Settings[$Id][$Property]}
    if($Property -eq 'Size'){
        $original=0; $null=[int]::TryParse([string]$node.Sizes,[ref]$original)
        if($original -le 0){return 0}
        return [int][Math]::Max(1,[Math]::Round($original*[double](Get-NodeValue $Model $Id 'Factor'),0,[MidpointRounding]::AwayFromZero))
    }
    if($node.Parent){return Get-NodeValue $Model $node.Parent $Property}
    if($Property -eq 'Font'){return $node.Original}; return 1.0
}
function Get-ModelSnapshot {
    param($Model)
    return (@{Nodes=$Model.Settings;Preferences=$Model.Preferences}|ConvertTo-Json -Depth 12 -Compress)
}
function Complete-ModelChange {
    param($Model,[string]$Before)
    if((Get-ModelSnapshot $Model) -ceq $Before){return $false}
    $Model.Undo.Add($Before); $Model.Redo.Clear(); return $true
}
function Set-NodeValue {
    param($Model,[string]$Id,[string]$Property,$Value)
    if(-not $Model.Nodes.ContainsKey($Id)){throw 'Unknown font hierarchy node.'}
    $node=$Model.Nodes[$Id]
    if($Property -eq 'Size'){
        if($node.Depth -ne 2){throw 'Absolute size is only supported for variants.'}
        $original=0;$null=[int]::TryParse([string]$node.Sizes,[ref]$original)
        if($original -le 0){throw 'This variant has no numeric tall; edit its parent factor instead.'}
        if([int]$Value -lt 1 -or [int]$Value -gt 512){throw 'Font size must be 1..512 VGUI pixels.'}
        if($Model.Settings.ContainsKey($Id)){$Model.Settings[$Id].Remove('Factor')}
        $inherited=[int][Math]::Max(1,[Math]::Round($original*[double](Get-NodeValue $Model $Id 'Factor'),0,[MidpointRounding]::AwayFromZero))
    }else{$inherited=if($node.Parent){Get-NodeValue $Model $node.Parent $Property}elseif($Property -eq 'Font'){$node.Original}else{1.0}}
    if(-not $Model.Settings.ContainsKey($Id)){$Model.Settings[$Id]=@{}}
    if($Value -eq $inherited){$Model.Settings[$Id].Remove($Property)}else{$Model.Settings[$Id][$Property]=$Value}
    if(-not $Model.Settings[$Id].Count){$Model.Settings.Remove($Id)}
}
function Invoke-ModelHistory {
    param($Model,[ValidateSet('Undo','Redo')][string]$Direction)
    $source=$Model[$Direction]; if(-not $source.Count){return $false}
    $target=$Model.Redo; if($Direction -eq 'Redo'){$target=$Model.Undo}
    $target.Add((Get-ModelSnapshot $Model)); $snapshot=$source[$source.Count-1]; $source.RemoveAt($source.Count-1)
    $restored=ConvertTo-PlainValue ($snapshot|ConvertFrom-Json)
    $Model.Settings=$restored.Nodes; $Model.Preferences=$restored.Preferences
    return $true
}
function Get-HierarchyProfile {
    param($Model)
    # Game profiles must never contain application layout preferences.
    return @{Version=2;Nodes=(ConvertTo-PlainValue $Model.Settings)}
}
function Get-VisibleFontNodes {
    param($Model)
    $visible=New-StringList
    $visit={param($id)
        $node=$Model.Nodes[$id]; $visible.Add($id)
        if($node.Expanded){foreach($child in $node.Children){& $visit $child}}
    }
    foreach($id in $Model.Roots){
        $node=$Model.Nodes[$id]; $configured=$false
        foreach($settingId in $Model.Settings.Keys){if($settingId -eq $id -or $settingId.StartsWith($id+'|')){$configured=$true;break}}
        if($Model.Preferences.Symbols -or $node.Kind -ne 'Symbol' -or $configured){& $visit $id}
    }
    return $visible.ToArray()
}
function Get-FontSearchMatches {
    param($Model,[string]$Query)
    if([string]::IsNullOrWhiteSpace($Query)){return}
    # Matches are limited to groups and aliases; variants would flood the
    # results because every alias owns several of them.
    $query=$Query.Trim();$matches=New-StringList
    $visit={param([string]$id)
        $node=$Model.Nodes[$id]
        if($node.Depth -le 1){
            $fields=New-StringList
            $fields.Add([string]$node.Label);$fields.Add([string]$node.Original);$fields.Add([string](Get-NodeValue $Model $id 'Font'))
            if($node.Depth -eq 1){
                foreach($location in $node.Locations){
                    foreach($key in @('Alias','Scheme','Source')){$fields.Add([string]$location.$key)}
                }
            }
            foreach($field in $fields){if($field.IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0){$matches.Add($id);break}}
        }
        foreach($child in $node.Children){& $visit $child}
    }
    foreach($id in $Model.Roots){
        $node=$Model.Nodes[$id];$configured=$false
        foreach($settingId in $Model.Settings.Keys){if($settingId -eq $id -or $settingId.StartsWith($id+'|')){$configured=$true;break}}
        if($Model.Preferences.Symbols -or $node.Kind -ne 'Symbol' -or $configured){& $visit $id}
    }
    return $matches.ToArray()
}
