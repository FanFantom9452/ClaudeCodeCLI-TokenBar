# ClaudeCodeCLI-TokenBar — Claude Code statusline (Windows / PowerShell)
#
#   line 1  [CAVEMAN:FULL] [PONYTAIL:FULL] | Opus 5 | my-project | main ↑2 +42/-7 ?1
#   line 2  ctx ███▊░░░░░░  38%  │  5h ██████▌░░░  66%  ↻ 1h 46m  │  7d █████▊░░░░  58%  ↻ 2d 12h 30m   -6%
#
# The three bars are coloured by three different rules on purpose:
#   ctx  absolute %, thresholds tiered by the model's context window size, plus an
#        escalating glyph ladder on windows large enough for it to mean something
#   5h   absolute %, five fixed bands
#   7d   pace only -- deviation from the even 1/7-per-day line. How full the bar is
#        does not colour it; only whether the burn rate reaches the reset does.
#
# Every threshold, colour and glyph below can be overridden per machine without
# touching this file: see the tokenbar-config.ps1 block after the ramps.
#
# Payload schema verified against Claude Code 2.1.223.

# ---- toggles: $true shows, $false hides ----------------------------------
$show = @{
    caveman   = $true    # [CAVEMAN:FULL] badge, if the caveman plugin is installed
    ponytail  = $true    # [PONYTAIL]     badge, if the ponytail plugin is installed
    toggles   = $true    # any other mode flag found in modes/<session_id>/
    model     = $true    # Opus 5
    dir       = $true    # current directory name
    branch    = $true    # main   (gets a * only when gitLines is off)
    gitAhead  = $true    # ↑2 ↓1  commits not pushed / not pulled
    gitLines  = $true    # +42/-7 uncommitted line delta vs HEAD
    gitUntrk  = $true    # ?1     untracked files, which no diff would catch
    context   = $true    # ctx bar
    quota5h   = $true    # 5h bar
    quota7d   = $true    # 7d bar
    delta     = $true    # +2% / -10% next to the 7d bar: quota points ahead of
                         # (or behind) the even 1/7-per-day line
}
$barWidth = 10           # cells per bar; shared so the three compare by eye
$fieldGap = '  '         # space between a bar's % and the ↻reset / ±delta that
                         # follow it. One space reads as glued to the number,
                         # since the % itself already sits two spaces off the bar.
$segGap   = '  '         # space each side of $segSep between bars. Keep the
                         # separator plus both its gaps wider than $fieldGap, or
                         # fields inside a segment look further apart than the
                         # segments themselves and the grouping reads backwards.
$segSep   = [char]0x2502 # what sits between two bars. A rule with vertical extent
                         # separates at a narrower gap than a mid-dot does, which
                         # is what lets $segGap sit at 2 without the bars merging.

# 256-colour palette. sev ranks severity so two rules can be compared and the
# worse one wins; without it there'd be no way to order "yellow" against "red".
$GREEN = 108; $AMBER = 179; $YELLOW = 226; $RED = 196; $PURPLE = 201
$CTRACK = 240; $DIM = 240

# Alert glyphs. ConvertFromUtf32, never a [char] cast: both emoji sit above the BMP
# so they are surrogate pairs, and [char] holds 16 bits and throws on them. They are
# also double-width, which is why the ladder stops at three -- the statusline has to
# stay readable in a narrow terminal.
$WARN  = [char]0x26A0
$SKULL = [char]::ConvertFromUtf32(0x1F480)
$BOOM  = [char]::ConvertFromUtf32(0x1F4A5)

# Plugin badges. Each plugin keeps its own hue; brightness within that hue tracks
# the intensity tier, so the level reads at a glance instead of only from the text
# suffix. A badge appears at all only when the plugin is installed and has written
# its flag file, so anyone without these plugins never sees them.
#
# `default` is for any toggle this script has never heard of. Adding one is meant to
# cost nothing here: drop a flag file in modes/<session_id>/ and it renders. Give it
# an entry below only when you want it off the neutral ramp and onto its own hue.
$badgeColors = @{
    caveman  = @{ off = 240; lite = 137; full = 172; ultra = 208 }   # gray -> tan -> orange -> bright orange
    ponytail = @{ off = 240; lite =  65; full = 108; ultra =  84 }   # gray -> dim sage -> sage -> bright mint
    default  = @{ off = 240; lite = 245; full = 250; ultra = 255 }   # gray -> ... -> white
}
# Modes each known plugin can legitimately be in. An unlisted name is validated on
# shape alone, which is all it takes to keep escapes and control bytes off the line.
$badgeModes = @{
    caveman  = @('off','lite','full','ultra','wenyan-lite','wenyan','wenyan-full','wenyan-ultra','commit','review','compress')
    ponytail = @('off','lite','full','ultra','review')
}

# ---- ctx: thresholds tiered by window size ------------------------------
# A flat 20%-is-yellow rule punishes small windows: 20% of 200k is 40k, which is
# nothing. First tier whose maxWindow covers the model's window wins.
#
# `marks` is an escalating glyph ladder, and only the largest tier carries one. On a
# 1M window 50% is half a million tokens and the rest of the session gets expensive
# fast, so escalation earns its noise; on a 200k window those same percentages are
# small absolute numbers and a skull there would be crying wolf. A tier with no
# `marks` keeps the single warning glyph at its purple threshold.
$ctxMarks = @(
    @{ at = 50; glyph = "$WARN" }
    @{ at = 60; glyph = "$SKULL" }
    @{ at = 70; glyph = "$BOOM" }
    @{ at = 80; glyph = "$BOOM$BOOM" }
    @{ at = 90; glyph = "$BOOM$BOOM$BOOM" }
)
$ctxTiers = @(
    @{ maxWindow =  200000; amber = 50; red = 70; purple = 85 }
    @{ maxWindow =  500000; amber = 40; red = 60; purple = 80 }
    @{ maxWindow =  800000; amber = 30; red = 55; purple = 80 }
    @{ maxWindow = [double]::MaxValue; amber = 20; red = 50; purple = 80; marks = $ctxMarks }
)
# Gradient inserted between the amber and red thresholds, evenly spaced. On a 1M
# window (amber 20, red 50) this lands on exactly 20/25/30/35/40/45.
$ctxGradient = @(226, 220, 214, 208, 202, 203)

# ---- 5h: five fixed bands ------------------------------------------------
# No deviation figure here: the window is only 5 hours, work arrives in bursts,
# and a rate over that span jitters too much to read.
$ramp5h = @(
    @{ at =  0; color = $GREEN;  sev = 0 }
    @{ at = 40; color = $AMBER;  sev = 1 }
    @{ at = 60; color = $YELLOW; sev = 2 }
    @{ at = 80; color = $RED;    sev = 3; bold = $true }
    @{ at = 95; color = $PURPLE; sev = 4; bold = $true; mark = "$WARN" }
)

# ---- 7d: cumulative deviation from the sustainable line -------------------
# A week's quota spread evenly is 100/7 = 14.3 points per day, so
#   deviation = used% - elapsed_fraction * 100
# is just how many quota points you are ahead of (or behind) that line. Negative
# means you banked some. It nets out across the week: a heavy Monday followed by
# frugal days walks back toward zero, which a single-day figure would never show.
#
# Subtraction, not a ratio, so it stays well defined at the very start of a window
# and needs no grace period: 3% used in the first hour is simply +3, where a ratio
# would divide by almost zero and read as a 5x overspend.
#
# There is deliberately no absolute-percentage rule on this bar. 90% used with
# twelve hours left and a deviation of -3 is a week that went exactly to plan, and
# painting it red for the size of the number tells you nothing the number itself
# was not already telling you. What the colour adds is the one thing the digits
# cannot: whether this rate still reaches the reset.
$dailyShare  = 100 / 7           # 14.3 points/day, the even line
$dev7dPurple = 14                # a day's share, rounded to where the digits flip
$devGradient = @(40, 76, 112, 148, 184, 220, 214, 208, 202)
# Fractional sev across the gradient so the steps stay ordered against each other,
# and against any second rule ever compared with Worse.
$devRamp = @(@{ at = [double]::MinValue; color = $GREEN; sev = 0 })
for ($i = 0; $i -lt $devGradient.Count; $i++) {
    $devRamp += @{ at    = $i * ($dev7dPurple / $devGradient.Count)
                   color = $devGradient[$i]
                   sev   = 1 + ($i + 1) / ($devGradient.Count + 1) }
}
$devRamp += @{ at = $dev7dPurple; color = $PURPLE; sev = 4; bold = $true; mark = "$WARN" }

# No resets_at means no elapsed fraction, so there is no pace to judge. Neutral grey
# rather than green, because "no reading" and "on budget" must not look alike.
$dev7dUnknown = @{ color = 245; sev = 0 }

# The single exception to "pace only". At 100% the quota is gone and the deviation
# has stopped meaning anything -- spend exactly on the line all week and you arrive
# at 100% with a deviation of 0, which the ramp above would paint green while you
# are locked out. Set to $null to drop the exception and let pace be the only input.
$hardStop7d  = 100
$exhausted7d = @{ color = $PURPLE; sev = 4; bold = $true; mark = "$WARN" }

$weekSeconds = 7 * 24 * 3600     # assumed window length; resets_at is its end
# -------------------------------------------------------------------------

# Per-machine overrides. Everything above is a default; this file, if it exists,
# runs last and wins. It is never touched by the updater, so a threshold tuned here
# survives every upgrade -- which is the whole reason the two are separate files.
#
# Resolved without the $ClaudeDir helper below, which is not defined yet, and
# guarded because a broken config must not take the statusline down with it.
$tbConfigDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$tbConfig = Join-Path $tbConfigDir 'tokenbar-config.ps1'
if (Test-Path -LiteralPath $tbConfig) { try { . $tbConfig } catch { } }

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# Read stdin as bytes and decode UTF-8 here, rather than [Console]::In.ReadToEnd().
# That reader decodes with the console input code page — 950 on a Traditional
# Chinese Windows, 936 on a Simplified one — so a project path with CJK in it came
# back as mojibake. Worse, in those double-byte pages 0x5C is a valid trail byte,
# so a mangled pair can swallow a path separator and take the whole JSON parse with
# it. Decoding the bytes ourselves is code-page independent.
#
# TrimStart for the BOM: [Console]::In stripped one, a manual decode does not, and
# a leading U+FEFF makes ConvertFrom-Json reject the document.
#
# Only when stdin is a pipe. Reading an interactive terminal blocks forever, so
# running this by hand to see what it does would hang instead of printing the
# "no payload" line that says what went wrong.
$raw = ''
if ([Console]::IsInputRedirected) {
    $stdinBuf = New-Object System.IO.MemoryStream
    [Console]::OpenStandardInput().CopyTo($stdinBuf)
    $raw = [System.Text.UTF8Encoding]::new($false).GetString($stdinBuf.ToArray()).TrimStart([char]0xFEFF)
}
if ($env:CLAUDE_STATUSLINE_DEBUG -eq '1') {
    $raw | Set-Content -LiteralPath (Join-Path $env:TEMP 'claude-statusline-payload.json') -Encoding utf8
}
$j = $raw | ConvertFrom-Json

$Esc = [char]27
function C($code, $text)    { "$Esc[38;5;${code}m$text$Esc[0m" }
function Bold($code, $text) { "$Esc[1;38;5;${code}m$text$Esc[0m" }
function Paint($step, $text) { if ($step.bold) { Bold $step.color $text } else { C $step.color $text } }

# Highest matching `at` wins, so ramps must stay sorted ascending.
function PickStep($ramp, $v) {
    $step = $ramp[0]
    foreach ($s in $ramp) { if ($v -ge $s.at) { $step = $s } }
    return $step
}
# Highest matching `at` wins here too, so a ladder must stay sorted ascending.
# Returns '' when nothing has been passed yet, which is falsy and draws no glyph.
function MarkFor($ladder, $v) {
    $glyph = ''
    foreach ($m in $ladder) { if ($v -ge $m.at) { $glyph = $m.glyph } }
    return $glyph
}

function CtxTier($windowSize) {
    foreach ($tier in $ctxTiers) { if ($windowSize -le $tier.maxWindow) { return $tier } }
    return $ctxTiers[-1]
}

# Build the ctx ramp for one tier: green, then the gradient spread evenly across
# [amber, red), then red, then purple.
function CtxRamp($t) {
    $ramp = @(@{ at = 0; color = $GREEN; sev = 0 })
    $span = ($t.red - $t.amber) / $ctxGradient.Count
    for ($i = 0; $i -lt $ctxGradient.Count; $i++) {
        $ramp += @{ at = $t.amber + $i * $span; color = $ctxGradient[$i]; sev = $(if ($i -eq 0) { 1 } else { 2 }) }
    }
    $ramp += @{ at = $t.red;    color = $RED;    sev = 3; bold = $true }
    $ramp += @{ at = $t.purple; color = $PURPLE; sev = 4; bold = $true; mark = "$WARN" }
    return $ramp
}

# Eighth-block bar: 8 sub-steps per cell, so 10 cells resolve ~80 levels.
# Names are deliberately not $FULL/$TRACK — PowerShell variables are case-insensitive,
# so those would collide with the $full/$track locals and render digits, not blocks.
$eighths = @([char]0x258F, [char]0x258E, [char]0x258D, [char]0x258C,
             [char]0x258B, [char]0x258A, [char]0x2589)   # 1/8 .. 7/8
$chBlock = [char]0x2588
$chTrack = [char]0x2591

function Bar($pct, $step, $mark) {
    # $mark left off falls back to whatever the step carries; pass one to override,
    # which is how the ctx glyph ladder replaces the step's single warning.
    if ($null -eq $mark) { $mark = $step.mark }
    $pct = [math]::Max(0, [math]::Min(100, [double]$pct))
    $cells   = $pct / 100 * $barWidth
    $nFull   = [int][math]::Floor($cells)
    $nRem    = [int][math]::Floor(($cells - $nFull) * 8)
    $fillStr = [string]$chBlock * $nFull
    if ($nRem -gt 0) { $fillStr += $eighths[$nRem - 1] }
    $trackStr = [string]$chTrack * ($barWidth - $nFull - $(if ($nRem -gt 0) { 1 } else { 0 }))
    # Percent padded to 3 columns so the line doesn't shift as digit count changes.
    $bar = (Paint $step $fillStr) + (C $CTRACK $trackStr) + ' ' + (Paint $step ('{0,3}%' -f [math]::Round($pct)))
    if ($mark) { $bar += Paint $step " $mark" }
    return $bar
}

# The bar for a number that does not exist yet. rate_limits only shows up once
# there has been an API response, and used_percentage is null until the first
# message, so for the opening seconds of a session there is genuinely nothing to
# plot.
#
# Drawing nothing then reads as broken, and drawing Bar 0 is worse: [double]$null
# is 0 in PowerShell, so "no data" would render as a green, entirely believable
# 0%. An empty track and a literal --% hold the column width and cannot be
# mistaken for a measurement.
function BarPending() {
    return (C $CTRACK ([string]$chTrack * $barWidth)) + ' ' + (C $CTRACK ('{0,3}%' -f '--'))
}

# TimeSpan until a reset stamp, or $null when there is nothing usable.
#
# Every plausible shape is handled because the type is not guaranteed: PowerShell's
# ConvertFrom-Json silently turns ISO-8601 strings into [datetime] objects, so a
# plain `-is [string]` test misses them and the value falls through to the epoch
# branch, where casting a DateTime to [double] throws and the whole thing collapses
# to null. That is what rendered as a bogus "now".
function ResetSpan($stamp) {
    if ($null -eq $stamp -or $stamp -eq '') { return $null }
    $t = $null
    try {
        if ($stamp -is [datetime]) {
            $t = $stamp.ToUniversalTime()
        }
        elseif ($stamp -is [string]) {
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse($stamp, [ref]$parsed)) { $t = $parsed.ToUniversalTime() }
        }
        else {
            $n = [double]$stamp
            # Past ~year 5138 in seconds it is really milliseconds.
            if ([math]::Abs($n) -gt 100000000000) { $n = $n / 1000 }
            # Not [datetime]::UnixEpoch — that was added in .NET Core 2.1 and does
            # not exist on the .NET Framework that PowerShell 5.1 runs on, where it
            # throws and silently takes the whole countdown with it.
            $epoch = New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)
            $t = $epoch.AddSeconds($n)
        }
    } catch { return $null }
    if ($null -eq $t) { return $null }
    return $t - [datetime]::UtcNow
}
# "0h 41m" for the 5h window, "5d 05h 20m" for the 7d one.
#
# Every unit is always printed, even at zero, so the field keeps a fixed width and
# the line doesn't shift as the clock ticks down. Trailing units are zero-padded for
# the same reason.
#
# Floor throughout, never [int]: PowerShell's [int] cast rounds, and rounds half to
# even, so a 6.65-day span would print as 7 days.
function FmtSpan($s, $units) {
    if ($null -eq $s -or $s.TotalSeconds -le 0) { return 'now' }
    $total = [math]::Floor($s.TotalSeconds)
    $m = [math]::Floor(($total % 3600) / 60)
    if ($units -eq 'dhm') {
        $d = [math]::Floor($total / 86400)
        $h = [math]::Floor(($total % 86400) / 3600)
        return '{0}d {1:00}h {2:00}m' -f $d, $h, $m
    }
    # Hours view: any whole days fold into the hour count rather than vanishing.
    return '{0}h {1:00}m' -f [math]::Floor($total / 3600), $m
}

$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }

# Mode value out of one flag file, or $null when there is nothing usable there.
#
# No flag file means the plugin isn't installed, so nothing is drawn. That's what
# keeps these tags invisible for people who don't use the plugins.
function ReadMode($path, $valid) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $item = Get-Item -LiteralPath $path -Force
    # Reject reparse points and oversized files: a flag pointed at another file would
    # otherwise get its bytes — ANSI escapes included — rendered on every render.
    if (-not $item -or $item.PSIsContainer) { return $null }
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return $null }
    if ($item.Length -gt 64) { return $null }
    $mode = ([string](Get-Content -LiteralPath $path -TotalCount 1)).Trim().ToLowerInvariant() -replace '[^a-z0-9-]', ''
    # An empty flag file means the plugin defaulted, which is full.
    if (-not $mode) { return 'full' }
    if ($valid) { if ($valid -notcontains $mode) { return $null } }
    elseif ($mode.Length -gt 16) { return $null }
    return $mode
}

function BadgeText($name, $mode, $palette) {
    # Match on the level word, not the whole mode name: caveman also has wenyan-lite
    # / wenyan-ultra and one-shot modes like commit, which all read as "full".
    $tier = if ($mode -eq 'off')      { 'off' }
            elseif ($mode -like '*ultra*') { 'ultra' }
            elseif ($mode -like '*lite*')  { 'lite' }
            else { 'full' }
    # The mode is always spelled out, `full` included. Hiding the suffix for full
    # meant the state you sit in almost all the time was the one carrying no
    # information -- a bare "[CAVEMAN]" never told you which tier was active.
    return (C $palette[$tier] "[$($name.ToUpperInvariant())`:$($mode.ToUpperInvariant())]")
}

# Every mode flag that applies to this session, newest layout first.
#
# Session-scoped flags live at modes/<session_id>/<name>, so each window carries its
# own level — that is what a plugin writes once it keys the flag by session id. The
# legacy layout is one global .<name>-active per plugin, which is what the stock
# caveman and ponytail write; there the badge necessarily shows whichever session
# changed it last, since the file has no way to say which one it meant.
#
# Both are read, session-scoped wins, so a stock install and a session-keyed one
# both render and a mixed setup renders the right thing for each.
function CollectModes($sessionId) {
    $found = [ordered]@{}
    $claimed = @{}   # names the session dir spoke for, whether or not it read back
    # The id lands in a path, so it is checked before it gets there rather than
    # trusted for being ours.
    if ($sessionId -match '^[0-9a-fA-F][0-9a-fA-F-]{7,63}$') {
        $dir = Join-Path (Join-Path $ClaudeDir 'modes') $sessionId
        if (Test-Path -LiteralPath $dir) {
            foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
                $n = $f.Name.ToLowerInvariant()
                if ($n -notmatch '^[a-z0-9][a-z0-9-]{0,31}$') { continue }
                $claimed[$n] = $true
                $m = ReadMode $f.FullName $badgeModes[$n]
                if ($m) { $found[$n] = $m }
            }
        }
    }
    # No fallback once the session dir has a file for that name, even an unreadable
    # one. Falling back would put another session's level on this window's line,
    # which is the exact confusion the session-scoped layout exists to end.
    foreach ($n in @('caveman', 'ponytail')) {
        if ($claimed.Contains($n)) { continue }
        $m = ReadMode (Join-Path $ClaudeDir ".$n-active") $badgeModes[$n]
        if ($m) { $found[$n] = $m }
    }
    return $found
}

# ================= line 1: environment =================
$l1 = @()

# Fixed order — caveman, ponytail, then everything else alphabetically — so the line
# never reshuffles between renders just because a flag file was touched.
$modes = CollectModes ([string]$j.session_id)
$order = @('caveman', 'ponytail') + @($modes.Keys | Where-Object { $_ -ne 'caveman' -and $_ -ne 'ponytail' } | Sort-Object)
foreach ($n in $order) {
    if (-not $modes.Contains($n)) { continue }
    $gate = if ($n -eq 'caveman') { $show.caveman } elseif ($n -eq 'ponytail') { $show.ponytail } else { $show.toggles }
    if (-not $gate) { continue }
    $pal = if ($badgeColors.Contains($n)) { $badgeColors[$n] } else { $badgeColors.default }
    $l1 += BadgeText $n $modes[$n] $pal
}

# The badges above are read off disk; every other segment, both lines, comes out
# of the payload. So an empty or unparseable stdin renders as two lonely plugin
# tags and no hint as to why — which reads like the tool half-broke rather than
# like it got nothing to work with. Say so instead.
if ($null -eq $j) { $l1 += C $RED 'no payload' }

if ($show.model -and $j.model.display_name) { $l1 += C 111 $j.model.display_name }

$dir = if ($j.workspace.current_dir) { $j.workspace.current_dir } else { $j.cwd }
if ($show.dir -and $dir) { $l1 += C 245 (Split-Path -Leaf $dir) }

if ($show.branch -and $dir) {
    # One porcelain=v2 call carries branch name, ahead/behind and per-file state
    # together, so this costs the same two subprocesses the old rev-parse+status
    # pair did — the second is the line delta below.
    #
    # --no-optional-locks matters here. A plain `git status` refreshes the index
    # stat cache, which rewrites .git/index and briefly takes .git/index.lock. A
    # statusline runs on every render, so that would both touch the repo and race
    # the user's own git commands ("Unable to create index.lock"). This flag exists
    # for precisely this case: shell prompts and IDE statuslines.
    $st = & git -C $dir --no-optional-locks status --porcelain=v2 --branch 2>$null
    if ($LASTEXITCODE -eq 0 -and $st) {
        $branch = ''; $ahead = 0; $behind = 0; $untracked = 0; $dirty = $false
        foreach ($line in $st) {
            if ($line.StartsWith('# branch.head ')) { $branch = $line.Substring(14) }
            elseif ($line.StartsWith('# branch.ab ') -and $line -match '\+(\d+)\s+-(\d+)') {
                $ahead = [int]$Matches[1]; $behind = [int]$Matches[2]
            }
            elseif ($line.StartsWith('? ')) { $untracked++ }
            elseif ($line -match '^[12u] ') { $dirty = $true }
        }

        $add = 0; $del = 0
        if ($show.gitLines) {
            # Against HEAD, so staged and unstaged changes are counted together.
            # Fails silently on a repo with no commits yet; 0/0 is the right answer there.
            $stat = (& git -C $dir --no-optional-locks diff HEAD --shortstat 2>$null) -join ''
            if ($stat -match '(\d+) insertion') { $add = [int]$Matches[1] }
            if ($stat -match '(\d+) deletion')  { $del = [int]$Matches[1] }
        }

        if ($branch) {
            # The * is redundant once the numbers are shown, so it only appears
            # when gitLines is switched off.
            $mark = if (-not $show.gitLines -and $dirty) { '*' } else { '' }
            $seg = C 150 "$branch$mark"
            if ($show.gitAhead -and ($ahead -or $behind)) {
                $ab = ''
                if ($ahead)  { $ab += "$([char]0x2191)$ahead" }
                if ($behind) { $ab += "$([char]0x2193)$behind" }
                $seg += ' ' + (C 245 $ab)
            }
            if ($show.gitLines -and ($add -or $del)) {
                $seg += ' ' + (C 150 "+$add") + (C $DIM '/') + (C 203 "-$del")
            }
            if ($show.gitUntrk -and $untracked) { $seg += ' ' + (C 179 "?$untracked") }
            $l1 += $seg
        }
    }
}

# ================= line 2: usage bars =================
$l2 = @()

$cw = $j.context_window
if ($show.context -and $cw.context_window_size -gt 0) {
    # `$null -eq`, never `-not`: 0 is falsy in PowerShell, so `-not` would call a
    # genuine 0% "no data" and simply move the lie to the other end. Every pending
    # test below is written this way for the same reason.
    if ($null -eq $cw.used_percentage) {
        $l2 += (C $DIM 'ctx ') + (BarPending)
    } else {
        $tier = CtxTier $cw.context_window_size
        $step = PickStep (CtxRamp $tier) $cw.used_percentage
        # A tier carrying a ladder replaces the step's own glyph outright, so the
        # two never both fire and the escalation stays the only thing being read.
        $mark = if ($tier.marks) { MarkFor $tier.marks $cw.used_percentage } else { $step.mark }
        $l2 += (C $DIM 'ctx ') + (Bar $cw.used_percentage $step $mark)
    }
}

# rate_limits goes missing for two different reasons, and a single payload only
# tells them apart indirectly. Before the first message it is simply not there yet
# — context_window's own used_percentage is null for exactly the same reason — and
# that transient gap is what BarPending exists for. But on plans that don't report
# quotas it never arrives at all, and a placeholder there is a permanent dead
# column promising a measurement that is never coming.
#
# used_percentage is the discriminator: once it is a real number at least one
# message has landed, so a rate_limits still absent at that point is absent for
# good and the bar is dropped instead — which is what the README documents and
# what statusline.sh does.
$quotaComing = $null -eq $cw.used_percentage

if ($show.quota5h) {
    $q = $j.rate_limits.five_hour
    if ($null -eq $q -or $null -eq $q.used_percentage) {
        if ($null -ne $q -or $quotaComing) { $l2 += (C $DIM '5h ') + (BarPending) }
    } else {
        $seg = (C $DIM '5h ') + (Bar $q.used_percentage (PickStep $ramp5h $q.used_percentage))
        # Omit the countdown entirely when there's no usable stamp — printing "now"
        # for missing data claims the window is resetting this second.
        $left5 = ResetSpan $q.resets_at
        # Space after the glyph: "↻41m" runs the icon into the number.
        if ($null -ne $left5) { $seg += C $DIM "$fieldGap$([char]0x21BB) $(FmtSpan $left5 'hm')" }
        $l2 += $seg
    }
}

if ($show.quota7d) {
    $q = $j.rate_limits.seven_day
    if ($null -eq $q -or $null -eq $q.used_percentage) {
        if ($null -ne $q -or $quotaComing) { $l2 += (C $DIM '7d ') + (BarPending) }
    } else {
        $dev = $null
        $left = ResetSpan $q.resets_at
        if ($null -ne $left) {
            $elapsed = [math]::Max(0.0, [math]::Min(1.0, 1 - ($left.TotalSeconds / $weekSeconds)))
            # Round before choosing the colour so the shade always agrees with the
            # digits shown: +0.4 renders as ±0% and must not be coloured as an overrun.
            $dev = [int][math]::Round($q.used_percentage - $elapsed * 100)
            $step = PickStep $devRamp $dev
        } else {
            $step = $dev7dUnknown
        }
        # Quota gone: the deviation has stopped carrying information, so the one
        # absolute rule on this bar takes over. See $hardStop7d.
        if ($null -ne $hardStop7d -and $q.used_percentage -ge $hardStop7d) { $step = $exhausted7d }
        $seg = (C $DIM '7d ') + (Bar $q.used_percentage $step)
        if ($null -ne $left) { $seg += C $DIM "$fieldGap$([char]0x21BB) $(FmtSpan $left 'dhm')" }
        if ($show.delta -and $null -ne $dev) {
            $txt = if ($dev -gt 0) { "+$dev%" } elseif ($dev -lt 0) { "$dev%" } else { "$([char]0xB1)0%" }
            # Same style as the bar. With the floor gone the bar *is* the deviation,
            # so painting the number separately would invent a second reading that
            # does not exist.
            $seg += $fieldGap + (Paint $step $txt)
        }
        $l2 += $seg
    }
}

$lines = @()
if ($l1.Count) { $lines += ($l1 -join (C $DIM ' | ')) }
if ($l2.Count) { $lines += ($l2 -join (C $DIM "$segGap$segSep$segGap")) }
[Console]::Write($lines -join "`n")
