function Expand-GetOperation {
    <#
    .SYNOPSIS
        展開 GET 操作中的遠端萬用字元。
    .PARAMETER Operations
        GET 操作陣列。
    .PARAMETER SessionId
        Posh-SSH 工作階段 ID。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Operations,

        [Parameter(Mandatory)]
        [int]$SessionId
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
        $remotePath = $op.RemotePath
        $dirPath = Split-Path $remotePath -Parent
        $pattern = Split-Path $remotePath -Leaf

        # 驗證模式不含危險字元（只允許 * ? [ ] 和一般檔名字元）
        if ($pattern -match '[;|$`\\<>&]') {
            throw "Invalid pattern contains dangerous characters: $pattern"
        }

        # 目錄路徑用 Base64 編碼
        $encodedDir = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($dirPath))

        # 使用 find 安全地展開萬用字元
        # find 的 -name 會自己處理萬用字元，不經過 shell glob
        $command = 'find "$(echo ' + $encodedDir + ' | base64 -d)" -maxdepth 1 -name ''' + $pattern + ''' -type f 2>/dev/null | sort'

        $findResult = Invoke-SSHCommand -SessionId $SessionId -Command $command -TimeOut 60

        if ($findResult.ExitStatus -ne 0 -or [string]::IsNullOrWhiteSpace($findResult.Output)) {
            Write-Host "  ⚠ No files match: $($op.RemotePath)" -ForegroundColor Yellow
            continue
        }

        $remoteFiles = $findResult.Output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

        foreach ($remoteFile in $remoteFiles) {
            $fileName = Split-Path $remoteFile -Leaf
            $localDir = Split-Path $op.LocalPath -Parent
            $localPath = Join-Path $localDir $fileName

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
