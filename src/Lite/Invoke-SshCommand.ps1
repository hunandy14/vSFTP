function Invoke-SshCommand {
    <#
    .SYNOPSIS
        統一的 SSH 指令執行函式。
    .DESCRIPTION
        集中處理 ssh 參數組裝、執行和錯誤捕獲。
        當 KeyFile 為空時不傳 -i，讓 ssh 自動選擇金鑰。
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
        PSCustomObject 包含 ExitCode 和 Output 屬性。
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

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output   = $output
    }
}
