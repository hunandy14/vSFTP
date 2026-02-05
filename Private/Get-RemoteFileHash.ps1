function Get-RemoteFileHash {
    <#
    .SYNOPSIS
        Calculates SHA256 hash of a remote file via SSH.
    .PARAMETER SessionId
        Posh-SSH session ID.
    .PARAMETER RemotePath
        Path to remote file.
    .PARAMETER RemoteOS
        Remote operating system (Linux, macOS, Windows).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$SessionId,
        
        [Parameter(Mandatory)]
        [string]$RemotePath,
        
        [Parameter(Mandatory)]
        [ValidateSet('Linux', 'macOS', 'Windows')]
        [string]$RemoteOS
    )
    
    # 根據作業系統選擇雜湊指令
    $command = switch ($RemoteOS) {
        'Linux' {
            "sha256sum '$RemotePath' | cut -d' ' -f1"
        }
        'macOS' {
            "shasum -a 256 '$RemotePath' | cut -d' ' -f1"
        }
        'Windows' {
            "powershell -NoProfile -Command `"(Get-FileHash -Path '$RemotePath' -Algorithm SHA256).Hash`""
        }
    }
    
    $result = Invoke-SSHCommand -SessionId $SessionId -Command $command -TimeOut 300
    
    if ($result.ExitStatus -ne 0) {
        throw "Failed to get hash for remote file '$RemotePath': $($result.Error)"
    }
    
    $hash = $result.Output.Trim().ToUpper()
    
    # 驗證雜湊格式（64 個十六進位字元）
    if ($hash -notmatch '^[A-F0-9]{64}$') {
        throw "Invalid hash returned for '$RemotePath': $hash"
    }
    
    return $hash
}
