#!/usr/bin/env pwsh
<#
.SYNOPSIS
    建置 vSFTP 模組為單一檔案
.DESCRIPTION
    合併所有 .ps1 檔案為單一 .psm1，輸出到 dist/
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

Write-Host "► 建置 vSFTP 模組..." -ForegroundColor Yellow

# 收集所有程式碼
$content = @()

# 標頭
$content += "#Requires -Version 7.0"
$content += "#Requires -Modules Posh-SSH"
$content += ""
$content += "# vSFTP - SFTP with Hash Verification"
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

# 匯出
$exportFunctions = ($publicFiles | ForEach-Object { $_.BaseName }) -join "', '"
$content += "Export-ModuleMember -Function '$exportFunctions'"

# 寫入 .psm1
$psmPath = Join-Path $DistDir "vSFTP.psm1"
$content -join "`n" | Set-Content -Path $psmPath -NoNewline

# 複製 .psd1（更新 RootModule 路徑）
$psdSource = Join-Path $SrcDir "vSFTP.psd1"
$psdDest = Join-Path $DistDir "vSFTP.psd1"
$psdContent = Get-Content $psdSource -Raw
$psdContent = $psdContent -replace "RootModule\s*=\s*'[^']*'", "RootModule = 'vSFTP.psm1'"
$psdContent | Set-Content -Path $psdDest -NoNewline

Write-Host ""
Write-Host "► 建置完成" -ForegroundColor Green
Write-Host "  輸出: $DistDir" -ForegroundColor Gray

# 顯示檔案大小
$psmSize = (Get-Item $psmPath).Length
$psdSize = (Get-Item $psdDest).Length
Write-Host ""
Write-Host "  vSFTP.psm1  $([math]::Round($psmSize / 1KB, 1)) KB" -ForegroundColor Gray
Write-Host "  vSFTP.psd1  $([math]::Round($psdSize / 1KB, 1)) KB" -ForegroundColor Gray
