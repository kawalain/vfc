function Get-InstalledFontFamilies {
    Add-Type -AssemblyName System.Drawing
    $collection = New-Object Drawing.Text.InstalledFontCollection
    try { return @($collection.Families | ForEach-Object Name | Sort-Object -Unique) }
    finally { $collection.Dispose() }
}

function Test-WindowsFont {
    param([string]$Family)
    if (-not ('VguiFontProbe' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class VguiFontProbe {
 [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] static extern IntPtr CreateFontW(int h,int w,int e,int o,int weight,uint italic,uint underline,uint strike,uint charset,uint output,uint clip,uint quality,uint pitch,string face);
 [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
 [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc,IntPtr obj);
 [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] static extern int GetTextFaceW(IntPtr dc,int count,StringBuilder name);
 [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] static extern uint GetGlyphIndicesW(IntPtr dc,string text,int count,[Out] ushort[] glyphs,uint flags);
 [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
 [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
 public static string[] Probe(string name) {
  IntPtr dc=CreateCompatibleDC(IntPtr.Zero), font=CreateFontW(-24,0,0,0,400,0,0,0,1,0,0,4,0,name), old=SelectObject(dc,font);
  try { var face=new StringBuilder(128); GetTextFaceW(dc,128,face); string sample="Ag\uac00\ud55c\ud7a3"; var glyphs=new ushort[sample.Length]; uint status=GetGlyphIndicesW(dc,sample,sample.Length,glyphs,1); var missing=new StringBuilder(); for(int i=0;i<sample.Length;i++) if(glyphs[i]==65535) missing.Append(sample[i]); return new[]{face.ToString(),status==0xffffffff?"GDI error":missing.ToString()}; }
  finally { SelectObject(dc,old); DeleteObject(font); DeleteDC(dc); }
 }
}
'@
    }
    $probe = [VguiFontProbe]::Probe($Family)
    $canonical=Get-CanonicalFontName $Family
    [pscustomobject]@{ Requested=$Family; CanonicalFamily=$canonical; GdiFace=$probe[0]; ExactMatch=($canonical -ieq (Get-CanonicalFontName $probe[0])); MissingGlyphs=$probe[1]; Charset='DEFAULT_CHARSET (GDI probe only)' }
}

function Invoke-FontDiagnosis {
    param([string]$GamePath, [string]$Family)
    $engineFamily=Get-CanonicalFontName $Family
    $sources = @(Get-SearchSources $GamePath '__include_generated__')
    $files = foreach ($name in $script:SchemeNames) {
        $file = Read-VirtualFile $sources "resource/$name"
        if ($file) {
            $doc = ConvertFrom-KeyValuesText $file.Text $file.Source
            $doc | Add-Member NoteProperty VirtualPath $name
            $records = @(Get-FontRecords @($doc))
            $custom=Find-KvChild (Find-KvRoot $doc 'Scheme') 'CustomFontFiles'
            $registrations=@()
            if($custom){
                foreach($entry in $custom.Children){
                    $registeredName=Find-KvChild $entry 'name'
                    if($registeredName -and $registeredName.Value -eq $engineFamily){
                        $registeredFile=Find-KvChild $entry 'font'
                        $korean=Find-KvChild $entry 'koreana'
                        $koreanRange=$null; if($korean){$koreanRange=Find-KvChild $korean 'range'}
                        $rangeValue=$null; if($koreanRange){$rangeValue=$koreanRange.Value}
                        $registrations += [pscustomobject]@{File=$registeredFile.Value;KoreanRange=$rangeValue;FileFound=($null -ne (Read-VirtualFile $sources $registeredFile.Value))}
                    }
                }
            }
            $requestedRecords=@($records | Where-Object Font -eq $engineFamily)
            $bypassCount=@($requestedRecords | Where-Object {$flag=Find-KvChild $_.GlyphSetNode 'custom'; $flag -and $flag.Value -eq '1'}).Count
            [pscustomobject]@{ Scheme=$name; Winner=$file.Source; Definitions=$records.Count; RequestedFontCount=$requestedRecords.Count; AsianFallbackBypassCount=$bypassCount; CustomFontRegistrations=$registrations; LegacyGlyphSetRangeCount=@($records | Where-Object { $range=Find-KvChild $_.GlyphSetNode 'range'; $range -and $range.Value -eq '0x0000 0x017F' }).Count }
        }
    }
    $fontFiles = @()
    foreach ($key in @('HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts','HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts')) {
        if (Test-Path $key) {
            $props = (Get-ItemProperty $key).PSObject.Properties
            foreach ($prop in $props) {
                if ($prop.Name -like "$Family*") {
                    $path=[string]$prop.Value
                    if (-not [IO.Path]::IsPathRooted($path)) { $path=Join-Path "$env:WINDIR/Fonts" $path }
                    if (Test-Path -LiteralPath $path) {
                        $bytes=[IO.File]::ReadAllBytes($path); $variable=$false
                        $tables=($bytes[4]*256)+$bytes[5]
                        for($i=0;$i -lt $tables;$i++) { if([Text.Encoding]::ASCII.GetString($bytes,12+16*$i,4) -eq 'fvar'){$variable=$true} }
                        $fontFiles += [pscustomobject]@{ Path=$path; Variable=$variable }
                    }
                }
            }
        }
    }
    $resolvedFontFile=Get-FontFile $engineFamily
    if($resolvedFontFile -and @($fontFiles | Where-Object Path -eq $resolvedFontFile).Count -eq 0){
        $fontFiles += [pscustomobject]@{Path=$resolvedFontFile;Variable=(Test-VariableFontFile $resolvedFontFile)}
    }
    $backend='engine default'; $backendSource=$null
    $backendFile=Read-VirtualFile $sources 'resource/FontInfo.kv'
    if($backendFile){
        $backendSource=$backendFile.Source
        $backendDoc=ConvertFrom-KeyValuesText $backendFile.Text $backendFile.Source
        $setting=Find-KvChild (Find-KvRoot $backendDoc 'FontInfo') $engineFamily
        if($setting){$backend=$setting.Value}
    }
    $report=[pscustomobject]@{ Font=(Test-WindowsFont $Family); FontFiles=$fontFiles; FontBackend=$backend; FontBackendSource=$backendSource; Schemes=@($files); GameRunning=@(Get-Process tf_win64,tf,hl2 -ErrorAction SilentlyContinue).Count -gt 0; Note='File winner is a startup filesystem prediction. Use the game console path and restart to confirm the live mount. Variable-font axes and actual engine rendering are not proven by this GDI probe.' }
    $report | ConvertTo-Json -Depth 6
}
