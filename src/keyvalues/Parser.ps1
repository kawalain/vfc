function Get-KvTokens {
    param([string] $Text, [string] $Source)
    $tokens = New-ObjectList
    $i = 0; $line = 1
    while ($i -lt $Text.Length) {
        if($i % 1024 -eq 0){Test-WorkCancellation}
        $c = $Text[$i]
        if ([char]::IsWhiteSpace($c)) { if ($c -eq "`n") { $line++ }; $i++; continue }
        if ($c -eq '/' -and $i + 1 -lt $Text.Length -and $Text[$i + 1] -eq '/') {
            $i += 2
            while ($i -lt $Text.Length -and $Text[$i] -ne "`n") { $i++ }
            continue
        }
        if ($c -eq '{' -or $c -eq '}') {
            $null = $tokens.Add([pscustomobject]@{ Value=[string]$c; Kind=if($c -eq '{'){'LBrace'}else{'RBrace'}; Line=$line })
            $i++; continue
        }
        if ($c -eq '"') {
            $startLine = $line; $i++; $builder = New-Object Text.StringBuilder
            while ($i -lt $Text.Length) {
                $q = $Text[$i]
                if ($q -eq '"') { $i++; break }
                if ($q -eq "`n") { $line++ }
                if ($q -eq '\' -and $i + 1 -lt $Text.Length -and $Text[$i + 1] -eq '"') {
                    $null = $builder.Append('"'); $i += 2; continue
                }
                $null = $builder.Append($q); $i++
            }
            $null = $tokens.Add([pscustomobject]@{ Value=$builder.ToString(); Kind='String'; Line=$startLine })
            continue
        }
        $start = $i; $startLine = $line
        while ($i -lt $Text.Length -and -not [char]::IsWhiteSpace($Text[$i]) -and $Text[$i] -ne '{' -and $Text[$i] -ne '}' -and $Text[$i] -ne '"') { $i++ }
        $value = $Text.Substring($start, $i - $start)
        $kind = if ($value.StartsWith('[') -and $value.EndsWith(']')) { 'Conditional' } else { 'String' }
        $null = $tokens.Add([pscustomobject]@{ Value=$value; Kind=$kind; Line=$startLine })
    }
    return ,$tokens
}

function Test-KvConditional {
    param([string] $Conditional)
    $body = $Conditional.Trim('[', ']').Trim()
    $negate = $body.StartsWith('!')
    if ($negate) { $body = $body.Substring(1) }
    $isTrue = $body -match '(?i)\$(WIN32|WINDOWS)'
    if ($negate) { return -not $isTrue }
    return $isTrue
}

function New-KvNode {
    param([string]$Key, [bool]$HasValue, [string]$Value, [object[]]$Children, [string]$Source, [int]$Line)
    $list = New-ObjectList
    foreach ($child in @($Children)) { if ($null -ne $child) { $null = $list.Add($child) } }
    return [pscustomobject]@{ Key=$Key; HasValue=$HasValue; Value=$Value; Children=$list; Source=$Source; Line=$Line; Condition='' }
}

function Read-KvNodeList {
    param([object[]]$Tokens, [ref]$Index, [string]$Source, [bool]$StopAtBrace)
    $nodes = New-ObjectList
    $directives = New-ObjectList
    while ($Index.Value -lt $Tokens.Count) {
        $keyToken = $Tokens[$Index.Value]
        if ($keyToken.Kind -eq 'RBrace') {
            if (-not $StopAtBrace) { throw "Unexpected } in ${Source}:$($keyToken.Line)" }
            $Index.Value++; break
        }
        $Index.Value++
        if ($keyToken.Value -ieq '#include' -or $keyToken.Value -ieq '#base') {
            if ($Index.Value -ge $Tokens.Count) { throw "Missing path after $($keyToken.Value) in ${Source}:$($keyToken.Line)" }
            $pathToken = $Tokens[$Index.Value]; $Index.Value++
            $null = $directives.Add([pscustomobject]@{ Kind=$keyToken.Value.ToLowerInvariant(); Path=$pathToken.Value; Line=$keyToken.Line })
            continue
        }
        $accepted = $true; $conditions=New-StringList
        if ($Index.Value -lt $Tokens.Count -and $Tokens[$Index.Value].Kind -eq 'Conditional') {
            $conditions.Add($Tokens[$Index.Value].Value); $accepted = Test-KvConditional $Tokens[$Index.Value].Value; $Index.Value++
        }
        if ($Index.Value -ge $Tokens.Count) { throw "Missing value for '$($keyToken.Value)' in ${Source}:$($keyToken.Line)" }
        $valueToken = $Tokens[$Index.Value]; $Index.Value++
        if ($valueToken.Kind -eq 'LBrace') {
            $inner = Read-KvNodeList $Tokens $Index $Source $true
            $node = New-KvNode $keyToken.Value $false $null $inner.Nodes.ToArray() $Source $keyToken.Line
            foreach ($directive in $inner.Directives) { $null = $directives.Add($directive) }
        } else {
            if ($valueToken.Kind -eq 'Conditional') {
                $conditions.Add($valueToken.Value); $accepted = Test-KvConditional $valueToken.Value
                if ($Index.Value -ge $Tokens.Count) { throw "Missing value after conditional in ${Source}:$($keyToken.Line)" }
                $valueToken = $Tokens[$Index.Value]; $Index.Value++
            }
            $node = New-KvNode $keyToken.Value $true $valueToken.Value @() $Source $keyToken.Line
            if ($Index.Value -lt $Tokens.Count -and $Tokens[$Index.Value].Kind -eq 'Conditional') {
                $conditions.Add($Tokens[$Index.Value].Value); $accepted = Test-KvConditional $Tokens[$Index.Value].Value; $Index.Value++
            }
        }
        $node.Condition=[string]::Join(' ',$conditions.ToArray())
        if ($accepted) { $null = $nodes.Add($node) }
    }
    return [pscustomobject]@{ Nodes=$nodes; Directives=$directives }
}

function ConvertFrom-KeyValuesText {
    param([string]$Text, [string]$Source)
    $tokens = Get-KvTokens $Text $Source
    $index = 0
    return Read-KvNodeList $tokens ([ref]$index) $Source $false
}

function Copy-KvNode {
    param($Node)
    $children = New-ObjectList
    foreach ($child in $Node.Children) { $null = $children.Add((Copy-KvNode $child)) }
    $copy=New-KvNode $Node.Key $Node.HasValue $Node.Value $children.ToArray() $Node.Source $Node.Line
    $copy.Condition=$Node.Condition
    return $copy
}

function Merge-KvBaseNode {
    param($Current, $Base)
    foreach ($baseChild in $Base.Children) {
        $match = $null
        foreach ($currentChild in $Current.Children) {
            if ($currentChild.Key -ceq $baseChild.Key) { $match = $currentChild; break }
        }
        if ($null -ne $match) { Merge-KvBaseNode $match $baseChild }
        else { $null = $Current.Children.Add((Copy-KvNode $baseChild)) }
    }
}

function Join-VirtualPath {
    param([string]$Parent, [string]$Child)
    $child = $Child.Replace('\', '/')
    if ($child.StartsWith('/')) { return $child.TrimStart('/') }
    $slash = $Parent.LastIndexOf('/')
    $folder = if ($slash -ge 0) { $Parent.Substring(0, $slash + 1) } else { '' }
    $segments = New-StringList
    foreach ($segment in ($folder + $child).Split('/')) {
        if ($segment -eq '' -or $segment -eq '.') { continue }
        if ($segment -eq '..') { if ($segments.Count -gt 0) { $segments.RemoveAt($segments.Count - 1) }; continue }
        $null = $segments.Add($segment)
    }
    return [string]::Join('/', $segments.ToArray())
}

function Resolve-KvDocument {
    param([object[]]$Sources, [string]$VirtualPath, [hashtable]$Stack)
    $normalized = $VirtualPath.Replace('\', '/').TrimStart('/')
    if ($Stack.ContainsKey($normalized.ToLowerInvariant())) { throw "Circular KeyValues dependency: $normalized" }
    $nextStack = @{} + $Stack; $nextStack[$normalized.ToLowerInvariant()] = $true
    $file = Read-VirtualFile $Sources $normalized
    if ($null -eq $file) { throw "Virtual file not found: $normalized" }
    $parsed = ConvertFrom-KeyValuesText $file.Text $file.Source

    $nodes = New-ObjectList
    foreach ($node in $parsed.Nodes) { $null = $nodes.Add($node) }
    $includes = @($parsed.Directives | Where-Object { $_.Kind -eq '#include' })
    $bases = @($parsed.Directives | Where-Object { $_.Kind -eq '#base' })
    $dependencies = New-StringList; $null = $dependencies.Add($file.Source)
    $inputs=New-StringList;$inputs.Add($normalized)

    foreach ($directive in $includes) {
        $dependencyPath = Join-VirtualPath $normalized $directive.Path
        if(-not $inputs.Contains($dependencyPath)){$inputs.Add($dependencyPath)}
        try { $included = Resolve-KvDocument $Sources $dependencyPath $nextStack }
        catch {
            if ($_.Exception.Message -like 'Virtual file not found:*') {
                Write-Warning "Missing optional #include dependency: $dependencyPath"
                continue
            }
            throw
        }
        foreach ($node in $included.Nodes) { $null = $nodes.Add((Copy-KvNode $node)) }
        foreach ($dependency in $included.Dependencies) { if (-not $dependencies.Contains($dependency)) { $null = $dependencies.Add($dependency) } }
        foreach($inputPath in $included.Inputs){if(-not $inputs.Contains($inputPath)){$inputs.Add($inputPath)}}
    }
    foreach ($directive in $bases) {
        $dependencyPath = Join-VirtualPath $normalized $directive.Path
        if(-not $inputs.Contains($dependencyPath)){$inputs.Add($dependencyPath)}
        try { $base = Resolve-KvDocument $Sources $dependencyPath $nextStack }
        catch {
            if ($_.Exception.Message -like 'Virtual file not found:*') {
                Write-Warning "Missing optional #base dependency: $dependencyPath"
                continue
            }
            throw
        }
        foreach ($baseRoot in $base.Nodes) {
            $rootMatch = $null
            foreach ($root in $nodes) { if ($root.Key -ceq $baseRoot.Key) { $rootMatch = $root; break } }
            if ($null -ne $rootMatch) { Merge-KvBaseNode $rootMatch $baseRoot }
            else { $null = $nodes.Add((Copy-KvNode $baseRoot)) }
        }
        foreach ($dependency in $base.Dependencies) { if (-not $dependencies.Contains($dependency)) { $null = $dependencies.Add($dependency) } }
        foreach($inputPath in $base.Inputs){if(-not $inputs.Contains($inputPath)){$inputs.Add($inputPath)}}
    }
    return [pscustomobject]@{ Nodes=$nodes; Entry=$file.Source; Dependencies=$dependencies; VirtualPath=$normalized;Inputs=$inputs }
}
