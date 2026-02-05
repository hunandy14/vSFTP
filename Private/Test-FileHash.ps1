function Test-FileHash {
    <#
    .SYNOPSIS
        驗證檔案的雜湊是否符合預期。
    .DESCRIPTION
        比較本地與遠端（或預期）的 SHA256 雜湊值。
    .PARAMETER LocalPath
        本地檔案路徑。
    .PARAMETER RemotePath
        遠端檔案路徑（用於顯示）。
    .PARAMETER SessionId
        Posh-SSH 工作階段 ID（PUT 操作需要）。
    .PARAMETER RemoteOS
        遠端作業系統（PUT 操作需要）。
    .PARAMETER ExpectedHash
        預期的雜湊值（GET 操作使用）。
    .PARAMETER Action
        操作類型：'put' 或 'get'。
    .OUTPUTS
        PSCustomObject，包含 Success、LocalHash、RemoteHash 屬性。
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
        Success    = $false
        LocalHash  = $null
        RemoteHash = $null
        Error      = $null
    }
    
    try {
        # 計算本地雜湊
        $result.LocalHash = Get-LocalFileHash -Path $LocalPath
        
        if ($Action -eq 'put') {
            # PUT：從遠端取得雜湊並比較
            $result.RemoteHash = Get-RemoteFileHash -SessionId $SessionId -RemotePath $RemotePath -RemoteOS $RemoteOS
            $result.Success = ($result.LocalHash -eq $result.RemoteHash)
        } else {
            # GET：與預期雜湊比較
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
