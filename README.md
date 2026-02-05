# vSFTP

SFTP with SHA256 hash verification.

## Features

- ✅ Execute standard SFTP batch scripts
- ✅ SHA256 hash verification for all transfers
- ✅ Support for Windows ↔ Linux bidirectional transfers
- ✅ Auto-detect remote OS
- ✅ Wildcard expansion support
- ✅ Progress display

## Requirements

- PowerShell 7+
- [Posh-SSH](https://github.com/darkoperator/Posh-SSH) module
- OpenSSH `sftp.exe` (included in Windows 10+ / Linux)

## Installation

```powershell
# Install Posh-SSH dependency
Install-Module -Name Posh-SSH -Scope CurrentUser

# Clone vSFTP
git clone https://github.com/yourname/vsftp.git
cd vsftp

# Import module
Import-Module ./vSFTP.psd1
```

## Usage

```powershell
# Set connection via environment variables
$env:SFTP_HOST = "example.com"
$env:SFTP_USER = "username"
$env:SFTP_KEYFILE = "~/.ssh/id_rsa"

# Execute SFTP script with hash verification
Invoke-vSFTP -ScriptFile ./upload.sftp

# Dry run (parse only, no execution)
Invoke-vSFTP -ScriptFile ./upload.sftp -DryRun

# Skip hash verification
Invoke-vSFTP -ScriptFile ./upload.sftp -NoVerify

# Continue on error
Invoke-vSFTP -ScriptFile ./upload.sftp -ContinueOnError
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SFTP_HOST` | ✅ | | Remote host |
| `SFTP_USER` | ✅ | | Username |
| `SFTP_KEYFILE` | ✅ | | Private key path |
| `SFTP_PORT` | | 22 | SSH port |

## SFTP Script Format

Standard SFTP batch script format:

```sftp
lcd /local/path
cd /remote/path
put file1.txt
put *.csv /remote/data/
get report.pdf
get *.log /local/logs/
```

### Supported Commands

| Command | Description |
|---------|-------------|
| `put <local> [remote]` | Upload file (verified) |
| `get <remote> [local]` | Download file (verified) |
| `cd <path>` | Change remote directory |
| `lcd <path>` | Change local directory |
| Others | Passed to sftp.exe |

### Not Supported

- `reput` / `reget` (resume transfer)

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Hash verification failed |
| 2 | Transfer failed |
| 3 | Connection failed |

## License

MIT
