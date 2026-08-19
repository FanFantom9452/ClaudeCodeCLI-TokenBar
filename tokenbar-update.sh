#!/bin/sh
# ClaudeCodeCLI-TokenBar updater — runs from the SessionStart hook (Linux / macOS).
#
# Three hard rules, because this runs before every session:
#   never write to stdout   a SessionStart hook's stdout is injected into the
#                           session as context, so a stray line would land in
#                           front of the model as if it were instructions
#   never fail loudly       a broken updater must not stop Claude Code starting
#   always exit 0           same reason
# Everything failable is guarded and failures go to a log file nobody has to read.
#
# Shape: the hook process only reads a local timestamp. Only when a check is
# actually due does it detach a worker for the network part, so session start
# never waits on GitHub.
#
# Only tagged releases are followed, never main. Auto-update is a channel for
# arbitrary commits to run on your machine; requiring a deliberate tag means a
# half-finished push cannot reach you on its own.
OWNER=FanFantom9452
REPO=ClaudeCodeCLI-TokenBar
INTERVAL=86400          # once a day

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SCRIPT="$CFG/statusline.sh"
STATE="$CFG/.tokenbar-state"
OPTOUT="$CFG/.tokenbar-noupdate"
LOGF="$CFG/.tokenbar-update.log"

log() {
    { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOGF"; } 2>/dev/null
    # Truncate rather than grow forever: this file exists to be read once, after
    # something went wrong.
    if [ -f "$LOGF" ] && [ "$(wc -l < "$LOGF" 2>/dev/null || echo 0)" -gt 200 ]; then
        tail -n 100 "$LOGF" > "$LOGF.t" 2>/dev/null && mv "$LOGF.t" "$LOGF" 2>/dev/null
    fi
}
# State is two lines, last-check epoch then tag. A flat file rather than JSON so
# the updater needs no parser to read its own bookkeeping.
read_state() {
    LAST=0; TAG=""
    if [ -r "$STATE" ]; then
        LAST=$(sed -n 1p "$STATE" 2>/dev/null); TAG=$(sed -n 2p "$STATE" 2>/dev/null)
        case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac
    fi
}
write_state() { printf '%s\n%s\n' "$1" "$2" > "$STATE" 2>/dev/null; }

fetch() { # url -> stdout
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 30 -A 'ClaudeCodeCLI-TokenBar-updater' "$1" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout=30 -U 'ClaudeCodeCLI-TokenBar-updater' "$1" 2>/dev/null
    else
        return 1
    fi
}

# ---------------- hook process: decide, delegate, get out of the way --------
if [ "$1" != "--worker" ]; then
    [ -e "$OPTOUT" ] && exit 0
    read_state
    now=$(date +%s)
    [ $((now - LAST)) -lt "$INTERVAL" ] && exit 0
    # Detached and fully redirected: nothing this spawns can reach the hook stdout.
    (sh "$0" --worker >/dev/null 2>&1 &) >/dev/null 2>&1
    exit 0
fi

# ---------------- worker: the part allowed to be slow -----------------------
read_state
# Stamped before the network call, not after. A GitHub outage that hangs every
# time must cost one attempt a day, not one attempt per session.
write_state "$(date +%s)" "$TAG"

rel=$(fetch "https://api.github.com/repos/$OWNER/$REPO/releases/latest") || {
    log 'release lookup failed (no curl/wget, or the request failed)'; exit 0; }
newtag=$(printf '%s' "$rel" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
[ -z "$newtag" ] && { log 'no tag_name in release response'; exit 0; }
[ "$newtag" = "$TAG" ] && exit 0

tmp="$SCRIPT.new"
fetch "https://raw.githubusercontent.com/$OWNER/$REPO/$newtag/statusline.sh" > "$tmp" 2>/dev/null || {
    log "download of $newtag failed"; rm -f "$tmp"; exit 0; }

# Three gates before anything replaces a working statusline: a 404 page, a
# truncated download and a syntactically broken script all fail here rather than
# at render time, where the only symptom would be a blank status line.
size=$(wc -c < "$tmp" 2>/dev/null || echo 0)
if [ "$size" -lt 2000 ]; then log "download too small to be the script ($size bytes)"; rm -f "$tmp"; exit 0; fi
if ! grep -q 'ClaudeCodeCLI-TokenBar' "$tmp"; then log 'download does not look like the script'; rm -f "$tmp"; exit 0; fi
if ! sh -n "$tmp" 2>/dev/null; then log 'download does not parse'; rm -f "$tmp"; exit 0; fi

[ -f "$SCRIPT" ] && cp "$SCRIPT" "$SCRIPT.bak" 2>/dev/null
mv "$tmp" "$SCRIPT" 2>/dev/null && chmod +x "$SCRIPT" 2>/dev/null
write_state "$(date +%s)" "$newtag"
log "updated statusline.sh to $newtag (previous kept as statusline.sh.bak)"
exit 0
