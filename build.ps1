#!/usr/bin/env pwsh
<#
.SYNOPSIS
    建置 vSFTP 為單一 .ps1 檔案
.DESCRIPTION
    合併所有函數為單一可執行腳本
.PARAMETER StripBlockComments
    移除函式區塊註解
.PARAMETER StripAllComments
    移除所有註解（區塊註解和行註解）
#>
param(
    [switch]$StripBlockComments,
    [switch]$StripAllComments
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$SrcDir = Join-Path $ProjectRoot "src"
$DistDir = Join-Path $ProjectRoot "dist"

# 清理並建立輸出目錄
if (Test-Path $DistDir) {
    Remove-Item $DistDir -Recurse -Force
}
New-Item -ItemType Directory -Path $DistDir | Out-Null

Write-Host "► 建置 vSFTP: " -ForegroundColor Yellow -NoNewline
Write-Host "$SrcDir/" -ForegroundColor DarkGray

# 收集所有程式碼
$content = @()

# 標頭
$content += "#!/usr/bin/env pwsh"
$content += "#Requires -Version 7.0"
$content += "#Requires -Modules Posh-SSH"
$content += ""
$content += "<#"
$content += ".SYNOPSIS"
$content += "    vSFTP - SFTP with Hash Verification"
$content += ".DESCRIPTION"
$content += "    執行 SFTP 傳輸並驗證 SHA256 雜湊"
$content += ".EXAMPLE"
$content += "    ./vSFTP.ps1 -ScriptFile upload.sftp"
$content += "#>"
$content += ""
$content += "# Built: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$content += ""

# 處理程式碼的輔助函數
function Remove-Comments {
    param(
        [string]$Code,
        [switch]$BlockComments,
        [switch]$AllComments
    )
    
    if ($AllComments) {
        # 移除區塊註解
        $Code = $Code -replace '(?s)<#.*?#>\s*', ''
        # 移除行註解（但保留 #region/#endregion/#Requires）和空行
        $Code = ($Code -split "`n" | Where-Object { 
            $_.Trim() -ne '' -and (
                $_.Trim() -notmatch '^#' -or 
                $_.Trim() -match '^#(region|endregion|Requires)'
            )
        }) -join "`n"
    } elseif ($BlockComments) {
        # 只移除區塊註解
        $Code = $Code -replace '(?s)<#.*?#>\s*', ''
    }
    
    return $Code.Trim()
}

# 統計資料
$stats = @()

# 私有函數
$privateFiles = if (Test-Path "$SrcDir/Private") { Get-ChildItem -Path "$SrcDir/Private/*.ps1" -File } else { @() }
foreach ($file in $privateFiles) {
    $originalCode = (Get-Content $file.FullName -Raw).Trim()
    $originalLines = ($originalCode -split "`n").Count
    $code = Remove-Comments -Code $originalCode -BlockComments:$StripBlockComments -AllComments:$StripAllComments
    $effectiveLines = ($code -split "`n").Count
    $ratio = if ($originalLines -gt 0) { [math]::Round($effectiveLines / $originalLines * 100) } else { 100 }
    $fileSizeKB = [math]::Round($file.Length / 1KB, 1)
    
    Write-Host "  + Private/" -ForegroundColor White -NoNewline
    Write-Host ("{0,-30}" -f $file.Name) -ForegroundColor White -NoNewline
    Write-Host (" {0,4}/{1,-4} ({2}%)  {3} KB" -f $effectiveLines, $originalLines, $ratio, $fileSizeKB) -ForegroundColor DarkGray
    $stats += [PSCustomObject]@{ Name = $file.Name; Original = $originalLines; Effective = $effectiveLines }
    
    $content += "#region $($file.BaseName)"
    $content += $code
    $content += "#endregion"
    $content += ""
}

# 公開函數
$publicFiles = if (Test-Path "$SrcDir/Public") { Get-ChildItem -Path "$SrcDir/Public/*.ps1" -File } else { @() }
foreach ($file in $publicFiles) {
    $originalCode = (Get-Content $file.FullName -Raw).Trim()
    $originalLines = ($originalCode -split "`n").Count
    $code = Remove-Comments -Code $originalCode -BlockComments:$StripBlockComments -AllComments:$StripAllComments
    $effectiveLines = ($code -split "`n").Count
    $ratio = if ($originalLines -gt 0) { [math]::Round($effectiveLines / $originalLines * 100) } else { 100 }
    $fileSizeKB = [math]::Round($file.Length / 1KB, 1)
    
    Write-Host "  + Public/" -ForegroundColor White -NoNewline
    Write-Host ("{0,-31}" -f $file.Name) -ForegroundColor White -NoNewline
    Write-Host (" {0,4}/{1,-4} ({2}%)  {3} KB" -f $effectiveLines, $originalLines, $ratio, $fileSizeKB) -ForegroundColor DarkGray
    $stats += [PSCustomObject]@{ Name = $file.Name; Original = $originalLines; Effective = $effectiveLines }
    
    $content += "#region $($file.BaseName)"
    $content += $code
    $content += "#endregion"
    $content += ""
}

# 主程式入口
$content += "#region Main"
$content += 'if ($MyInvocation.InvocationName -ne ".") {'
$content += '    # 直接執行時，呼叫 Invoke-vSFTP'
$content += '    Invoke-vSFTP @args'
$content += '}'
$content += "#endregion"

# 寫入 .ps1
$outputPath = Join-Path $DistDir "vSFTP.ps1"
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
Write-Host "    1. " -ForegroundColor DarkGray -NoNewline
Write-Host ("{0,-38}" -f "vSFTP.ps1") -ForegroundColor Cyan -NoNewline
Write-Host (" {0,4}/{1,-4} ({2}%)  {3} KB" -f $outputEffective, $outputTotal, $outputRatio, $sizeKB) -ForegroundColor DarkGray
Write-Host ""
Write-Host "  使用方式: " -ForegroundColor White -NoNewline
Write-Host "./dist/vSFTP.ps1 " -ForegroundColor Yellow -NoNewline
Write-Host "-ScriptFile " -ForegroundColor DarkGray -NoNewline
Write-Host "<script.sftp>" -ForegroundColor White
