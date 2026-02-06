function ConvertFrom-ConnectionString {
    <#
    .SYNOPSIS
        解析 SFTP 連線字串。
    .DESCRIPTION
        將 key=value 格式的連線字串轉換為設定物件。
        格式：host=<host>;user=<user>[;key=<keypath>][;port=<port>]
        
        若省略 key，會按照 OpenSSH 順序自動搜尋 ~/.ssh/ 下的私鑰：
        id_rsa → id_ecdsa → id_ecdsa_sk → id_ed25519 → id_ed25519_sk
        
        注意：欄位值不能包含分號（;），因為分號用於分隔欄位。
    .PARAMETER ConnectionString
        連線字串。
    .OUTPUTS
        PSCustomObject 包含 Host, User, Port, KeyFile 屬性。
    .EXAMPLE
        ConvertFrom-ConnectionString "host=example.com;user=admin;key=/path/to/key"
    .EXAMPLE
        # 省略 key，自動使用 ~/.ssh/id_ed25519 等
        ConvertFrom-ConnectionString "host=example.com;user=admin"
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
    
    if ($missing) {
        throw "Missing required fields: $($missing -join ', '). Format: host=<host>;user=<user>[;key=<keypath>][;port=<port>]"
    }

    # 若未指定 key，按 OpenSSH 順序自動搜尋
    if (-not $config.KeyFile) {
        $config.KeyFile = Get-DefaultSshKey
        if (-not $config.KeyFile) {
            throw "No SSH key specified and no default key found in ~/.ssh/ (tried: id_rsa, id_ecdsa, id_ecdsa_sk, id_ed25519, id_ed25519_sk)"
        }
    }

    [PSCustomObject]@{
        Host    = $config.Host
        User    = $config.User
        Port    = $config.Port
        KeyFile = $config.KeyFile
    }
}
