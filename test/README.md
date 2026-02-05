# vSFTP 測試環境

## 快速開始

```bash
# 啟動測試伺服器
pwsh test/init.ps1

# 設定環境變數
export SFTP_HOST=localhost
export SFTP_PORT=2222
export SFTP_USER=testuser
export SFTP_KEYFILE=test/test_key

# 執行測試
pwsh -Command "Import-Module ./vSFTP.psd1; Invoke-vSFTP -ScriptFile test/scripts/test-upload.sftp -SkipHostKeyCheck"

# 關閉測試伺服器
pwsh test/init.ps1 -Down
```

## 測試伺服器資訊

| 設定 | 值 |
|------|-----|
| 主機 | localhost |
| 連接埠 | 2222 |
| 使用者 | testuser |
| 認證方式 | SSH 金鑰 (test/test_key) |
| 上傳目錄 | /home/testuser/upload |

## 測試檔案

- `test/local/` - 上傳測試用的本地檔案
- `test/remote/` - 掛載為遠端上傳目錄
- `test/scripts/` - SFTP 測試腳本
