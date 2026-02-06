# vSFTP

[![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

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
git clone https://github.com/hunandy14/vSFTP.git
cd vSFTP

# 匯入模組
Import-Module ./src/vSFTP.psd1 -Force
```

## 使用方式

```powershell
# 透過環境變數設定連線資訊
$env:SFTP_CONNECTION = "host=example.com;user=username;key=~/.ssh/id_rsa"

# 執行 SFTP 腳本並驗證雜湊
Invoke-vSFTP -ScriptFile ./upload.sftp

# 或直接使用 -Connection 參數
Invoke-vSFTP -ScriptFile ./upload.sftp -Connection "host=example.com;user=admin;port=2222;key=~/.ssh/id_rsa"

# 試執行（僅解析，不實際執行）
Invoke-vSFTP -ScriptFile ./upload.sftp -DryRun

# 跳過雜湊驗證
Invoke-vSFTP -ScriptFile ./upload.sftp -NoVerify

# 錯誤時繼續執行
Invoke-vSFTP -ScriptFile ./upload.sftp -ContinueOnError
```

## 連線字串

格式：`host=<host>;user=<user>;key=<keypath>[;port=<port>]`

| 欄位 | 必要 | 預設值 | 說明 |
|------|------|--------|------|
| `host` | ✅ | | 遠端主機 |
| `user` | ✅ | | 使用者名稱 |
| `key` | ✅ | | 私鑰路徑 |
| `port` | | 22 | SSH 連接埠 |

**注意：** 欄位值不能包含分號（`;`）

### 範例

```powershell
# Linux 路徑
$env:SFTP_CONNECTION = "host=192.168.1.100;user=admin;key=/home/user/.ssh/id_rsa"

# Windows 路徑
$env:SFTP_CONNECTION = "host=server.com;user=admin;key=C:\Users\me\.ssh\id_rsa"

# 自訂連接埠
$env:SFTP_CONNECTION = "host=server.com;port=2222;user=admin;key=~/.ssh/id_rsa"
```

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

## 建置

```powershell
# 建置為單一檔案
./build.ps1

# 移除區塊註解（較小）
./build.ps1 -StripBlockComments

# 移除所有註解和空行（最小）
./build.ps1 -StripAllComments
```

輸出：`dist/vSFTP.ps1`

## 結束代碼

| 代碼 | 意義 |
|------|------|
| 0 | 成功 |
| 1 | 雜湊驗證失敗 |
| 2 | 傳輸失敗 |
| 3 | 連線失敗 |

## 授權

MIT
