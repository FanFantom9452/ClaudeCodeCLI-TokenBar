# ClaudeCodeCLI-TokenBar installer (Windows)
#   irm https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main/install.ps1 | iex
# Touches only files under the Claude config dir, and backs up settings.json first.

$ErrorActionPreference = 'Stop'
$Repo = 'https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main'

# Resolve the config dir from the environment — never a hardcoded user path.
$Cfg = if ($env:CLAUDE_CONFIG_DIR)  { $env:CLAUDE_CONFIG_DIR }
       elseif ($HOME)               { Join-Path $HOME '.claude' }
       elseif ($env:USERPROFILE)    { Join-Path $env:USERPROFILE '.claude' }
       else { throw 'Cannot locate your home directory. Set CLAUDE_CONFIG_DIR and retry.' }

New-Item -ItemType Directory -Force -Path $Cfg | Out-Null
$Script   = Join-Path $Cfg 'statusline.ps1'
$Settings = Join-Path $Cfg 'settings.json'

Write-Host "Config dir : $Cfg"
Write-Host "Downloading statusline.ps1 ..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -UseBasicParsing -Uri "$Repo/statusline.ps1" -OutFile $Script

# Back up before touching settings, to a name that never overwrites an older backup.
$obj = [pscustomobject]@{}
if (Test-Path $Settings) {
    $i = 1; while (Test-Path "$Settings.bak.$i") { $i++ }
    Copy-Item -LiteralPath $Settings -Destination "$Settings.bak.$i"
    Write-Host "Backed up  : settings.json.bak.$i"
    $existing = (Get-Content -LiteralPath $Settings -Raw).TrimStart([char]0xFEFF)
    if ($existing.Trim()) { $obj = $existing | ConvertFrom-Json }
}

$Cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$Script`""
$obj | Add-Member -NotePropertyName statusLine -Force `
       -NotePropertyValue ([pscustomobject]@{ type = 'command'; command = $Cmd })

# -Depth 100 is not optional: ConvertTo-Json defaults to depth 2 and would flatten
# nested settings (enabledPlugins, permissions, hooks) into literal strings.
# WriteAllText with UTF8Encoding($false) because -Encoding utf8 adds a BOM on PS 5.1.
$json = $obj | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($Settings, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "Wired into : settings.json"

# Smoke test with a synthetic payload, so the install proves itself.
Write-Host "`nPreview:"
$sample = @{
    cwd = (Get-Location).Path
    model = @{ id = 'claude-opus-5[1m]'; display_name = 'Opus 5' }
    workspace = @{ current_dir = (Get-Location).Path }
    cost = @{ total_cost_usd = 8.1 }
    context_window = @{ context_window_size = 1000000; used_percentage = 38 }
    rate_limits = @{
        five_hour = @{ used_percentage = 66; resets_at = (Get-Date).ToUniversalTime().AddMinutes(107).ToString('yyyy-MM-ddTHH:mm:ssZ') }
        seven_day = @{ used_percentage = 58; resets_at = (Get-Date).ToUniversalTime().AddHours(126).ToString('yyyy-MM-ddTHH:mm:ssZ') }
    }
} | ConvertTo-Json -Depth 10 -Compress
$sample | & powershell -NoProfile -ExecutionPolicy Bypass -File $Script
Write-Host "`n"
Write-Host "Done. Restart Claude Code to see it."
Write-Host "Customise: edit $Script - the toggle block is at the top."
