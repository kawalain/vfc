function Get-PreviewFont {
    param($Cache,[string]$Name,[hashtable]$PrivateFamilies,[double]$Factor=1.0,[single]$BasePixels=0)
    $cacheKey=$Name; if($Factor -ne 1.0){$cacheKey=$Name+'|'+$Factor.ToString('0.0',[Globalization.CultureInfo]::InvariantCulture)}
    $previewSize=[single](11.0*$Factor)
    $unit=[Drawing.GraphicsUnit]::Point
    if($BasePixels -gt 0){$previewSize=[single]($BasePixels*$Factor);$unit=[Drawing.GraphicsUnit]::Pixel;$cacheKey=$Name+'|px|'+$previewSize.ToString('0.######',[Globalization.CultureInfo]::InvariantCulture)}
    if(-not $Cache.ContainsKey($cacheKey)){
        try{
            if($PrivateFamilies -and $PrivateFamilies.ContainsKey($Name)){
                $family=$PrivateFamilies[$Name]
                $style=[Drawing.FontStyle]::Regular
                foreach($candidate in @([Drawing.FontStyle]::Regular,[Drawing.FontStyle]::Bold,[Drawing.FontStyle]::Italic,[Drawing.FontStyle]3)){
                    if($family.IsStyleAvailable($candidate)){$style=$candidate;break}
                }
                $Cache[$cacheKey]=[Drawing.Font]::new([Drawing.FontFamily]$family,$previewSize,[Drawing.FontStyle]$style,$unit)
            }else{$Cache[$cacheKey]=[Drawing.Font]::new($Name,$previewSize,[Drawing.FontStyle]::Regular,$unit)}
        }
        catch{$Cache[$cacheKey]=[Drawing.Font]::new([Drawing.SystemFonts]::MessageBoxFont.FontFamily,$previewSize,[Drawing.FontStyle]::Regular,$unit)}
    }
    return $Cache[$cacheKey]
}
function Test-PreviewFontAvailable {
    param([string]$Name,[hashtable]$PrivateFamilies)
    if($PrivateFamilies -and $PrivateFamilies.ContainsKey($Name)){return $true}
    # Font.Name may be English even when the localized name resolved correctly.
    # FontFamily throws for unknown names; Font silently substitutes instead.
    try{$family=New-Object Drawing.FontFamily($Name); $family.Dispose(); return $true}catch{return $false}
}
