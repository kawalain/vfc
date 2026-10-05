function Invoke-VpkIndexSelfTest {
    $testRoot=Join-Path ([IO.Path]::GetTempPath()) ('VGUIFontChanger-vpk-test-'+[guid]::NewGuid().ToString('N'))
    $oldWork=$script:Work
    $null=[IO.Directory]::CreateDirectory($testRoot)
    try{
        foreach($version in @(1,2)){
            $treeStream=[IO.MemoryStream]::new();$treeWriter=[IO.BinaryWriter]::new($treeStream)
            $writeString={param([string]$value);$treeWriter.Write([Text.Encoding]::UTF8.GetBytes($value));$treeWriter.Write([byte]0)}
            try{
                foreach($item in @(
                    @{Extension='vtf';Directory='materials';Name='ignored';Preload=[byte[]]@(1,2,3);Length=0},
                    @{Extension='res';Directory='resource';Name='ClientScheme';Preload=[Text.Encoding]::UTF8.GetBytes('scheme-preload');Length=5},
                    @{Extension='ttf';Directory=' ';Name='root-font';Preload=[byte[]]@(10,20,30);Length=0}
                )){
                    & $writeString $item.Extension;& $writeString $item.Directory;& $writeString $item.Name
                    $treeWriter.Write([uint32]1234);$treeWriter.Write([uint16]$item.Preload.Length)
                    $treeWriter.Write([uint16]0x7fff);$treeWriter.Write([uint32]0);$treeWriter.Write([uint32]$item.Length);$treeWriter.Write([uint16]0xffff)
                    $treeWriter.Write([byte[]]$item.Preload)
                    $treeWriter.Write([byte]0);$treeWriter.Write([byte]0)
                }
                $treeWriter.Write([byte]0);$tree=$treeStream.ToArray()
            }finally{$treeWriter.Dispose();$treeStream.Dispose()}
            $path=Join-Path $testRoot ('fixture-v'+$version+'_dir.vpk')
            $writer=[IO.BinaryWriter]::new([IO.File]::Create($path))
            try{
                $writer.Write([uint32]0x55aa1234);$writer.Write([uint32]$version);$writer.Write([uint32]$tree.Length)
                if($version -eq 2){$writer.Write([uint32]5);$writer.Write([uint32]0);$writer.Write([uint32]0);$writer.Write([uint32]0)}
                $writer.Write([byte[]]$tree);$writer.Write([Text.Encoding]::UTF8.GetBytes(' tail'))
            }finally{$writer.Dispose()}
            $index=Get-VpkIndex $path
            if($index.Entries.Count -ne 2 -or $index.Entries.ContainsKey('materials/ignored.vtf') -or -not $index.Entries.ContainsKey('root-font.ttf')){throw 'Filtered VPK paths/preload skipping failed'}
            if($index.Entries['resource/ClientScheme.res'].Crc -ne 1234){throw 'VPK metadata changed'}
            if([Text.Encoding]::UTF8.GetString((Read-VpkEntryBytes $path 'resource/ClientScheme.res')) -ne 'scheme-preload tail'){throw 'VPK preload/data offsets changed'}
            if(((Read-VpkEntryBytes $path 'root-font.ttf') -join ',') -ne '10,20,30'){throw 'Root VPK font preload changed'}
            $null=$script:VpkIndexCache.Remove([IO.Path]::GetFullPath($path))
            $script:Work=@{Cancel=$true;CanCancel=$true;Message=''}
            $cancelled=$false;try{$null=Get-VpkIndex $path}catch [OperationCanceledException]{$cancelled=$true}
            if(-not $cancelled){throw 'VPK indexing must honor cancellation'}
            $script:Work=$oldWork
        }
        $batchSources=@(Get-ChildItem -LiteralPath $testRoot -Filter '*.vpk' | ForEach-Object {[pscustomobject]@{Type='Vpk';Path=$_.FullName}})
        Initialize-VpkIndexes $batchSources
        foreach($source in $batchSources){if((Get-VpkIndex $source.Path).Entries.Count -ne 2){throw 'Parallel VPK batch changed its entries'}}
        $script:Work=@{Cancel=$true;CanCancel=$true;Message=''}
        $cancelled=$false;try{$null=[VfcVpkReader]::ReadBatch([string[]]@($batchSources.Path),$script:Work,2)}catch{$cancelled=$true}
        if(-not $cancelled){throw 'Parallel VPK batch ignored cancellation'}
        $script:Work=$oldWork
        'VPK v1/v2 tests passed: native/parallel indexes, paths, metadata/data offsets, preload and cancellation.'
    }finally{
        $script:Work=$oldWork
        $resolvedTestRoot=[IO.Path]::GetFullPath($testRoot)
        if(-not $resolvedTestRoot.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolvedTestRoot -Leaf) -notlike 'VGUIFontChanger-vpk-test-*'){throw 'Unsafe VPK test cleanup path'}
        if(Test-Path -LiteralPath $resolvedTestRoot){Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force}
    }
}
