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
        私鑰檔案路徑（必須）。
    .PARAMETER Port
        SSH 連接埠。
    .PARAMETER SkipHostKeyCheck
        跳過主機金鑰驗證。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptFile,

        [Parameter(Mandatory)]
        [string]$RemoteHost,

        [Parameter(Mandatory)]
        [string]$User,

        [Parameter(Mandatory)]
        [string]$KeyFile,

        [int]$Port = 22,

        [switch]$SkipHostKeyCheck
    )

    $hostKeyOption = if ($SkipHostKeyCheck) { "no" } else { "accept-new" }

    $sftpArgs = @(
        "-b", $ScriptFile,
        "-P", $Port,
        "-o", "StrictHostKeyChecking=$hostKeyOption",
        "-o", "BatchMode=yes",
        "-i", $KeyFile
    )

    $sftpArgs += "$User@$RemoteHost"

    Write-Verbose "Executing: sftp $($sftpArgs -join ' ')"

    # 執行 sftp
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "sftp"
    $pinfo.Arguments = $sftpArgs -join ' '
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $pinfo

    # 擷取輸出
    $stdout = New-Object System.Text.StringBuilder
    $stderr = New-Object System.Text.StringBuilder

    $process.Start() | Out-Null

    # 非同步讀取輸出
    while (-not $process.HasExited) {
        $line = $process.StandardOutput.ReadLine()
        if ($line) {
            [void]$stdout.AppendLine($line)
            Write-Host $line
        }
        Start-Sleep -Milliseconds 100
    }

    # 讀取剩餘輸出
    $remaining = $process.StandardOutput.ReadToEnd()
    if ($remaining) {
        [void]$stdout.Append($remaining)
        Write-Host $remaining
    }

    $errorOutput = $process.StandardError.ReadToEnd()
    if ($errorOutput) {
        [void]$stderr.Append($errorOutput)
        Write-Host $errorOutput -ForegroundColor Red
    }

    return [PSCustomObject]@{
        ExitCode = $process.ExitCode
        Output   = $stdout.ToString()
        Error    = $stderr.ToString()
    }
}
