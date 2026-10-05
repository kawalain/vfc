#requires -Version 5.1
[CmdletBinding()]
param(
    [switch] $Cli,
    [string] $GamePath,
    [string] $DefaultFont,
    [string[]] $Replace,
    [switch] $ListFonts,
    [switch] $DryRun,
    [switch] $LaunchGame,
    [switch] $ShowDuplicates,
    [switch] $ShowSymbols,
    [switch] $Diagnose,
    [string] $TestFont = 'Pretendard GOV Variable',
    [int] $DefaultSize,
    [string[]] $Size,
    [string[]] $Factor,
    [switch] $SelfTest,
    [string] $Locale,
    [string] $OutputModName = '!VGUIFontChanger',
    [switch] $NoRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
# Release version, SemVer with the major pinned to 0 while pre-1.0: features
# bump the minor, fixes bump the patch. Build.ps1 injects the short commit
# hash of the built revision into $script:VfcCommit.
$script:VfcVersion = '0.2.0'
$script:VfcCommit = ''
# Project home page; the About title links here and the version links to the
# built revision's commit page.
$script:VfcRepository = 'https://github.com/kawalain/vfc'
# Invoke-Expression binds this optional parameter to an empty string. ValidateSet
# rejects that before startup; validate only explicitly supplied locale values.
if ($Locale -and $Locale -notin @('en-US','ko-KR')) { throw 'Locale must be en-US or ko-KR.' }

$script:VpkIndexCache = @{}
$script:VpkToolIndexCache = @{}
$script:SchemeNames = @('ClientScheme.res', 'SourceScheme.res', 'ChatScheme.res')
$script:SymbolFontPattern = '(?i)(marlett|webdings|wingdings|symbol|icons?|glyph|buttons?|crosshairs?|halflife2)'
$script:Work = $null
$script:GameFontPaths = @{}
$script:LogPath = ''
$script:VfcLogLevel = 'INFO'
$script:SymbolAliasPattern = '(?i)(icon|glyph|button|crosshair)'
