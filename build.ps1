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
        # 移除行註解（但保留 #region/#endregion/#Requires）
        $Code = ($Code -split "`n" | Where-Object { 
            $_.Trim() -eq '' -or 
            $_.Trim() -notmatch '^#' -or 
            $_.Trim() -match '^#(region|endregion|Requires)'
        }) -join "`n"
        # 移除連續空行
        $Code = $Code -replace "(`n\s*){3,}", "`n`n"
    } elseif ($BlockComments) {
        # 只移除區塊註解
        $Code = $Code -replace '(?s)<#.*?#>\s*', ''
    }
    
    return $Code.Trim()
}

# 私有函數
$privateFiles = if (Test-Path "$SrcDir/Private") { Get-ChildItem -Path "$SrcDir/Private/*.ps1" -File } else { @() }
foreach ($file in $privateFiles) {
    Write-Host "  + Private/$($file.Name)" -ForegroundColor Gray
    $code = (Get-Content $file.FullName -Raw).Trim()
    $code = Remove-Comments -Code $code -BlockComments:$StripBlockComments -AllComments:$StripAllComments
    $content += "#region $($file.BaseName)"
    $content += $code
    $content += "#endregion"
    $content += ""
}

# 公開函數
$publicFiles = if (Test-Path "$SrcDir/Public") { Get-ChildItem -Path "$SrcDir/Public/*.ps1" -File } else { @() }
foreach ($file in $publicFiles) {
    Write-Host "  + Public/$($file.Name)" -ForegroundColor Gray
    $code = (Get-Content $file.FullName -Raw).Trim()
    $code = Remove-Comments -Code $code -BlockComments:$StripBlockComments -AllComments:$StripAllComments
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

Write-Host ""
Write-Host "► 建置完成" -ForegroundColor Green
Write-Host "  輸出: $outputPath" -ForegroundColor Gray

# 顯示檔案大小
$fileSize = (Get-Item $outputPath).Length
Write-Host "  大小: $([math]::Round($fileSize / 1KB, 1)) KB" -ForegroundColor Gray

Write-Host ""
Write-Host "  使用方式:" -ForegroundColor White
Write-Host "    ./dist/vSFTP.ps1 -ScriptFile <script.sftp>" -ForegroundColor Gray
