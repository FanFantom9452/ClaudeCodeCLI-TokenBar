# ClaudeCodeCLI-TokenBar updater — runs from the SessionStart hook (Windows).
#
# Three hard rules, because this runs before every session:
#   never write to stdout   a SessionStart hook's stdout is injected into the
#                           session as context, so a stray line would land in
#                           front of the model as if it were instructions
#   never throw             a broken updater must not stop Claude Code starting
#   always exit 0           same reason
# Everything is wrapped and failures go to a log file nobody has to read.
#
# Shape: the hook process only reads a local timestamp. Only when a check is
# actually due does it spawn a detached worker for the network part, so session
# start never waits on GitHub — at most it pays for one Start-Process, once a day.
#
# Only tagged releases are followed, never main. Auto-update is a channel for
# arbitrary commits to run on your machine; requiring a deliberate tag means a
# half-finished push cannot reach you on its own.
param([switch]$Worker)

$ErrorActionPreference = 'Stop'
$Owner = 'FanFantom9452'
$Repo  = 'ClaudeCodeCLI-TokenBar'
$IntervalHours = 24

$Cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR }
       elseif ($HOME)              { Join-Path $HOME '.claude' }
       elseif ($env:USERPROFILE)   { Join-Path $env:USERPROFILE '.claude' }
       else { exit 0 }

$Script = Join-Path $Cfg 'statusline.ps1'
$State  = Join-Path $Cfg '.tokenbar-state.json'
$OptOut = Join-Path $Cfg '.tokenbar-noupdate'
$LogF   = Join-Path $Cfg '.tokenbar-update.log'

function Log($msg) {
    try {
        $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
        Add-Content -LiteralPath $LogF -Value $line -Encoding utf8
        # Truncate rather than grow forever: this file exists to be read once,
        # after something went wrong.
        $all = @(Get-Content -LiteralPath $LogF)
        if ($all.Count -gt 200) { $all[-100..-1] | Set-Content -LiteralPath $LogF -Encoding utf8 }
    } catch { }
}
function ReadState {
    try {
        if (Test-Path -LiteralPath $State) {
            return (Get-Content -LiteralPath $State -Raw | ConvertFrom-Json)
        }
    } catch { }
    return [pscustomobject]@{ lastCheck = 0; tag = '' }
}
function WriteState($lastCheck, $tag) {
    try {
        $o = [pscustomobject]@{ lastCheck = $lastCheck; tag = $tag }
        [System.IO.File]::WriteAllText($State, ($o | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
    } catch { }
}
function NowSec { [int][double]::Parse((Get-Date -UFormat %s)) }

# ---------------- hook process: decide, delegate, get out of the way --------
if (-not $Worker) {
    try {
        if (Test-Path -LiteralPath $OptOut) { exit 0 }
        $st = ReadState
        if ((NowSec) - [int]$st.lastCheck -lt $IntervalHours * 3600) { exit 0 }
        # Same host that is already running this, so a machine with only Windows
        # PowerShell or only pwsh both work.
        $exe = try { [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { 'powershell.exe' }
        Start-Process -FilePath $exe `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Worker') `
            -WindowStyle Hidden | Out-Null
    } catch { }
    exit 0
}

# ---------------- worker: the part allowed to be slow -----------------------
try {
    $st = ReadState
    # Stamped before the network call, not after. A GitHub outage that hangs every
    # time must cost one attempt a day, not one attempt per session.
    WriteState (NowSec) $st.tag

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $hdr = @{ 'User-Agent' = 'ClaudeCodeCLI-TokenBar-updater' }
    $rel = Invoke-RestMethod -UseBasicParsing -TimeoutSec 15 -Headers $hdr `
             -Uri "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    $tag = $rel.tag_name
    if (-not $tag) { Log 'no tag_name in release response'; exit 0 }
    if ($tag -eq $st.tag) { exit 0 }

    $tmp = "$Script.new"
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 `
        -Uri "https://raw.githubusercontent.com/$Owner/$Repo/$tag/statusline.ps1" -OutFile $tmp
    $text = Get-Content -LiteralPath $tmp -Raw

    # Three gates before anything replaces a working statusline: a 404 page, a
    # truncated download and a syntactically broken script all fail here rather
    # than at render time, where the only symptom would be a blank status line.
    if ($text.Length -lt 2000)                { throw 'download too small to be the script' }
    if ($text -notmatch 'ClaudeCodeCLI-TokenBar') { throw 'download does not look like the script' }
    $perrs = $null
    [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$perrs) | Out-Null
    if ($perrs -and $perrs.Count) { throw "download has $($perrs.Count) parse error(s)" }

    if (Test-Path -LiteralPath $Script) { Copy-Item -LiteralPath $Script -Destination "$Script.bak" -Force }
    Move-Item -LiteralPath $tmp -Destination $Script -Force
    WriteState (NowSec) $tag
    Log "updated statusline.ps1 to $tag (previous kept as statusline.ps1.bak)"
} catch {
    Log "update failed: $($_.Exception.Message)"
    try { if (Test-Path -LiteralPath "$Script.new") { Remove-Item -LiteralPath "$Script.new" -Force } } catch { }
}
exit 0
