# vSFTP Design Document

## Overview

vSFTP is a PowerShell tool that wraps SFTP transfers with SHA256 hash verification.

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│                        Invoke-vSFTP                        │
├────────────────────────────────────────────────────────────┤
│ 1. Parse Script                                            │
│    • Track cd/lcd for path resolution                      │
│    • Expand wildcards locally                              │
│    • Build expected file list                              │
├────────────────────────────────────────────────────────────┤
│ 2. Connect & Detect Remote OS                              │
│    • Posh-SSH: New-SSHSession                              │
│    • Run: uname -s (Linux) or assume Windows               │
├────────────────────────────────────────────────────────────┤
│ 3. Pre-transfer: Get remote hash for GET operations        │
│    • Linux: sha256sum <file>                               │
│    • Windows: powershell -c "(Get-FileHash).Hash"          │
├────────────────────────────────────────────────────────────┤
│ 4. Execute Transfer                                        │
│    • sftp.exe -b <script>                                  │
│    • Show progress                                         │
├────────────────────────────────────────────────────────────┤
│ 5. Post-transfer: Hash Verification                        │
│    • PUT: local hash vs remote hash                        │
│    • GET: remote hash (from step 3) vs local hash          │
├────────────────────────────────────────────────────────────┤
│ 6. Output Results                                          │
│    • Per-file status                                       │
│    • Summary                                               │
└────────────────────────────────────────────────────────────┘
```

## Components

### 1. Script Parser (`Parse-SftpScript`)

Parses SFTP batch script and extracts file operations.

**Input:** Script file path, base local/remote directories
**Output:** Array of transfer operations

```powershell
[PSCustomObject]@{
    Action     = "put" | "get"
    LocalPath  = "C:\data\file.txt"      # Absolute path
    RemotePath = "/upload/file.txt"      # Absolute path
    Line       = 5                        # Source line number
}
```

**Tracked Commands:**
- `put <local> [remote]` - Add to transfer list
- `get <remote> [local]` - Add to transfer list
- `cd <path>` - Update remote working directory
- `lcd <path>` - Update local working directory

**Wildcard Expansion:**
- Uses `Get-ChildItem` for local wildcards
- Each expanded file becomes separate entry

### 2. Remote OS Detector (`Get-RemoteOS`)

Detects remote operating system via SSH.

```powershell
$result = Invoke-SSHCommand -SessionId $id -Command "uname -s"
if ($result.ExitStatus -eq 0) {
    # Linux/macOS
} else {
    # Windows
}
```

### 3. Hash Calculator

**Local (PowerShell):**
```powershell
(Get-FileHash -Path $path -Algorithm SHA256).Hash
```

**Remote Linux:**
```bash
sha256sum /path/to/file | cut -d' ' -f1
```

**Remote Windows:**
```powershell
powershell -NoProfile -Command "(Get-FileHash -Path 'C:\path\to\file' -Algorithm SHA256).Hash"
```

### 4. Transfer Executor

Uses native `sftp.exe` for actual transfers:

```powershell
$process = Start-Process -FilePath "sftp" -ArgumentList @(
    "-b", $scriptFile,
    "-P", $port,
    "-i", $keyFile,
    "$user@$host"
) -Wait -PassThru -NoNewWindow

if ($process.ExitCode -ne 0) {
    # Transfer failed
}
```

## Data Flow

### PUT Operation

```
1. Parse: put local.txt /remote/path/
   └─> {Action:put, Local:C:\data\local.txt, Remote:/remote/path/local.txt}

2. Calculate local hash
   └─> Hash: ABC123...

3. sftp.exe executes transfer

4. Calculate remote hash via SSH
   └─> Hash: ABC123...

5. Compare hashes
   └─> Match: ✓
```

### GET Operation

```
1. Parse: get /remote/file.txt
   └─> {Action:get, Local:C:\cwd\file.txt, Remote:/remote/file.txt}

2. Get remote hash BEFORE transfer
   └─> ExpectedHash: ABC123...

3. sftp.exe executes transfer

4. Calculate local hash
   └─> ActualHash: ABC123...

5. Compare hashes
   └─> Match: ✓
```

## Error Handling

| Error Type | Exit Code | Behavior |
|------------|-----------|----------|
| Missing env vars | 3 | Abort immediately |
| SSH connection failed | 3 | Abort immediately |
| sftp.exe failed | 2 | Abort (or continue with -ContinueOnError) |
| Hash mismatch | 1 | Abort (or continue with -ContinueOnError) |
| Remote hash command failed | 1 | Abort (or continue with -ContinueOnError) |

## Timeouts

| Operation | Timeout |
|-----------|---------|
| SSH Connection | 30 seconds |
| SSH Command | 300 seconds |

## Limitations

1. No support for `reput`/`reget` (resume transfers)
2. No tracking of `rm` commands (hash verification may fail if script deletes files)
3. Wildcard expansion done locally (may differ from server-side expansion in edge cases)
4. Requires both `sftp.exe` and Posh-SSH (dual connection)
