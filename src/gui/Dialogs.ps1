function Set-KvSyntaxHighlighting {
    param($Editor,$Theme)
    $dark=$Theme.Name -in @('Dark','AMOLED','HighContrast')
    $comment=if($dark){[Drawing.Color]::FromArgb(142,168,145)}else{[Drawing.Color]::FromArgb(67,117,72)}
    $value=if($dark){[Drawing.Color]::FromArgb(216,186,143)}else{[Drawing.Color]::FromArgb(152,67,30)}
    $key=if($dark){[Drawing.Color]::FromArgb(130,202,255)}else{[Drawing.Color]::FromArgb(20,77,147)}
    $Editor.SelectAll();$Editor.SelectionColor=$Theme.Fore;$Editor.SelectionBackColor=$Theme.Back
    foreach($token in [regex]::Matches($Editor.Text,'//[^\r\n]*|"(?:\\.|[^"\\])*"|#[A-Za-z]+|\[[^\]\r\n]*\]|[{}]')){
        $Editor.Select($token.Index,$token.Length)
        $color=$key
        if($token.Value.StartsWith('//')){$color=$comment}
        elseif($token.Value.StartsWith('"')){
            $lineStart=$Editor.Text.LastIndexOf("`n",[Math]::Max(0,$token.Index-1))+1
            if($Editor.Text.Substring($lineStart,$token.Index-$lineStart) -match '"'){$color=$value}
        }
        $Editor.SelectionColor=$color
    }
}
function Get-UiMetricFont {
    param([hashtable]$Cache,[single]$Pixels=0,[switch]$Monospace,[int]$Dpi=96)
    $systemFont=[Drawing.SystemFonts]::MessageBoxFont
    $family=$systemFont.FontFamily;$style=$systemFont.Style
    if($Pixels -le 0){$Pixels=[single]($systemFont.SizeInPoints*$Dpi/72.0)}
    if($Monospace){$family='Consolas';$style=[Drawing.FontStyle]::Regular}
    $name=if($Monospace){'Consolas'}else{$family.Name}
    $key=$name+'|'+$style+'|'+$Pixels.ToString('0.######',[Globalization.CultureInfo]::InvariantCulture)
    if(-not $Cache.ContainsKey($key)){$Cache[$key]=[Drawing.Font]::new($family,$Pixels,$style,[Drawing.GraphicsUnit]::Pixel)}
    # Control.Font may retain an equal-valued old Font instead of replacing its
    # reference. Keep every UI font alive until its entire control tree is gone.
    return $Cache[$key]
}
function Get-MaintainerProfileTarget {
    param([switch]$WebOnly)
    if(-not $WebOnly){
        foreach($root in @(Get-SteamRoots)){
            if([IO.File]::Exists((Join-Path $root 'steam.exe'))){return 'steam://url/SteamIDPage/76561198436496102'}
        }
    }
    return 'https://steamcommunity.com/id/kawalain'
}
function Open-MaintainerProfile {
    param([scriptblock]$Launcher)
    if(-not $Launcher){$Launcher={param($target)
        $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=$target;$start.UseShellExecute=$true
        $null=[Diagnostics.Process]::Start($start)
    }}
    $target=Get-MaintainerProfileTarget
    try{& $Launcher $target}catch{
        if(-not $target.StartsWith('steam:')){throw}
        & $Launcher (Get-MaintainerProfileTarget -WebOnly)
    }
}
function New-AboutDialog {
    param($Owner,[string]$Language,$Theme,$Operation,[string]$Task='')
    Initialize-GuiRuntime
    if(-not $Theme){$Theme=Get-UiTheme 'System'}
    $window=New-Object VguiAboutForm;$window.Text='About VGUIFontChanger';$window.StartPosition='CenterParent'
    $window.FormBorderStyle='FixedDialog';$window.MaximizeBox=$false;$window.MinimizeBox=$false;$window.ShowInTaskbar=$false
    $title=New-Object Windows.Forms.Label;$title.Text='VGUIFontChanger'
    $description=New-Object Windows.Forms.Label;$description.Text=Get-UiText 'AboutDescription' $Language
    # Credits are deliberately identical in every locale.
    $credits=New-Object Windows.Forms.LinkLabel;$credits.Text='Built by Codex · Maintained by kawalain'
    $null=$credits.Links.Add($credits.Text.IndexOf('kawalain'),'kawalain'.Length,'https://steamcommunity.com/id/kawalain')
    $message=New-Object Windows.Forms.Label;$message.AutoEllipsis=$true
    $progress=New-Object Windows.Forms.ProgressBar;$progress.Style='Marquee';$progress.MarqueeAnimationSpeed=30
    $button=New-Object Windows.Forms.Button
    $isOperation=($null -ne $Operation)
    if($isOperation){$window.Text=if($Task){Get-UiText ('Task'+$Task) $Language}else{Get-UiText 'Starting' $Language}}
    $message.Visible=$isOperation;$progress.Visible=$isOperation
    $window.OperationActive=$isOperation;$window.ControlBox=-not $isOperation
    if($isOperation){$button.Text=Get-UiText 'Cancel' $Language;$message.Text=Get-UiText 'Starting' $Language}
    else{$button.Text=Get-UiText 'CloseDialog' $Language;$button.DialogResult='OK';$window.AcceptButton=$button;$window.CancelButton=$button}
    $window.Controls.AddRange(@($title,$description,$credits,$message,$progress,$button))
    $dialog=@{Window=$window;Title=$title;Description=$description;Credits=$credits;Message=$message;Progress=$progress;Button=$button;Fonts=@{};Operation=$Operation;Language=$Language}
    # Capture helper scriptblocks explicitly: event closures live in a dynamic
    # module, where functions defined by a downloaded script aren't guaranteed.
    $metricFont=${function:Get-UiMetricFont};$uiText=${function:Get-UiText};$openProfile=${function:Open-MaintainerProfile}
    $metrics={
        $ratio=$window.UiDpi/96.0
        $window.Font=& $metricFont $dialog.Fonts -Dpi $window.UiDpi
        $title.Font=& $metricFont $dialog.Fonts ([single]([Drawing.SystemFonts]::MessageBoxFont.SizeInPoints*$window.UiDpi/72.0*1.5))
        $height=if($isOperation){262}else{194}
        $window.ClientSize=New-Object Drawing.Size([int](480*$ratio),[int]($height*$ratio))
        $title.SetBounds([int](22*$ratio),[int](18*$ratio),[int](436*$ratio),[int](32*$ratio))
        $description.SetBounds([int](22*$ratio),[int](62*$ratio),[int](436*$ratio),[int](26*$ratio))
        $credits.SetBounds([int](22*$ratio),[int](101*$ratio),[int](436*$ratio),[int](28*$ratio))
        $message.SetBounds([int](22*$ratio),[int](142*$ratio),[int](436*$ratio),[int](26*$ratio))
        $progress.SetBounds([int](22*$ratio),[int](178*$ratio),[int](436*$ratio),[int](16*$ratio))
        $button.SetBounds([int](358*$ratio),[int](($height-46)*$ratio),[int](100*$ratio),[int](30*$ratio))
        if($window.OperationActive){$window.CenterOnOwner()}
    }.GetNewClosure()
    $dialog.Metrics=$metrics
    $window.Add_UiDpiChanged($metrics)
    $credits.Add_LinkClicked({param($sender,$e)
        try{& $openProfile}catch{[Windows.Forms.MessageBox]::Show($window,$_.Exception.Message,'VGUIFontChanger','OK','Error')|Out-Null}
    }.GetNewClosure())
    if($isOperation){$button.Add_Click({
        if($Operation.CanCancel -and -not $Operation.Cancel){
            $Operation.Cancel=$true;$button.Enabled=$false;$message.Text=& $uiText 'Cancelling' $Language
        }
    }.GetNewClosure())}
    Apply-ControlTheme $window $Theme;$credits.LinkColor=$Theme.Accent;$credits.ActiveLinkColor=$Theme.Accent;$credits.VisitedLinkColor=$Theme.Accent
    & $metrics
    return $dialog
}
function Close-AboutDialog {
    param($Dialog,[switch]$NoActivate)
    if(-not $Dialog){return}
    $owner=$Dialog.Window.Owner;$restore=$false
    if($owner -and -not $owner.IsDisposed -and -not $Dialog.Window.IsDisposed){
        $restore=[VguiDpiNative]::IsForeground($owner.Handle,$Dialog.Window.Handle)
        # Enable the owner BEFORE destroying the active owned window. Otherwise
        # Windows selects an unrelated application as the next foreground window.
        if($Dialog.Window.OperationActive){$owner.Enabled=$true}
    }
    $Dialog.Window.OperationActive=$false
    try{$Dialog.Window.Close();$Dialog.Window.Dispose()}finally{foreach($font in $Dialog.Fonts.Values){$font.Dispose()}}
    if($restore -and -not $NoActivate -and $owner -and -not $owner.IsDisposed -and $owner.Visible){
        $owner.BringToFront();$owner.Activate();$null=$owner.Focus()
    }
}
function Show-AboutWindow {
    param($Owner,[string]$Language,$Theme,[switch]$SmokeTest)
    $dialog=New-AboutDialog $Owner $Language $Theme
    $window=$dialog.Window;$credits=$dialog.Credits;$description=$dialog.Description
    try{
        if($SmokeTest){
            if($credits.Text -cne 'Built by Codex · Maintained by kawalain' -or $credits.Links.Count -ne 1 -or $credits.Links[0].LinkData -ne 'https://steamcommunity.com/id/kawalain'){throw 'About credits/link test failed'}
            if($credits.Text.Substring($credits.Links[0].Start,$credits.Links[0].Length) -cne 'kawalain'){throw 'About author link range failed'}
            if($description.Text -cne (Get-UiText 'AboutDescription' $Language)){throw 'About description locale failed'}
            if($window.Font.FontFamily.Name -ne [Drawing.SystemFonts]::MessageBoxFont.FontFamily.Name){throw 'About must use Windows system UI font'}
            $null=$window.Handle;$window.UpdateUiDpi(144)
            if($window.ClientSize.Width -ne 720){throw 'About dialog DPI test failed'}
            $bitmap=New-Object Drawing.Bitmap($window.ClientSize.Width,$window.ClientSize.Height)
            try{$window.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height)))}finally{$bitmap.Dispose()}
        }else{$null=$window.ShowDialog($Owner)}
    }finally{Close-AboutDialog $dialog}
}
function Open-LocalPath {
    param([string]$Path)
    $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=$Path;$start.UseShellExecute=$true
    $null=[Diagnostics.Process]::Start($start)
}
function Show-OperationError {
    param($Owner,[string]$Language,$Theme,[string]$LogPath,[switch]$SmokeTest)
    $window=New-Object VguiDpiForm;$window.Text='VGUIFontChanger';$window.StartPosition='CenterParent';$window.FormBorderStyle='FixedDialog';$window.MaximizeBox=$false;$window.MinimizeBox=$false;$window.ShowInTaskbar=$false
    $message=New-Object Windows.Forms.LinkLabel;$message.Text=Get-UiText 'OperationError' $Language
    $message.Links.Clear()
    $link=Get-UiText 'LogFile' $Language;$position=$message.Text.IndexOf($link)
    if($LogPath -and $position -ge 0){$null=$message.Links.Add($position,$link.Length,$LogPath)}else{$message.LinkArea=New-Object Windows.Forms.LinkArea(0,0)}
    $message.Add_LinkClicked({param($sender,$e);Open-LocalPath ([string]$e.Link.LinkData)})
    $button=New-Object Windows.Forms.Button;$button.Text=Get-UiText 'CloseDialog' $Language;$button.DialogResult='OK'
    $window.AcceptButton=$button;$window.CancelButton=$button;$window.Controls.AddRange(@($message,$button))
    $fonts=@{};$fontFactory=${function:Get-UiMetricFont}
    $metrics={
        $scale=$window.UiDpi/96.0;$font=& $fontFactory $fonts -Dpi $window.UiDpi
        $window.Font=$font;$message.Font=$font;$button.Font=$font
        $window.ClientSize=New-Object Drawing.Size([int](460*$scale),[int](150*$scale))
        $message.SetBounds([int](20*$scale),[int](20*$scale),[int](420*$scale),[int](70*$scale))
        $button.SetBounds([int](340*$scale),[int](100*$scale),[int](100*$scale),[int](30*$scale))
    }.GetNewClosure()
    $window.Add_UiDpiChanged($metrics);& $metrics
    Apply-ControlTheme $window $Theme;$message.LinkColor=$Theme.Accent
    try{
        if($SmokeTest){
            $null=$window.Handle;$window.UpdateUiDpi(144)
            if($message.Text -cne (Get-UiText 'OperationError' $Language) -or $message.Links.Count -ne 1 -or $message.Links[0].LinkData -cne $LogPath){throw 'Localized error/log-link dialog failed'}
            if($message.Text.Substring($message.Links[0].Start,$message.Links[0].Length) -cne $link){throw 'Only the log-file text should be a link'}
            if($window.Font.FontFamily.Name -ne [Drawing.SystemFonts]::MessageBoxFont.FontFamily.Name){throw 'Error dialog must use the Windows UI font'}
            $bitmap=New-Object Drawing.Bitmap($window.ClientSize.Width,$window.ClientSize.Height)
            try{$window.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$bitmap.Width,$bitmap.Height)))}finally{$bitmap.Dispose()}
        }else{$null=$window.ShowDialog($Owner)}
    }finally{$window.Dispose();foreach($font in $fonts.Values){$font.Dispose()}}
}
function Show-FontUsesWindow {
    param($Owner,$Summary,[string]$Language,[switch]$SmokeTest,$Theme)
    Initialize-GuiRuntime
    $window=New-Object VguiDpiForm; $window.Text=Get-UiText 'UsesTitle' $Language @($Summary.Font)
    $window.Size=New-Object Drawing.Size(1080,650); $window.MinimumSize=New-Object Drawing.Size(760,450); $window.StartPosition='CenterParent'
    if(-not $Theme){$Theme=Get-UiTheme 'System'}
    $code=New-Object Windows.Forms.RichTextBox; $code.Dock='Fill';$code.ReadOnly=$true;$code.WordWrap=$false;$code.DetectUrls=$false;$code.HideSelection=$false
    $window.Controls.Add($code)
    $text=New-Object Text.StringBuilder; $targets=New-ObjectList
    foreach($group in @($Summary.Locations | Group-Object Source | Sort-Object Name)){
        $null=$text.AppendLine('// File: '+($group.Name -replace '[\r\n]',' '))
        foreach($location in @($group.Group | Sort-Object Line,Alias)){
            $null=$text.AppendLine(('// Scheme: {0} | Key: {1}/{2} | Line: {3}' -f $location.Scheme,$location.Alias,$location.GlyphSet,$location.Line))
            $offset=$text.Length
            if($location.Context.Text){
                $targets.Add(@{Offset=$offset+$location.Context.Offset;Length=$location.Context.Length})
                $null=$text.AppendLine($location.Context.Text)
            }else{$null=$text.AppendLine('// '+(Get-UiText 'NoSource' $Language))}
            $null=$text.AppendLine()
        }
    }
    $code.Text=$text.ToString()
    $menu=New-Object Windows.Forms.ContextMenuStrip
    $copy=$menu.Items.Add((Get-UiText 'Copy' $Language));$selectAll=$menu.Items.Add((Get-UiText 'SelectAll' $Language))
    $copy.Add_Click({$code.Copy()});$selectAll.Add_Click({$code.SelectAll()});$code.ContextMenuStrip=$menu
    $editorState=@{Fonts=@{}}
    $editorMetrics={
        $dpi=$window.UiDpi/96.0
        $code.Font=Get-UiMetricFont $editorState.Fonts ([single](17*$dpi)) -Monospace
        $window.MinimumSize=New-Object Drawing.Size([int](760*$dpi),[int](450*$dpi))
        $caret=$code.SelectionStart;$length=$code.SelectionLength
        Set-KvSyntaxHighlighting $code $Theme
        foreach($target in $targets){$code.Select($target.Offset,$target.Length);$code.SelectionBackColor=$Theme.Selection}
        $code.Select($caret,$length)
    }
    $window.Add_UiDpiChanged($editorMetrics)
    try{
        Apply-ControlTheme $window $Theme;Apply-ControlTheme $menu $Theme
        & $editorMetrics
        Set-KvSyntaxHighlighting $code $Theme
        foreach($target in $targets){$code.Select($target.Offset,$target.Length);$code.SelectionBackColor=$Theme.Selection}
        if($targets.Count){$code.Select($targets[0].Offset,0);$code.ScrollToCaret()}
        if($SmokeTest){
            if($window.Controls.Count -ne 1 -or -not $code.ReadOnly -or $code.Text -notmatch '// File:' -or $code.Text -notmatch 'name'){throw 'Editor-only source viewer test failed'}
            $null=$window.Handle;$window.UpdateUiDpi(144)
            $expectedPixels=[single](17*$window.UiDpi/96.0)
            $expectedFont=Get-UiMetricFont $editorState.Fonts $expectedPixels -Monospace
            if($window.UiDpi -ne 144 -or $expectedFont.Unit -ne [Drawing.GraphicsUnit]::Pixel -or [Math]::Abs($expectedFont.Size-$expectedPixels) -gt 0.1){throw 'Source editor DPI update failed'}
            $commentIndex=$code.Text.IndexOf('// File:');$code.Select($commentIndex,2)
            if($code.SelectionColor.ToArgb() -eq $Theme.Fore.ToArgb()){throw 'Source syntax highlighting failed'}
        }else{$null=$window.ShowDialog($Owner)}
    }finally{$menu.Dispose();$window.Dispose();foreach($font in $editorState.Fonts.Values){$font.Dispose()}}
}
