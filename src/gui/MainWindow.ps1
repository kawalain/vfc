function Show-VguiFontGui {
    param([switch]$SmokeTest,[string]$PreviewPath)
    Initialize-GuiRuntime
    $previousDpiContext=[VguiDpiNative]::Enter()
    [Windows.Forms.Application]::EnableVisualStyles()
    $form=New-Object VguiDpiForm
    $form.Text='VGUIFontChanger'; $form.StartPosition='CenterScreen'; $form.Size=New-Object Drawing.Size(1160,760)
    $form.MinimumSize=New-Object Drawing.Size(1000,540); $form.Font=[Drawing.SystemFonts]::MessageBoxFont.Clone(); $form.KeyPreview=$true
    $layout=Read-LayoutPreferences;if($Locale){$layout.Locale=$Locale}
    $model=New-FontHierarchy @() @{Nodes=@{}} $layout.Locale $layout.Theme;$model.Preferences=$layout
    $script:VfcLogLevel=if($model.Preferences.LogLevel){[string]$model.Preferences.LogLevel}else{'INFO'}
    $state=@{Model=$model;Pipeline=$null;Handle=$null;Work=$null;Task='';Game='';Fonts=@();EditorId='';FontCache=@{};PreviewAvailable=@{};PrivateFamilies=@{};PrivateStores=(New-ObjectList);Sync=$false;Closing=$false;GestureBefore='';SavedNodes='{}';Theme=$null;ThemeName='';ThemeTick=0;Dpi=96;MetricZoom=0;ListFont=$null;UiFont=$null;MetricFonts=@{initial=$form.Font};LayoutSaveAt=$null;OperationDialog=$null;MetricsBusy=$false}
    $menu=New-Object Windows.Forms.MenuStrip
    $fileMenu=New-Object Windows.Forms.ToolStripMenuItem; $editMenu=New-Object Windows.Forms.ToolStripMenuItem; $viewMenu=New-Object Windows.Forms.ToolStripMenuItem
    $null=$menu.Items.Add($fileMenu); $null=$menu.Items.Add($editMenu); $null=$menu.Items.Add($viewMenu)
    $aboutMenu=New-Object Windows.Forms.ToolStripMenuItem;$null=$menu.Items.Add($aboutMenu)
    $commands=@{}
    $addMenu={param($parent,$key,$shortcut)
        $item=New-Object Windows.Forms.ToolStripMenuItem; $item.Tag=$key
        if($shortcut){$item.ShortcutKeys=[Windows.Forms.Keys]$shortcut}
        $null=$parent.DropDownItems.Add($item); $commands[$key]=$item
    }
    & $addMenu $fileMenu 'ChooseGame' 'Control,G'; & $addMenu $fileMenu 'Scan' 'F5'
    $null=$fileMenu.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator))
    & $addMenu $fileMenu 'Save' 'Control,S'; & $addMenu $fileMenu 'Import' 'Control,O'; & $addMenu $fileMenu 'Export' 'Control,Shift,S'; & $addMenu $fileMenu 'Apply' 'Control,Shift,A'
    & $addMenu $fileMenu 'LaunchGame' ''; $commands.LaunchGame.CheckOnClick=$true
    & $addMenu $fileMenu 'RemoveOverride' ''; & $addMenu $fileMenu 'OpenAppData' ''
    $null=$fileMenu.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator)); & $addMenu $fileMenu 'Exit' 'Alt,F4'
    & $addMenu $editMenu 'Undo' 'Control,Z'; & $addMenu $editMenu 'Redo' 'Control,Y'
    $null=$editMenu.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator))
    & $addMenu $editMenu 'Reset' 'Delete'
    $null=$editMenu.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator));& $addMenu $editMenu 'Find' 'Control,F'
    & $addMenu $viewMenu 'ExpandAll' ''; & $addMenu $viewMenu 'CollapseAll' ''; & $addMenu $viewMenu 'Symbols' ''; & $addMenu $viewMenu 'EffectiveOnly' ''
    $commands.EffectiveOnly.CheckOnClick=$true
    $languageMenu=New-Object Windows.Forms.ToolStripMenuItem; $themeMenu=New-Object Windows.Forms.ToolStripMenuItem
    $null=$viewMenu.DropDownItems.Add($languageMenu); $null=$viewMenu.DropDownItems.Add($themeMenu)
    $languages=@{}; foreach($language in @('en-US','ko-KR')){$item=New-Object Windows.Forms.ToolStripMenuItem; $item.Text=if($language -eq 'ko-KR'){'한국어 (ko-KR)'}else{'English (en-US)'}; $item.Tag=$language; $null=$languageMenu.DropDownItems.Add($item);$languages[$language]=$item}
    $themes=@{}; foreach($theme in @('System','Light','Dark','AMOLED')){$item=New-Object Windows.Forms.ToolStripMenuItem;$item.Tag=$theme;$null=$themeMenu.DropDownItems.Add($item);$themes[$theme]=$item}
    $logMenu=New-Object Windows.Forms.ToolStripMenuItem;$null=$viewMenu.DropDownItems.Add($logMenu)
    $logLevels=@{}; foreach($level in @('TRACE','DEBUG','INFO','WARN','ERROR')){$item=New-Object Windows.Forms.ToolStripMenuItem;$item.Text=$level;$item.Tag=$level;$null=$logMenu.DropDownItems.Add($item);$logLevels[$level]=$item}
    $form.MainMenuStrip=$menu
    # Hosted controls keep font preview and multi-selection editing inside the menu.
    $context=New-Object Windows.Forms.ContextMenuStrip; $context.AutoClose=$true
    $contextPanel=New-Object Windows.Forms.Panel; $contextPanel.Size=New-Object Drawing.Size(390,92)
    $fontBox=New-Object Windows.Forms.ComboBox; $fontBox.SetBounds(8,6,374,30); Set-PreviewCombo $fontBox $state.FontCache $state.PrivateFamilies
    $scale=New-Object Windows.Forms.TrackBar; $scale.SetBounds(8,44,302,42); $scale.Minimum=1;$scale.Maximum=40;$scale.Value=10;$scale.TickFrequency=10;$scale.SmallChange=1;$scale.LargeChange=1
    $scaleLabel=New-Object Windows.Forms.Label; $scaleLabel.SetBounds(314,53,70,24)
    $sizeInput=New-Object Windows.Forms.NumericUpDown; $sizeInput.SetBounds(8,50,180,30);$sizeInput.Minimum=1;$sizeInput.Maximum=512;$sizeInput.Visible=$false
    $sizeUnit=New-Object Windows.Forms.Label;$sizeUnit.Text='px';$sizeUnit.SetBounds(196,53,50,24);$sizeUnit.Visible=$false
    $contextPanel.Controls.AddRange(@($fontBox,$scale,$scaleLabel,$sizeInput,$sizeUnit))
    $contextHost=[Windows.Forms.ToolStripControlHost]::new($contextPanel); $contextHost.AutoSize=$false;$contextHost.Size=$contextPanel.Size
    $null=$context.Items.Add($contextHost);$null=$context.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    $contextReset=New-Object Windows.Forms.ToolStripMenuItem
    $contextCopy=New-Object Windows.Forms.ToolStripMenuItem; $contextCopy.ShortcutKeyDisplayString='Ctrl+C'
    $contextPaste=New-Object Windows.Forms.ToolStripMenuItem; $contextPaste.ShortcutKeyDisplayString='Ctrl+V'
    $null=$context.Items.Add($contextReset);$null=$context.Items.Add($contextCopy);$null=$context.Items.Add($contextPaste)
    $statusBar=New-Object Windows.Forms.StatusStrip; $statusBar.ShowItemToolTips=$true
    $status=New-Object Windows.Forms.ToolStripStatusLabel; $status.Spring=$true;$status.TextAlign='MiddleLeft'
    $null=$statusBar.Items.Add($status)
    $grid=New-Object VguiFontGrid; $grid.Dock='Fill';$grid.AllowUserToAddRows=$false;$grid.AllowUserToDeleteRows=$false
    $grid.RowHeadersVisible=$false;$grid.SelectionMode='FullRowSelect';$grid.MultiSelect=$true;$grid.ReadOnly=$true;$grid.AutoSizeColumnsMode='Fill';$grid.RowTemplate.Height=42
    $null=$grid.Columns.Add('Node','Key')
    $null=$grid.Columns.Add('Replacement','Replacement font');$null=$grid.Columns.Add('Scale','Size factor')
    $grid.Columns['Node'].FillWeight=220;$grid.Columns['Replacement'].FillWeight=130;$grid.Columns['Scale'].FillWeight=90
    $grid.Columns['Node'].SortMode='NotSortable';foreach($column in $grid.Columns){$column.SortMode='NotSortable'}
    $inline=New-Object Windows.Forms.ComboBox; $inline.Visible=$false;Set-PreviewCombo $inline $state.FontCache $state.PrivateFamilies;$grid.Controls.Add($inline)
    $inlineSize=New-Object Windows.Forms.NumericUpDown;$inlineSize.Minimum=1;$inlineSize.Maximum=512;$inlineSize.Visible=$false;$grid.Controls.Add($inlineSize)
    $grid.ContextMenuStrip=$context
    $findPanel=New-Object Windows.Forms.Panel;$findPanel.Dock='None';$findPanel.Anchor='Bottom,Right';$findPanel.BorderStyle='FixedSingle';$findPanel.Visible=$false
    $findBox=New-Object Windows.Forms.TextBox
    $findCount=New-Object Windows.Forms.Label;$findCount.TextAlign='MiddleCenter'
    $findPrevious=New-Object Windows.Forms.Button;$findNext=New-Object Windows.Forms.Button;$findClose=New-Object Windows.Forms.Button;$findClose.Text='×'
    $findPanel.Controls.AddRange(@($findBox,$findCount,$findPrevious,$findNext,$findClose))
    $state.SearchMatches=@();$state.SearchIndex=-1;$state.SearchDue=$null;$state.SearchQuery='';$state.RowByTag=@{}
    $form.Controls.AddRange(@($grid,$findPanel,$menu,$statusBar))
    $findPanel.BringToFront()
    $state.FindLayoutBusy=$false
    $layoutFind={
        if($state.FindLayoutBusy){return};$state.FindLayoutBusy=$true
        try{
        $ratio=$state.Dpi/96.0;$margin=[int](12*$ratio)
        $width=[int][Math]::Min(640*$ratio,[Math]::Max(1,$grid.Width-2*$margin))
        $height=[int](48*$ratio)
        $findPanel.SetBounds([Math]::Max($grid.Left,$grid.Right-$width-$margin),[Math]::Max($grid.Top,$grid.Bottom-$height-$margin),$width,$height)
        $width=$findPanel.ClientSize.Width;$textWidth=[Math]::Max(100,[int]($width-330*$ratio))
        $findBox.SetBounds([int](8*$ratio),[int](7*$ratio),$textWidth,[int](28*$ratio))
        $x=$textWidth+[int](16*$ratio)
        $findCount.SetBounds($x,[int](7*$ratio),[int](106*$ratio),[int](28*$ratio));$x+=[int](110*$ratio)
        $findPrevious.SetBounds($x,[int](5*$ratio),[int](76*$ratio),[int](30*$ratio));$x+=[int](80*$ratio)
        $findNext.SetBounds($x,[int](5*$ratio),[int](66*$ratio),[int](30*$ratio));$x+=[int](70*$ratio)
        $findClose.SetBounds($x,[int](5*$ratio),[int](32*$ratio),[int](30*$ratio))
        }finally{$state.FindLayoutBusy=$false}
    }
    $findPanel.Add_Resize({& $layoutFind})
    $grid.Add_Resize({& $layoutFind})
    $updateMetrics={
        if($state.MetricsBusy){return};$state.MetricsBusy=$true
        try{
        $dpi=$form.UiDpi;$zoom=[double]$state.Model.Preferences.ListZoom
        if($state.Dpi -eq $dpi -and $state.MetricZoom -eq $zoom){return}
        $ratio=$dpi/96.0;$unit=$ratio*$zoom
        $oldDpi=$state.Dpi
        $state.Dpi=$dpi;$state.MetricZoom=$zoom
        if($dpi -ne $oldDpi -and $form.WindowState -eq 'Normal'){$resize=$dpi/[double]$oldDpi;$form.Size=New-Object Drawing.Size([int]($form.Width*$resize),[int]($form.Height*$resize))}
        & $layoutFind
        $state.ListFont=Get-UiMetricFont $state.MetricFonts ([single](17*$unit)) -Monospace
        $state.UiFont=Get-UiMetricFont $state.MetricFonts -Dpi $dpi
        $form.Font=$state.UiFont;$grid.Font=$state.ListFont;$inline.Font=$state.ListFont;$inlineSize.Font=$state.ListFont
        $context.Font=$state.UiFont;$contextPanel.Font=$state.UiFont
        $grid.RowTemplate.Height=[int](48*$unit);foreach($row in $grid.Rows){$row.Height=$grid.RowTemplate.Height}
        $grid.ColumnHeadersHeightSizeMode='EnableResizing';$grid.ColumnHeadersHeight=[int](32*$unit)
        $form.MinimumSize=New-Object Drawing.Size([int](1000*$ratio),[int](540*$ratio))
        $contextPanel.Size=New-Object Drawing.Size([int](390*$ratio),[int](92*$ratio));$contextHost.Size=$contextPanel.Size
        $fontBox.SetBounds([int](8*$ratio),[int](6*$ratio),[int](374*$ratio),[int](30*$ratio))
        $scale.SetBounds([int](8*$ratio),[int](44*$ratio),[int](302*$ratio),[int](42*$ratio))
        $scaleLabel.SetBounds([int](314*$ratio),[int](53*$ratio),[int](70*$ratio),[int](24*$ratio))
        $sizeInput.SetBounds([int](8*$ratio),[int](50*$ratio),[int](180*$ratio),[int](30*$ratio))
        $sizeUnit.SetBounds([int](196*$ratio),[int](53*$ratio),[int](50*$ratio),[int](24*$ratio))
        $fontBox.ItemHeight=[int](30*$ratio);$fontBox.DropDownHeight=[int](360*$ratio);$inline.ItemHeight=[int](30*$unit);$inline.DropDownHeight=[int](360*$ratio)
        $inline.Visible=$false;$inlineSize.Visible=$false
        foreach($font in $state.FontCache.Values){$font.Dispose()};$state.FontCache.Clear()
        $grid.Invalidate()
        }finally{$state.MetricsBusy=$false}
    }
    $form.Add_UiDpiChanged({& $updateMetrics})
    $rowValues={param($row)
        $id=[string]$row.Tag; $node=$state.Model.Nodes[$id]
        $prefix=if($node.Children.Count){if($node.Expanded){'▼ '}else{'▶ '}}else{'  '}
        $row.Cells['Node'].Value=('  '*$node.Depth)+$prefix+$node.Label
        $own=$state.Model.Settings[$id]
        $row.Cells['Replacement'].Value=if($node.Depth -eq 0 -or ($own -and $own.ContainsKey('Font') -and (Get-NodeValue $state.Model $id 'Font') -cne (Get-NodeValue $state.Model $node.Parent 'Font'))){Get-NodeValue $state.Model $id 'Font'}else{''}
        $property=if($node.Depth -eq 2){'Size'}else{'Factor'}
        $show=($node.Depth -eq 0)
        if($node.Depth -eq 1 -and $own -and $own.ContainsKey('Factor')){$show=((Get-NodeValue $state.Model $id 'Factor') -ne (Get-NodeValue $state.Model $node.Parent 'Factor'))}
        if($node.Depth -eq 2 -and $own -and ($own.ContainsKey('Size') -or $own.ContainsKey('Factor'))){
            $original=0;$null=[int]::TryParse([string]$node.Sizes,[ref]$original)
            $inheritedSize=[Math]::Max(1,[Math]::Round($original*[double](Get-NodeValue $state.Model $node.Parent 'Factor'),0,[MidpointRounding]::AwayFromZero))
            $show=([int](Get-NodeValue $state.Model $id 'Size') -ne $inheritedSize)
        }
        $row.Cells['Scale'].Value=if($show){Get-NodeValue $state.Model $id $property}else{''}
    }
    $refreshRows={foreach($row in $grid.Rows){& $rowValues $row};$grid.Invalidate()}
    $syncToolbar={
        $canEdit=($grid.SelectedRows.Count -gt 0 -and -not $state.Pipeline)
        $fontBox.Enabled=$canEdit;$scale.Enabled=$canEdit
        if(-not $grid.CurrentRow){return}
        $id=[string]$grid.CurrentRow.Tag;if(-not $state.Model.Nodes.ContainsKey($id)){return}
        $state.Sync=$true
        try{
            $font=[string](Get-NodeValue $state.Model $id 'Font')
            if(-not $fontBox.Items.Contains($font)){$null=$fontBox.Items.Add($font)}
            $fontBox.SelectedItem=$font;$scale.Value=[int]([double](Get-NodeValue $state.Model $id 'Factor')*10)
            $scaleLabel.Text=('{0:0.0}x' -f ($scale.Value/10.0))
            $leaves=@($grid.SelectedRows | Where-Object {$state.Model.Nodes[[string]$_.Tag].Depth -eq 2})
            $leafOnly=($leaves.Count -eq $grid.SelectedRows.Count)
            $mixed=($leaves.Count -gt 0 -and -not $leafOnly)
            $scale.Visible=-not $leafOnly;$scaleLabel.Visible=-not $leafOnly;$sizeInput.Visible=$leafOnly;$sizeUnit.Visible=$leafOnly
            $scale.Enabled=$canEdit -and -not $mixed;$sizeInput.Enabled=$canEdit -and $leafOnly -and (@($leaves | Where-Object {[int](Get-NodeValue $state.Model ([string]$_.Tag) 'Size') -lt 1}).Count -eq 0)
            $sizeInput.Value=[Math]::Min(512,[Math]::Max(1,[int](Get-NodeValue $state.Model $id 'Size')))
        }finally{$state.Sync=$false}
    }
    $rebuildRows={
        $selected=@($grid.SelectedRows | ForEach-Object {[string]$_.Tag}); $current=if($grid.CurrentRow){[string]$grid.CurrentRow.Tag}else{''}
        $state.Sync=$true
        try{
            $grid.Rows.Clear()
            $rows=@{}
            foreach($id in @(Get-VisibleFontNodes $state.Model)){$idx=$grid.Rows.Add();$grid.Rows[$idx].Tag=$id;& $rowValues $grid.Rows[$idx];$rows[$id]=$grid.Rows[$idx]}
            $state.RowByTag=$rows
            $grid.ClearSelection()
            foreach($row in $grid.Rows){if($row.Tag -in $selected){$row.Selected=$true};if($row.Tag -eq $current){$grid.CurrentCell=$row.Cells['Node']}}
        }finally{$state.Sync=$false}
        $inline.Visible=$false;$inlineSize.Visible=$false
        & $syncToolbar
    }
    $refresh={
        & $updateMetrics
        $language=$state.Model.Preferences.Locale
        $fileMenu.Text=Get-UiText 'FileMenu' $language;$editMenu.Text=Get-UiText 'EditMenu' $language;$viewMenu.Text=Get-UiText 'ViewMenu' $language
        $aboutMenu.Text=Get-UiText 'About' $language
        $findPrevious.Text=Get-UiText 'FindPrevious' $language;$findNext.Text=Get-UiText 'FindNext' $language
        $findBox.AccessibleName=Get-UiText 'FindHint' $language
        foreach($key in $commands.Keys){$commands[$key].Text=Get-UiText $key $language}
        foreach($key in @('Replacement','Scale')){$grid.Columns[$key].HeaderText=Get-UiText $key $language}
        $grid.Columns['Node'].HeaderText=if($language -eq 'ko-KR'){'키'}else{'Key'}
        $grid.Columns['Scale'].HeaderText=if($language -eq 'ko-KR'){'크기 / 배율'}else{'Size / factor'}
        $languageMenu.Text=Get-UiText 'Language' $language;$themeMenu.Text=Get-UiText 'Theme' $language
        foreach($key in $languages.Keys){$languages[$key].Checked=($key -eq $language)}
        foreach($key in $themes.Keys){$themes[$key].Text=Get-UiText ('Theme'+$key) $language;$themes[$key].Checked=($key -eq $state.Model.Preferences.Theme)}
        $logMenu.Text=Get-UiText 'LogLevel' $language
        foreach($key in $logLevels.Keys){$logLevels[$key].Checked=($key -eq $state.Model.Preferences.LogLevel)}
        $commands.Symbols.Checked=[bool]$state.Model.Preferences.Symbols
        $commands.LaunchGame.Checked=[bool]$state.Model.Preferences.LaunchGame
        $commands.EffectiveOnly.Checked=($state.Model.Preferences.EffectiveOnly -ne $false)
        $commands.Undo.Enabled=($state.Model.Undo.Count -gt 0 -and -not $state.Pipeline)
        $commands.Redo.Enabled=($state.Model.Redo.Count -gt 0 -and -not $state.Pipeline)
        $commands.Apply.Enabled=($state.Model.Roots.Count -gt 0 -and -not $state.Pipeline)
        $commands.Save.Enabled=($state.Model.Roots.Count -gt 0 -and -not $state.Pipeline)
        $contextReset.Text=Get-UiText 'Reset' $language;$contextCopy.Text=Get-UiText 'CopyValues' $language;$contextPaste.Text=Get-UiText 'PasteValues' $language
        if(-not $state.Pipeline){$status.Text=(Get-UiText 'GameFolder' $language)+': '+$state.Game}
        $scaleLabel.Text=('{0:0.0}x' -f ($scale.Value/10.0))
        $state.Theme=Get-UiTheme $state.Model.Preferences.Theme;$state.ThemeName=$state.Theme.Name
        Apply-ControlTheme $form $state.Theme;Apply-ControlTheme $menu $state.Theme;Apply-ControlTheme $statusBar $state.Theme
        Apply-ControlTheme $context $state.Theme;Apply-ControlTheme $contextPanel $state.Theme
        & $refreshRows
        & $syncToolbar
        & $updateFindCount
    }
    $persistUi={$state.LayoutSaveAt=[DateTime]::UtcNow.AddMilliseconds(600)}
    $flushLayout={if($state.LayoutSaveAt -and -not $SmokeTest){try{Save-GuiPreferences $state.Model.Preferences;$state.LayoutSaveAt=$null}catch{$status.ToolTipText=$_.Exception.Message;$state.LayoutSaveAt=[DateTime]::UtcNow.AddSeconds(5)}}}
    $grid.Add_ZoomRequested({param($sender,$e)
        if($state.Pipeline){return}
        $zoom=[Math]::Round([Math]::Min(3.0,[Math]::Max(0.5,[double]$state.Model.Preferences.ListZoom+0.1*[Math]::Sign($e.Delta))),1)
        if($zoom -eq $state.Model.Preferences.ListZoom){return}
        $before=Get-ModelSnapshot $state.Model;$state.Model.Preferences.ListZoom=$zoom;$null=Complete-ModelChange $state.Model $before;& $refresh;& $persistUi
    })
    $finishGesture={
        if($state.GestureBefore){$null=Complete-ModelChange $state.Model $state.GestureBefore;$state.GestureBefore='';& $refresh}
    }
    $changeValues={param([string]$property,$value,[string[]]$ids)
        if($state.Pipeline -or $state.Sync){return}
        $before=Get-ModelSnapshot $state.Model
        foreach($id in $ids){Set-NodeValue $state.Model $id $property $value}
        if(-not $state.GestureBefore){$null=Complete-ModelChange $state.Model $before}
        & $refreshRows
        $commands.Undo.Enabled=($state.Model.Undo.Count -gt 0);$commands.Redo.Enabled=($state.Model.Redo.Count -gt 0)
    }
    $resetValues={param([string[]]$ids,[string]$property='')
        if($state.Pipeline){return}
        $modified=@($ids | Where-Object {$state.Model.Settings.ContainsKey($_) -and (-not $property -or $state.Model.Settings[$_].ContainsKey($property))})
        if(-not $modified.Count){return}
        $language=$state.Model.Preferences.Locale
        if([Windows.Forms.MessageBox]::Show($form,(Get-UiText 'ResetConfirm' $language),(Get-UiText 'Reset' $language),'YesNo','Question') -ne 'Yes'){return}
        $before=Get-ModelSnapshot $state.Model
        foreach($id in $modified){if($property){$state.Model.Settings[$id].Remove($property);if(-not $state.Model.Settings[$id].Count){$state.Model.Settings.Remove($id)}}else{$state.Model.Settings.Remove($id)}}
        $null=Complete-ModelChange $state.Model $before;& $rebuildRows;& $refresh
    }
    $confirmDiscard={
        if(($state.Model.Settings|ConvertTo-Json -Depth 12 -Compress) -ceq $state.SavedNodes){return $true}
        return ([Windows.Forms.MessageBox]::Show($form,(Get-UiText 'DiscardConfirm' $state.Model.Preferences.Locale),'VGUIFontChanger','YesNo','Warning') -eq 'Yes')
    }
    $busy={param([bool]$value)
        if(-not $value -and $state.OperationDialog){
            Close-AboutDialog $state.OperationDialog;$state.OperationDialog=$null;$form.Enabled=$true
        }
        $grid.Enabled=-not $value;$menu.Enabled=-not $value;$context.Enabled=-not $value;$findPanel.Enabled=-not $value
        if($value){$context.Close()}
        $inline.Visible=$false;$inlineSize.Visible=$false
        & $refresh
    }
    $beginTask={param([string]$task,[string]$game,$profile)
        & $busy $true
        try{
            Start-GuiTask $state $task $game @{} @{} $profile
            $timer.Work=$state.Work
            $state.OperationDialog=New-AboutDialog $form $state.Model.Preferences.Locale $state.Theme $state.Work $task
            $state.OperationDialog.Window.Show($form)
            $form.Enabled=$false;$state.OperationDialog.Window.CenterOnOwner()
        }catch{
            if($state.Pipeline){$state.Pipeline.Stop();$state.Pipeline.Dispose();$state.Pipeline=$null;$state.Handle=$null}
            & $busy $false
            if($SmokeTest){throw}
            $logFile=if($state.ContainsKey('CurrentLogPath')){$state.CurrentLogPath}else{''}
            Write-VfcLog 'ERROR' ($_.Exception.ToString()+[Environment]::NewLine+$_.ScriptStackTrace) -LogFile $logFile
            Show-OperationError $form $state.Model.Preferences.Locale $state.Theme $logFile
        }
    }
    $centerOperation={if($state.OperationDialog){$state.OperationDialog.Window.CenterOnOwner()}}
    $form.Add_LocationChanged($centerOperation);$form.Add_SizeChanged($centerOperation)
    $startScan={param([string]$game)
        if($state.Pipeline){return}
        & $beginTask 'Scan' $game $null
    }
    $commands.ChooseGame.Add_Click({
        if(-not (& $confirmDiscard)){return}
        $dialog=New-Object Windows.Forms.FolderBrowserDialog
        try{if($state.Game){$dialog.SelectedPath=$state.Game};if($dialog.ShowDialog($form) -eq 'OK'){& $startScan $dialog.SelectedPath}}finally{$dialog.Dispose()}
    })
    $commands.Scan.Add_Click({if(& $confirmDiscard){& $startScan $state.Game}})
    $commands.Exit.Add_Click({$form.Close()})
    $aboutMenu.Add_Click({Show-AboutWindow $form $state.Model.Preferences.Locale $state.Theme})
    $updateFindCount={
        $count=$state.SearchMatches.Count
        $findCount.Text=if([string]::IsNullOrWhiteSpace($findBox.Text)){''}elseif(-not $count){Get-UiText 'FindEmpty' $state.Model.Preferences.Locale}else{Get-UiText 'FindCount' $state.Model.Preferences.Locale @(($state.SearchIndex+1),$count)}
        $findPrevious.Enabled=($count -gt 0);$findNext.Enabled=($count -gt 0)
    }
    $runFind={param([int]$Direction=1,[bool]$Reset=$false)
        if($state.Pipeline){return}
        $state.SearchDue=$null;$query=$findBox.Text.Trim()
        # Recompute matches only when the query changes; navigation reuses the
        # cached result and selects rows directly instead of rebuilding the list.
        if($Reset -or $query -cne $state.SearchQuery){
            $state.SearchIndex=-1
            $state.SearchQuery=$query
            $state.SearchMatches=@(Get-FontSearchMatches $state.Model $query)
        }
        if($state.SearchMatches.Count){$state.SearchMatches=@($state.SearchMatches | Where-Object {$state.Model.Nodes.ContainsKey($_)})}
        $count=$state.SearchMatches.Count
        if(-not $count){$state.SearchIndex=-1;& $updateFindCount;return}
        if($state.SearchIndex -lt 0){$state.SearchIndex=if($Direction -lt 0){$count-1}else{0}}
        else{$state.SearchIndex=($state.SearchIndex+$Direction+$count)%$count}
        $id=$state.SearchMatches[$state.SearchIndex]
        $row=$null
        if($state.RowByTag.ContainsKey($id)){$row=$state.RowByTag[$id]}
        if(-not $row){
            $parent=$state.Model.Nodes[$id].Parent
            while($parent){$state.Model.Nodes[$parent].Expanded=$true;$parent=$state.Model.Nodes[$parent].Parent}
            & $rebuildRows
            if($state.RowByTag.ContainsKey($id)){$row=$state.RowByTag[$id]}
        }
        $grid.ClearSelection()
        if($row){$grid.CurrentCell=$row.Cells['Node'];$row.Selected=$true}
        & $updateFindCount
    }
    $openFind={if($state.Pipeline){return};$findPanel.Visible=$true;$findPanel.BringToFront();& $layoutFind;$null=$findBox.Focus();$findBox.SelectAll();& $runFind 0}
    $closeFind={$findPanel.Visible=$false;$state.SearchDue=$null;$null=$grid.Focus()}
    $commands.Find.Add_Click($openFind)
    $findNext.Add_Click({& $runFind 1});$findPrevious.Add_Click({& $runFind -1});$findClose.Add_Click($closeFind)
    $findBox.Add_TextChanged({$state.SearchDue=[DateTime]::UtcNow.AddMilliseconds(180)})
    $applyBuild={
        if($state.Pipeline -or -not $state.Game){return}
        & $finishGesture
        $profile=Get-HierarchyProfile $state.Model
        & $beginTask 'Build' $state.Game $profile
    }
    $commands.Apply.Add_Click($applyBuild)
    $commands.OpenAppData.Add_Click({$root=Get-SettingsRoot;$null=[IO.Directory]::CreateDirectory($root);Open-LocalPath $root})
    $commands.RemoveOverride.Add_Click({
        if($state.Pipeline -or -not $state.Game){return}
        if([Windows.Forms.MessageBox]::Show($form,(Get-UiText 'RemoveConfirm' $state.Model.Preferences.Locale),'VGUIFontChanger','YesNo','Question') -ne 'Yes'){return}
        & $beginTask 'RemoveOverride' $state.Game $null
    })
    $commands.Save.Add_Click({
        if($state.Pipeline -or -not $state.Game){return}
        & $finishGesture;& $beginTask 'Save' $state.Game (Get-HierarchyProfile $state.Model)
    })
    foreach($key in @('Undo','Redo')){
        $commands[$key].Tag=$key
        $commands[$key].Add_Click({param($sender,$e);if(Invoke-ModelHistory $state.Model ([string]$sender.Tag)){& $rebuildRows;& $refresh;& $persistUi}})
    }
    $commands.Reset.Add_Click({& $resetValues @($grid.SelectedRows | ForEach-Object {[string]$_.Tag})})
    $commands.LaunchGame.Add_Click({$state.Model.Preferences.LaunchGame=[bool]$commands.LaunchGame.Checked;& $persistUi})
    $commands.EffectiveOnly.Add_Click({
        $state.Model.Preferences.EffectiveOnly=[bool]$commands.EffectiveOnly.Checked;& $persistUi
        if($SmokeTest){return}
        if(-not $state.Game -or $state.Pipeline){return}
        if(-not (& $confirmDiscard)){return}
        & $startScan $state.Game
    })
    $commands.Symbols.Add_Click({
        $before=Get-ModelSnapshot $state.Model;$state.Model.Preferences.Symbols=-not $state.Model.Preferences.Symbols
        $null=Complete-ModelChange $state.Model $before;& $rebuildRows;& $refresh;& $persistUi
    })
    foreach($key in @('ExpandAll','CollapseAll')){$commands[$key].Add_Click({param($sender,$e);foreach($node in $state.Model.Nodes.Values){$node.Expanded=($sender.Tag -eq 'ExpandAll')}; & $rebuildRows})}
    foreach($item in $languages.Values){$item.Add_Click({param($sender,$e)
        $before=Get-ModelSnapshot $state.Model;$state.Model.Preferences.Locale=[string]$sender.Tag
        $null=Complete-ModelChange $state.Model $before;& $refresh;& $persistUi
    })}
    foreach($item in $themes.Values){$item.Add_Click({param($sender,$e)
        $before=Get-ModelSnapshot $state.Model;$state.Model.Preferences.Theme=[string]$sender.Tag
        $null=Complete-ModelChange $state.Model $before;& $refresh;& $persistUi
    })}
    foreach($item in $logLevels.Values){$item.Add_Click({param($sender,$e)
        $state.Model.Preferences.LogLevel=[string]$sender.Tag
        $script:VfcLogLevel=[string]$sender.Tag
        & $persistUi;& $refresh
    })}
    $commands.Import.Add_Click({
        $dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Filter='VGUIFontChanger JSON (*.json)|*.json'
        try{
            if($dialog.ShowDialog($form) -ne 'OK'){return}
            & $beginTask 'Import' $dialog.FileName $null
        }catch{$status.Text=$_.Exception.Message}finally{$dialog.Dispose()}
    })
    $commands.Export.Add_Click({
        $dialog=New-Object Windows.Forms.SaveFileDialog;$dialog.Filter='VGUIFontChanger JSON (*.json)|*.json';$dialog.FileName='VGUIFontChanger-settings.json'
        try{if($dialog.ShowDialog($form) -eq 'OK'){& $finishGesture;& $beginTask 'Export' $dialog.FileName (Get-HierarchyProfile $state.Model)}}catch{$status.Text=$_.Exception.Message}finally{$dialog.Dispose()}
    })
    $fontBox.Add_SelectionChangeCommitted({if($fontBox.SelectedIndex -ge 0){& $changeValues 'Font' ([string]$fontBox.SelectedItem) @($grid.SelectedRows | ForEach-Object {[string]$_.Tag})}})
    $scale.Add_MouseDown({if(-not $state.Sync){$state.GestureBefore=Get-ModelSnapshot $state.Model}})
    $scale.Add_MouseUp({& $finishGesture})
    $scale.Add_ValueChanged({
        $scaleLabel.Text=('{0:0.0}x' -f ($scale.Value/10.0))
        if(-not $state.Sync){& $changeValues 'Factor' ($scale.Value/10.0) @($grid.SelectedRows | ForEach-Object {[string]$_.Tag})}
    })
    $sizeInput.Add_ValueChanged({if(-not $state.Sync -and $sizeInput.Enabled){& $changeValues 'Size' ([int]$sizeInput.Value) @($grid.SelectedRows | ForEach-Object {[string]$_.Tag})}})
    $copyValues={
        if(-not $grid.CurrentRow -or $state.Pipeline){return}
        $id=[string]$grid.CurrentRow.Tag;$node=$state.Model.Nodes[$id]
        $values=@{Font=[string](Get-NodeValue $state.Model $id 'Font')}
        if($node.Depth -eq 2){$size=[int](Get-NodeValue $state.Model $id 'Size');if($size -gt 0){$values.Size=$size}}
        else{$values.Factor=[double](Get-NodeValue $state.Model $id 'Factor')}
        [Windows.Forms.Clipboard]::SetText((@{VGUIFontChangerValues=1;Values=$values}|ConvertTo-Json -Compress))
    }
    $readClipboardValues={param([string]$text='')
        if(-not $text){if(-not [Windows.Forms.Clipboard]::ContainsText()){return $null};$text=[Windows.Forms.Clipboard]::GetText()}
        if($text.Length -gt 16384){return $null}
        try{
            $data=ConvertTo-PlainValue ($text|ConvertFrom-Json)
            if($data.VGUIFontChangerValues -ne 1 -or $data.Values -isnot [hashtable]){return $null}
            $validated=ConvertTo-NodeSettings @{Nodes=@{'group|clipboard|variant|1|1'=$data.Values}}
            return $validated['group|clipboard|variant|1|1']
        }catch{return $null}
    }
    $pasteValues={param($values=$null)
        if($state.Pipeline -or -not $grid.SelectedRows.Count){return}
        if(-not $values){$values=& $readClipboardValues};if(-not $values){return}
        $before=Get-ModelSnapshot $state.Model
        try{
            foreach($row in $grid.SelectedRows){
                $id=[string]$row.Tag;$node=$state.Model.Nodes[$id]
                if($values.ContainsKey('Font')){Set-NodeValue $state.Model $id 'Font' $values.Font}
                if($node.Depth -eq 2 -and $values.ContainsKey('Size') -and [int](Get-NodeValue $state.Model $id 'Size') -gt 0){Set-NodeValue $state.Model $id 'Size' $values.Size}
                elseif($node.Depth -lt 2 -and $values.ContainsKey('Factor')){Set-NodeValue $state.Model $id 'Factor' $values.Factor}
            }
            $null=Complete-ModelChange $state.Model $before;& $refresh
        }catch{
            $state.Model.Settings=(ConvertTo-PlainValue ($before|ConvertFrom-Json)).Nodes
            [Windows.Forms.MessageBox]::Show($form,$_.Exception.Message,'VGUIFontChanger','OK','Error')|Out-Null
        }
    }
    $contextCopy.Add_Click({& $copyValues;$context.Close()})
    $contextPaste.Add_Click({& $pasteValues;$context.Close()})
    $contextReset.Add_Click({$context.Close();& $resetValues @($grid.SelectedRows | ForEach-Object {[string]$_.Tag})})
    $context.Add_Opening({param($sender,$e)
        if($state.Pipeline -or -not $grid.SelectedRows.Count){$e.Cancel=$true;return}
        & $syncToolbar
        $contextPaste.Enabled=($null -ne (& $readClipboardValues))
        $contextCopy.Enabled=($null -ne $grid.CurrentRow)
    })
    $context.Add_Closing({& $finishGesture})
    $grid.Add_CellMouseDown({param($sender,$e)
        if($e.Button -ne 'Right' -or $e.RowIndex -lt 0){return}
        $row=$grid.Rows[$e.RowIndex];$selected=$row.Selected
        if(-not $selected){$grid.ClearSelection();$grid.CurrentCell=$row.Cells['Node'];$row.Selected=$true}
        # Preserve the multi-selection and its anchor when opening on a selected row.
        & $syncToolbar
    })
    $grid.Add_SelectionChanged({
        $inline.Visible=$false;$inlineSize.Visible=$false
        if($state.Sync){return}
        & $syncToolbar
    })
    $grid.Add_CellClick({param($sender,$e)
        if($e.RowIndex -lt 0 -or $e.ColumnIndex -ne 0){return}
        $id=[string]$grid.Rows[$e.RowIndex].Tag;$node=$state.Model.Nodes[$id]
        $hit=($grid.PointToClient([Windows.Forms.Cursor]::Position).X - $grid.GetCellDisplayRectangle(0,$e.RowIndex,$false).X)
        if($node.Children.Count -gt 0 -and $hit -lt (28+$node.Depth*16)*($state.Dpi/96.0)*$state.Model.Preferences.ListZoom){$node.Expanded=-not $node.Expanded;& $rebuildRows}
    })
    $grid.Add_CellDoubleClick({param($sender,$e)
        if($e.RowIndex -lt 0 -or $e.ColumnIndex -lt 0){return}
        $id=[string]$grid.Rows[$e.RowIndex].Tag;$column=$grid.Columns[$e.ColumnIndex].Name;$node=$state.Model.Nodes[$id]
        if($column -in @('Node','Original')){
            # PS 5.1's object-array binder fails on List[object] inside @(...).
            # Enumerate through a pipeline instead (aliases store generic lists).
            if($node.Depth -gt 0){Show-FontUsesWindow $form ([pscustomobject]@{Font=$node.Label;Locations=@($node.Locations | ForEach-Object {$_})}) $state.Model.Preferences.Locale -Theme $state.Theme -SmokeTest:$SmokeTest}
            elseif($node.Children.Count){$node.Expanded=-not $node.Expanded;& $rebuildRows}
        }elseif($column -eq 'Replacement'){
            if($state.Model.Settings.ContainsKey($id) -and $state.Model.Settings[$id].ContainsKey('Font')){& $resetValues @($id) 'Font';return}
            $state.EditorId=$id;$inline.Bounds=$grid.GetCellDisplayRectangle($e.ColumnIndex,$e.RowIndex,$false)
            if(-not $inline.Items.Contains([string](Get-NodeValue $state.Model $id 'Font'))){$null=$inline.Items.Add([string](Get-NodeValue $state.Model $id 'Font'))}
            $inline.SelectedItem=[string](Get-NodeValue $state.Model $id 'Font');$inline.Visible=$true;$inline.BringToFront();$inline.Focus();$inline.DroppedDown=$true
        }elseif($column -eq 'Scale'){
            if($node.Depth -eq 2){
                if($state.Model.Settings.ContainsKey($id) -and $state.Model.Settings[$id].ContainsKey('Size')){& $resetValues @($id) 'Size';return}
                $size=[int](Get-NodeValue $state.Model $id 'Size');if($size -lt 1){return}
                $state.EditorId=$id;$state.Sync=$true;try{$inlineSize.Value=[Math]::Min(512,$size)}finally{$state.Sync=$false}
                $inlineSize.Bounds=$grid.GetCellDisplayRectangle($e.ColumnIndex,$e.RowIndex,$false);$inlineSize.Visible=$true;$inlineSize.BringToFront();$inlineSize.Focus()
            }else{& $resetValues @($id) 'Factor'}
        }
    })
    $inline.Add_SelectionChangeCommitted({if($state.EditorId -and $inline.SelectedIndex -ge 0){& $changeValues 'Font' ([string]$inline.SelectedItem) @($state.EditorId);$inline.Visible=$false}})
    $inline.Add_DropDownClosed({$inline.Visible=$false});$grid.Add_Scroll({$inline.Visible=$false;$inlineSize.Visible=$false})
    $inlineSize.Add_ValueChanged({if(-not $state.Sync -and $inlineSize.Visible -and $state.EditorId){& $changeValues 'Size' ([int]$inlineSize.Value) @($state.EditorId)}})
    $inlineSize.Add_KeyDown({param($sender,$e);if($e.KeyCode -in @('Enter','Escape')){$inlineSize.Visible=$false;$grid.Focus();$e.SuppressKeyPress=$true}})
    $changeCellScale={param($e)
        if($e.RowIndex -lt 0 -or $e.ColumnIndex -lt 0 -or $grid.Columns[$e.ColumnIndex].Name -ne 'Scale'){return}
        $id=[string]$grid.Rows[$e.RowIndex].Tag;$width=$grid.Columns[$e.ColumnIndex].Width
        if($state.Model.Nodes[$id].Depth -eq 2){return}
        $unit=($state.Dpi/96.0)*$state.Model.Preferences.ListZoom
        $ratio=[Math]::Min(1.0,[Math]::Max(0.0,($e.X-14*$unit)/[double][Math]::Max(1,$width-69*$unit)))
        $value=[Math]::Round((0.1+3.9*$ratio)*10)/10
        & $changeValues 'Factor' $value @($id)
        $state.Sync=$true;try{$scale.Value=[int]($value*10)}finally{$state.Sync=$false}
    }
    $grid.Add_CellMouseDown({param($sender,$e)
        if($e.Button -eq 'Left' -and $e.Clicks -eq 1 -and $e.ColumnIndex -ge 0 -and $grid.Columns[$e.ColumnIndex].Name -eq 'Scale'){$state.GestureBefore=Get-ModelSnapshot $state.Model;& $changeCellScale $e}
    })
    $grid.Add_CellMouseMove({param($sender,$e);if($e.Button -eq 'Left'){& $changeCellScale $e}})
    $grid.Add_CellMouseUp({& $finishGesture})
    $grid.Add_MouseUp({& $finishGesture})
    $scale.Add_LostFocus({& $finishGesture})
    $grid.Add_CellToolTipTextNeeded({param($sender,$e)
        if($e.RowIndex -lt 0 -or $e.ColumnIndex -lt 0){return}
        $id=[string]$grid.Rows[$e.RowIndex].Tag;$node=$state.Model.Nodes[$id]
        $e.ToolTipText=Get-UiText 'InheritanceHint' $state.Model.Preferences.Locale
        if($grid.Columns[$e.ColumnIndex].Name -eq 'Scale'){$e.ToolTipText=(Get-UiText 'OriginalSizes' $state.Model.Preferences.Locale @($node.Sizes))+' '+$e.ToolTipText}
    })
    $grid.Add_CellPainting({param($sender,$e)
        if($e.RowIndex -lt 0 -or $e.ColumnIndex -lt 0){return}
        $row=$grid.Rows[$e.RowIndex];$id=[string]$row.Tag;$node=$state.Model.Nodes[$id];$column=$grid.Columns[$e.ColumnIndex].Name
        $theme=$state.Theme;$b=$e.CellBounds;$selected=$row.Selected;$unit=($state.Dpi/96.0)*$state.Model.Preferences.ListZoom
        $bg=if($selected){$theme.Selection}elseif($node.Depth -eq 0){$theme.Panel}else{$theme.Back};$fg=if($selected){$theme.SelectedText}else{$theme.Fore}
        $brush=New-Object Drawing.SolidBrush($bg);try{$e.Graphics.FillRectangle($brush,$b)}finally{$brush.Dispose()}
        $pen=New-Object Drawing.Pen($theme.Border);try{$e.Graphics.DrawRectangle($pen,$b.X,$b.Y,$b.Width-1,$b.Height-1)}finally{$pen.Dispose()}
        $property=if($column -eq 'Replacement'){'Font'}elseif($column -eq 'Scale'){if($node.Depth -eq 2){'Size'}else{'Factor'}}else{''}
        $explicit=($property -and $state.Model.Settings.ContainsKey($id) -and $state.Model.Settings[$id].ContainsKey($property))
        if($column -eq 'Scale'){
            if([string]$row.Cells['Scale'].Value -eq ''){$e.Handled=$true;return}
            if($node.Depth -eq 2){
                $text=[string](Get-NodeValue $state.Model $id 'Size');if($explicit){$text+=' ●'}
                $brush=New-Object Drawing.SolidBrush($fg);try{$e.Graphics.DrawString($text,$grid.Font,$brush,[single]($b.X+8*$unit),[single]($b.Y+11*$unit))}finally{$brush.Dispose()}
                $e.Handled=$true;return
            }
            $factor=[double](Get-NodeValue $state.Model $id 'Factor');$left=[single]($b.X+14*$unit);$right=[single]([Math]::Max($left+1,$b.Right-55*$unit));$y=[single]($b.Y+$b.Height/2.0)
            $pen=New-Object Drawing.Pen($theme.Border,[single](3*$unit));try{$e.Graphics.DrawLine($pen,$left,$y,$right,$y)}finally{$pen.Dispose()}
            $x=$left+[int](($right-$left)*($factor-0.1)/3.9);$accent=New-Object Drawing.SolidBrush($theme.Accent)
            try{$e.Graphics.FillEllipse($accent,[single]($x-6*$unit),[single]($y-6*$unit),[single](12*$unit),[single](12*$unit))}finally{$accent.Dispose()}
            $text=('{0:0.0}x' -f $factor);if($explicit){$text+=' ●'}
            $brush=New-Object Drawing.SolidBrush($fg);try{$e.Graphics.DrawString($text,$grid.Font,$brush,[single]($b.Right-51*$unit),[single]($b.Y+11*$unit))}finally{$brush.Dispose()}
        }else{
            $text=[string]$row.Cells[$column].Value;$font=$grid.Font
            if(($column -eq 'Replacement' -or ($column -eq 'Node' -and $node.Depth -eq 0)) -and $text){
                $family=$text;if($column -eq 'Node'){$family=$node.Original}
                $factor=1.0;if($column -eq 'Replacement'){$factor=[double](Get-NodeValue $state.Model $id 'Factor')}
                if($node.Depth -eq 2 -and $column -eq 'Replacement'){$original=0;$null=[int]::TryParse([string]$node.Sizes,[ref]$original);if($original -gt 0){$factor=[double](Get-NodeValue $state.Model $id 'Size')/$original}}
                $font=Get-PreviewFont $state.FontCache $family $state.PrivateFamilies $factor ([single](17*$unit))
                if(-not $state.PreviewAvailable.ContainsKey($family)){$state.PreviewAvailable[$family]=Test-PreviewFontAvailable $family $state.PrivateFamilies}
                if(-not $state.PreviewAvailable[$family]){$text+=' ['+(Get-UiText 'Unavailable' $state.Model.Preferences.Locale)+']'}
            }
            if($explicit -and $text){$text+=' ●'}
            $format=New-Object Drawing.StringFormat;$format.LineAlignment='Center';$format.Trimming='EllipsisCharacter';$format.FormatFlags='NoWrap'
            $rect=[Drawing.RectangleF]::new([single]($b.X+6*$unit),[single]$b.Y,[single]([Math]::Max(1,$b.Width-12*$unit)),[single]$b.Height)
            $brush=New-Object Drawing.SolidBrush($fg);try{$e.Graphics.DrawString($text,$font,$brush,$rect,$format)}finally{$brush.Dispose();$format.Dispose()}
        }
        $e.Handled=$true
    })
    $form.Add_KeyDown({param($sender,$e)
        if($state.Pipeline){return}
        if($e.KeyCode -eq 'Escape' -and $findPanel.Visible){& $closeFind;$e.SuppressKeyPress=$true;return}
        if($e.KeyCode -eq 'F3' -or ($e.KeyCode -eq 'Enter' -and $findBox.Focused)){
            if(-not $findPanel.Visible){& $openFind}
            if($e.Shift){& $runFind -1}else{& $runFind 1}
            $e.SuppressKeyPress=$true;return
        }
        if($e.Control -and $grid.Focused -and $e.KeyCode -in @('C','V')){
            if($e.KeyCode -eq 'C'){& $copyValues}else{& $pasteValues}
            $e.SuppressKeyPress=$true;return
        }
        if($e.Control -and $e.Shift -and $e.KeyCode -eq 'Z'){if(Invoke-ModelHistory $state.Model 'Redo'){& $rebuildRows;& $refresh;& $persistUi};$e.SuppressKeyPress=$true}
        if($e.KeyCode -in @('Left','Right') -and $grid.Focused -and $grid.CurrentRow){
            $node=$state.Model.Nodes[[string]$grid.CurrentRow.Tag];if($node.Children.Count){$node.Expanded=($e.KeyCode -eq 'Right');& $rebuildRows;$e.SuppressKeyPress=$true}
        }
    })
    [VguiTaskTimer]::Reset()
    $timer=New-Object VguiTaskTimer;$timer.Interval=100;$timer.MainWindow=$form
    $timer.Add_Tick({
        if($state.SearchDue -and [DateTime]::UtcNow -ge $state.SearchDue -and -not $state.Pipeline){& $runFind 1 $true}
        if($state.LayoutSaveAt -and [DateTime]::UtcNow -ge $state.LayoutSaveAt){& $flushLayout}
        if($state.GestureBefore -and [Windows.Forms.Control]::MouseButtons -ne [Windows.Forms.MouseButtons]::Left){& $finishGesture}
        $state.ThemeTick++
        if($state.ThemeTick -ge 10){$state.ThemeTick=0;$theme=Get-UiTheme $state.Model.Preferences.Theme;if($theme.Name -ne $state.ThemeName){& $refresh}}
        if(-not $state.Pipeline){
            $idle=(Get-UiText 'GameFolder' $state.Model.Preferences.Locale)+': '+$state.Game
            if($status.Text -ne $idle){$status.ToolTipText=$status.Text}
            $status.Text=$idle;return
        }
        if($state.OperationDialog){
            $dialog=$state.OperationDialog
            $dialog.Message.Text=if($state.Work.Cancel){Get-UiText 'Cancelling' $state.Model.Preferences.Locale}else{ConvertTo-UiStatus ([string]$state.Work.Message) $state.Model.Preferences.Locale}
            $dialog.Button.Enabled=($state.Work.CanCancel -and -not $state.Work.Cancel)
        }
        if(-not $state.Handle.IsCompleted){return}
        try{
            $results=$state.Pipeline.EndInvoke($state.Handle);if($state.Pipeline.Streams.Error.Count){throw $state.Pipeline.Streams.Error[0]}
            $result=$results[$results.Count-1]
            if($state.Task -eq 'Scan'){
                $state.Game=$result.Game
                $state.ScanSnapshot=$result.ScanSnapshot
                foreach($font in $state.FontCache.Values){$font.Dispose()};$state.FontCache.Clear();$state.PreviewAvailable.Clear();$state.PrivateFamilies.Clear()
                foreach($store in $state.PrivateStores){$store.Dispose()};$state.PrivateStores.Clear()
                foreach($asset in $result.GameFonts){
                    $store=New-PrivateFontStore
                    try{$store.Add($asset.Path);$families=@($store.Collection.Families);foreach($family in $families){$state.PrivateFamilies[$family.Name]=$family}
                        if($families.Count){foreach($name in $asset.Names){if(-not $state.PrivateFamilies.ContainsKey($name)){$state.PrivateFamilies[$name]=$families[0]}}};$state.PrivateStores.Add($store)
                    }catch{$store.Dispose()}
                }
                $layout=ConvertTo-PlainValue $state.Model.Preferences
                $layout.GamePath=$result.Game
                $state.Model=New-FontHierarchy $result.Summary $result.Profile $state.Model.Preferences.Locale $state.Model.Preferences.Theme
                $state.Model.Preferences=$layout
                & $persistUi
                $state.SavedNodes=$state.Model.Settings|ConvertTo-Json -Depth 12 -Compress
                $state.Fonts=@(@($result.Families)+@($state.PrivateFamilies.Keys)+@($state.Model.Settings.Values | Where-Object {$_.ContainsKey('Font')} | ForEach-Object Font) | Sort-Object -Unique)
                $fontBox.Items.Clear();$inline.Items.Clear();foreach($name in $state.Fonts){$null=$fontBox.Items.Add($name);$null=$inline.Items.Add($name)}
                & $rebuildRows;$status.Text=Get-UiText 'TreeHint' $state.Model.Preferences.Locale
            }elseif($state.Task -eq 'Import'){
                $before=Get-ModelSnapshot $state.Model
                # Legacy embedded Preferences remain deliberately ignored.
                $state.Model.Settings=ConvertTo-PlainValue $result.Settings
                $null=Complete-ModelChange $state.Model $before;& $rebuildRows;& $refresh
                $status.Text=Get-UiText 'Imported' $state.Model.Preferences.Locale
            }elseif($state.Task -eq 'Export'){
                $status.Text=Get-UiText 'Exported' $state.Model.Preferences.Locale
            }elseif($state.Task -eq 'Save'){
                $state.SavedNodes=$state.Model.Settings|ConvertTo-Json -Depth 12 -Compress
                $status.Text=Get-UiText 'Saved' $state.Model.Preferences.Locale
            }elseif($state.Task -eq 'RemoveOverride'){
                $status.Text=Get-UiText 'Removed' $state.Model.Preferences.Locale
            }else{
                $state.SavedNodes=$state.Model.Settings|ConvertTo-Json -Depth 12 -Compress
                $status.Text=Get-UiText 'Applied' $state.Model.Preferences.Locale @($result.Changed,$result.SizeChanged)
                if($state.OperationDialog){Close-AboutDialog $state.OperationDialog;$state.OperationDialog=$null;$form.Enabled=$true}
                if(-not $SmokeTest){$null=[Windows.Forms.MessageBox]::Show($form,(Get-UiText 'ApplySuccess' $state.Model.Preferences.Locale @($result.FileCount)),'VGUIFontChanger','OK','Information')}
            }
        }catch{if($state.Work.Cancel){$status.Text=Get-UiText 'Cancelled' $state.Model.Preferences.Locale}else{$status.Text=$_.Exception.Message;Write-VfcLog 'ERROR' ($_.Exception.ToString()+[Environment]::NewLine+$_.ScriptStackTrace) -LogFile $state.Work.LogPath;if($state.OperationDialog){Close-AboutDialog $state.OperationDialog;$state.OperationDialog=$null;$form.Enabled=$true};if(-not $SmokeTest){Show-OperationError $form $state.Model.Preferences.Locale $state.Theme $state.Work.LogPath}}}
        finally{$status.ToolTipText=$status.Text;$state.Pipeline.Dispose();$state.Pipeline=$null;$state.Handle=$null;& $busy $false;if($findPanel.Visible){& $runFind 0 $true};if($state.Closing){$state.Closing=$false;$form.Close()}}
    })
    $form.Add_FormClosing({param($sender,$e)
        if($state.Pipeline){$e.Cancel=$true;$state.Closing=$true;if($state.Work.CanCancel){$state.Work.Cancel=$true};return}
        if(-not $SmokeTest -and -not (& $confirmDiscard)){$e.Cancel=$true}
    })
    & $refresh;& $persistUi
    $form.Add_Shown({$timer.Start();& $startScan $GamePath})
    try{
        if($SmokeTest){
            $fixtureSummary=@([pscustomobject]@{Font='Tahoma';Kind='Text';Sizes='10';Locations=@([pscustomobject]@{Id='group|Tahoma|alias|fixture|Text|variant|1|1';AliasId='group|Tahoma|alias|fixture|Text';GroupId='group|Tahoma';Alias='Text';Variant='1';Condition='yres 720 1080';Scheme='fixture';Source='fixture';Line=1;Tall='10';Context=(Get-NumberedContext 'name Tahoma' 1)})})
            $state.Model=New-FontHierarchy $fixtureSummary @{Nodes=@{}} $state.Model.Preferences.Locale 'System'
            & $rebuildRows;& $refresh;$form.PerformLayout()
            if($grid.Columns.Contains('Uses') -or $statusBar.Dock -ne 'Bottom' -or $menu.Items.Count -ne 4){throw 'Hierarchy GUI layout test failed'}
            if($statusBar.Items.Count -ne 1){throw 'Progress/cancel controls must not remain in the status bar'}
            $operation=[hashtable]::Synchronized(@{Cancel=$false;CanCancel=$true;Message='Starting...'})
            $operationDialog=New-AboutDialog $form $state.Model.Preferences.Locale $state.Theme $operation 'Scan'
            try{
                $operationDialog.Window.Show($form);$operationDialog.Window.CenterOnOwner()
                $form.Enabled=$false
                if($operationDialog.Window.Text -ne (Get-UiText 'TaskScan' $state.Model.Preferences.Locale)){throw 'Operation dialog task title failed'}
                if(-not $operationDialog.Window.OperationActive -or $operationDialog.Window.ControlBox -or $operationDialog.Window.CancelButton){throw 'Operation dialog must not allow closing'}
                if($operationDialog.Progress.Style -ne 'Marquee' -or -not $operationDialog.Progress.Visible -or -not $operationDialog.Credits.Enabled){throw 'Operation About/progress controls/link failed'}
                $position=$operationDialog.Window.Location
                $operationDialog.Window.Left+=40
                if($operationDialog.Window.Location -ne $position){throw 'Operation dialog must remain centered'}
                $operationDialog.Window.Close()
                if($operationDialog.Window.IsDisposed){throw 'Operation dialog accepted a close while busy'}
                $operationDialog.Button.PerformClick()
                if(-not $operation.Cancel -or $operationDialog.Button.Enabled -or $operationDialog.Message.Text -ne (Get-UiText 'Cancelling' $state.Model.Preferences.Locale)){throw 'Operation cancellation button failed'}
                $operationDialog.Window.UpdateUiDpi(144)
                if($operationDialog.Window.ClientSize.Width -ne 720){throw 'Operation dialog DPI test failed'}
            }finally{Close-AboutDialog $operationDialog}
            if(-not $form.Enabled){throw 'Operation close must re-enable its owner before disposal'}
            $form.UpdateUiDpi(96)
            if($menu.Bottom -gt $grid.Top -or $grid.Bottom -gt $statusBar.Top){throw 'Docked menu, hierarchy or status bar overlap'}
            if($contextHost.Control -ne $contextPanel -or $fontBox.Parent -ne $contextPanel -or $scale.Parent -ne $contextPanel){throw 'Context menu editors were not hosted'}
            $root=$state.Model.Nodes[$state.Model.Roots[0]];$root.Expanded=$true;$state.Model.Nodes[$root.Children[0]].Expanded=$true
            & $rebuildRows;if($grid.Rows.Count -ne 3){throw 'Hierarchy expansion test failed'}
            $bitmap=New-Object Drawing.Bitmap(1100,50);$graphics=[Drawing.Graphics]::FromImage($bitmap)
            try{
                $drawMethod=[Windows.Forms.ComboBox].GetMethod('OnDrawItem',[Reflection.BindingFlags]'Instance,NonPublic')
                foreach($combo in @($fontBox,$inline)){$null=$combo.Items.Add('Tahoma');$args=New-Object Windows.Forms.DrawItemEventArgs($graphics,$form.Font,(New-Object Drawing.Rectangle(0,0,400,40)),0,[Windows.Forms.DrawItemState]::Default);$null=$drawMethod.Invoke($combo,[object[]]@($args.PSObject.BaseObject))}
                $paint=[Windows.Forms.DataGridView].GetMethod('OnCellPainting',[Reflection.BindingFlags]'Instance,NonPublic')
                foreach($themeName in @('Light','Dark','AMOLED')){
                    $state.Model.Preferences.Theme=$themeName;& $refresh
                    Show-AboutWindow $null $state.Model.Preferences.Locale $state.Theme -SmokeTest
                    Show-FontUsesWindow $null ([pscustomobject]@{Font='Text';Locations=$fixtureSummary[0].Locations}) $state.Model.Preferences.Locale -SmokeTest -Theme $state.Theme
                    foreach($column in $grid.Columns){
                        $b=$grid.GetCellDisplayRectangle($column.Index,2,$false);$cell=$grid.Rows[2].Cells[$column.Index];$text=$cell.Value
                        $args=[Windows.Forms.DataGridViewCellPaintingEventArgs]::new($grid,$graphics,$b,$b,2,$column.Index,[Windows.Forms.DataGridViewElementStates]::Visible,$text,$text,'',$cell.InheritedStyle,$grid.AdvancedCellBorderStyle,[Windows.Forms.DataGridViewPaintParts]::All)
                        $null=$paint.Invoke($grid,[object[]]@($args.PSObject.BaseObject));if(-not $args.Handled){throw 'Hierarchy cell painting failed'}
                    }
                }
                $grid.ClearSelection();$grid.CurrentCell=$grid.Rows[0].Cells['Node'];$grid.Rows[0].Selected=$true
                $before=Get-ModelSnapshot $state.Model;& $changeValues 'Factor' 2.0 @($root.Id)
                if([double](Get-NodeValue $state.Model $grid.Rows[2].Tag 'Factor') -ne 2.0){throw 'GUI propagation failed'}
                if(-not (Invoke-ModelHistory $state.Model 'Undo')){throw 'GUI undo failed'}
                & $refresh
                $undoCount=$state.Model.Undo.Count;$factorColumn=$grid.Columns['Scale'].Index;$trackWidth=$grid.Columns['Scale'].Width-69
                foreach($methodName in @('OnCellMouseDown','OnCellMouseMove','OnCellMouseUp')){
                    $method=[Windows.Forms.DataGridView].GetMethods([Reflection.BindingFlags]'Instance,NonPublic') | Where-Object {$_.Name -eq $methodName -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType -eq [Windows.Forms.DataGridViewCellMouseEventArgs]} | Select-Object -First 1
                    $samples=@(0.0);if($methodName -eq 'OnCellMouseMove'){$samples=@(0.2,0.4,0.6,0.8,1.0)}elseif($methodName -eq 'OnCellMouseUp'){$samples=@(1.0)}
                    foreach($ratio in $samples){
                        $x=14+[int]($trackWidth*$ratio);$mouse=New-Object Windows.Forms.MouseEventArgs([Windows.Forms.MouseButtons]::Left,1,$x,20,0)
                        $args=New-Object Windows.Forms.DataGridViewCellMouseEventArgs($factorColumn,1,$x,20,$mouse)
                        $null=$method.Invoke($grid,[object[]]@($args.PSObject.BaseObject))
                        if($methodName -ne 'OnCellMouseUp'){
                            $expected=[Math]::Round((0.1+3.9*(($x-14)/[double]$trackWidth))*10)/10
                            if([double](Get-NodeValue $state.Model $grid.Rows[1].Tag 'Factor') -ne $expected){throw 'Hierarchical slider position failed'}
                        }
                    }
                }
                if($state.Model.Undo.Count -ne $undoCount+1 -or $state.GestureBefore){throw 'Slider drag was not one undo step'}
                $null=Invoke-ModelHistory $state.Model 'Undo'; & $refresh
                if([string]$grid.Rows[2].Cells['Scale'].Value -ne '' -or $scale.Value -ne 10){throw 'Undo did not synchronize inherited rows and menu'}
                if($grid.Columns.Contains('Original') -or $grid.Columns.Count -ne 3 -or $form.Controls.Count -ne 4 -or $grid.Font.Name -ne 'Consolas' -or $form.Font.FontFamily.Name -ne [Drawing.SystemFonts]::MessageBoxFont.FontFamily.Name){throw 'System UI font / monospace list test failed'}
                if([string]$grid.Rows[1].Cells['Replacement'].Value -ne '' -or [string]$grid.Rows[2].Cells['Replacement'].Value -ne ''){throw 'Inherited font cells must be blank'}
                $doubleClick=[Windows.Forms.DataGridView].GetMethod('OnCellDoubleClick',[Reflection.BindingFlags]'Instance,NonPublic')
                foreach($rowIndex in @(1,2)){
                    $args=New-Object Windows.Forms.DataGridViewCellEventArgs(0,$rowIndex)
                    $null=$doubleClick.Invoke($grid,[object[]]@($args.PSObject.BaseObject))
                }
                $grid.ClearSelection();$grid.CurrentCell=$grid.Rows[2].Cells['Scale'];$grid.Rows[2].Selected=$true;& $syncToolbar
                if(-not $sizeInput.Enabled -or $scale.Visible){throw 'Leaf menu must use numeric size'}
                $values=& $readClipboardValues '{"VGUIFontChangerValues":1,"Values":{"Font":"Arial","Size":27}}'
                & $pasteValues $values
                if((Get-NodeValue $state.Model $grid.Rows[2].Tag 'Size') -ne 27 -or $grid.Rows[2].Cells['Scale'].Value -ne 27){throw 'Pasted absolute size failed'}
                $null=Invoke-ModelHistory $state.Model 'Undo';& $refresh
                if([string]$grid.Rows[2].Cells['Scale'].Value -ne ''){throw 'Paste undo did not restore inheritance'}
                if($commands.Save.ShortcutKeys -ne [Windows.Forms.Keys]'Control,S' -or $commands.Apply.ShortcutKeys -ne [Windows.Forms.Keys]'Control,Shift,A'){throw 'Save/apply shortcuts failed'}
                if(-not $commands.LaunchGame.CheckOnClick){throw 'Launch game option failed'}
                $commands.LaunchGame.PerformClick()
                if(-not $state.Model.Preferences.LaunchGame){throw 'Launch game preference toggle failed'}
                $commands.LaunchGame.PerformClick()
                if($state.Model.Preferences.LaunchGame){throw 'Launch game preference toggle failed'}
                if(-not $commands.EffectiveOnly.CheckOnClick){throw 'Effective aliases option failed'}
                if($state.Model.Preferences.EffectiveOnly -eq $false){throw 'Effective aliases default failed'}
                $commands.EffectiveOnly.PerformClick()
                if($state.Model.Preferences.EffectiveOnly){throw 'Effective aliases preference toggle failed'}
                $commands.EffectiveOnly.PerformClick()
                if($state.Model.Preferences.EffectiveOnly -eq $false){throw 'Effective aliases preference toggle failed'}
                if($contextPanel.Controls.Count -ne 5 -or $sizeUnit.Text -ne 'px'){throw 'Compact context menu test failed'}
                $null=$form.Handle;$form.UpdateUiDpi(96)
                $nodesBefore=$state.Model.Settings|ConvertTo-Json -Depth 12 -Compress
                $form.UpdateUiDpi(144)
                if([Math]::Abs($grid.Font.Size-25.5) -gt 0.01 -or $grid.Rows[0].Height -ne 72 -or $contextPanel.Width -ne 585){throw 'Main window dynamic DPI metrics failed'}
                $grid.RequestZoom(120)
                if($state.Model.Preferences.ListZoom -ne 1.1 -or [Math]::Abs($grid.Font.Size-28.05) -gt 0.01 -or -not $state.LayoutSaveAt){throw 'Ctrl-wheel zoom or debounce scheduling failed'}
                $labelPaint=[Windows.Forms.Label].GetMethod('OnPaint',[Reflection.BindingFlags]'Instance,NonPublic')
                foreach($label in @($scaleLabel,$sizeUnit)){
                    $label.UseCompatibleTextRendering=$true
                    $args=New-Object Windows.Forms.PaintEventArgs($graphics,(New-Object Drawing.Rectangle(0,0,$label.Width,$label.Height)))
                    $null=$labelPaint.Invoke($label,[object[]]@($args.PSObject.BaseObject))
                }
                $profile=Get-HierarchyProfile $state.Model
                if($profile.ContainsKey('Preferences') -or ($state.Model.Settings|ConvertTo-Json -Depth 12 -Compress) -cne $nodesBefore){throw 'Layout settings leaked into game settings'}
                $grid.RequestZoom(-120);$form.UpdateUiDpi(96)
                if([Math]::Abs($grid.Font.Size-17) -gt 0.01){throw 'DPI/zoom round-trip drifted'}
                # Paint the actual label delegates, not just the grid's custom
                # renderer. WinForms can retain an equal-valued previous Font.
                $labelPaint=[Windows.Forms.Label].GetMethod('OnPaint',[Reflection.BindingFlags]'Instance,NonPublic')
                foreach($label in @($scaleLabel,$sizeUnit)){
                    $args=New-Object Windows.Forms.PaintEventArgs($graphics,(New-Object Drawing.Rectangle(0,0,$label.Width,$label.Height)))
                    $null=$labelPaint.Invoke($label,[object[]]@($args.PSObject.BaseObject))
                }
                $settingsBeforeSearch=ConvertTo-PlainValue $state.Model.Settings
                $gridBoundsBeforeFind=$grid.Bounds
                & $openFind;$form.PerformLayout();& $layoutFind
                if($findPanel.Dock -ne 'None' -or $grid.Bounds -ne $gridBoundsBeforeFind -or $findPanel.Right -gt $grid.Right -or $findPanel.Bottom -gt $grid.Bottom -or $findPanel.Left -le $grid.Left -or $findPanel.Top -le $grid.Top -or $form.Controls.GetChildIndex($findPanel) -ne 0){throw 'Bottom-right floating search layout failed'}
                $oldFormSize=$form.Size;$form.Size=New-Object Drawing.Size([int]($form.Width+100),[int]($form.Height+80));$form.PerformLayout();& $layoutFind
                if([Math]::Abs(($grid.Right-$findPanel.Right)-12) -gt 1 -or [Math]::Abs(($grid.Bottom-$findPanel.Bottom)-12) -gt 1){throw 'Floating search did not follow window resize'}
                $form.UpdateUiDpi(144);$form.PerformLayout();& $layoutFind
                if([Math]::Abs(($grid.Right-$findPanel.Right)-18) -gt 1 -or [Math]::Abs(($grid.Bottom-$findPanel.Bottom)-18) -gt 1){throw 'Floating search DPI positioning failed'}
                $form.UpdateUiDpi(96);$form.Size=$oldFormSize;$form.PerformLayout();& $layoutFind
                foreach($node in $state.Model.Nodes.Values){$node.Expanded=$false};& $rebuildRows
                $findBox.Text='tExT';& $runFind 1 $true
                if($state.SearchMatches.Count -ne 1 -or [string]$grid.CurrentRow.Tag -ne $root.Children[0] -or -not $root.Expanded){throw 'Case-insensitive key search or ancestor expansion failed'}
                & $runFind 1
                if([string]$grid.CurrentRow.Tag -ne $root.Children[0] -or $grid.Rows.Count -ne 2){throw 'Find next wrap-around failed'}
                & $runFind -1
                if([string]$grid.CurrentRow.Tag -ne $root.Children[0]){throw 'Find previous wrap-around failed'}
                $findBox.Text='yres 720';& $runFind 1 $true
                if($state.SearchMatches.Count -ne 0 -or $state.SearchIndex -ne -1){throw 'Variant condition must not match'}
                $findBox.Text='FIXTURE';& $runFind 1 $true
                if($state.SearchMatches.Count -ne 1){throw 'Scheme/source filename search failed'}
                $findBox.Text='tahoma';& $runFind 1 $true
                if($state.SearchMatches.Count -ne 2){throw 'Original font search failed'}
                Set-NodeValue $state.Model $root.Children[0] 'Font' 'Arial';$findBox.Text='arial';& $runFind 1 $true
                if($state.SearchMatches.Count -ne 1 -or [string]$grid.CurrentRow.Tag -ne $root.Children[0]){throw 'Replacement font search failed'}
                $findBox.Text='[missing*literal]';& $runFind 1 $true
                if($state.SearchMatches.Count -ne 0 -or $state.SearchIndex -ne -1){throw 'Literal no-match search failed'}
                $state.Model.Settings=$settingsBeforeSearch;$findBox.Text=''; & $closeFind;& $rebuildRows
                if($commands.Find.ShortcutKeys -ne [Windows.Forms.Keys]'Control,F'){throw 'Find shortcut failed'}
                if($PreviewPath){
                    $null=$form.Handle;$form.PerformLayout()
                    $preview=New-Object Drawing.Bitmap($form.ClientSize.Width,$form.ClientSize.Height)
                    try{
                        foreach($control in @($grid,$menu,$statusBar)){
                            $x=$control.Left;$y=$control.Top
                            $control.DrawToBitmap($preview,(New-Object Drawing.Rectangle($x,$y,$control.Width,$control.Height)))
                        }
                        $preview.Save($PreviewPath,[Drawing.Imaging.ImageFormat]::Png)
                    }finally{$preview.Dispose()}
                }
                return 'GUI tests passed: Windows UI fonts, floating search/resize/DPI, alias-scoped font/key/file search, label painting, profile isolation and undo.'
            }finally{$graphics.Dispose();$bitmap.Dispose()}
        }else{$null=$form.ShowDialog()}
    }finally{
        $timer.Stop()
        if($state.Work){$state.Work.Cancel=$true}
        if($state.OperationDialog){Close-AboutDialog $state.OperationDialog -NoActivate;$state.OperationDialog=$null;$form.Enabled=$true}
        if(-not [VguiTaskTimer]::Interrupted){& $flushLayout}
        $timer.Stop();$timer.Dispose()
        $context.Dispose()
        if($state.Pipeline){
            # Ctrl+C must not force-stop the rollback-sensitive commit worker.
            if($state.Work -and -not $state.Work.CanCancel -and $state.Handle -and -not $state.Handle.IsCompleted){
                try{$null=$state.Pipeline.EndInvoke($state.Handle)}catch{}
            }else{$state.Pipeline.Stop()}
            $state.Pipeline.Dispose()
        }
        foreach($font in $state.FontCache.Values){$font.Dispose()};foreach($store in $state.PrivateStores){$store.Dispose()}
        $form.Dispose()
        foreach($font in $state.MetricFonts.Values){$font.Dispose()}
        [VguiDpiNative]::Restore($previousDpiContext)
    }
}
