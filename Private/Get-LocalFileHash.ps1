function Get-LocalFileHash {
    <#
    .SYNOPSIS
        計算本地檔案的 SHA256 雜湊。
    .PARAMETER Path
        本地檔案的路徑。
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
