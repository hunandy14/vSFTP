# vSFTP Test Environment

## Quick Start

```bash
# Start test server
docker compose up -d

# Wait for container to be ready
sleep 5

# Set environment
export SFTP_HOST=localhost
export SFTP_PORT=2222
export SFTP_USER=testuser
export SFTP_PASS=testpass

# Create test file
echo "Hello vSFTP" > test/local/test.txt

# Run test
pwsh -Command "Import-Module ./vSFTP.psd1; Invoke-vSFTP -ScriptFile test/scripts/test-upload.sftp -Verbose"

# Stop test server
docker compose down
```

## Test Server Details

| Setting | Value |
|---------|-------|
| Host | localhost |
| Port | 2222 |
| User | testuser |
| Password | testpass |
| Upload Dir | /home/testuser/upload |

## Test Files

- `test/local/` - Local files for upload tests
- `test/remote/` - Mounted as remote upload directory
- `test/scripts/` - SFTP test scripts
