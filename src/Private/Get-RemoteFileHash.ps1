function Get-RemoteFileHash {
    <#
    .SYNOPSIS
        透過 SSH 計算遠端檔案的 SHA256 雜湊。
    .PARAMETER SessionId
        Posh-SSH 工作階段 ID。
    .PARAMETER RemotePath
        遠端檔案的路徑。
    .PARAMETER RemoteOS
        遠端作業系統（Linux、macOS、Windows）。
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

    # Base64 編碼路徑，防止命令注入
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($RemotePath))

    # 根據作業系統選擇雜湊指令
    $command = switch ($RemoteOS) {
        'Linux' {
            'sha256sum "$(echo ' + $encoded + ' | base64 -d)" | cut -d'' '' -f1'
        }
        'macOS' {
            'shasum -a 256 "$(echo ' + $encoded + ' | base64 -d)" | cut -d'' '' -f1'
        }
        'Windows' {
            # Windows PowerShell 使用 .NET 解碼
            "powershell -NoProfile -Command `"(Get-FileHash -Path ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded'))) -Algorithm SHA256).Hash`""
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
