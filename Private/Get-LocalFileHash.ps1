function Get-LocalFileHash {
    <#
    .SYNOPSIS
        Calculates SHA256 hash of a local file.
    .PARAMETER Path
        Path to local file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    if (-not (Test-Path $Path)) {
        throw "Local file not found: $Path"
    }
    
    $hash = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToUpper()
    return $hash
}
