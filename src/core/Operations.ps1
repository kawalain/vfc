function Test-WorkCancellation {
    if($script:Work -and $script:Work.Cancel -and $script:Work.CanCancel){throw [OperationCanceledException]::new('Operation cancelled.')}
}
function Set-WorkStatus {
    param([string]$Message)
    Write-VfcLog 'TRACE' $Message
    if($script:Work){$script:Work.Message=$Message}
}
function Initialize-OperationRuntime {
    if('VfcOperationRuntime' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
public static class VfcOperationRuntime {
    static readonly object LogLock=new object();
    public static void Log(string path,string level,string message) {
        string line=DateTimeOffset.Now.ToString("o")+" ["+level+"] [thread "+System.Threading.Thread.CurrentThread.ManagedThreadId+"] "+message+Environment.NewLine;
        lock(LogLock) { File.AppendAllText(path,line,new UTF8Encoding(false)); Console.Error.Write(line); }
    }
    static void Field(byte[] header,int offset,int length,string value) {
        byte[] bytes=Encoding.UTF8.GetBytes(value);
        if(bytes.Length>length) throw new IOException("Archive path exceeds the ustar field limit: "+value);
        Buffer.BlockCopy(bytes,0,header,offset,bytes.Length);
    }
    static void Octal(byte[] header,int offset,int width,long value) {
        Field(header,offset,width,Convert.ToString(value,8).PadLeft(width-1,'0')+"\0");
    }
    static void TarDirectory(string root,string directory,string prefix,Stream output) {
        string[] paths=Directory.GetFileSystemEntries(directory);Array.Sort(paths,StringComparer.Ordinal);
        foreach(string path in paths) {
            FileAttributes flags=File.GetAttributes(path);
            if((flags & FileAttributes.ReparsePoint)!=0) throw new IOException("Backup refuses a reparse point: "+path);
            if((flags & FileAttributes.Directory)!=0) { TarDirectory(root,path,prefix,output);continue; }
            string name=prefix+"/"+path.Substring(root.Length).TrimStart('\\','/').Replace('\\','/');
            byte[] header=new byte[512];string shortName=name, parent="";
            if(Encoding.UTF8.GetByteCount(name)>100) {int slash=name.LastIndexOf('/');shortName=name.Substring(slash+1);parent=name.Substring(0,slash);}
            Field(header,0,100,shortName);Field(header,345,155,parent);Octal(header,100,8,420);
            Octal(header,108,8,0);Octal(header,116,8,0);
            using(var input=File.OpenRead(path)) {
                Octal(header,124,12,input.Length);
                Octal(header,136,12,(long)(File.GetLastWriteTimeUtc(path)-new DateTime(1970,1,1)).TotalSeconds);
                for(int i=148;i<156;i++) header[i]=32;
                header[156]=(byte)'0';Field(header,257,6,"ustar\0");Field(header,263,2,"00");
                int sum=0;foreach(byte b in header) sum+=b;
                Field(header,148,8,Convert.ToString(sum,8).PadLeft(6,'0')+"\0 ");
                output.Write(header,0,512);input.CopyTo(output);
                int padding=(int)((512-input.Length%512)%512);output.Write(new byte[padding],0,padding);
            }
        }
    }
    static void Block(Stream output,byte[] data,int start,int length,bool rle,bool last) {
        int value=(length<<3)|(rle?2:0)|(last?1:0);
        output.WriteByte((byte)value);output.WriteByte((byte)(value>>8));output.WriteByte((byte)(value>>16));
        if(rle) output.WriteByte(data[start]);else output.Write(data,start,length);
    }
    static void Zstd(Stream input,Stream output) {
        // Zstandard frame: 128 KiB window, 8-byte content size, raw/RLE blocks.
        // No external executable/DLL. Repeated runs compress; other bytes remain raw.
        output.Write(new byte[]{0x28,0xb5,0x2f,0xfd,0xc0,0x38},0,6);
        long size=input.Length;for(int i=0;i<8;i++) output.WriteByte((byte)(size>>(8*i)));
        byte[] buffer=new byte[128*1024];
        if(size==0) {Block(output,buffer,0,0,false,true);return;}
        int count;
        while((count=input.Read(buffer,0,buffer.Length))>0) {
            int begin=0,scan=0;
            while(scan<count) {
                int end=scan+1;while(end<count && buffer[end]==buffer[scan]) end++;
                if(end-scan>=16) {
                    if(scan>begin) Block(output,buffer,begin,scan-begin,false,false);
                    Block(output,buffer,scan,end-scan,true,input.Position==size && end==count);begin=end;
                }
                scan=end;
            }
            if(begin<count) Block(output,buffer,begin,count-begin,false,input.Position==size);
        }
    }
    public static void Backup(string root,string target) {
        root=Path.GetFullPath(root).TrimEnd('\\','/');
        if((File.GetAttributes(root)&FileAttributes.ReparsePoint)!=0) throw new IOException("Backup refuses a reparse root");
        string temporary=target+"."+Guid.NewGuid().ToString("N")+".tmp";
        bool created=false;
        try {
            using(var tar=new FileStream(temporary,FileMode.CreateNew,FileAccess.ReadWrite,FileShare.None)) {
                TarDirectory(root,root,Path.GetFileName(root),tar);tar.Write(new byte[1024],0,1024);tar.Position=0;
                using(var packed=new FileStream(target,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {created=true;Zstd(tar,packed);}
            }
        } catch { if(created && File.Exists(target)) File.Delete(target);throw; }
        finally {if(File.Exists(temporary)) File.Delete(temporary);}
    }
}
'@
}
function Write-VfcLog {
    param([string]$Level='INFO',[string]$Message,[string]$LogFile='')
    # The threshold comes from the GUI menu ($script:VfcLogLevel) or from the
    # running operation ($script:Work.LogLevel); workers have no menu state.
    $threshold=$script:VfcLogLevel;if(-not $threshold){$threshold='INFO'}
    if($script:Work -and $script:Work.ContainsKey('LogLevel') -and $script:Work.LogLevel){$threshold=[string]$script:Work.LogLevel}
    $rank=@{TRACE=0;DEBUG=1;INFO=2;WARN=3;ERROR=4}
    if($rank.ContainsKey($Level) -and $rank.ContainsKey($threshold) -and $rank[$Level] -lt $rank[$threshold]){return}
    $path=$LogFile
    if(-not $path){$path=$script:LogPath;if($script:Work -and $script:Work.ContainsKey('LogPath')){$path=$script:Work.LogPath}}
    if(-not $path){return}
    Initialize-OperationRuntime
    try{[VfcOperationRuntime]::Log($path,$Level,$Message)}catch{[Console]::Error.WriteLine('Log write failed: '+$_.Exception.Message+[Environment]::NewLine+$Message)}
}
function New-OperationLog {
    param([string]$Task,[string]$Game)
    if($SelfTest){return ''}
    $root=Join-Path (Get-SettingsRoot) 'logs';$null=[IO.Directory]::CreateDirectory($root)
    $path=Join-Path $root ([DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff')+'-'+$Task+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)+'.log')
    Initialize-OperationRuntime
    [VfcOperationRuntime]::Log($path,'INFO',"Operation started: task=$Task; game=$Game; output=$OutputModName; PowerShell=$($PSVersionTable.PSVersion); OS=$([Environment]::OSVersion); process=$PID")
    return $path
}
function New-OutputBackup {
    param([string]$Root,[string]$Game)
    if(-not [IO.Directory]::Exists($Root)){return $null}
    Initialize-OperationRuntime
    $directory=Join-Path (Get-SettingsRoot) 'backups';$null=[IO.Directory]::CreateDirectory($directory)
    $code=[IO.Path]::GetFileName($Game.TrimEnd('\','/')) -replace '[^A-Za-z0-9_-]','_'
    $timestamp=[DateTime]::Now
    $path=Join-Path $directory ($code+'_'+$timestamp.ToString('yyyyMMdd-HHmmss-fffffff',[Globalization.CultureInfo]::InvariantCulture)+'.tar.zst')
    while([IO.File]::Exists($path)){$timestamp=$timestamp.AddTicks(1);$path=Join-Path $directory ($code+'_'+$timestamp.ToString('yyyyMMdd-HHmmss-fffffff',[Globalization.CultureInfo]::InvariantCulture)+'.tar.zst')}
    Write-VfcLog 'INFO' "Creating Zstandard backup: source=$Root; archive=$path; encoder=raw/RLE"
    [VfcOperationRuntime]::Backup($Root,$path)
    Write-VfcLog 'INFO' "Backup complete: archive=$path; bytes=$((Get-Item -LiteralPath $path).Length)"
    return $path
}
function Get-ManagedOutputRoot {
    param([string]$Game,[string]$Mod)
    if([string]::IsNullOrWhiteSpace($Mod) -or $Mod.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $Mod -in @('.','..')){throw 'Invalid output folder name.'}
    $custom=[IO.Path]::GetFullPath((Join-Path $Game 'custom')).TrimEnd('\','/')
    $root=[IO.Path]::GetFullPath((Join-Path $custom $Mod))
    if((Split-Path $root -Parent) -ine $custom){throw 'Output folder must be a direct child of custom.'}
    $null=Get-GeneratedFontDirectory $root
    return $root
}
