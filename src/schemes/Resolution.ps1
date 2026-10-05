function Get-ResolvedSchemes {
    param([string]$GamePath, [string]$OutputModName,[switch]$Sequential)
    $sources = Get-SearchSources $GamePath $OutputModName
    $documents = New-ObjectList
    $paths=@(Get-SchemeVirtualPaths $sources)
    $directory=Get-ScanCacheDirectory $GamePath $OutputModName
    $entries=@{};$fingerprints=@{};$validEntries=@{};$found=@{};$pending=New-StringList
    if(-not $Sequential){try{
        $manifestPath=Join-Path $directory 'index.json'
        if([IO.File]::Exists($manifestPath)){
            $manifest=ConvertTo-PlainValue ([IO.File]::ReadAllText($manifestPath)|ConvertFrom-Json)
            if($manifest.Version -eq 1){$entries=$manifest.Documents}
        }
    }catch{$entries=@{}}}
    foreach($path in $paths){
        $cached=$null
        if($entries.ContainsKey($path)){$cached=Read-CachedScheme $sources $path $entries[$path] $directory $fingerprints}
        if($cached){$found[$path]=$cached;$validEntries[$path]=$entries[$path]}else{$pending.Add($path)}
    }
    if($pending.Count -ge 4 -and -not $Sequential){
        foreach($document in (Get-SchemeDocumentsParallel $sources $pending.ToArray())){$found[$document.VirtualPath]=$document}
    }else{foreach ($virtualPath in $pending) {
        if(-not (Read-VirtualFile $sources $virtualPath)){continue}
        try { $found[$virtualPath]=Resolve-KvDocument $sources $virtualPath @{} }
        catch [System.Management.Automation.RuntimeException] {
            if ($_.Exception.Message -like 'Virtual file not found:*') { Write-Warning $_.Exception.Message }
            else { throw }
        }
    }}
    foreach($path in $paths){if($found.ContainsKey($path)){$documents.Add($found[$path])}}
    if(-not $documents.Count){throw 'No VGUI2 Scheme files were found in the selected game.'}
    if(-not $Sequential){Save-ScanCache $sources $documents $directory $fingerprints $validEntries}
    Write-VfcLog 'INFO' "Scheme scan complete: documents=$($documents.Count); cacheHits=$($validEntries.Count); cacheMisses=$($documents.Count-$validEntries.Count); index=$directory"
    return [pscustomobject]@{ Sources=$sources; Documents=$documents;GameDirectory=(Get-GameContext $GamePath).GameDirectory;CacheHits=$validEntries.Count;CacheMisses=($documents.Count-$validEntries.Count) }
}

function ConvertTo-ReplacementMap {
    param([string[]]$Pairs)
    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($pair in @($Pairs)) {
        if ([string]::IsNullOrWhiteSpace($pair)) { continue }
        $index = $pair.IndexOf('=')
        if ($index -le 0) { throw "Invalid -Replace value '$pair'. Use Original=Replacement." }
        $map[$pair.Substring(0, $index).Trim()] = $pair.Substring($index + 1).Trim()
    }
    return $map
}

function Get-GeneratedFontDirectory {
    param([string]$OutputRoot)
    $root=[IO.Path]::GetFullPath($OutputRoot).TrimEnd('\','/')
    $target=[IO.Path]::GetFullPath((Join-Path $root 'resource/fonts/vguifontchanger'))
    if(-not $target.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe generated font cleanup path.'}
    $check=$target
    while($check.Length -ge $root.Length){
        if(Test-Path -LiteralPath $check){if((Get-Item -LiteralPath $check -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Refusing cleanup through a junction or symbolic link: $check"}}
        if($check -ieq $root){break};$check=Split-Path $check -Parent
    }
    return $target
}
function Copy-ResolvedSchemes {
    param($Resolved)
    Initialize-ScanCacheRuntime
    $documents=New-ObjectList
    foreach($document in $Resolved.Documents){
        Test-WorkCancellation
        $documents.Add([VfcScanCacheReader]::Clone($document))
    }
    return [pscustomobject]@{Sources=$Resolved.Sources;Documents=$documents;GameDirectory=$Resolved.GameDirectory}
}
