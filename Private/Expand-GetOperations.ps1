function Expand-GetOperations {
    <#
    .SYNOPSIS
        展開 GET 操作中的遠端萬用字元。
    .PARAMETER Operations
        GET 操作陣列。
    .PARAMETER SessionId
        Posh-SSH 工作階段 ID。
    .OUTPUTS
        展開後的操作陣列。
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
        if ($op.HasWildcard) {
            $remoteFiles = Expand-RemoteWildcard -SessionId $SessionId -RemotePath $op.RemotePath
            
            if ($remoteFiles.Count -eq 0) {
                Write-Host "  ⚠ No files match: $($op.RemotePath)" -ForegroundColor Yellow
                continue
            }
            
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
        } else {
            $expandedOps += $op
        }
    }
    
    Write-Host "  Expanded to $($expandedOps.Count) files" -ForegroundColor Gray
    Write-Host ""
    
    return $expandedOps
}
