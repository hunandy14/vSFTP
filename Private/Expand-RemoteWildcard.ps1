function Expand-RemoteWildcard {
    <#
    .SYNOPSIS
        使用 SSH ls 指令展開遠端萬用字元模式。
    .PARAMETER SessionId
        Posh-SSH 工作階段 ID。
    .PARAMETER RemotePath
        包含萬用字元的遠端路徑（例如 /logs/*.log）。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$SessionId,
        
        [Parameter(Mandatory)]
        [string]$RemotePath
    )
    
    # 使用 ls -1 列出符合模式的檔案（每行一個）
    $command = "ls -1d $RemotePath 2>/dev/null"
    
    $result = Invoke-SSHCommand -SessionId $SessionId -Command $command -TimeOut 60
    
    if ($result.ExitStatus -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        Write-Warning "No files match pattern: $RemotePath"
        return @()
    }
    
    # 將輸出分割成個別檔案路徑
    $files = $result.Output -split "`n" | 
             ForEach-Object { $_.Trim() } | 
             Where-Object { $_ -and $_ -notmatch '^\s*$' }
    
    return $files
}
