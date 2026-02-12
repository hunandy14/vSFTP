function ConvertFrom-ConnectionString {
    <#
    .SYNOPSIS
        解析 SFTP 連線字串。
    .DESCRIPTION
        將 key=value 格式的連線字串轉換為設定物件。
        格式：HostName=<host>;User=<user>[;IdentityFile=<keypath>][;Port=<port>]
        
        欄位名稱與 OpenSSH config 一致（大小寫不敏感）。
        
        若省略 IdentityFile，會按照 OpenSSH 順序自動搜尋 ~/.ssh/ 下的私鑰：
        id_rsa → id_ecdsa → id_ecdsa_sk → id_ed25519 → id_ed25519_sk
        
        注意：欄位值不能包含分號（;），因為分號用於分隔欄位。
    .PARAMETER ConnectionString
        連線字串。
    .OUTPUTS
        PSCustomObject 包含 Host, User, Port, KeyFile 屬性。
    .EXAMPLE
        ConvertFrom-ConnectionString "HostName=example.com;User=admin;IdentityFile=/path/to/key"
    .EXAMPLE
        # 省略 IdentityFile，自動使用 ~/.ssh/id_ed25519 等
        ConvertFrom-ConnectionString "HostName=example.com;User=admin"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$ConnectionString
    )

    $config = @{ Port = 22 }  # Port 預設值

    $ConnectionString -split ';' | ForEach-Object {
        if ($_ -match '^([^=]+)=(.+)$') {
            $k = $Matches[1].Trim().ToLower()
            $v = $Matches[2].Trim()
            switch ($k) {
                'hostname'     { $config.Host = $v }
                'user'         { $config.User = $v }
                'port'         { $config.Port = [int]$v }
                'identityfile' { $config.KeyFile = $v }
            }
        }
    }

    # 驗證必要欄位
    $missing = @()
    if (-not $config.Host) { $missing += 'HostName' }
    if (-not $config.User) { $missing += 'User' }
    
    if ($missing) {
        throw "Missing required fields: $($missing -join ', '). Format: HostName=<host>;User=<user>[;IdentityFile=<keypath>][;Port=<port>]"
    }

    # 若未指定 IdentityFile，按 OpenSSH 順序自動搜尋
    if (-not $config.KeyFile) {
        $config.KeyFile = Get-DefaultSshKey
        # KeyFile 可以是 $null（Lite 版讓 ssh 自動選擇金鑰）
    }

    [PSCustomObject]@{
        Host    = $config.Host
        User    = $config.User
        Port    = $config.Port
        KeyFile = $config.KeyFile
    }
}
