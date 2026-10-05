function Get-UiTheme {
    param([string]$Requested='System')
    if([Windows.Forms.SystemInformation]::HighContrast){return @{Back=[Drawing.SystemColors]::Window;Fore=[Drawing.SystemColors]::WindowText;Panel=[Drawing.SystemColors]::Control;Border=[Drawing.SystemColors]::WindowText;Selection=[Drawing.SystemColors]::Highlight;SelectedText=[Drawing.SystemColors]::HighlightText;Accent=[Drawing.SystemColors]::Highlight;Name='HighContrast'}}
    if($Requested -eq 'System'){
        $mode=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction SilentlyContinue
        $Requested=if($mode -and $mode.AppsUseLightTheme -eq 0){'Dark'}else{'Light'}
    }
    if($Requested -eq 'Light'){return @{Back=[Drawing.Color]::White;Fore=[Drawing.Color]::FromArgb(28,28,28);Panel=[Drawing.Color]::FromArgb(245,245,245);Border=[Drawing.Color]::FromArgb(210,210,210);Selection=[Drawing.Color]::FromArgb(210,230,250);SelectedText=[Drawing.Color]::Black;Accent=[Drawing.Color]::FromArgb(0,100,190);Name='Light'}}
    $back=if($Requested -eq 'AMOLED'){[Drawing.Color]::Black}else{[Drawing.Color]::FromArgb(30,30,30)}
    $panel=if($Requested -eq 'AMOLED'){[Drawing.Color]::Black}else{[Drawing.Color]::FromArgb(40,40,40)}
    return @{Back=$back;Fore=[Drawing.Color]::FromArgb(235,235,235);Panel=$panel;Border=[Drawing.Color]::FromArgb(75,75,75);Selection=[Drawing.Color]::FromArgb(30,65,95);SelectedText=[Drawing.Color]::White;Accent=[Drawing.Color]::FromArgb(90,175,255);Name=$Requested}
}
function Apply-ControlTheme {
    param($Control,$Theme)
    $Control.BackColor=$Theme.Panel; $Control.ForeColor=$Theme.Fore
    if($Control -is [Windows.Forms.DataGridView]){
        $Control.BackgroundColor=$Theme.Back; $Control.GridColor=$Theme.Border; $Control.EnableHeadersVisualStyles=$false
        foreach($style in @($Control.DefaultCellStyle,$Control.ColumnHeadersDefaultCellStyle)){$style.BackColor=$Theme.Back;$style.ForeColor=$Theme.Fore;$style.SelectionBackColor=$Theme.Selection;$style.SelectionForeColor=$Theme.SelectedText}
    }
    if($Control -is [Windows.Forms.Button]){$Control.FlatStyle='Flat';$Control.FlatAppearance.BorderColor=$Theme.Border}
    if($Control -is [Windows.Forms.ComboBox] -or $Control -is [Windows.Forms.RichTextBox] -or $Control -is [Windows.Forms.TreeView]){$Control.BackColor=$Theme.Back}
    if($Control -is [Windows.Forms.ToolStrip]){
        $Control.Renderer=New-Object Windows.Forms.ToolStripSystemRenderer
        foreach($item in $Control.Items){Set-MenuTheme $item $Theme}
    }
    foreach($child in $Control.Controls){Apply-ControlTheme $child $Theme}
}
function Set-MenuTheme {
    param($Item,$Theme)
    $Item.BackColor=$Theme.Panel;$Item.ForeColor=$Theme.Fore
    if($Item -is [Windows.Forms.ToolStripMenuItem]){$Item.DropDown.BackColor=$Theme.Panel;foreach($child in $Item.DropDownItems){Set-MenuTheme $child $Theme}}
}
function Save-GuiPreferences {
    param($Preferences,[string]$Root='')
    if(-not $Root){$Root=Get-SettingsRoot};$null=[IO.Directory]::CreateDirectory($Root)
    $layout=@{Version=1;Locale=$Preferences.Locale;Theme=$Preferences.Theme;Symbols=[bool]$Preferences.Symbols;ListZoom=[double]$Preferences.ListZoom;GamePath=[string]$Preferences.GamePath;LogLevel=[string]$Preferences.LogLevel;LaunchGame=[bool]$Preferences.LaunchGame;EffectiveOnly=($Preferences.EffectiveOnly -ne $false)}
    [IO.File]::WriteAllText((Join-Path $Root 'layout.json'),($layout|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
}
function Read-LayoutPreferences {
    param([string]$Root='')
    if(-not $Root){$Root=Get-SettingsRoot}
    $language=Get-WindowsGuiLocale
    $layout=@{Locale=$language;Theme='System';Symbols=$false;ListZoom=1.0;GamePath='';LogLevel='INFO';LaunchGame=$false;EffectiveOnly=$true}
    foreach($name in @('layout.json','ui.json')){
        $path=Join-Path $Root $name
        try{
            if(-not (Test-Path -LiteralPath $path)){continue}
            $saved=ConvertTo-PlainValue ([IO.File]::ReadAllText($path)|ConvertFrom-Json)
            if($saved.Locale -in @('en-US','ko-KR')){$layout.Locale=$saved.Locale}
            if($saved.Theme -in @('System','Light','Dark','AMOLED')){$layout.Theme=$saved.Theme}
            if($saved.Symbols -is [bool]){$layout.Symbols=$saved.Symbols}
            if($saved.ContainsKey('LogLevel') -and $saved['LogLevel'] -in @('TRACE','DEBUG','INFO','WARN','ERROR')){$layout.LogLevel=$saved['LogLevel']}
            if($saved.ContainsKey('LaunchGame')){$layout.LaunchGame=($saved['LaunchGame'] -eq $true)}
            if($saved.ContainsKey('EffectiveOnly')){$layout.EffectiveOnly=($saved['EffectiveOnly'] -eq $true)}
            if($saved.ContainsKey('GamePath') -and $saved.GamePath -is [string]){$layout.GamePath=$saved.GamePath}
            if($saved.ContainsKey('ListZoom')){$zoom=[double]$saved.ListZoom;if(-not [double]::IsNaN($zoom) -and $zoom -ge 0.5 -and $zoom -le 3){$layout.ListZoom=$zoom}}
            break
        }catch{}
    }
    return $layout
}
