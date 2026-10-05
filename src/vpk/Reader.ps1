function Read-VpkTreeString {
    param([byte[]]$Tree, [ref]$Position)
    $end = [Array]::IndexOf($Tree, [byte]0, $Position.Value)
    if ($end -lt 0) { throw 'Invalid unterminated VPK tree string.' }
    $value = [Text.Encoding]::UTF8.GetString($Tree, $Position.Value, $end - $Position.Value)
    $Position.Value = $end + 1
    return $value
}

function Initialize-VpkRuntime {
    if('VfcVpkReader' -as [type]){return}
    # Built-in .NET only. Thread-pool workers never invoke PowerShell callbacks.
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Collections;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
public sealed class VfcVpkEntry {
    public uint Crc; public byte[] Preload; public ushort ArchiveIndex;
    public uint Offset; public uint Length;
}
public sealed class VfcVpkIndex {
    public string Path; public int HeaderSize; public uint TreeSize;
    public Dictionary<string,VfcVpkEntry> Entries;
}
public static class VfcVpkReader {
    private sealed class Progress {
        public IDictionary Work; public int Total; public int Completed;
        public void Check() {
            if(Work==null) return;
            lock(Work.SyncRoot) {
                if(Convert.ToBoolean(Work["Cancel"]) && Convert.ToBoolean(Work["CanCancel"]))
                    throw new OperationCanceledException("Operation cancelled.");
            }
        }
        public void Report(string path,int percent) {
            if(Work==null) return;
            lock(Work.SyncRoot) Work["Message"]="Indexing "+System.IO.Path.GetFileName(path)+
                " ("+percent+"%; "+Completed+"/"+Total+")";
        }
    }
    private static string ReadString(byte[] tree,ref int position) {
        if(position>=tree.Length) throw new InvalidDataException("Truncated VPK tree.");
        int end=Array.IndexOf(tree,(byte)0,position);
        if(end<0) throw new InvalidDataException("Unterminated VPK string.");
        string value=Encoding.UTF8.GetString(tree,position,end-position);
        position=end+1;return value;
    }
    private static bool Relevant(string extension) {
        switch(extension.ToLowerInvariant()) {
            case "res":case "txt":case "vdf":case "kv":case "scheme":
            case "ttf":case "otf":case "ttc":return true;
            default:return false;
        }
    }
    private static VfcVpkIndex ReadCore(string path,Progress progress) {
        progress.Check();progress.Report(path,0);
        using(var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite))
        using(var reader=new BinaryReader(stream)) {
            if(reader.ReadUInt32()!=0x55aa1234) throw new InvalidDataException("Invalid VPK signature: "+path);
            uint version=reader.ReadUInt32(),treeSize=reader.ReadUInt32();int headerSize;
            if(version==1) headerSize=12;
            else if(version==2) {
                headerSize=28;for(int i=0;i<4;i++) reader.ReadUInt32();
            } else throw new InvalidDataException("Unsupported VPK version: "+version+"; "+path);
            if(treeSize>int.MaxValue || treeSize>stream.Length-stream.Position)
                throw new InvalidDataException("Truncated VPK tree: "+path);
            byte[] tree=reader.ReadBytes((int)treeSize);
            if(tree.Length!=(int)treeSize) throw new InvalidDataException("Truncated VPK tree: "+path);
            int position=0,count=0;
            var entries=new Dictionary<string,VfcVpkEntry>(StringComparer.OrdinalIgnoreCase);
            while(true) {
                string extension=ReadString(tree,ref position);if(extension.Length==0) break;
                bool relevant=Relevant(extension);
                while(true) {
                    progress.Check();string directory=ReadString(tree,ref position);
                    if(directory.Length==0) break;
                    string prefix=directory==" " ? "" : directory.Trim('/').Replace('\\','/')+"/";
                    while(true) {
                        string name=ReadString(tree,ref position);if(name.Length==0) break;
                        if((count++ & 127)==0) {
                            progress.Check();progress.Report(path,(int)(100L*position/Math.Max(1,tree.Length)));
                        }
                        if(position>tree.Length-18) throw new InvalidDataException("Truncated VPK entry: "+path);
                        int start=position;ushort preloadLength=BitConverter.ToUInt16(tree,start+4);
                        if(BitConverter.ToUInt16(tree,start+16)!=0xffff)
                            throw new InvalidDataException("Invalid VPK entry terminator: "+path);
                        position+=18;
                        if(preloadLength>tree.Length-position) throw new InvalidDataException("Truncated VPK preload: "+path);
                        if(relevant) {
                            byte[] preload=new byte[preloadLength];
                            if(preloadLength>0) Buffer.BlockCopy(tree,position,preload,0,preloadLength);
                            entries[prefix+name+"."+extension]=new VfcVpkEntry {
                                Crc=BitConverter.ToUInt32(tree,start),Preload=preload,
                                ArchiveIndex=BitConverter.ToUInt16(tree,start+6),
                                Offset=BitConverter.ToUInt32(tree,start+8),Length=BitConverter.ToUInt32(tree,start+12)
                            };
                        }
                        position+=preloadLength;
                    }
                }
            }
            progress.Check();Interlocked.Increment(ref progress.Completed);progress.Report(path,100);
            return new VfcVpkIndex {Path=path,HeaderSize=headerSize,TreeSize=treeSize,Entries=entries};
        }
    }
    public static VfcVpkIndex Read(string path,IDictionary work) {
        return ReadCore(path,new Progress {Work=work,Total=1});
    }
    public static VfcVpkIndex[] ReadBatch(string[] paths,IDictionary work,int concurrency) {
        var indexes=new VfcVpkIndex[paths.Length];var progress=new Progress {Work=work,Total=paths.Length};
        Parallel.For(0,paths.Length,new ParallelOptions {MaxDegreeOfParallelism=Math.Max(1,concurrency)},
            i=> {indexes[i]=ReadCore(paths[i],progress);});
        progress.Check();return indexes;
    }
}
'@
}
function Get-VpkIndex {
    param([string]$VpkPath)
    Test-WorkCancellation
    $fullPath=[IO.Path]::GetFullPath($VpkPath)
    if($script:VpkIndexCache.ContainsKey($fullPath)){return $script:VpkIndexCache[$fullPath]}
    Initialize-VpkRuntime
    try{$index=[VfcVpkReader]::Read($fullPath,$script:Work)}catch{Test-WorkCancellation;throw}
    $script:VpkIndexCache[$fullPath]=$index
    return $index
}
function Initialize-VpkIndexes {
    param([object[]]$Sources)
    $paths=New-StringList
    foreach($source in $Sources){
        if($source.Type -ne 'Vpk'){continue}
        $path=[IO.Path]::GetFullPath($source.Path)
        if(-not $script:VpkIndexCache.ContainsKey($path) -and -not $paths.Contains($path)){$paths.Add($path)}
    }
    if(-not $paths.Count){return}
    Test-WorkCancellation;Initialize-VpkRuntime
    try{$indexes=[VfcVpkReader]::ReadBatch($paths.ToArray(),$script:Work,[Math]::Min(4,[Environment]::ProcessorCount))}catch{Test-WorkCancellation;throw}
    # Commit results on this PowerShell thread; filesystem search order is unchanged.
    foreach($index in $indexes){$script:VpkIndexCache[$index.Path]=$index}
}

function Get-VpkToolIndex {
    param([string]$ToolPath, [string]$VpkPath)
    $key = [IO.Path]::GetFullPath($VpkPath)
    if ($script:VpkToolIndexCache.ContainsKey($key)) { return $script:VpkToolIndexCache[$key] }
    $entries = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $ToolPath
    $start.Arguments = 'l "' + $VpkPath.Replace('"', '\"') + '"'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    while (-not $process.StandardOutput.EndOfStream) {
        $line = $process.StandardOutput.ReadLine().Trim().Replace('\', '/')
        if ($line -match '(?i)\.(res|txt|vdf|kv|scheme|ttf|otf|ttc)$') { $null = $entries.Add($line) }
    }
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $process.Dispose()
    if ($exitCode -ne 0) { throw "Unable to list VPK '$VpkPath': $stderr" }
    $result = [pscustomobject]@{ Entries=$entries }
    $script:VpkToolIndexCache[$key] = $result
    return $result
}

function Read-VpkEntryBytesWithTool {
    param([string]$ToolPath, [string]$VpkPath, [string]$VirtualPath)
    if (-not $ToolPath -or -not (Test-Path -LiteralPath $ToolPath -PathType Leaf)) { return $null }
    $lookupPath = $VirtualPath.Replace('\', '/').TrimStart('/').ToLowerInvariant()
    $index = Get-VpkToolIndex $ToolPath $VpkPath
    if (-not $index.Entries.Contains($lookupPath)) { return $null }
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('VGUIFontChanger-' + [guid]::NewGuid().ToString('N'))
    $null = [IO.Directory]::CreateDirectory($tempRoot)
    try {
        $extracted = Join-Path $tempRoot ($lookupPath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $null = [IO.Directory]::CreateDirectory((Split-Path $extracted -Parent))
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $ToolPath
        $start.Arguments = 'x "' + $VpkPath.Replace('"', '\"') + '" "' + $lookupPath.Replace('"', '\"') + '"'
        $start.WorkingDirectory = $tempRoot
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $process = [Diagnostics.Process]::Start($start)
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $process.Dispose()
        if ($exitCode -ne 0) { return $null }
        if (-not (Test-Path -LiteralPath $extracted -PathType Leaf)) { return $null }
        return ,([IO.File]::ReadAllBytes($extracted))
    } finally {
        if ([IO.Directory]::Exists($tempRoot)) { [IO.Directory]::Delete($tempRoot, $true) }
    }
}

function Read-VpkEntryBytes {
    param([string] $VpkPath, [string] $VirtualPath, [string]$ToolPath)
    if ($ToolPath -and (Test-Path -LiteralPath $ToolPath -PathType Leaf)) {
        return Read-VpkEntryBytesWithTool $ToolPath $VpkPath $VirtualPath
    }
    $index = Get-VpkIndex $VpkPath
    $key = $VirtualPath.Replace('\', '/').TrimStart('/')
    if (-not $index.Entries.ContainsKey($key)) { return $null }
    $entry = $index.Entries[$key]

    if ($entry.ArchiveIndex -eq 0x7FFF) {
        $dataPath = $index.Path
        $offset = [int64]$index.HeaderSize + [int64]$index.TreeSize + [int64]$entry.Offset
    } else {
        $base = $index.Path
        if ($base -match '(?i)_dir\.vpk$') { $dataPath = $base -replace '(?i)_dir\.vpk$', ('_{0:D3}.vpk' -f $entry.ArchiveIndex) }
        else { $dataPath = $base -replace '(?i)\.vpk$', ('_{0:D3}.vpk' -f $entry.ArchiveIndex) }
        $offset = [int64]$entry.Offset
    }
    if (-not (Test-Path -LiteralPath $dataPath)) { throw "Missing VPK archive: $dataPath" }

    $payload = [byte[]]@()
    if ($entry.Length -gt 0) {
        $stream = [IO.File]::Open($dataPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $null = $stream.Seek($offset, [IO.SeekOrigin]::Begin)
            $payload = New-Object byte[] ([int]$entry.Length)
            $read = 0
            while ($read -lt $payload.Length) {
                $count = $stream.Read($payload, $read, $payload.Length - $read)
                if ($count -le 0) { throw "Unexpected end of VPK data: $dataPath" }
                $read += $count
            }
        } finally { $stream.Dispose() }
    }
    $result = New-Object byte[] ($entry.Preload.Length + $payload.Length)
    if ($entry.Preload.Length -gt 0) { [Array]::Copy($entry.Preload, 0, $result, 0, $entry.Preload.Length) }
    if ($payload.Length -gt 0) { [Array]::Copy($payload, 0, $result, $entry.Preload.Length, $payload.Length) }
    return ,$result
}
