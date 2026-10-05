function Get-SettingsRoot { return Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'VGUIFontChanger' }
function Get-ProfilePath {
    param([string]$Game)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$id=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Game.ToLowerInvariant())))).Replace('-','').Substring(0,16)}finally{$sha.Dispose()}
    return Join-Path (Get-SettingsRoot) ("settings-$id.json")
}
function Read-FontProfile {
    param([string]$Game)
    $path=Get-ProfilePath $Game
    if(Test-Path -LiteralPath $path){return ([IO.File]::ReadAllText($path)|ConvertFrom-Json)}
    if(Test-Path -LiteralPath (Join-Path $Game 'gameinfo.txt')){
        $oldProfile=Get-ProfilePath (Split-Path $Game -Parent)
        if(Test-Path -LiteralPath $oldProfile){return ([IO.File]::ReadAllText($oldProfile)|ConvertFrom-Json)}
    }
    $legacy=Join-Path $Game 'custom/!fonts/font-settings.json'
    if(Test-Path -LiteralPath $legacy){
        $old=[IO.File]::ReadAllText($legacy)|ConvertFrom-Json
        $profile=[pscustomobject]@{Fonts=$old.Fonts;Factors=[pscustomobject]@{}}
        Save-FontProfile $Game $profile
        $archive=Join-Path (Get-SettingsRoot) ('legacy-settings-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff')+'.json')
        Move-Item -LiteralPath $legacy -Destination $archive
        return $profile
    }
    return [pscustomobject]@{Fonts=[pscustomobject]@{};Factors=[pscustomobject]@{}}
}
function Save-FontProfile {
    param([string]$Game,$Profile)
    $root=Get-SettingsRoot
    $null=[IO.Directory]::CreateDirectory($root)
    Write-SettingsFile (Get-ProfilePath $Game) $Profile
}
function Write-SettingsFile {
    param([string]$Path,$Profile)
    $target=[IO.Path]::GetFullPath($Path)
    $temporary=Join-Path (Split-Path $target -Parent) ('.settings-'+[Guid]::NewGuid().ToString('N')+'.tmp')
    try{
        [IO.File]::WriteAllText($temporary,($Profile|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)))
        if([IO.File]::Exists($target)){[IO.File]::Replace($temporary,$target,[NullString]::Value)}else{[IO.File]::Move($temporary,$target)}
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
