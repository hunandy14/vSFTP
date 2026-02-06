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

    # 根據作業系統選擇指令
    # Linux/macOS: sha256sum/shasum 輸出格式為 "hash  path"（兩個空格分隔）
    # Windows: 輸出兩行（Path, Hash）
    $command = switch ($RemoteOS) {
        'Linux' {
            # 解碼一次，realpath 取絕對路徑，sha256sum 輸出含路徑
            'f="$(echo ' + $encoded + ' | base64 -d)"; p="$(realpath "$f")"; sha256sum "$p"'
        }
        'macOS' {
            # 解碼一次，cd+pwd 取絕對路徑（macOS 無 realpath）
            'f="$(echo ' + $encoded + ' | base64 -d)"; p="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"; shasum -a 256 "$p"'
        }
        'Windows' {
            # Windows PowerShell：Get-FileHash 已包含絕對路徑
            "powershell -NoProfile -Command `"\`$h=Get-FileHash -Path ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded'))) -Algorithm SHA256; \`$h.Path; \`$h.Hash`""
        }
    }

    $result = Invoke-SSHCommand -SessionId $SessionId -Command $command -TimeOut 300

    if ($result.ExitStatus -ne 0) {
        throw "Failed to get hash for remote file '$RemotePath': $($result.Error)"
    }

    $output = $result.Output.Trim()

    # 解析輸出
    if ($RemoteOS -eq 'Windows') {
        # Windows: 兩行輸出（Path, Hash）
        $lines = $output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        if ($lines.Count -lt 2) {
            throw "Unexpected output for '$RemotePath': $output"
        }
        $absolutePath = $lines[0]
        $hash = $lines[1].ToUpper()
    } else {
        # Linux/macOS: 單行 "hash  path" 格式
        if ($output -notmatch '^([a-fA-F0-9]{64})\s+(.+)$') {
            throw "Unexpected output for '$RemotePath': $output"
        }
        $hash = $Matches[1].ToUpper()
        $absolutePath = $Matches[2]
    }

    # 驗證雜湊格式（64 個十六進位字元）
    if ($hash -notmatch '^[A-F0-9]{64}$') {
        throw "Invalid hash returned for '$RemotePath': $hash"
    }

    return [PSCustomObject]@{
        Hash         = $hash
        AbsolutePath = $absolutePath
    }
}
