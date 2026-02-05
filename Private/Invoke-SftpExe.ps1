function Invoke-SftpExe {
    <#
    .SYNOPSIS
        Executes sftp.exe with a batch script.
    .PARAMETER ScriptFile
        Path to SFTP batch script.
    .PARAMETER Host
        Remote host.
    .PARAMETER User
        Username.
    .PARAMETER Port
        SSH port.
    .PARAMETER KeyFile
        Private key file path (required).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptFile,
        
        [Parameter(Mandatory)]
        [string]$Host,
        
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
    
    $sftpArgs += "$User@$Host"
    
    Write-Verbose "Executing: sftp $($sftpArgs -join ' ')"
    
    # Execute sftp
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "sftp"
    $pinfo.Arguments = $sftpArgs -join ' '
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $pinfo
    
    # Capture output
    $stdout = New-Object System.Text.StringBuilder
    $stderr = New-Object System.Text.StringBuilder
    
    $process.Start() | Out-Null
    
    # Read output asynchronously
    while (-not $process.HasExited) {
        $line = $process.StandardOutput.ReadLine()
        if ($line) {
            [void]$stdout.AppendLine($line)
            Write-Host $line
        }
        Start-Sleep -Milliseconds 100
    }
    
    # Read remaining output
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
