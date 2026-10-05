function Invoke-VguiSelfTest {
    Invoke-TimerSelfTest
    Invoke-HierarchySelfTest
    Invoke-VpkIndexSelfTest
    Invoke-SourceGameSelfTest
    Invoke-PortableSelfTest
    $layoutTestRoot=Join-Path ([IO.Path]::GetTempPath()) ('VGUIFontChanger-layout-test-'+[Guid]::NewGuid().ToString('N'))
    try{
        $null=[IO.Directory]::CreateDirectory($layoutTestRoot)
        [IO.File]::WriteAllText((Join-Path $layoutTestRoot 'ui.json'),'{"Locale":"ko-KR","Theme":"Dark","Symbols":true}')
        $layout=Read-LayoutPreferences $layoutTestRoot
        if($layout.Locale -ne 'ko-KR' -or $layout.Theme -ne 'Dark' -or $layout.ListZoom -ne 1){throw 'Legacy UI preferences migration failed'}
        $layout.ListZoom=1.4;Save-GuiPreferences $layout $layoutTestRoot
        $loaded=Read-LayoutPreferences $layoutTestRoot
        if($loaded.ListZoom -ne 1.4 -or $loaded.Locale -ne 'ko-KR' -or -not $loaded.Symbols){throw 'Layout settings round-trip failed'}
        $saved=[IO.File]::ReadAllText((Join-Path $layoutTestRoot 'layout.json'))|ConvertFrom-Json
        if($saved.PSObject.Properties.Name -contains 'Nodes'){throw 'Game values leaked into layout file'}
    }finally{
        foreach($name in @('layout.json','ui.json')){$testFile=Join-Path $layoutTestRoot $name;if([IO.File]::Exists($testFile)){[IO.File]::Delete($testFile)}}
        if([IO.Directory]::Exists($layoutTestRoot)){[IO.Directory]::Delete($layoutTestRoot)}
    }
    if(-not (Test-DedicatedGuiLaunch @('powershell.exe','-File','C:\test\VGUIFontChanger.ps1'))){throw 'Dedicated GUI launch detection failed'}
    if(-not (Test-DedicatedGuiLaunch @('powershell.exe','-Command',"& 'C:\test\VGUIFontChanger.ps1'"))){throw 'Explorer GUI launch detection failed'}
    if(-not (Test-DedicatedGuiLaunch @('pwsh.exe','-File','C:\test\VGUIFontChanger.ps1'))){throw 'PowerShell 7 GUI launch detection failed'}
    foreach($launchArguments in @(@('powershell.exe'),@('pwsh.exe'),@('powershell.exe','-NoExit','-File','VGUIFontChanger.ps1'),@('pwsh.exe','-NoExit','-File','VGUIFontChanger.ps1'),@('powershell.exe','-File','Other.ps1'),@('powershell.exe','-Command','-'))){
        if(Test-DedicatedGuiLaunch $launchArguments){throw 'Interactive console protection failed'}
    }
    $fixture=ConvertFrom-KeyValuesText '"Scheme" { "Fonts" { "Text" { "1" { "name" "Verdana" "tall" "10" "tall_lodef" "12" "tall_hidef" "14" } "2" { "name" "Verdana" "tall" "20" } } "Icon" { "1" { "name" "Marlett" "tall" "12" } } "Bitmap" { "1" { "name" "Buttons" "bitmap" "1" "scalex" "1.5" "scaley" "2" } } } }' 'fixture'
    $fixture | Add-Member NoteProperty VirtualPath 'resource/ClientScheme.res'
    $fixture | Add-Member NoteProperty Entry 'fixture'
    $fixture | Add-Member NoteProperty Dependencies @('fixture')
    $originalFunction=(Get-Command Get-ResolvedSchemes).ScriptBlock
    $script:Fixture=$fixture
    try{
        Set-Item Function:Get-ResolvedSchemes {
            param($GamePath,$OutputModName)
            $list=New-ObjectList; $list.Add($script:Fixture)
            [pscustomobject]@{Documents=$list;Sources=@()}
        }
        $map=ConvertTo-ReplacementMap @('Verdana=Tahoma')
        $r=Invoke-FontBuild '.' '!fonts' $map $null -WhatIf -FactorMap @{Verdana=1.5;Buttons=2.0}
        $text=ConvertTo-KeyValuesText $fixture @{}
        if($r.Changed -ne 2 -or $text -notmatch '"tall"\s+"15"' -or $text -notmatch '"tall"\s+"30"' -or $text -notmatch '"name"\s+"Marlett"'){throw 'Factor/font preservation self-test failed'}
        if($text -notmatch '"scalex"\s+"3"' -or $text -notmatch '"scaley"\s+"4"'){throw 'Bitmap factor test failed'}
        if($text -notmatch '"tall_lodef"\s+"18"' -or $text -notmatch '"tall_hidef"\s+"21"'){throw 'Resolution-specific factor test failed'}
        if($text -notmatch '"koreana"' -or $text -match '"korean"' -or $text -notmatch '"font"\s+"resource/fonts/vguifontchanger/'){throw 'Custom font registration self-test failed'}
        $textRecords=@(Get-FontRecords @($fixture) | Where-Object Kind -eq 'Text')
        foreach($record in $textRecords){
            if((Find-KvChild $record.VariantNode 'custom').Value -ne '0'){throw 'Asian fallback preservation test failed'}
            $registration=(Find-KvChild (Find-KvRoot $fixture 'Scheme') 'CustomFontFiles').Children | Where-Object {(Find-KvChild $_ 'name').Value -eq $record.Node.Value} | Select-Object -First 1
            $range=Find-KvChild (Find-KvChild $registration 'koreana') 'range'
            $bounds=$range.Value -split '\s+'
            $lower=[Convert]::ToInt32($bounds[0],16); $upper=[Convert]::ToInt32($bounds[1],16)
            foreach($codePoint in @(0x1100,0x3131,0xAC00,0xD7A3)){if($codePoint -lt $lower -or $codePoint -gt $upper){throw 'Hangul range coverage test failed'}}
        }
        foreach($fontPair in @(@('바탕','Batang'),@('바탕체','BatangChe'),@('맑은 고딕','Malgun Gothic'),@('ONE 모바일POP OTF','ONE Mobile POP OTF'))){
            $fontName=$fontPair[0]
            if(-not (Test-PreviewFontAvailable $fontPair[1] @{})){continue}
            if(-not (Test-PreviewFontAvailable $fontName @{})){throw ('Localized font availability test failed: '+$fontName)}
            $canonical=Get-CanonicalFontName $fontName
            if($canonical -eq $fontName -or -not (Get-FontFile $canonical)){throw ('Localized name / collection file resolution failed: '+$fontName)}
        }
        if(Test-PreviewFontAvailable 'Monatendard Nerd Font Mono' @{}){
            $fontPath=Get-FontFile 'Monatendard Nerd Font Mono'
            if(-not $fontPath){throw 'Registry style label / internal family resolution failed'}
            $collection=New-Object Drawing.Text.PrivateFontCollection
            try{
                $collection.AddFontFile($fontPath)
                if(@($collection.Families | Where-Object {$_.GetName(1033) -eq 'Monatendard Nerd Font Mono'}).Count -eq 0){throw 'Resolved file has a different internal font family'}
            }finally{foreach($font in $collection.Families){$font.Dispose()};$collection.Dispose()}
        }
        foreach($language in @('en-US','ko-KR')){
            if((Get-UiText 'Apply' $language) -match 'TF2'){throw 'Game-specific UI string test failed'}
            $context=Get-NumberedContext "first`nname Tahoma`nthird" 2
            if($context.Text.Substring($context.Offset,$context.Length) -notmatch '2\s+name Tahoma'){throw 'Numbered context test failed'}
            $usage=[pscustomobject]@{Font='Tahoma';Locations=@([pscustomobject]@{Source='fixture';Line=2;Alias='Text';Variant='1';Scheme='fixture';Context=$context})}
            Show-FontUsesWindow $null $usage $language -SmokeTest
            $Locale=$language; Show-VguiFontGui -SmokeTest
        }
        $variablePath=Get-FontFile 'Pretendard GOV Variable'
        if($variablePath -and (Test-VariableFontFile $variablePath)){
            $backend=New-FontBackendDocument @() @{'Pretendard GOV Variable'=[pscustomobject]@{Path=$variablePath}}
            if((Find-KvChild (Find-KvRoot $backend 'FontInfo') 'Pretendard GOV Variable').Value -ne 'freetype2'){throw 'Variable font backend selection test failed'}
        }
        $script:Work=[hashtable]::Synchronized(@{Cancel=$true;CanCancel=$true;Message=''})
        $cancelled=$false
        try{Test-WorkCancellation}catch [OperationCanceledException]{$cancelled=$true}
        if(-not $cancelled){throw 'Cancellation test failed'}
        $script:Work=$null
        $logFile=Join-Path ([IO.Path]::GetTempPath()) ('VGUIFontChanger-logtest-'+[Guid]::NewGuid().ToString('N')+'.log')
        $previousLogLevel=$script:VfcLogLevel;$script:VfcLogLevel='WARN'
        try{
            Write-VfcLog 'DEBUG' 'debug suppressed' -LogFile $logFile
            Write-VfcLog 'ERROR' 'error kept' -LogFile $logFile
            $text=if([IO.File]::Exists($logFile)){[IO.File]::ReadAllText($logFile)}else{''}
            if($text -match 'debug suppressed' -or $text -notmatch 'error kept'){throw 'Log level filter test failed'}
        }finally{
            $script:VfcLogLevel=$previousLogLevel
            if([IO.File]::Exists($logFile)){[IO.File]::Delete($logFile)}
        }
        $exeRoot=Join-Path ([IO.Path]::GetTempPath()) ('VGUIFontChanger-exe-test-'+[Guid]::NewGuid().ToString('N'))
        try{
            $null=[IO.Directory]::CreateDirectory($exeRoot)
            foreach($name in @('steam.exe','vpk.exe','hl2.exe')){[IO.File]::WriteAllText((Join-Path $exeRoot $name),'')}
            if((Find-GameExecutable $exeRoot) -ne (Join-Path $exeRoot 'hl2.exe')){throw 'Game executable discovery failed'}
            if(Test-ProcessPathMatch 'C:\elsewhere\hl2.exe' $exeRoot $exeRoot){throw 'Game process path match failed'}
            if(-not (Test-ProcessPathMatch ((Join-Path $exeRoot 'tf')+'\hl2.exe') $exeRoot '')){throw 'Game process path match failed'}
            if(-not (Test-ProcessPathMatch ((Join-Path $exeRoot 'tf').Replace('\','/')+'/hl2.exe') ((Join-Path $exeRoot 'tf').Replace('\','/')+'/tf') $exeRoot)){throw 'Game process path match failed'}
        }finally{if([IO.Directory]::Exists($exeRoot)){[IO.Directory]::Delete($exeRoot,$true)}}
        $workerState=@{Pipeline=$null;Handle=$null;Work=$null;Task=''}
        Start-GuiTask $workerState 'Scan' '' @{} @{}
        $workerState.Work.Cancel=$true
        try{
            $null=$workerState.Pipeline.EndInvoke($workerState.Handle)
            throw 'Background cancellation self-test failed'
        }catch{
            if($_.Exception.Message -notlike '*Operation cancelled*'){throw}
        }finally{$workerState.Pipeline.Dispose()}
        Initialize-PrivateFontPreview
        $privateStore=New-PrivateFontStore
        $previewCache=@{}
        try{
            $privateStore.Add((Get-FontFile 'Tahoma'))
            $family=$privateStore.Collection.Families[0]
            $privatePreview=Get-PreviewFont $previewCache '__uninstalled_test_alias__' @{__uninstalled_test_alias__=$family}
            if($privatePreview.Name -ne $family.Name){throw 'Private font file preview test failed'}
            $scaledPreview=Get-PreviewFont $previewCache '__uninstalled_test_alias__' @{__uninstalled_test_alias__=$family} 2.0
            if($scaledPreview.Size -ne 22 -or $privatePreview.Size -ne 11){throw 'Size-factor preview test failed'}
        }finally{
            foreach($font in $previewCache.Values){$font.Dispose()}
            $privateStore.Dispose()
        }
        'Self-test passed: text/bitmap factors, localized font names, koreana ranges, source viewer, both locales, cancellation, log level filter, game restart discovery and GUI controls.'
    }finally{
        Set-Item Function:Get-ResolvedSchemes $originalFunction
        $script:Work=$null
    }
}
