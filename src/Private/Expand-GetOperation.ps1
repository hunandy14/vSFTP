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

        # 使用 ls -1 列出符合模式的檔案
        $lsResult = Invoke-SSHCommand -SessionId $SessionId -Command "ls -1d $($op.RemotePath) 2>/dev/null" -TimeOut 60

        if ($lsResult.ExitStatus -ne 0 -or [string]::IsNullOrWhiteSpace($lsResult.Output)) {
            Write-Host "  ⚠ No files match: $($op.RemotePath)" -ForegroundColor Yellow
            continue
        }

        $remoteFiles = $lsResult.Output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

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
