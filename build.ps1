#!/usr/bin/env pwsh
<#
.SYNOPSIS
    建置 vSFTP 為單一 .ps1 檔案
.DESCRIPTION
    合併所有函數為單一可執行腳本
#>

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$SrcDir = Join-Path $ProjectRoot "src"
$DistDir = Join-Path $ProjectRoot "dist"

# 清理並建立輸出目錄
if (Test-Path $DistDir) {
    Remove-Item $DistDir -Recurse -Force
}
New-Item -ItemType Directory -Path $DistDir | Out-Null

Write-Host "► 建置 vSFTP..." -ForegroundColor Yellow

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

# 私有函數
$privateFiles = Get-ChildItem -Path "$SrcDir/Private/*.ps1" -ErrorAction SilentlyContinue
foreach ($file in $privateFiles) {
    Write-Host "  + Private/$($file.Name)" -ForegroundColor Gray
    $content += "#region $($file.BaseName)"
    $content += (Get-Content $file.FullName -Raw).Trim()
    $content += "#endregion"
    $content += ""
}

# 公開函數
$publicFiles = Get-ChildItem -Path "$SrcDir/Public/*.ps1" -ErrorAction SilentlyContinue
foreach ($file in $publicFiles) {
    Write-Host "  + Public/$($file.Name)" -ForegroundColor Gray
    $content += "#region $($file.BaseName)"
    $content += (Get-Content $file.FullName -Raw).Trim()
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

Write-Host ""
Write-Host "► 建置完成" -ForegroundColor Green
Write-Host "  輸出: $outputPath" -ForegroundColor Gray

# 顯示檔案大小
$fileSize = (Get-Item $outputPath).Length
Write-Host "  大小: $([math]::Round($fileSize / 1KB, 1)) KB" -ForegroundColor Gray

Write-Host ""
Write-Host "  使用方式:" -ForegroundColor White
Write-Host "    ./dist/vSFTP.ps1 -ScriptFile <script.sftp>" -ForegroundColor Gray
