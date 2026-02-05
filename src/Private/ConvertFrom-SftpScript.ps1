function ConvertFrom-SftpScript {
    <#
    .SYNOPSIS
        解析 SFTP 批次腳本並提取檔案傳輸操作。
    .DESCRIPTION
        追蹤 cd/lcd 指令以解析路徑，並展開萬用字元。
    .PARAMETER ScriptFile
        SFTP 批次腳本的路徑。
    .PARAMETER LocalBase
        本地基礎目錄（預設為當前目錄）。
    .PARAMETER RemoteBase
        遠端基礎目錄（預設為 /）。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptFile,

        [string]$LocalBase = (Get-Location).Path,

        [string]$RemoteBase = "/"
    )

    if (-not (Test-Path $ScriptFile)) {
        throw "Script file not found: $ScriptFile"
    }

    $localDir = $LocalBase
    $remoteDir = $RemoteBase
    $operations = @()
    $lineNum = 0

    foreach ($line in Get-Content $ScriptFile) {
        $lineNum++
        $line = $line.Trim()

        # 跳過空行和註解
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }

        # 解析指令和參數（支援引號內的空格）
        $tokens = @()
        $current = ""
        $inQuote = $false
        $quoteChar = $null
        
        foreach ($char in $line.ToCharArray()) {
            if ($inQuote) {
                if ($char -eq $quoteChar) {
                    $inQuote = $false
                    $quoteChar = $null
                } else {
                    $current += $char
                }
            } elseif ($char -eq '"' -or $char -eq "'") {
                $inQuote = $true
                $quoteChar = $char
            } elseif ($char -match '\s') {
                if ($current) {
                    $tokens += $current
                    $current = ""
                }
            } else {
                $current += $char
            }
        }
        if ($current) { $tokens += $current }
        
        $cmd = if ($tokens.Count -gt 0) { $tokens[0].ToLower() } else { continue }
        $arg1 = if ($tokens.Count -gt 1) { $tokens[1] } else { $null }
        $arg2 = if ($tokens.Count -gt 2) { $tokens[2] } else { $null }

        switch ($cmd) {
            'lcd' {
                if ($arg1) {
                    if ([System.IO.Path]::IsPathRooted($arg1)) {
                        $localDir = $arg1
                    } else {
                        $localDir = Join-Path $localDir $arg1
                    }
                    $localDir = [System.IO.Path]::GetFullPath($localDir)
                    Write-Verbose "Line $lineNum : lcd -> $localDir"
                }
            }

            'cd' {
                if ($arg1) {
                    if ($arg1.StartsWith('/')) {
                        $remoteDir = $arg1
                    } else {
                        $remoteDir = "$remoteDir/$arg1" -replace '//+', '/'
                    }
                    # 正規化路徑（移除 . 和 ..）
                    $remoteParts = $remoteDir -split '/' | Where-Object { $_ -and $_ -ne '.' }
                    $normalized = @()
                    foreach ($part in $remoteParts) {
                        if ($part -eq '..') {
                            if ($normalized.Count -gt 0) {
                                $normalized = $normalized[0..($normalized.Count - 2)]
                            }
                        } else {
                            $normalized += $part
                        }
                    }
                    $remoteDir = '/' + ($normalized -join '/')
                    Write-Verbose "Line $lineNum : cd -> $remoteDir"
                }
            }

            'put' {
                if (-not $arg1) {
                    Write-Warning "Line $lineNum : put command missing source"
                    continue
                }

                # 解析本地路徑
                $localPattern = if ([System.IO.Path]::IsPathRooted($arg1)) {
                    $arg1
                } else {
                    Join-Path $localDir $arg1
                }

                # 展開萬用字元
                try {
                    $localFiles = @(Get-ChildItem -Path $localPattern -File -ErrorAction Stop)
                } catch {
                    throw "Line $lineNum : $($_.Exception.Message)"
                }

                if ($localFiles.Count -eq 0) {
                    throw "Line $lineNum : No files match pattern: $localPattern"
                }

                foreach ($localFile in $localFiles) {
                    # 決定遠端路徑
                    $remotePath = if ($arg2) {
                        if ($arg2.StartsWith('/')) {
                            if ($arg2.EndsWith('/')) {
                                "$arg2$($localFile.Name)"
                            } else {
                                $arg2
                            }
                        } else {
                            "$remoteDir/$arg2" -replace '//+', '/'
                        }
                    } else {
                        "$remoteDir/$($localFile.Name)" -replace '//+', '/'
                    }

                    $operations += [PSCustomObject]@{
                        Action     = 'put'
                        LocalPath  = $localFile.FullName
                        RemotePath = $remotePath
                        Line       = $lineNum
                    }
                    Write-Verbose "Line $lineNum : put $($localFile.FullName) -> $remotePath"
                }
            }

            'get' {
                if (-not $arg1) {
                    Write-Warning "Line $lineNum : get command missing source"
                    continue
                }

                # 解析遠端路徑
                $remotePath = if ($arg1.StartsWith('/')) {
                    $arg1
                } else {
                    "$remoteDir/$arg1" -replace '//+', '/'
                }

                # 決定本地路徑
                $remoteFileName = Split-Path $remotePath -Leaf
                $localPath = if ($arg2) {
                    if ([System.IO.Path]::IsPathRooted($arg2)) {
                        if ($arg2.EndsWith('/') -or $arg2.EndsWith('\')) {
                            Join-Path $arg2 $remoteFileName
                        } else {
                            $arg2
                        }
                    } else {
                        Join-Path $localDir $arg2
                    }
                } else {
                    Join-Path $localDir $remoteFileName
                }
                $localPath = [System.IO.Path]::GetFullPath($localPath)

                # 注意：遠端萬用字元無法在本地展開
                # 我們將它們視為單一項目；驗證時會處理多個檔案
                $operations += [PSCustomObject]@{
                    Action     = 'get'
                    LocalPath  = $localPath
                    RemotePath = $remotePath
                    Line       = $lineNum
                    HasWildcard = $remotePath -match '[\*\?]'
                }
                Write-Verbose "Line $lineNum : get $remotePath -> $localPath"
            }

            default {
                Write-Verbose "Line $lineNum : Untracked command: $cmd (passed to sftp.exe)"
            }
        }
    }

    return $operations
}
