function Parse-SftpScript {
    <#
    .SYNOPSIS
        Parses SFTP batch script and extracts file transfer operations.
    .DESCRIPTION
        Tracks cd/lcd commands for path resolution and expands wildcards.
    .PARAMETER ScriptFile
        Path to SFTP batch script.
    .PARAMETER LocalBase
        Base local directory (defaults to current directory).
    .PARAMETER RemoteBase
        Base remote directory (defaults to /).
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
        
        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }
        
        # Parse command and arguments
        $parts = $line -split '\s+', 3
        $cmd = $parts[0].ToLower()
        $arg1 = if ($parts.Count -gt 1) { $parts[1] } else { $null }
        $arg2 = if ($parts.Count -gt 2) { $parts[2] } else { $null }
        
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
                    # Normalize path (remove . and ..)
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
                
                # Resolve local path
                $localPattern = if ([System.IO.Path]::IsPathRooted($arg1)) {
                    $arg1
                } else {
                    Join-Path $localDir $arg1
                }
                
                # Expand wildcards
                $localFiles = @(Get-ChildItem -Path $localPattern -File -ErrorAction SilentlyContinue)
                
                if ($localFiles.Count -eq 0) {
                    Write-Warning "Line $lineNum : No files match pattern: $localPattern"
                    continue
                }
                
                foreach ($localFile in $localFiles) {
                    # Determine remote path
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
                
                # Resolve remote path
                $remotePath = if ($arg1.StartsWith('/')) {
                    $arg1
                } else {
                    "$remoteDir/$arg1" -replace '//+', '/'
                }
                
                # Determine local path
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
                
                # Note: Remote wildcards cannot be expanded locally
                # We treat them as single entries; verification will handle multiple files
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
