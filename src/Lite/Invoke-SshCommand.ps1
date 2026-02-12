function Invoke-SshCommand {
    <#
    .SYNOPSIS
        統一的 SSH 指令執行函式。
    .DESCRIPTION
        集中處理 ssh 參數組裝、執行和錯誤捕獲。
        當 KeyFile 為空時不傳 -i，讓 ssh 自動選擇金鑰。
        執行失敗時使用 Write-Error 報告錯誤（非終止），呼叫者可用 -ErrorAction 控制。
    .PARAMETER SshHost
        遠端主機（user@host 格式）。
    .PARAMETER Port
        SSH 連接埠。
    .PARAMETER KeyFile
        私鑰檔案路徑。$null 或空字串時不傳 -i。
    .PARAMETER Command
        要在遠端執行的指令。
    .PARAMETER SkipHostKeyCheck
        跳過主機金鑰驗證。
    .OUTPUTS
        成功時回傳 ssh 輸出（字串陣列），失敗時 Write-Error 並回傳 $null。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SshHost,

        [int]$Port = 22,

        [string]$KeyFile,

        [Parameter(Mandatory)]
        [string]$Command,

        [switch]$SkipHostKeyCheck
    )

    $hostKeyOption = if ($SkipHostKeyCheck) { "no" } else { "accept-new" }

    $sshArgs = @()
    if ($KeyFile) {
        $sshArgs += "-i", $KeyFile
    }
    $sshArgs += "-p", $Port
    $sshArgs += "-o", "BatchMode=yes"
    $sshArgs += "-o", "StrictHostKeyChecking=$hostKeyOption"
    $sshArgs += "-o", "ConnectTimeout=30"
    $sshArgs += $SshHost
    $sshArgs += $Command

    Write-Verbose "Executing: ssh $($sshArgs -join ' ')"

    $output = & ssh @sshArgs 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        Write-Error "SSH command failed (exit $exitCode): $Command`n$($output | Out-String)"
        return
    }

    return $output
}
