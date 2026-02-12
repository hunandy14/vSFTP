function Expand-GetOperation {
    <#
    .SYNOPSIS
        展開 GET 操作中的遠端萬用字元。
    .PARAMETER Operations
        GET 操作陣列。
    .PARAMETER SshHost
        遠端主機 (user@host)。
    .PARAMETER Port
        SSH 連接埠。
    .PARAMETER KeyFile
        私鑰檔案路徑。
    .PARAMETER RemoteOS
        遠端作業系統（Linux、macOS、Windows）。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Operations,

        [Parameter(Mandatory)]
        [string]$SshHost,

        [int]$Port = 22,

        [string]$KeyFile,

        [Parameter(Mandatory)]
        [ValidateSet('Linux', 'macOS', 'Windows')]
        [string]$RemoteOS
    )

    $wildcardOps = @($Operations | Where-Object { $_.HasWildcard })

    if ($wildcardOps.Count -eq 0) {
        return $Operations
    }

    Write-Host "► Expanding remote wildcards..." -ForegroundColor Yellow

    $expandedOps = @()

    foreach ($op in $Operations) {
        if (-not $op.HasWildcard) {
            $expandedOps += $op
            continue
        }

        # 分離目錄和檔名模式
        $dirPath = Split-Path $op.RemotePath -Parent
        $pattern = Split-Path $op.RemotePath -Leaf

        if (-not $dirPath) { $dirPath = "." }

        # 驗證模式不含危險字元
        if ($pattern -match '[;|$`<>&''"\r\n]') {
            throw "Invalid pattern contains dangerous characters: $pattern"
        }
        
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            throw "Invalid pattern: empty pattern"
        }

        # 根據遠端 OS 選擇展開命令
        $remoteCmd = switch ($RemoteOS) {
            'Windows' {
                $fullPattern = Join-Path $dirPath $pattern
                $encodedPath = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($fullPattern))
                "powershell -NoProfile -Command `"Get-ChildItem -Path ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encodedPath'))) -File | ForEach-Object { `$_.FullName }`""
            }
            default {
                $encodedDir = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($dirPath))
                'find "$(echo ' + $encodedDir + ' | base64 -d)" -maxdepth 1 -name ''' + $pattern + ''' -type f 2>/dev/null | sort'
            }
        }

        $result = Invoke-SshCommand -SshHost $SshHost -Port $Port -KeyFile $KeyFile -Command $remoteCmd

        if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace(($result.Output | Out-String))) {
            Write-Host "  ⚠ No files match: $($op.RemotePath)" -ForegroundColor Yellow
            continue
        }

        $remoteFiles = ($result.Output | Out-String) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $localDir = Split-Path $op.LocalPath -Parent

        foreach ($remoteFile in $remoteFiles) {
            if ($RemoteOS -eq 'Windows') {
                $remoteFile = $remoteFile -replace '\\', '/'
            }

            $localPath = Join-Path $localDir (Split-Path $remoteFile -Leaf)

            $expandedOps += [PSCustomObject]@{
                Action      = 'get'
                LocalPath   = $localPath
                RemotePath  = $remoteFile
                Line        = $op.Line
                HasWildcard = $false
            }
            Write-Host "  $($op.RemotePath) → $remoteFile" -ForegroundColor Gray
        }
    }

    Write-Host "  Expanded to $($expandedOps.Count) files" -ForegroundColor Gray
    Write-Host ""

    return $expandedOps
}
