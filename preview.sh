#!/bin/sh
# ClaudeCodeCLI-TokenBar preview (Linux / macOS)
#
#   sh preview.sh [path-to-statusline.sh]
#
# Feeds synthetic payloads through the real statusline and prints what comes back,
# so a threshold or colour edited in tokenbar-config.sh can be checked without
# waiting to burn through an actual quota to see it.
#
# It runs the installed script by default, which means it picks up your config file
# exactly as Claude Code would. Pass a path to preview a working copy before
# installing it.
#
# Roughly two seconds on Linux or macOS. Under Git Bash on Windows it takes over a
# minute, because every row forks sh, perl and awk and Windows charges dearly for
# that - use preview.ps1 there instead.
set -eu

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SCRIPT="${1:-}"
if [ -z "$SCRIPT" ]; then
    if [ -f "$here/statusline.sh" ]; then SCRIPT="$here/statusline.sh"; else SCRIPT="$CFG/statusline.sh"; fi
fi
[ -f "$SCRIPT" ] || { echo "Not found: $SCRIPT" >&2; exit 1; }
USERCFG="$CFG/tokenbar-config.sh"

ESC=$(printf '\033')
WEEK=604800
now=$(date +%s)

# ctxsize ctxpct q5 q7 dev -> the bar line only; line 1 is the git/model line.
render() {
    _cs=$1; _cp=$2; _q5=$3; _q7=$4; _dv=$5
    _rl=''
    if [ -n "$_q5" ]; then
        _rl="\"five_hour\":{\"used_percentage\":$_q5,\"resets_at\":$((now + 6360))}"
    fi
    if [ -n "$_q7" ]; then
        # resets_at is derived from the deviation being asked for: the elapsed
        # fraction is whatever makes used% - elapsed% land on the requested dev.
        _r7=$(awk -v n="$now" -v w="$WEEK" -v u="$_q7" -v d="$_dv" 'BEGIN{printf "%d", n + w*(1-(u-d)/100)}')
        [ -n "$_rl" ] && _rl="$_rl,"
        _rl="$_rl\"seven_day\":{\"used_percentage\":$_q7,\"resets_at\":$_r7}"
    fi
    [ -n "$_rl" ] && _rl=",\"rate_limits\":{$_rl}"
    printf '{"cwd":"%s","model":{"id":"claude-opus-5[1m]","display_name":"Opus 5"},"workspace":{"current_dir":"%s"},"context_window":{"context_window_size":%s,"used_percentage":%s}%s}' \
        "$here" "$here" "$_cs" "$_cp" "$_rl" | sh "$SCRIPT" | tail -n 1
}
row()  { printf '  %-22s %s\n' "$1" "$(shift; echo "$@")"; }
head_() { printf '\n%s[1m  %s%s[0m\n\n' "$ESC" "$1" "$ESC"; }

printf '\n script  : %s\n' "$SCRIPT"
if [ -f "$USERCFG" ]; then
    live=$(grep -Ev '^[[:space:]]*(#|$)' "$USERCFG" 2>/dev/null | wc -l | tr -d ' ')
    printf ' config  : %s  (%s active line(s))\n' "$USERCFG" "$live"
else
    printf ' config  : none at %s - showing defaults\n' "$USERCFG"
fi

for t in 200000:200k 500000:500k 800000:800k 1000000:1M; do
    w=${t%%:*}; n=${t##*:}
    head_ "ctx $n window"
    for p in 10 40 50 55 60 70 80 85 90 95 100; do
        printf '  %-22s %s\n' "$n  $p%" "$(render "$w" "$p" '' '' 0)"
    done
done

head_ '5h'
for p in 20 39 40 59 60 79 80 94 95 100; do
    printf '  %-22s %s\n' "5h  $p%" "$(render 200000 10 "$p" '' 0)"
done

head_ '7d - the bar is the deviation, not the percentage'
# used:dev:note
for c in '30:-14:a full day banked' '45:-5:comfortably under' '90:-3:90% used, still on pace' \
         '55:0:dead on the line' '50:3:slightly over' '48:7:half a day ahead' \
         '60:11:nearly a day ahead' '70:14:a full day ahead' '62:20:well past sustainable' \
         '97:-1:nearly empty, on pace' '100:0:quota gone (hard stop)'; do
    p=$(echo "$c" | cut -d: -f1); d=$(echo "$c" | cut -d: -f2); note=$(echo "$c" | cut -d: -f3-)
    printf '  %-22s %s  %s[38;5;240m%s%s[0m\n' "7d  $p%  dev $d" "$(render 200000 10 '' "$p" "$d")" "$ESC" "$note" "$ESC"
done

head_ 'full line, as it actually renders'
printf '  %-22s %s\n' 'quiet'    "$(render 1000000 22 30 25 2)"
printf '  %-22s %s\n' 'mid-week' "$(render 1000000 48 66 58 -6)"
printf '  %-22s %s\n' 'pressed'  "$(render 1000000 72 88 71 15)"
printf '  %-22s %s\n' 'critical' "$(render 1000000 93 97 96 8)"
printf '\n'
