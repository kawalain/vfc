function New-StringList {
    New-Object 'System.Collections.Generic.List[string]'
}

function New-ObjectList {
    New-Object 'System.Collections.Generic.List[object]'
}

function ConvertFrom-VdfEscapedString {
    param([string] $Value)
    return $Value.Replace('\\\\', '\').Replace('\\"', '"')
}
