function Test-FileHash {
    <#
    .SYNOPSIS
        驗證檔案的雜湊是否符合預期。
    .PARAMETER LocalPath
        本地檔案路徑。
    .PARAMETER RemotePath
        遠端檔案路徑。
    .PARAMETER SessionId
        Posh-SSH 工作階段 ID（PUT 操作需要）。
    .PARAMETER RemoteOS
        遠端作業系統（PUT 操作需要）。
    .PARAMETER ExpectedHash
        預期的雜湊值（GET 操作使用）。
    .PARAMETER Action
        操作類型：'put' 或 'get'。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LocalPath,

        [Parameter(Mandatory)]
        [string]$RemotePath,

        [int]$SessionId,
        [string]$RemoteOS,
        [string]$ExpectedHash,

        [Parameter(Mandatory)]
        [ValidateSet('put', 'get')]
        [string]$Action
    )

    $result = [PSCustomObject]@{
        Success          = $false
        LocalHash        = $null
        LocalAbsPath     = $null
        RemoteHash       = $null
        RemoteAbsPath    = $null
        Error            = $null
    }

    try {
        if (-not (Test-Path $LocalPath)) {
            $result.Error = "Local file not found: $LocalPath"
            return $result
        }

        $fileHash = Get-FileHash -Path $LocalPath -Algorithm SHA256
        $result.LocalAbsPath = $fileHash.Path
        $result.LocalHash = $fileHash.Hash.ToUpper()

        if ($Action -eq 'put') {
            $remoteResult = Get-RemoteFileHash -SessionId $SessionId -RemotePath $RemotePath -RemoteOS $RemoteOS
            $result.RemoteHash = $remoteResult.Hash
            $result.RemoteAbsPath = $remoteResult.AbsolutePath
            $result.Success = ($result.LocalHash -eq $result.RemoteHash)
        } else {
            $result.RemoteHash = $ExpectedHash
            if (-not $ExpectedHash) {
                $result.Error = "No pre-transfer hash recorded"
                return $result
            }
            $result.Success = ($result.LocalHash -eq $ExpectedHash)
        }
    } catch {
        $result.Error = $_.Exception.Message
    }

    return $result
}
