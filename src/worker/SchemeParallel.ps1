function Get-SchemeDocumentsParallel {
    param([object[]]$Sources,[string[]]$Paths)
    $initial=[Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach($name in @('New-StringList','New-ObjectList','Get-VpkIndex','Initialize-VpkRuntime','Get-VpkToolIndex','Read-VpkEntryBytesWithTool','Read-VpkEntryBytes','Convert-BytesToText','Read-VirtualFile','Get-KvTokens','Test-KvConditional','New-KvNode','Read-KvNodeList','ConvertFrom-KeyValuesText','Copy-KvNode','Merge-KvBaseNode','Join-VirtualPath','Resolve-KvDocument','Test-WorkCancellation','Set-WorkStatus','Write-VfcLog','Initialize-OperationRuntime')){
        $definition=(Get-Command $name -CommandType Function).Definition
        $initial.Commands.Add([Management.Automation.Runspaces.SessionStateFunctionEntry]::new($name,$definition))
    }
    $limit=[Math]::Max(1,[Math]::Min(4,[Environment]::ProcessorCount))
    $pool=[Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool($initial)
    $null=$pool.SetMaxRunspaces($limit)
    $pool.ApartmentState='MTA';$jobs=New-ObjectList;$documents=@{}
    try{
        $pool.Open()
        foreach($path in $Paths){
            Test-WorkCancellation
            $pipeline=[PowerShell]::Create();$pipeline.RunspacePool=$pool
            $worker={param($sources,$path,$indexes,$work)
                $ErrorActionPreference='Stop';Set-StrictMode -Version 2.0
                $script:VpkIndexCache=$indexes;$script:VpkToolIndexCache=@{};$script:Work=$work;$script:LogPath='';$script:VfcLogLevel='INFO'
                Test-WorkCancellation
                if(-not (Read-VirtualFile $sources $path)){return}
                try{Resolve-KvDocument $sources $path @{}}
                catch [Management.Automation.RuntimeException]{
                    if($_.Exception.Message -like 'Virtual file not found:*'){Write-Warning $_.Exception.Message}else{throw}
                }
            }
            $null=$pipeline.AddScript($worker.ToString()).AddArgument($Sources).AddArgument($path).AddArgument($script:VpkIndexCache).AddArgument($script:Work)
            $job=@{Pipeline=$pipeline;Handle=$null;Path=$path;Done=$false};$jobs.Add($job)
            $job.Handle=$pipeline.BeginInvoke()
        }
        $remaining=$jobs.Count
        while($remaining -gt 0){
            Test-WorkCancellation
            foreach($job in $jobs){
                if($job.Done -or -not $job.Handle.IsCompleted){continue}
                $values=$job.Pipeline.EndInvoke($job.Handle)
                if($job.Pipeline.Streams.Error.Count){throw $job.Pipeline.Streams.Error[0]}
                foreach($warning in $job.Pipeline.Streams.Warning){Write-Warning $warning.Message}
                if($values.Count){$documents[$job.Path]=$values[$values.Count-1]}
                $job.Done=$true;$remaining--
            }
            if($remaining -gt 0){Start-Sleep -Milliseconds 15}
        }
        # Completion order must not change output/search order. Every job builds
        # its own AST; only immutable file contents and prebuilt VPK indexes are shared.
        foreach($path in $Paths){if($documents.ContainsKey($path)){$documents[$path]}}
    }finally{
        foreach($job in $jobs){if(-not $job.Done){$job.Pipeline.Stop()};$job.Pipeline.Dispose()}
        $pool.Close();$pool.Dispose()
    }
}
