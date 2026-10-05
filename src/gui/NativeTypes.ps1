function Initialize-GuiRuntime {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if('VguiDpiForm' -as [type]){return}
    $references=@('System.Windows.Forms','System.Drawing')
    if($PSVersionTable.PSEdition -eq 'Core'){
        $references=@(
            @(([string][AppContext]::GetData('TRUSTED_PLATFORM_ASSEMBLIES')).Split([IO.Path]::PathSeparator,[StringSplitOptions]::RemoveEmptyEntries))
            @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object Location | ForEach-Object Location)
        ) | Sort-Object -Unique
    }
    Add-Type -ReferencedAssemblies $references -TypeDefinition @'
using System;
using System.Collections;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public static class VguiDpiNative {
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    public static bool IsForeground(IntPtr owner,IntPtr dialog) {
        IntPtr foreground=GetForegroundWindow();
        return foreground!=IntPtr.Zero && (foreground==owner || foreground==dialog);
    }
    public static IntPtr Enter() {
        try { IntPtr old=SetThreadDpiAwarenessContext(new IntPtr(-4));
              if(old==IntPtr.Zero) old=SetThreadDpiAwarenessContext(new IntPtr(-3)); return old; }
        catch(EntryPointNotFoundException) { return IntPtr.Zero; }
    }
    public static void Restore(IntPtr old) {
        if(old!=IntPtr.Zero) try { SetThreadDpiAwarenessContext(old); } catch(EntryPointNotFoundException) { }
    }
    public static int Dpi(IntPtr window) {
        try { uint value=GetDpiForWindow(window); if(value>0) return (int)value; } catch(EntryPointNotFoundException) { }
        using(Graphics g=Graphics.FromHwnd(window)) return (int)g.DpiX;
    }
}
public class VguiDpiForm : Form {
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left,Top,Right,Bottom; }
    public int UiDpi { get; private set; }
    public event EventHandler UiDpiChanged;
    public VguiDpiForm() { UiDpi=96; AutoScaleMode=AutoScaleMode.None; }
    protected override void OnFormClosing(FormClosingEventArgs e) {
        if(!VguiTaskTimer.Interrupted) base.OnFormClosing(e);
    }
    protected override void OnFormClosed(FormClosedEventArgs e) {
        if(!VguiTaskTimer.Interrupted) base.OnFormClosed(e);
    }
    public void UpdateUiDpi(int dpi) {
        if(dpi<48 || dpi>768 || dpi==UiDpi) return;
        UiDpi=dpi; if(UiDpiChanged!=null) UiDpiChanged(this,EventArgs.Empty);
    }
    protected override void OnHandleCreated(EventArgs e) {
        base.OnHandleCreated(e); UpdateUiDpi(VguiDpiNative.Dpi(Handle));
    }
    protected override void WndProc(ref Message m) {
        if(m.Msg==0x02E0) {
            Rect r=(Rect)Marshal.PtrToStructure(m.LParam,typeof(Rect));
            UpdateUiDpi((int)(m.WParam.ToInt64() & 0xffff));
            Bounds=Rectangle.FromLTRB(r.Left,r.Top,r.Right,r.Bottom);m.Result=IntPtr.Zero;return;
        }
        base.WndProc(ref m);
    }
}
public class VguiTaskTimer : System.Windows.Forms.Timer {
    private bool tickActive;
    public static bool Interrupted { get; private set; }
    public Form MainWindow { get; set; }
    public IDictionary Work { get; set; }
    public static void Reset() { Interrupted=false; }
    static bool IsPipelineStop(Exception error) {
        for(Exception e=error;e!=null;e=e.InnerException)
            if(e.GetType().FullName=="System.Management.Automation.PipelineStoppedException") return true;
        return false;
    }
    protected override void OnTick(EventArgs e) {
        // Modal dialogs pump timer messages before the handler can clean up.
        // A completed worker must only be handled once.
        if(tickActive) return;
        tickActive=true;
        try { base.OnTick(e); }
        catch(Exception error) {
            if(!IsPipelineStop(error)) throw;
            // A stopped PowerShell pipeline cannot execute another scriptblock,
            // including a PowerShell catch/event handler. Finish in managed code.
            Interrupted=true; Stop();
            if(Work!=null) Work["Cancel"]=true;
            Form[] windows=new Form[Application.OpenForms.Count];
            for(int i=0;i<windows.Length;i++) windows[i]=Application.OpenForms[i];
            for(int i=windows.Length-1;i>=0;i--) {
                if(!(windows[i] is VguiDpiForm)) continue;
                VguiAboutForm operation=windows[i] as VguiAboutForm;
                if(operation!=null) operation.OperationActive=false;
                windows[i].Close();
            }
        }
        finally { tickActive=false; }
    }
}
public class VguiZoomEventArgs : EventArgs { public int Delta { get; private set; } public VguiZoomEventArgs(int delta) { Delta=delta; } }
public class VguiAboutForm : VguiDpiForm {
    public bool OperationActive { get; set; }
    private bool centering;
    public void CenterOnOwner() {
        if(Owner==null || centering) return;
        centering=true;
        try { Location=new Point(Owner.Left+(Owner.Width-Width)/2,Owner.Top+(Owner.Height-Height)/2); }
        finally { centering=false; }
    }
    protected override void OnLocationChanged(EventArgs e) {
        base.OnLocationChanged(e);
        if(OperationActive) CenterOnOwner();
    }
    protected override void OnFormClosing(FormClosingEventArgs e) {
        if(OperationActive) { e.Cancel=true; return; }
        base.OnFormClosing(e);
    }
    protected override void WndProc(ref Message m) {
        if(OperationActive && ((m.Msg==0x00A1 && m.WParam.ToInt64()==2) ||
            (m.Msg==0x0112 && ((m.WParam.ToInt64() & 0xfff0)==0xf010 ||
                              (m.WParam.ToInt64() & 0xfff0)==0xf000 ||
                              (m.WParam.ToInt64() & 0xfff0)==0xf060)))) {
            m.Result=IntPtr.Zero; return;
        }
        base.WndProc(ref m);
    }
}
public class VguiFontGrid : DataGridView {
    public event EventHandler<VguiZoomEventArgs> ZoomRequested;
    public void RequestZoom(int delta) { if(ZoomRequested!=null) ZoomRequested(this,new VguiZoomEventArgs(delta)); }
    protected override void OnMouseWheel(MouseEventArgs e) {
        if((ModifierKeys & Keys.Control)!=0) { RequestZoom(e.Delta);return; }
        base.OnMouseWheel(e);
    }
}
'@
}
