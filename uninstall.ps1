# ClaudeCodeCLI-TokenBar uninstaller (Windows)
#   irm https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main/uninstall.ps1 | iex
# Removes only what the installer added. Backs up settings.json first, and leaves
# every settings.json.bak.* in place so an earlier state can still be restored.
#
# Pure ASCII with no BOM on purpose: via `irm | iex` a BOM survives into the string
# and breaks the first line.

$ErrorActionPreference = 'Stop'

# Resolve the config dir from the environment - never a hardcoded user path.
$Cfg = if ($env:CLAUDE_CONFIG_DIR)  { $env:CLAUDE_CONFIG_DIR }
       elseif ($HOME)               { Join-Path $HOME '.claude' }
       elseif ($env:USERPROFILE)    { Join-Path $env:USERPROFILE '.claude' }
       else { throw 'Cannot locate your home directory. Set CLAUDE_CONFIG_DIR and retry.' }

$Script   = Join-Path $Cfg 'statusline.ps1'
$Settings = Join-Path $Cfg 'settings.json'
Write-Host "Config dir : $Cfg"

if (Test-Path $Settings) {
    $i = 1; while (Test-Path "$Settings.bak.$i") { $i++ }
    Copy-Item -LiteralPath $Settings -Destination "$Settings.bak.$i"
    Write-Host "Backed up  : settings.json.bak.$i"

    $raw = (Get-Content -LiteralPath $Settings -Raw).TrimStart([char]0xFEFF)
    $obj = if ($raw.Trim()) { $raw | ConvertFrom-Json } else { [pscustomobject]@{} }

    # Only drop statusLine if it actually points at our script. Someone may have
    # switched to a different statusline since installing, and blowing that away
    # would be destroying config this tool never owned.
    $cmd = $obj.statusLine.command
    if ($cmd -and $cmd.ToLower().Contains($Script.ToLower())) {
        $obj.PSObject.Properties.Remove('statusLine')
        # -Depth 100: ConvertTo-Json defaults to depth 2 and would flatten nested
        # settings (enabledPlugins, permissions, hooks) into literal strings.
        # WriteAllText with UTF8Encoding($false) because -Encoding utf8 adds a BOM on PS 5.1.
        $json = $obj | ConvertTo-Json -Depth 100
        [System.IO.File]::WriteAllText($Settings, $json, [System.Text.UTF8Encoding]::new($false))
        Write-Host "Removed    : statusLine from settings.json"
    }
    elseif ($cmd) {
        Write-Host "Kept       : statusLine points somewhere else, left untouched"
        Write-Host "             $cmd"
    }
    else {
        Write-Host "Nothing    : no statusLine in settings.json"
    }
}
else {
    Write-Host "Nothing    : no settings.json found"
}

if (Test-Path $Script) {
    Remove-Item -LiteralPath $Script -Force
    Write-Host "Deleted    : statusline.ps1"
}

$dump = Join-Path $env:TEMP 'claude-statusline-payload.json'
if (Test-Path $dump) { Remove-Item -LiteralPath $dump -Force; Write-Host "Deleted    : debug payload dump" }

Write-Host ""
Write-Host "Done. Restart Claude Code."
Write-Host "Backups kept at $Settings.bak.* if you need an earlier state."
