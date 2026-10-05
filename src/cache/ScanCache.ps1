function Get-ScanCacheDirectory {
    param([string]$Game,[string]$Mod)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$id=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($Game+'|'+$Mod).ToLowerInvariant()))).Replace('-','')}finally{$sha.Dispose()}
    return Join-Path (Join-Path (Get-SettingsRoot) 'scan-cache') $id
}
function Get-ContentSha256 {
    param([byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','')}finally{$sha.Dispose()}
}
function Get-ScanInputFingerprint {
    param([object[]]$Sources,[string]$Path,[hashtable]$Fingerprints)
    if($Fingerprints.ContainsKey($Path)){return $Fingerprints[$Path]}
    Test-WorkCancellation;Set-WorkStatus ('Verifying '+$Path)
    $file=Read-VirtualFile $Sources $Path -Binary
    $value=if($null -eq $file){@{Sha256='missing';Source=''}}else{@{Sha256=(Get-ContentSha256 $file.Bytes);Source=$file.Source}}
    Write-VfcLog 'DEBUG' "Input fingerprint: virtual=$Path; winner=$($value.Source); sha256=$($value.Sha256)"
    $Fingerprints[$Path]=$value;return $value
}
function Initialize-ScanCacheRuntime {
    if('VfcScanCacheReader' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
public sealed class VfcCachedKvNode {
    public string Key,Value,Source,Condition;
    public bool HasValue;
    public int Line;
    public List<object> Children=new List<object>();
}
public sealed class VfcCachedScheme {
    public List<object> Nodes=new List<object>();
    public string Entry,VirtualPath;
    public string[] Dependencies,Inputs;
}
public static class VfcScanCacheReader {
    static object Unwrap(object value) {
        PSObject wrapped=value as PSObject;
        return wrapped==null ? value : wrapped.BaseObject;
    }
    static VfcCachedKvNode Copy(object value,int depth) {
        if(depth>100) throw new ArgumentException("Invalid node depth");
        var wrapper=value as PSObject;
        var native=(wrapper==null ? value : wrapper.BaseObject) as VfcCachedKvNode;
        if(native!=null) {
            var result=new VfcCachedKvNode {Key=native.Key,Value=native.Value,Source=native.Source,
                Condition=native.Condition,HasValue=native.HasValue,Line=native.Line};
            foreach(var child in native.Children) result.Children.Add(Copy(child,depth+1));
            return result;
        }
        var node=PSObject.AsPSObject(value);
        var copy=new VfcCachedKvNode {Key=LanguagePrimitives.ConvertTo<string>(node.Properties["Key"].Value),
            Value=LanguagePrimitives.ConvertTo<string>(node.Properties["Value"].Value),Source=LanguagePrimitives.ConvertTo<string>(node.Properties["Source"].Value),
            Condition=LanguagePrimitives.ConvertTo<string>(node.Properties["Condition"].Value),HasValue=LanguagePrimitives.ConvertTo<bool>(node.Properties["HasValue"].Value),
            Line=LanguagePrimitives.ConvertTo<int>(node.Properties["Line"].Value)};
        foreach(var child in (IEnumerable)Unwrap(node.Properties["Children"].Value)) copy.Children.Add(Copy(child,depth+1));
        return copy;
    }
    static string[] Strings(object value) {
        var result=new List<string>();
        foreach(var item in (IEnumerable)Unwrap(value)) result.Add(LanguagePrimitives.ConvertTo<string>(item));
        return result.ToArray();
    }
    public static VfcCachedScheme Clone(object value) {
        var document=PSObject.AsPSObject(value);
        var result=new VfcCachedScheme {Entry=LanguagePrimitives.ConvertTo<string>(document.Properties["Entry"].Value),
            VirtualPath=LanguagePrimitives.ConvertTo<string>(document.Properties["VirtualPath"].Value),
            Dependencies=Strings(document.Properties["Dependencies"].Value),Inputs=Strings(document.Properties["Inputs"].Value)};
        foreach(var node in (IEnumerable)Unwrap(document.Properties["Nodes"].Value)) result.Nodes.Add(Copy(node,0));
        return result;
    }
}
'@
}
function Read-CachedScheme {
    param([object[]]$Sources,[string]$Path,$Entry,[string]$Directory,[hashtable]$Fingerprints)
    if(-not $Entry){return}
    try{
        if($Entry.AstHash -notmatch '^[A-F0-9]{64}$' -or -not $Entry.Inputs.ContainsKey($Path)){return}
        foreach($inputPath in $Entry.Inputs.Keys){
            $actual=Get-ScanInputFingerprint $Sources $inputPath $Fingerprints
            $expected=$Entry.Inputs[$inputPath]
            if($actual.Sha256 -cne $expected.Sha256 -or $actual.Source -ine $expected.Source){return}
        }
        $astPath=Join-Path $Directory ($Entry.AstHash+'.json')
        $bytes=[IO.File]::ReadAllBytes($astPath)
        if((Get-ContentSha256 $bytes) -cne $Entry.AstHash){return}
        Initialize-ScanCacheRuntime
        $stored=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
        $cached=[VfcScanCacheReader]::Clone($stored)
        if($cached.VirtualPath -ine $Path){return}
        return $cached
    }catch{Test-WorkCancellation;return}
}
function Save-ScanCache {
    param([object[]]$Sources,$Documents,[string]$Directory,[hashtable]$Fingerprints,[hashtable]$OldEntries)
    Test-WorkCancellation
    try{
        $null=[IO.Directory]::CreateDirectory($Directory)
        $entries=@{}
        foreach($document in $Documents){
            Test-WorkCancellation
            $inputs=@{}
            foreach($inputPath in $document.Inputs){$inputs[$inputPath]=Get-ScanInputFingerprint $Sources $inputPath $Fingerprints}
            if($OldEntries.ContainsKey($document.VirtualPath)){
                $entries[$document.VirtualPath]=$OldEntries[$document.VirtualPath];continue
            }
            $text=$document|ConvertTo-Json -Depth 100 -Compress
            $bytes=[Text.Encoding]::UTF8.GetBytes($text);$hash=Get-ContentSha256 $bytes
            $astPath=Join-Path $Directory ($hash+'.json')
            # Content-addressed AST files are immutable; publish the manifest last.
            if(-not [IO.File]::Exists($astPath) -or (Get-ContentSha256 ([IO.File]::ReadAllBytes($astPath))) -cne $hash){[IO.File]::WriteAllBytes($astPath,$bytes)}
            $entries[$document.VirtualPath]=@{AstHash=$hash;Inputs=$inputs}
        }
        $manifest=@{Version=1;Documents=$entries;Files=$Fingerprints}
        Write-SettingsFile (Join-Path $Directory 'index.json') $manifest
    }catch{Test-WorkCancellation;Write-Warning ('Could not save scan cache: '+$_.Exception.Message)}
}
