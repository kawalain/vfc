function Get-SearchSources {
    param([string]$GamePath,[string]$ExcludedModName)
    Set-WorkStatus 'Reading game search paths'
    $context=Get-GameContext $GamePath
    $tool=Join-Path $context.InstallDirectory 'bin/vpk.exe'
    if(-not (Test-Path -LiteralPath $tool -PathType Leaf)){$tool=$null}
    $sources=New-ObjectList;$seen=@{};$fileCache=[hashtable]::Synchronized(@{})
    $add={param([string]$path)
        if($path -match '(?i)_\d{3}\.vpk$'){return}
        $type='Directory'
        if([IO.Path]::GetExtension($path) -ieq '.vpk'){
            $type='Vpk'
            if(-not (Test-Path -LiteralPath $path)){
                $path=[IO.Path]::Combine([IO.Path]::GetDirectoryName($path),[IO.Path]::GetFileNameWithoutExtension($path)+'_dir.vpk')
            }
        }
        if(-not (Test-Path -LiteralPath $path)){return}
        $key=$type+'|'+[IO.Path]::GetFullPath($path)
        if($seen.ContainsKey($key)){return};$seen[$key]=$true
        $sources.Add([pscustomobject]@{Type=$type;Path=$path;Label=$path;Tool=$tool;FileCache=$fileCache})
        if($type -eq 'Directory'){
            foreach($pak in @(Get-ChildItem -LiteralPath $path -Filter 'pak*_dir.vpk' -File -ErrorAction SilentlyContinue | Sort-Object Name)){& $add $pak.FullName}
        }
    }
    foreach($entry in $context.SearchPaths){
        Test-WorkCancellation
        $ids=$entry.Key -split '\+'
        if($ids -notcontains 'game' -and $ids -notcontains 'mod' -and $ids -notcontains 'vgui' -and $ids -notcontains 'platform'){continue}
        $path=Expand-GameSearchPath $entry.Value $context.GameDirectory $context.InstallDirectory
        if([Management.Automation.WildcardPattern]::ContainsWildcardCharacters($path)){
            foreach($item in @(Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue | Sort-Object @{Expression={$_.Name.ToLowerInvariant()}},Name)){
                if((Split-Path $item.FullName -Parent) -ieq $context.CustomDirectory){
                    if($item.Name -ieq $ExcludedModName -or $item.Name -ieq '!VGUIFontChanger' -or $item.Name -ieq '!fonts'){continue}
                }
                if($item.PSIsContainer -or $item.Extension -ieq '.vpk'){& $add $item.FullName}
            }
        }else{& $add $path}
    }
    return $sources.ToArray()
}
function Get-SchemeVirtualPaths {
    param([object[]]$Sources)
    Set-WorkStatus 'Discovering Scheme files'
    Initialize-VpkIndexes $Sources
    $paths=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($name in $script:SchemeNames){$null=$paths.Add('resource/'+$name)}
    foreach($source in $Sources){
        Test-WorkCancellation
        if($source.Type -eq 'Directory'){
            $resource=Join-Path $source.Path 'resource'
            Set-WorkStatus ('Scanning '+$resource)
            foreach($file in @(Get-ChildItem -LiteralPath $resource -Filter '*scheme*.res' -File -Recurse -ErrorAction SilentlyContinue)){
                Test-WorkCancellation
                $null=$paths.Add($file.FullName.Substring($source.Path.Length).TrimStart('\','/').Replace('\','/'))
            }
        }else{
            foreach($path in (Get-VpkIndex $source.Path).Entries.Keys){Test-WorkCancellation;if($path -match '(?i)^resource/.*scheme.*\.res$'){$null=$paths.Add($path)}}
        }
    }
    return @($paths | Sort-Object)
}

function Read-VirtualFile {
    param([object[]] $Sources, [string] $VirtualPath, [switch]$Binary)
    Test-WorkCancellation
    Set-WorkStatus ('Reading '+$VirtualPath)
    $normalized = $VirtualPath.Replace('\', '/').TrimStart('/')
    $cache=$null
    # PS 5.1's intrinsic PSObject view is unreliable after nested-runspace
    # parameter binding. Read the optional note property through its adapter.
    if($Sources.Count -gt 0){try{$cache=$Sources[0].FileCache}catch{}}
    $cacheKey=$normalized+'|'+[string][bool]$Binary
    if($null -ne $cache -and $cache.ContainsKey($cacheKey)){Write-VfcLog 'TRACE' "File cache hit: virtual=$normalized; binary=$Binary";return $cache[$cacheKey]}
    if(-not $Binary -and $null -ne $cache -and $cache.ContainsKey($normalized+'|True')){
        $raw=$cache[$normalized+'|True']
        if($null -eq $raw){$cache[$cacheKey]=$null;return $null}
        $result=[pscustomobject]@{Text=(Convert-BytesToText $raw.Bytes);Source=$raw.Source;Container=$raw.Container;VirtualPath=$normalized}
        $cache[$cacheKey]=$result;return $result
    }
    foreach ($source in $Sources) {
        if ($source.Type -eq 'Directory') {
            $physical = Join-Path $source.Path ($normalized.Replace('/', [IO.Path]::DirectorySeparatorChar))
            if (Test-Path -LiteralPath $physical -PathType Leaf) {
                $bytes = [IO.File]::ReadAllBytes($physical)
                $raw=[pscustomobject]@{Bytes=$bytes;Source=$physical;Container=$source.Label;VirtualPath=$normalized}
                if($null -ne $cache){$cache[$normalized+'|True']=$raw}
                if($Binary){$result=$raw}
                else{$result=[pscustomobject]@{ Text=(Convert-BytesToText $bytes); Source=$physical; Container=$source.Label; VirtualPath=$normalized }}
                if($null -ne $cache){$cache[$cacheKey]=$result};return $result
            }
        } else {
            try { $bytes = Read-VpkEntryBytes $source.Path $normalized $source.Tool } catch { throw }
            if ($null -ne $bytes) {
                $raw=[pscustomobject]@{Bytes=$bytes;Source="$($source.Path):$normalized";Container=$source.Label;VirtualPath=$normalized}
                if($null -ne $cache){$cache[$normalized+'|True']=$raw}
                if($Binary){$result=$raw}
                else{$result=[pscustomobject]@{ Text=(Convert-BytesToText $bytes); Source="$($source.Path):$normalized"; Container=$source.Label; VirtualPath=$normalized }}
                if($null -ne $cache){$cache[$cacheKey]=$result};return $result
            }
        }
    }
    if($null -ne $cache){$cache[$cacheKey]=$null}
    return $null
}
