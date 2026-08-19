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
$Updater  = Join-Path $Cfg 'tokenbar-update.ps1'
$UserCfg  = Join-Path $Cfg 'tokenbar-config.ps1'
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

    # Drop only our own SessionStart entry. Other plugins keep theirs in the same
    # array, and PreToolUse and friends live in the same object.
    if ($obj.PSObject.Properties['hooks'] -and $obj.hooks.PSObject.Properties['SessionStart']) {
        $before = @($obj.hooks.SessionStart)
        $after  = @($before | Where-Object {
            -not (@($_.hooks) | Where-Object { $_.command -and $_.command.ToLower().Contains('tokenbar-update') })
        })
        if ($after.Count -ne $before.Count) {
            if ($after.Count) {
                $obj.hooks | Add-Member -NotePropertyName SessionStart -Force -NotePropertyValue $after
            } else {
                # Leaving an empty array behind is litter, and so is an empty hooks
                # object once it was the only thing in there.
                $obj.hooks.PSObject.Properties.Remove('SessionStart')
                if (-not @($obj.hooks.PSObject.Properties).Count) { $obj.PSObject.Properties.Remove('hooks') }
            }
            $json = $obj | ConvertTo-Json -Depth 100
            [System.IO.File]::WriteAllText($Settings, $json, [System.Text.UTF8Encoding]::new($false))
            Write-Host "Removed    : auto-update hook from settings.json"
        }
    }
}
else {
    Write-Host "Nothing    : no settings.json found"
}

foreach ($f in @($Script, $Updater, "$Script.bak", "$Updater.bak",
                 (Join-Path $Cfg '.tokenbar-state.json'),
                 (Join-Path $Cfg '.tokenbar-update.log'),
                 (Join-Path $Cfg '.tokenbar-noupdate'))) {
    if (Test-Path -LiteralPath $f) {
        Remove-Item -LiteralPath $f -Force
        Write-Host "Deleted    : $(Split-Path $f -Leaf)"
    }
}

# The overrides file is the one thing here that can hold work you did. It is only
# deleted when every line in it is still a comment, which means nothing was ever
# set and there is nothing to lose.
if (Test-Path $UserCfg) {
    $live = @(Get-Content -LiteralPath $UserCfg | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
    if ($live.Count) {
        Write-Host "Kept       : tokenbar-config.ps1 has $($live.Count) active line(s), left in place"
        Write-Host "             $UserCfg"
    } else {
        Remove-Item -LiteralPath $UserCfg -Force
        Write-Host "Deleted    : tokenbar-config.ps1 (nothing was overridden in it)"
    }
}

$dump = Join-Path $env:TEMP 'claude-statusline-payload.json'
if (Test-Path $dump) { Remove-Item -LiteralPath $dump -Force; Write-Host "Deleted    : debug payload dump" }

Write-Host ""
Write-Host "Done. Restart Claude Code."
Write-Host "Backups kept at $Settings.bak.* if you need an earlier state."
