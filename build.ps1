#!/usr/bin/env pwsh
<#
.SYNOPSIS
    建置 vSFTP 為單一 .ps1 檔案
.DESCRIPTION
    合併所有函數為單一可執行腳本
.PARAMETER Lite
    建置輕量版（使用 ssh/sftp 指令，無需 Posh-SSH）
.PARAMETER StripBlockComments
    移除函式區塊註解
.PARAMETER StripAllComments
    移除所有註解（區塊註解和行註解）
#>
param(
    [switch]$Lite,
    [switch]$StripBlockComments,
    [switch]$StripAllComments
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$SrcDir = Join-Path $ProjectRoot "src"
$DistDir = Join-Path $ProjectRoot "dist"

# 確保輸出目錄存在
if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir | Out-Null
}

$variant = if ($Lite) { "Lite" } else { "Full" }
$outputName = if ($Lite) { "vSFTP-Lite.ps1" } else { "vSFTP.ps1" }

Write-Host "► 建置 vSFTP ($variant): " -ForegroundColor Yellow -NoNewline
Write-Host "$SrcDir/" -ForegroundColor DarkGray

# 收集所有程式碼
$content = @()

# 標頭
$content += "#!/usr/bin/env pwsh"
$content += "#Requires -Version 7.0"
if (-not $Lite) {
    $content += "#Requires -Modules Posh-SSH"
}
$content += ""
$content += "<#"
$content += ".SYNOPSIS"
$content += "    vSFTP$(if ($Lite) { ' Lite' } else { '' }) - SFTP with Hash Verification"
$content += ".DESCRIPTION"
$content += "    執行 SFTP 傳輸並驗證 SHA256 雜湊$(if ($Lite) { '（輕量版，使用 ssh/sftp 指令）' } else { '' })"
$content += ".EXAMPLE"
$content += "    ./$outputName -ScriptFile upload.sftp"
$content += "#>"
$content += ""
$content += "# Built: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ($variant)"
$content += ""

# 處理程式碼的輔助函數
function Remove-Comments {
    param(
        [string]$Code,
        [switch]$BlockComments,
        [switch]$AllComments
    )
    
    if ($AllComments) {
        $Code = $Code -replace '(?s)<#.*?#>\s*', ''
        $Code = ($Code -split "`n" | Where-Object { 
            $_.Trim() -ne '' -and (
                $_.Trim() -notmatch '^#' -or 
                $_.Trim() -match '^#(region|endregion|Requires)'
            )
        }) -join "`n"
    } elseif ($BlockComments) {
        $Code = $Code -replace '(?s)<#.*?#>\s*', ''
    }
    
    return $Code.Trim()
}

function Add-SourceFile {
    param(
        [string]$FilePath,
        [string]$DisplayDir
    )
    
    $file = Get-Item $FilePath
    $originalCode = (Get-Content $file.FullName -Raw).Trim()
    $originalLines = ($originalCode -split "`n").Count
    $code = Remove-Comments -Code $originalCode -BlockComments:$StripBlockComments -AllComments:$StripAllComments
    $effectiveLines = ($code -split "`n").Count
    $ratio = if ($originalLines -gt 0) { [math]::Round($effectiveLines / $originalLines * 100) } else { 100 }
    $fileSizeKB = [math]::Round($file.Length / 1KB, 1)
    
    Write-Host "  + $DisplayDir/" -ForegroundColor White -NoNewline
    Write-Host ("{0,-30}" -f $file.Name) -ForegroundColor White -NoNewline
    Write-Host (" {0,4}/{1,-4} ({2}%)  {3} KB" -f $effectiveLines, $originalLines, $ratio, $fileSizeKB) -ForegroundColor DarkGray
    
    return @(
        "#region $($file.BaseName)"
        $code
        "#endregion"
        ""
    )
}

# 共用函數
$commonDir = Join-Path $SrcDir "Common"
if (Test-Path $commonDir) {
    foreach ($file in Get-ChildItem -Path "$commonDir/*.ps1" -File) {
        $content += Add-SourceFile -FilePath $file.FullName -DisplayDir "Common"
    }
}

# 版本專用函數
$variantDir = Join-Path $SrcDir $variant
if (Test-Path $variantDir) {
    foreach ($file in Get-ChildItem -Path "$variantDir/*.ps1" -File) {
        $content += Add-SourceFile -FilePath $file.FullName -DisplayDir $variant
    }
}

# 主程式入口
$content += "#region Main"
$content += 'if ($MyInvocation.InvocationName -ne ".") {'
$content += '    # 直接執行時，呼叫 Invoke-vSFTP'
$content += '    Invoke-vSFTP @args'
$content += '}'
$content += "#endregion"

# 寫入 .ps1
$outputPath = Join-Path $DistDir $outputName
$content -join "`n" | Set-Content -Path $outputPath -NoNewline

# 輸出檔案統計
$outputContent = Get-Content $outputPath
$outputTotal = $outputContent.Count
$outputEffective = ($outputContent | Where-Object { $_.Trim() -ne '' -and ($_.Trim() -notmatch '^#' -or $_.Trim() -match '^#(region|endregion|Requires)') }).Count
$outputRatio = if ($outputTotal -gt 0) { [math]::Round($outputEffective / $outputTotal * 100) } else { 100 }
$fileSize = (Get-Item $outputPath).Length
$sizeKB = [math]::Round($fileSize / 1KB, 1)

Write-Host ""
Write-Host "► 建置完成: " -ForegroundColor Green -NoNewline
Write-Host "$DistDir/" -ForegroundColor DarkGray
Write-Host "    → " -ForegroundColor DarkGray -NoNewline
Write-Host ("{0,-38}" -f $outputName) -ForegroundColor Cyan -NoNewline
Write-Host (" {0,4}/{1,-4} ({2}%)  {3} KB" -f $outputEffective, $outputTotal, $outputRatio, $sizeKB) -ForegroundColor DarkGray
Write-Host ""
Write-Host "  使用方式: " -ForegroundColor White -NoNewline
Write-Host "./dist/$outputName " -ForegroundColor Yellow -NoNewline
Write-Host "-ScriptFile " -ForegroundColor DarkGray -NoNewline
Write-Host "<script.sftp>" -ForegroundColor White
