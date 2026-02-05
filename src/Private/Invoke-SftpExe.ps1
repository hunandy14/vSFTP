function Invoke-SftpExe {
    <#
    .SYNOPSIS
        使用批次腳本執行 sftp.exe。
    .PARAMETER ScriptFile
        SFTP 批次腳本的路徑。
    .PARAMETER RemoteHost
        遠端主機。
    .PARAMETER User
        使用者名稱。
    .PARAMETER KeyFile
        私鑰檔案路徑。
    .PARAMETER Port
        SSH 連接埠。
    .PARAMETER SkipHostKeyCheck
        跳過主機金鑰驗證。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptFile,
        [Parameter(Mandatory)][string]$RemoteHost,
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][string]$KeyFile,
        [int]$Port = 22,
        [switch]$SkipHostKeyCheck
    )

    $hostKeyOption = if ($SkipHostKeyCheck) { "no" } else { "accept-new" }

    $sftpArgs = @(
        "-b", $ScriptFile,
        "-P", $Port,
        "-o", "StrictHostKeyChecking=$hostKeyOption",
        "-o", "BatchMode=yes",
        "-i", $KeyFile,
        "$User@$RemoteHost"
    )

    Write-Verbose "Executing: sftp $($sftpArgs -join ' ')"

    # 使用 & 執行並即時顯示輸出
    $output = & sftp @sftpArgs 2>&1
    $output | ForEach-Object { Write-Host $_ }

    return [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        Output   = $output -join "`n"
    }
}
