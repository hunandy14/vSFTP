# vSFTP

帶有 SHA256 雜湊驗證的 SFTP 工具。

## 功能

- ✅ 執行標準 SFTP 批次腳本
- ✅ 所有傳輸皆進行 SHA256 雜湊驗證
- ✅ 支援 Windows ↔ Linux 雙向傳輸
- ✅ 自動偵測遠端作業系統
- ✅ 支援萬用字元展開
- ✅ 顯示傳輸進度

## 需求

- PowerShell 7+
- [Posh-SSH](https://github.com/darkoperator/Posh-SSH) 模組
- OpenSSH `sftp.exe`（Windows 10+ / Linux 內建）

## 安裝

```powershell
# 安裝 Posh-SSH 相依套件
Install-Module -Name Posh-SSH -Scope CurrentUser

# 複製 vSFTP
git clone https://github.com/yourname/vsftp.git
cd vsftp

# 匯入模組
Import-Module ./src/vSFTP.psd1
```

## 使用方式

```powershell
# 透過環境變數設定連線資訊
$env:SFTP_HOST = "example.com"
$env:SFTP_USER = "username"
$env:SFTP_KEYFILE = "~/.ssh/id_rsa"

# 執行 SFTP 腳本並驗證雜湊
Invoke-vSFTP -ScriptFile ./upload.sftp

# 試執行（僅解析，不實際執行）
Invoke-vSFTP -ScriptFile ./upload.sftp -DryRun

# 跳過雜湊驗證
Invoke-vSFTP -ScriptFile ./upload.sftp -NoVerify

# 錯誤時繼續執行
Invoke-vSFTP -ScriptFile ./upload.sftp -ContinueOnError
```

## 環境變數

| 變數 | 必要 | 預設值 | 說明 |
|------|------|--------|------|
| `SFTP_HOST` | ✅ | | 遠端主機 |
| `SFTP_USER` | ✅ | | 使用者名稱 |
| `SFTP_KEYFILE` | ✅ | | 私鑰路徑 |
| `SFTP_PORT` | | 22 | SSH 連接埠 |

## SFTP 腳本格式

標準 SFTP 批次腳本格式：

```sftp
lcd /local/path
cd /remote/path
put file1.txt
put *.csv /remote/data/
get report.pdf
get *.log /local/logs/
```

### 支援的指令

| 指令 | 說明 |
|------|------|
| `put <本地> [遠端]` | 上傳檔案（會驗證） |
| `get <遠端> [本地]` | 下載檔案（會驗證） |
| `cd <路徑>` | 切換遠端目錄 |
| `lcd <路徑>` | 切換本地目錄 |
| 其他 | 傳遞給 sftp.exe |

### 不支援

- `reput` / `reget`（續傳）

## 結束代碼

| 代碼 | 意義 |
|------|------|
| 0 | 成功 |
| 1 | 雜湊驗證失敗 |
| 2 | 傳輸失敗 |
| 3 | 連線失敗 |

## 授權

MIT
