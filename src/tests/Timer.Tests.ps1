function Invoke-TimerSelfTest {
    Initialize-GuiRuntime
    $timer=New-Object VguiTaskTimer
    $tick=[VguiTaskTimer].GetMethod('OnTick',[Reflection.BindingFlags]'Instance,NonPublic')
    $probe=@{Count=0;Fail=$false}
    $handler={
        $probe.Count++
        # Simulate the nested timer dispatch caused by a modal message loop.
        $null=$tick.Invoke($timer,@([EventArgs]::Empty))
        if($probe.Fail){throw 'Timer regression fixture failure'}
    }.GetNewClosure()
    $timer.Add_Tick($handler)
    try{
        $null=$tick.Invoke($timer,@([EventArgs]::Empty))
        if($probe.Count -ne 1){throw 'Timer handler re-entered during modal dispatch'}
        $null=$tick.Invoke($timer,@([EventArgs]::Empty))
        if($probe.Count -ne 2){throw 'Timer did not resume after completion'}
        $probe.Fail=$true
        try{$null=$tick.Invoke($timer,@([EventArgs]::Empty));throw 'Timer failure was swallowed'}
        catch{if($_.Exception.ToString() -notlike '*Timer regression fixture failure*'){throw}}
        $probe.Fail=$false
        $null=$tick.Invoke($timer,@([EventArgs]::Empty))
        if($probe.Count -ne 4){throw 'Timer did not resume after a failed handler'}
    }finally{$timer.Dispose()}
    'Timer tests passed: nested dispatch suppressed; subsequent and failed ticks recover.'
}
