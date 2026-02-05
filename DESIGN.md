# vSFTP 設計文件

## 概述

vSFTP 是一個 PowerShell 工具，在 SFTP 傳輸後進行 SHA256 雜湊驗證。

## 架構

```
┌────────────────────────────────────────────────────────────┐
│                        Invoke-vSFTP                        │
├────────────────────────────────────────────────────────────┤
│ 1. 解析腳本                                                │
│    • 追蹤 cd/lcd 以解析路徑                                │
│    • 展開本地萬用字元                                      │
│    • 建立預期檔案清單                                      │
├────────────────────────────────────────────────────────────┤
│ 2. 連線並偵測遠端作業系統                                  │
│    • Posh-SSH: New-SSHSession                              │
│    • 執行: uname -s (Linux) 或假設為 Windows               │
├────────────────────────────────────────────────────────────┤
│ 3. 傳輸前：取得 GET 操作的遠端雜湊                         │
│    • Linux: sha256sum <file>                               │
│    • Windows: powershell -c "(Get-FileHash).Hash"          │
├────────────────────────────────────────────────────────────┤
│ 4. 執行傳輸                                                │
│    • sftp.exe -b <script>                                  │
│    • 顯示進度                                              │
├────────────────────────────────────────────────────────────┤
│ 5. 傳輸後：雜湊驗證                                        │
│    • PUT: 本地雜湊 vs 遠端雜湊                             │
│    • GET: 遠端雜湊 (步驟 3) vs 本地雜湊                    │
├────────────────────────────────────────────────────────────┤
│ 6. 輸出結果                                                │
│    • 每個檔案的狀態                                        │
│    • 摘要                                                  │
└────────────────────────────────────────────────────────────┘
```

## 元件

### 1. 腳本解析器 (`Parse-SftpScript`)

解析 SFTP 批次腳本並提取檔案操作。

**輸入：** 腳本檔案路徑、基礎本地/遠端目錄
**輸出：** 傳輸操作陣列

```powershell
[PSCustomObject]@{
    Action     = "put" | "get"
    LocalPath  = "C:\data\file.txt"      # 絕對路徑
    RemotePath = "/upload/file.txt"      # 絕對路徑
    Line       = 5                        # 來源行號
}
```

**追蹤的指令：**
- `put <local> [remote]` - 加入傳輸清單
- `get <remote> [local]` - 加入傳輸清單
- `cd <path>` - 更新遠端工作目錄
- `lcd <path>` - 更新本地工作目錄

**萬用字元展開：**
- 使用 `Get-ChildItem` 展開本地萬用字元
- 每個展開的檔案成為獨立項目

### 2. 遠端作業系統偵測 (`Get-RemoteOS`)

透過 SSH 偵測遠端作業系統。

```powershell
$result = Invoke-SSHCommand -SessionId $id -Command "uname -s"
if ($result.ExitStatus -eq 0) {
    # Linux/macOS
} else {
    # Windows
}
```

### 3. 雜湊計算

**本地 (PowerShell)：**
```powershell
(Get-FileHash -Path $path -Algorithm SHA256).Hash
```

**遠端 Linux：**
```bash
sha256sum /path/to/file | cut -d' ' -f1
```

**遠端 Windows：**
```powershell
powershell -NoProfile -Command "(Get-FileHash -Path 'C:\path\to\file' -Algorithm SHA256).Hash"
```

### 4. 傳輸執行器

使用原生 `sftp.exe` 執行實際傳輸：

```powershell
$process = Start-Process -FilePath "sftp" -ArgumentList @(
    "-b", $scriptFile,
    "-P", $port,
    "-i", $keyFile,
    "$user@$host"
) -Wait -PassThru -NoNewWindow

if ($process.ExitCode -ne 0) {
    # 傳輸失敗
}
```

## 資料流程

### PUT 操作

```
1. 解析: put local.txt /remote/path/
   └─> {Action:put, Local:C:\data\local.txt, Remote:/remote/path/local.txt}

2. 計算本地雜湊
   └─> Hash: ABC123...

3. sftp.exe 執行傳輸

4. 透過 SSH 計算遠端雜湊
   └─> Hash: ABC123...

5. 比對雜湊
   └─> 相符: ✓
```

### GET 操作

```
1. 解析: get /remote/file.txt
   └─> {Action:get, Local:C:\cwd\file.txt, Remote:/remote/file.txt}

2. 傳輸前取得遠端雜湊
   └─> ExpectedHash: ABC123...

3. sftp.exe 執行傳輸

4. 計算本地雜湊
   └─> ActualHash: ABC123...

5. 比對雜湊
   └─> 相符: ✓
```

## 錯誤處理

| 錯誤類型 | 結束碼 | 行為 |
|----------|--------|------|
| 缺少環境變數 | 3 | 立即中止 |
| SSH 連線失敗 | 3 | 立即中止 |
| sftp.exe 失敗 | 2 | 中止（或使用 -ContinueOnError 繼續）|
| 雜湊不符 | 1 | 中止（或使用 -ContinueOnError 繼續）|
| 遠端雜湊指令失敗 | 1 | 中止（或使用 -ContinueOnError 繼續）|

## 逾時設定

| 操作 | 逾時 |
|------|------|
| SSH 連線 | 30 秒 |
| SSH 指令 | 300 秒 |

## 限制

1. 不支援 `reput`/`reget`（續傳）
2. 不追蹤 `rm` 指令（若腳本刪除檔案，雜湊驗證可能失敗）
3. 萬用字元在本地展開（邊緣情況可能與伺服器端展開不同）
4. 需要同時使用 `sftp.exe` 和 Posh-SSH（雙重連線）
