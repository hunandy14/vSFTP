function Get-RemoteFileHash {
    <#
    .SYNOPSIS
        透過 SSH 計算遠端檔案的 SHA256 雜湊並回傳絕對路徑。
    .PARAMETER SessionId
        Posh-SSH 工作階段 ID。
    .PARAMETER RemotePath
        遠端檔案的路徑。
    .PARAMETER RemoteOS
        遠端作業系統（Linux、macOS、Windows）。
    .OUTPUTS
        PSCustomObject 包含 Hash 和 AbsolutePath 屬性。
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

    # 根據作業系統選擇指令：輸出兩行（1. 絕對路徑 2. Hash）
    $command = switch ($RemoteOS) {
        'Linux' {
            'p="$(realpath "$(echo ' + $encoded + ' | base64 -d)")"; echo "$p"; sha256sum "$p" | cut -d'' '' -f1'
        }
        'macOS' {
            # macOS 的 realpath 可能需要 coreutils，退而使用 cd + pwd
            'p="$(cd "$(dirname "$(echo ' + $encoded + ' | base64 -d)")" && pwd)/$(basename "$(echo ' + $encoded + ' | base64 -d)")"; echo "$p"; shasum -a 256 "$p" | cut -d'' '' -f1'
        }
        'Windows' {
            # Windows PowerShell：回傳完整路徑和 Hash
            "powershell -NoProfile -Command `"\`$f=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded')); (Resolve-Path \`$f).Path; (Get-FileHash -Path \`$f -Algorithm SHA256).Hash`""
        }
    }

    $result = Invoke-SSHCommand -SessionId $SessionId -Command $command -TimeOut 300

    if ($result.ExitStatus -ne 0) {
        throw "Failed to get hash for remote file '$RemotePath': $($result.Error)"
    }

    $lines = $result.Output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    
    if ($lines.Count -lt 2) {
        throw "Unexpected output for '$RemotePath': $($result.Output)"
    }

    $absolutePath = $lines[0]
    $hash = $lines[1].ToUpper()

    # 驗證雜湊格式（64 個十六進位字元）
    if ($hash -notmatch '^[A-F0-9]{64}$') {
        throw "Invalid hash returned for '$RemotePath': $hash"
    }

    return [PSCustomObject]@{
        Hash         = $hash
        AbsolutePath = $absolutePath
    }
}
