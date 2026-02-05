function Expand-GetOperation {
    <#
    .SYNOPSIS
        展開 GET 操作中的遠端萬用字元。
    .PARAMETER Operations
        GET 操作陣列。
    .PARAMETER SessionId
        Posh-SSH 工作階段 ID。
    .PARAMETER RemoteOS
        遠端作業系統（Linux、macOS、Windows）。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Operations,

        [Parameter(Mandatory)]
        [int]$SessionId,

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

        # 空目錄路徑時預設為當前目錄
        if (-not $dirPath) { $dirPath = "." }

        # 驗證模式不含危險字元（只允許 * ? [ ] 和一般檔名字元）
        # 禁止: ; | $ ` \ < > & ' " 換行符
        if ($pattern -match '[;|$`<>&''"\r\n]') {
            throw "Invalid pattern contains dangerous characters: $pattern"
        }
        
        # 驗證模式不為空
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            throw "Invalid pattern: empty pattern"
        }

        # 根據遠端 OS 選擇展開命令
        $command = switch ($RemoteOS) {
            'Windows' {
                # Windows: 用 PowerShell Get-ChildItem
                # 目錄和模式都用 Base64 編碼
                $encodedDir = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($dirPath))
                $encodedPattern = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pattern))
                "powershell -NoProfile -Command `"Get-ChildItem -Path ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encodedDir'))) -Filter ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encodedPattern'))) -File | ForEach-Object { `$_.FullName }`""
            }
            default {
                # Linux/macOS: 用 find
                $encodedDir = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($dirPath))
                'find "$(echo ' + $encodedDir + ' | base64 -d)" -maxdepth 1 -name ''' + $pattern + ''' -type f 2>/dev/null | sort'
            }
        }

        $findResult = Invoke-SSHCommand -SessionId $SessionId -Command $command -TimeOut 60

        if ($findResult.ExitStatus -ne 0 -or [string]::IsNullOrWhiteSpace($findResult.Output)) {
            Write-Host "  ⚠ No files match: $($op.RemotePath)" -ForegroundColor Yellow
            continue
        }

        $remoteFiles = $findResult.Output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $localDir = Split-Path $op.LocalPath -Parent

        foreach ($remoteFile in $remoteFiles) {
            # Windows 路徑正規化
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
