# ClaudeCodeCLI-TokenBar installer (Windows)
#   irm https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main/install.ps1 | iex
# Touches only files under the Claude config dir, and backs up settings.json first.

$ErrorActionPreference = 'Stop'
$Owner = 'FanFantom9452'
$Name  = 'ClaudeCodeCLI-TokenBar'

# Resolve the config dir from the environment - never a hardcoded user path.
$Cfg = if ($env:CLAUDE_CONFIG_DIR)  { $env:CLAUDE_CONFIG_DIR }
       elseif ($HOME)               { Join-Path $HOME '.claude' }
       elseif ($env:USERPROFILE)    { Join-Path $env:USERPROFILE '.claude' }
       else { throw 'Cannot locate your home directory. Set CLAUDE_CONFIG_DIR and retry.' }

# The preview at the bottom is nothing but block glyphs and arrows, and the
# console renders those in whatever code page it happens to be on — 950 on a
# Traditional Chinese Windows, 936 on a Simplified one, 932 on a Japanese one.
# Without this the install ends by showing its own output as mojibake, which
# reads like the statusline is broken before it has even run once.
#
# OutputEncoding only, never InputEncoding: that setter throws on Windows
# PowerShell when stdin is redirected, which is how `irm | iex` runs this.
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }

New-Item -ItemType Directory -Force -Path $Cfg | Out-Null

# Install from the latest release, the same ref the updater follows. Installing from
# main instead would hand you code newer than any release and then let the updater
# quietly walk you back to the older tag on its first run.
#
# No release yet means main is all there is, which is the honest fallback for a repo
# that has not cut one.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Ref = 'main'
try {
    $rel = Invoke-RestMethod -UseBasicParsing -TimeoutSec 15 `
             -Headers @{ 'User-Agent' = 'ClaudeCodeCLI-TokenBar-installer' } `
             -Uri "https://api.github.com/repos/$Owner/$Name/releases/latest"
    if ($rel.tag_name) { $Ref = $rel.tag_name }
} catch { }
$Repo = "https://raw.githubusercontent.com/$Owner/$Name/$Ref"
$Script   = Join-Path $Cfg 'statusline.ps1'
$Updater  = Join-Path $Cfg 'tokenbar-update.ps1'
$UserCfg  = Join-Path $Cfg 'tokenbar-config.ps1'
$Settings = Join-Path $Cfg 'settings.json'

Write-Host "Config dir : $Cfg"
if ($Ref -eq 'main') {
    Write-Host "Version    : main (no tagged release published yet)"
} else {
    Write-Host "Version    : $Ref"
}
Write-Host "Downloading statusline.ps1 ..."
Invoke-WebRequest -UseBasicParsing -Uri "$Repo/statusline.ps1" -OutFile $Script
Invoke-WebRequest -UseBasicParsing -Uri "$Repo/tokenbar-update.ps1" -OutFile $Updater

# Only when absent. This file is where thresholds get tuned, and the whole point
# of keeping it out of statusline.ps1 is that neither an upgrade nor a reinstall
# is allowed to overwrite it.
if (Test-Path $UserCfg) {
    Write-Host "Kept       : tokenbar-config.ps1 (your overrides, left untouched)"
} else {
    Invoke-WebRequest -UseBasicParsing -Uri "$Repo/tokenbar-config.ps1" -OutFile $UserCfg
    Write-Host "Created    : tokenbar-config.ps1 (all defaults, commented out)"
}

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

# SessionStart hook for the updater, unless switched off at install time.
#
# hooks is a shared, nested structure - other plugins keep their own entries in it -
# so it is merged rather than replaced, and any entry this installer added before is
# dropped first so re-running does not stack a second copy of the same hook.
#
# matcher 'startup' only: resume, clear and compact all fire SessionStart too, and
# there is nothing to gain from re-checking on every one of them.
if ($env:TOKENBAR_NO_AUTOUPDATE) {
    Write-Host "Skipped    : auto-update hook (TOKENBAR_NO_AUTOUPDATE is set)"
} else {
    $UpdCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$Updater`""
    $hooks = if ($obj.PSObject.Properties['hooks']) { $obj.hooks } else { [pscustomobject]@{} }
    $sessionStart = @()
    if ($hooks.PSObject.Properties['SessionStart']) { $sessionStart = @($hooks.SessionStart) }
    $sessionStart = @($sessionStart | Where-Object {
        -not (@($_.hooks) | Where-Object { $_.command -and $_.command.ToLower().Contains('tokenbar-update') })
    })
    $sessionStart += [pscustomobject]@{
        matcher = 'startup'
        hooks   = @([pscustomobject]@{ type = 'command'; command = $UpdCmd })
    }
    $hooks | Add-Member -NotePropertyName SessionStart -Force -NotePropertyValue $sessionStart
    $obj   | Add-Member -NotePropertyName hooks -Force -NotePropertyValue $hooks
    Write-Host "Auto-update: on, once a day, tagged releases only"
}

# -Depth 100 is not optional: ConvertTo-Json defaults to depth 2 and would flatten
# nested settings (enabledPlugins, permissions, hooks) into literal strings.
# WriteAllText with UTF8Encoding($false) because -Encoding utf8 adds a BOM on PS 5.1.
$json = $obj | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($Settings, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "Wired into : settings.json"

# Seed the updater's bookkeeping with what was just installed, so its first run does
# not re-download the very same release.
if ($Ref -ne 'main') {
    $stamp = [int][double]::Parse((Get-Date -UFormat %s))
    $state = [pscustomobject]@{ lastCheck = $stamp; tag = $Ref } | ConvertTo-Json
    [System.IO.File]::WriteAllText((Join-Path $Cfg '.tokenbar-state.json'), $state, [System.Text.UTF8Encoding]::new($false))
}

# Smoke test with a synthetic payload, so the install proves itself.
Write-Host "`nPreview:"
$sample = @{
    cwd = (Get-Location).Path
    model = @{ id = 'claude-opus-5[1m]'; display_name = 'Opus 5' }
    workspace = @{ current_dir = (Get-Location).Path }
    context_window = @{ context_window_size = 1000000; used_percentage = 38 }
    rate_limits = @{
        five_hour = @{ used_percentage = 66; resets_at = (Get-Date).ToUniversalTime().AddMinutes(107).ToString('yyyy-MM-ddTHH:mm:ssZ') }
        seven_day = @{ used_percentage = 58; resets_at = (Get-Date).ToUniversalTime().AddMinutes(3630).ToString('yyyy-MM-ddTHH:mm:ssZ') }
    }
} | ConvertTo-Json -Depth 10 -Compress
$sample | & powershell -NoProfile -ExecutionPolicy Bypass -File $Script
Write-Host "`n"
Write-Host "Done. Restart Claude Code to see it."
Write-Host "Customise    : edit $UserCfg"
Write-Host "               Everything is listed there, commented out. It survives updates."
Write-Host "Stop updates : create $Cfg\.tokenbar-noupdate"
Write-Host "Update log   : $Cfg\.tokenbar-update.log (only written when one fails)"
