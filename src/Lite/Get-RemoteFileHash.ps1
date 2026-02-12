function Get-RemoteFileHash {
    <#
    .SYNOPSIS
        透過 ssh 指令計算遠端檔案的 SHA256 雜湊並回傳絕對路徑。
    .PARAMETER SshHost
        遠端主機 (user@host)。
    .PARAMETER Port
        SSH 連接埠。
    .PARAMETER KeyFile
        私鑰檔案路徑。
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
        [string]$SshHost,

        [int]$Port = 22,

        [string]$KeyFile,

        [Parameter(Mandatory)]
        [string]$RemotePath,

        [Parameter(Mandatory)]
        [ValidateSet('Linux', 'macOS', 'Windows')]
        [string]$RemoteOS
    )

    # Base64 編碼路徑，防止命令注入
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($RemotePath))

    # 根據作業系統選擇指令
    $remoteCmd = switch ($RemoteOS) {
        'Linux' {
            'f="$(echo ' + $encoded + ' | base64 -d)"; p="$(realpath "$f")"; sha256sum "$p"'
        }
        'macOS' {
            'f="$(echo ' + $encoded + ' | base64 -d)"; p="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"; shasum -a 256 "$p"'
        }
        'Windows' {
            "powershell -NoProfile -Command `"\`$h=Get-FileHash -Path ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded'))) -Algorithm SHA256; \`$h.Path; \`$h.Hash`""
        }
    }

    $result = Invoke-SshCommand -SshHost $SshHost -Port $Port -KeyFile $KeyFile -Command $remoteCmd

    if ($result.ExitCode -ne 0) {
        throw "Failed to get hash for remote file '$RemotePath': $($result.Output)"
    }

    $output = ($result.Output | Out-String).Trim()

    # 解析輸出
    if ($RemoteOS -eq 'Windows') {
        $lines = $output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        if ($lines.Count -lt 2) {
            throw "Unexpected output for '$RemotePath': $output"
        }
        $absolutePath = $lines[0]
        $hash = $lines[1].ToUpper()
    } else {
        if ($output -notmatch '^([a-fA-F0-9]{64})\s+(.+)$') {
            throw "Unexpected output for '$RemotePath': $output"
        }
        $hash = $Matches[1].ToUpper()
        $absolutePath = $Matches[2]
    }

    if ($hash -notmatch '^[A-F0-9]{64}$') {
        throw "Invalid hash returned for '$RemotePath': $hash"
    }

    return [PSCustomObject]@{
        Hash         = $hash
        AbsolutePath = $absolutePath
    }
}
