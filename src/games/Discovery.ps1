function Get-SteamRoots {
    $roots = New-StringList
    $registryKeys = @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\Software\WOW6432Node\Valve\Steam',
        'HKLM:\Software\Valve\Steam'
    )

    foreach ($key in $registryKeys) {
        try {
            $item = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            foreach ($property in @('SteamPath', 'InstallPath')) {
                $value = $item.$property
                if ($value -and (Test-Path -LiteralPath $value)) {
                    $full = [IO.Path]::GetFullPath($value)
                    if (-not $roots.Contains($full)) { $null = $roots.Add($full) }
                }
            }
        } catch { }
    }

    return $roots.ToArray()
}

function Get-SteamLibraries {
    $libraries=New-StringList
    foreach($root in (Get-SteamRoots)){
        if(-not $libraries.Contains($root)){$libraries.Add($root)}
        $file=Join-Path $root 'steamapps/libraryfolders.vdf'
        if(Test-Path -LiteralPath $file){
            foreach($match in [regex]::Matches([IO.File]::ReadAllText($file),'(?im)^\s*"path"\s*"((?:\\.|[^"])*)"')){
                $path=ConvertFrom-VdfEscapedString $match.Groups[1].Value
                if($path -and -not $libraries.Contains($path)){$libraries.Add($path)}
            }
        }
    }
    return $libraries.ToArray()
}
function Get-GameContext {
    param([string]$Path)
    $directory=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    if([IO.File]::Exists($directory)){$directory=Split-Path $directory -Parent}
    $file=Join-Path $directory 'gameinfo.txt'
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw "gameinfo.txt was not found: $directory"}
    $document=ConvertFrom-KeyValuesText ([IO.File]::ReadAllText($file)) $file
    $root=Find-KvRoot $document 'GameInfo'
    $paths=Find-KvChild (Find-KvChild $root 'FileSystem') 'SearchPaths'
    if(-not $paths){throw "No SearchPaths in gameinfo.txt: $directory"}
    $install=Split-Path $directory -Parent
    $custom=$null
    foreach($entry in $paths.Children){
        if(($entry.Key -split '\+') -notcontains 'game' -and ($entry.Key -split '\+') -notcontains 'vgui'){continue}
        $expanded=Expand-GameSearchPath $entry.Value $directory $install
        if($expanded.Replace('\','/').TrimEnd('/') -ieq ((Join-Path $directory 'custom').Replace('\','/')+'/*')){$custom=Join-Path $directory 'custom';break}
    }
    if(-not $custom){throw "This game does not declare a game/VGUI custom/* search path: $directory"}
    $name=Find-KvChild $root 'game';$app=Find-KvChild (Find-KvChild $root 'FileSystem') 'SteamAppId'
    return [pscustomobject]@{GameDirectory=$directory;InstallDirectory=$install;SearchPaths=$paths.Children;CustomDirectory=$custom;SteamAppId=if($app){$app.Value}else{''};Name=if($name){$name.Value}else{Split-Path $directory -Leaf}}
}
function Expand-GameSearchPath {
    param([string]$Value,[string]$GameDirectory,[string]$InstallDirectory)
    $path=$Value.Replace('|gameinfo_path|',$GameDirectory+'\').Replace('|all_source_engine_paths|',$InstallDirectory+'\')
    if($path -match '\|appid_(\d+)\|'){
        $token=$Matches[0];$appId=$Matches[1];$mounted=$null
        foreach($library in (Get-SteamLibraries)){
            $manifest=Join-Path $library "steamapps/appmanifest_$appId.acf"
            if(Test-Path -LiteralPath $manifest){
                $match=[regex]::Match([IO.File]::ReadAllText($manifest),'"installdir"\s*"([^"]+)"')
                if($match.Success){$mounted=Join-Path $library ('steamapps/common/'+$match.Groups[1].Value);break}
            }
        }
        if(-not $mounted){throw "Mounted Steam application $appId could not be located."}
        $path=$path.Replace($token,$mounted+'\')
    }
    if($path -match '\|'){throw "Unsupported gameinfo search path token: $Value"}
    if(-not [IO.Path]::IsPathRooted($path)){$path=Join-Path $InstallDirectory $path}
    if($path -match '[*?]'){
        $wildcard=Split-Path $path -Leaf;$parent=Split-Path $path -Parent
        if($parent -match '[*?]'){throw "Unsupported nested wildcard in search path: $Value"}
        return Join-Path ([IO.Path]::GetFullPath($parent)) $wildcard
    }
    return [IO.Path]::GetFullPath($path)
}
function Find-SourceGames {
    $results=New-StringList
    foreach($library in (Get-SteamLibraries)){
        $common=Join-Path $library 'steamapps/common'
        foreach($install in @(Get-ChildItem -LiteralPath $common -Directory -ErrorAction SilentlyContinue)){
            foreach($directory in (@($install)+@(Get-ChildItem -LiteralPath $install.FullName -Directory -ErrorAction SilentlyContinue))){
                Test-WorkCancellation
                if(-not (Test-Path -LiteralPath (Join-Path $directory.FullName 'gameinfo.txt'))){continue}
                try{$context=Get-GameContext $directory.FullName;if(-not $results.Contains($context.GameDirectory)){$results.Add($context.GameDirectory)}}catch{}
            }
        }
        foreach($directory in @(Get-ChildItem -LiteralPath (Join-Path $library 'steamapps/sourcemods') -Directory -ErrorAction SilentlyContinue)){
            try{$context=Get-GameContext $directory.FullName;if(-not $results.Contains($context.GameDirectory)){$results.Add($context.GameDirectory)}}catch{}
        }
    }
    return $results.ToArray()
}
function Find-DefaultGamePath {
    # Default startup needs only app 440, not a walk through every installed game.
    foreach($library in (Get-SteamLibraries)){
        Test-WorkCancellation
        $candidates=New-StringList
        $manifest=Join-Path $library 'steamapps/appmanifest_440.acf'
        if([IO.File]::Exists($manifest)){
            $match=[regex]::Match([IO.File]::ReadAllText($manifest),'"installdir"\s*"((?:\\.|[^"\\])+)"')
            if($match.Success){
                $install=ConvertFrom-VdfEscapedString $match.Groups[1].Value
                $candidates.Add((Join-Path $library ('steamapps/common/'+$install+'/tf')))
            }
        }
        $candidates.Add((Join-Path $library 'steamapps/common/Team Fortress 2/tf'))
        foreach($candidate in $candidates){
            Test-WorkCancellation
            if(-not [IO.File]::Exists((Join-Path $candidate 'gameinfo.txt'))){continue}
            try{
                $context=Get-GameContext $candidate
                if($context.SteamAppId -eq '440'){return $context.GameDirectory}
            }catch [OperationCanceledException]{throw}catch{}
        }
    }
    return $null
}
function Resolve-GamePath {
    param([string]$RequestedPath)
    if($RequestedPath){
        $candidate=[IO.Path]::GetFullPath($RequestedPath)
        if((Test-Path -LiteralPath $candidate -PathType Leaf) -or (Test-Path -LiteralPath (Join-Path $candidate 'gameinfo.txt'))){return (Get-GameContext $candidate).GameDirectory}
        $found=New-StringList
        foreach($child in @(Get-ChildItem -LiteralPath $candidate -Directory -ErrorAction SilentlyContinue)){
            if(Test-Path -LiteralPath (Join-Path $child.FullName 'gameinfo.txt')){
                try{$found.Add((Get-GameContext $child.FullName).GameDirectory)}catch{}
            }
        }
        if($found.Count -eq 1){return $found[0]}
        if($found.Count -gt 1){throw 'Multiple game directories found. Select the directory containing the desired gameinfo.txt.'}
        throw "No supported Source game directory was found: $RequestedPath"
    }
    $layout=Read-LayoutPreferences
    if($layout.GamePath){try{return (Get-GameContext $layout.GamePath).GameDirectory}catch{}}
    $default=Find-DefaultGamePath
    if($default){return $default}
    Set-WorkStatus 'Locating Source games'
    $found=@(Find-SourceGames)
    if(-not $found.Count){throw 'No supported Source games found. Choose a directory containing gameinfo.txt.'}
    foreach($directory in $found){if((Get-GameContext $directory).SteamAppId -eq '440'){return $directory}}
    return $found[0]
}
function Test-ProcessPathMatch {
    param([string]$ProcessPath,[string]$GameDirectory,[string]$InstallDirectory)
    if(-not $ProcessPath){return $false}
    $path=$ProcessPath.Replace('/','\').ToLowerInvariant()
    foreach($directory in @($GameDirectory,$InstallDirectory)){
        if(-not $directory){continue}
        $prefix=$directory.Replace('/','\').TrimEnd('\').ToLowerInvariant()+'\'
        if($path.StartsWith($prefix)){return $true}
    }
    return $false
}
function Find-GameProcessList {
    param([string]$GameDirectory,[string]$InstallDirectory)
    $result=@()
    foreach($process in [Diagnostics.Process]::GetProcesses()){
        $path=$null
        try{$path=$process.MainModule.FileName}catch{}
        if(Test-ProcessPathMatch $path $GameDirectory $InstallDirectory){$result+=$process;continue}
        $process.Dispose()
    }
    return $result
}
function Find-GameExecutable {
    param([string]$InstallDirectory)
    foreach($name in @('hl2.exe','tf.exe','tf_win64.exe','hl1.exe','bms.exe','swarm.exe')){
        $candidate=Join-Path $InstallDirectory $name
        if([IO.File]::Exists($candidate)){return $candidate}
    }
    $fallbacks=@()
    foreach($file in @(Get-ChildItem -LiteralPath $InstallDirectory -Filter '*.exe' -File -ErrorAction SilentlyContinue)){
        if($file.Name -imatch '^(steam|vpk|uninstall|uninst|setup|update|crash|hl2_launcher)'){continue}
        $fallbacks+=$file.FullName
    }
    if($fallbacks.Count -eq 1){return $fallbacks[0]}
    return $null
}
function Restart-GameProcess {
    param([string]$GamePath)
    $context=Get-GameContext $GamePath
    $running=@(Find-GameProcessList $context.GameDirectory $context.InstallDirectory)
    foreach($process in $running){
        try{
            Write-VfcLog 'INFO' "Stopping game process: pid=$($process.Id); name=$($process.ProcessName)"
            if($process.HasExited){continue}
            $null=$process.CloseMainWindow()
            if(-not $process.WaitForExit(3000)){$process.Kill()}
        }catch{Write-VfcLog 'WARN' "Could not stop game process pid=$($process.Id): $($_.Exception.Message)"}finally{$process.Dispose()}
    }
    if($running.Count){Write-VfcLog 'INFO' "Game processes stopped: count=$($running.Count)"}
    if($context.SteamAppId){
        $start=New-Object Diagnostics.ProcessStartInfo
        $start.FileName='steam://rungameid/'+$context.SteamAppId
        $start.UseShellExecute=$true
        $null=[Diagnostics.Process]::Start($start)
        Write-VfcLog 'INFO' "Game start requested through Steam: appid=$($context.SteamAppId)"
        return
    }
    $executable=Find-GameExecutable $context.InstallDirectory
    if($executable){
        $start=New-Object Diagnostics.ProcessStartInfo
        $start.FileName=$executable;$start.WorkingDirectory=$context.InstallDirectory;$start.UseShellExecute=$true
        $null=[Diagnostics.Process]::Start($start)
        Write-VfcLog 'INFO' "Game started: exe=$executable"
    }else{
        Write-VfcLog 'WARN' 'Game start skipped: no executable was found in the install directory.'
    }
}
