function Expand-RemoteWildcard {
    <#
    .SYNOPSIS
        Expands remote wildcard pattern using SSH ls command.
    .PARAMETER SessionId
        Posh-SSH session ID.
    .PARAMETER RemotePath
        Remote path with wildcard (e.g., /logs/*.log).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$SessionId,
        
        [Parameter(Mandatory)]
        [string]$RemotePath
    )
    
    # Use ls -1 to list files matching pattern (one per line)
    $command = "ls -1d $RemotePath 2>/dev/null"
    
    $result = Invoke-SSHCommand -SessionId $SessionId -Command $command -TimeOut 60
    
    if ($result.ExitStatus -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        Write-Warning "No files match pattern: $RemotePath"
        return @()
    }
    
    # Split output into individual file paths
    $files = $result.Output -split "`n" | 
             ForEach-Object { $_.Trim() } | 
             Where-Object { $_ -and $_ -notmatch '^\s*$' }
    
    return $files
}
