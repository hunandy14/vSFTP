# 測試

使用 [Pester](https://pester.dev/) 執行測試。

## 執行測試

```powershell
# 執行所有測試
Invoke-Pester ./test

# 執行特定測試檔
Invoke-Pester ./test/vSFTP.Tests.ps1
Invoke-Pester ./test/ConvertFrom-SftpScript.Tests.ps1

# 詳細輸出
Invoke-Pester ./test -Output Detailed
```

## 整合測試

整合測試需要先啟動測試伺服器：

```powershell
# 啟動測試伺服器
./dev.ps1

# 執行整合測試
Invoke-Pester ./test -Tag "Integration"

# 關閉測試伺服器
./dev.ps1 -Down
```

## 測試檔案

| 檔案 | 說明 |
|------|------|
| `vSFTP.Tests.ps1` | 模組功能測試 |
| `ConvertFrom-SftpScript.Tests.ps1` | SFTP 腳本解析測試 |
| `scripts/*.sftp` | 手動測試用 SFTP 腳本 |
