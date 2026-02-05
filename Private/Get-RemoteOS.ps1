function Get-RemoteOS {
    <#
    .SYNOPSIS
        Detects remote operating system via SSH.
    .PARAMETER SessionId
        Posh-SSH session ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$SessionId
    )
    
    $result = Invoke-SSHCommand -SessionId $SessionId -Command "uname -s" -TimeOut 30
    
    if ($result.ExitStatus -eq 0) {
        $os = $result.Output.Trim()
        switch -Regex ($os) {
            'Linux'  { return 'Linux' }
            'Darwin' { return 'macOS' }
            default  { return 'Linux' }  # 其他 Unix 系統假設為 Linux
        }
    } else {
        # uname 失敗，可能是 Windows
        return 'Windows'
    }
}
