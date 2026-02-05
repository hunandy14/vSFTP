function ConvertFrom-ConnectionString {
    <#
    .SYNOPSIS
        解析 SFTP 連線字串。
    .DESCRIPTION
        將 key=value 格式的連線字串轉換為設定物件。
        格式：host=<host>;user=<user>;key=<keypath>[;port=<port>]
    .PARAMETER ConnectionString
        連線字串。
    .OUTPUTS
        PSCustomObject 包含 Host, User, Port, KeyFile 屬性。
    .EXAMPLE
        ConvertFrom-ConnectionString "host=example.com;user=admin;key=/path/to/key"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$ConnectionString
    )

    $config = @{ Port = 22 }  # port 預設值

    $ConnectionString -split ';' | ForEach-Object {
        if ($_ -match '^([^=]+)=(.+)$') {
            $k = $Matches[1].Trim().ToLower()
            $v = $Matches[2].Trim()
            switch ($k) {
                'host' { $config.Host = $v }
                'user' { $config.User = $v }
                'port' { $config.Port = [int]$v }
                'key'  { $config.KeyFile = $v }
            }
        }
    }

    # 驗證必要欄位
    $missing = @()
    if (-not $config.Host) { $missing += 'host' }
    if (-not $config.User) { $missing += 'user' }
    if (-not $config.KeyFile) { $missing += 'key' }
    
    if ($missing) {
        throw "Missing required fields: $($missing -join ', '). Format: host=<host>;user=<user>;key=<keypath>[;port=<port>]"
    }

    [PSCustomObject]@{
        Host    = $config.Host
        User    = $config.User
        Port    = $config.Port
        KeyFile = $config.KeyFile
    }
}
