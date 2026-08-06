#!/bin/sh
# ClaudeCodeCLI-TokenBar — Claude Code statusline (Linux / macOS)
#
#   line 1  [CAVEMAN] [PONYTAIL] | Opus 5 | my-project | main ↑2 +42/-7 ?1
#   line 2  ctx ███▊░░░░░░  38%  ·  5h ██████▌░░░  66% ↻1h46m  ·  7d █████▊░░░░  58% ↻5d5h ×2.3
#
# The three bars are coloured by three different rules on purpose:
#   ctx  absolute %, thresholds tiered by the model's context window size
#   5h   absolute %, five fixed bands
#   7d   burn *pace* against the weekly allowance, with an absolute floor
#
# Needs perl (JSON::PP and Time::Local are core modules, so nothing to install)
# and awk. Payload schema verified against Claude Code 2.1.223.

# ---- toggles: 1 shows, 0 hides -------------------------------------------
SHOW_CAVEMAN=1     # [CAVEMAN:FULL] badge, if the caveman plugin is installed
SHOW_PONYTAIL=1    # [PONYTAIL]     badge, if the ponytail plugin is installed
SHOW_MODEL=1       # Opus 5
SHOW_DIR=1         # current directory name
SHOW_BRANCH=1      # main   (gets a * only when SHOW_GITLINES is off)
SHOW_GITAHEAD=1    # ↑2 ↓1  commits not pushed / not pulled
SHOW_GITLINES=1    # +42/-7 uncommitted line delta vs HEAD
SHOW_GITUNTRK=1    # ?1     untracked files, which no diff would catch
SHOW_CONTEXT=1     # ctx bar
SHOW_QUOTA5H=1     # 5h bar
SHOW_QUOTA7D=1     # 7d bar
SHOW_PACE=1        # ×2.1 multiplier next to the 7d bar
BAR_WIDTH=10       # cells per bar; shared so the three compare by eye
# -------------------------------------------------------------------------

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
ESC=$(printf '\033')

payload=$(cat)
[ "${CLAUDE_STATUSLINE_DEBUG:-}" = "1" ] && printf '%s' "$payload" > "${TMPDIR:-/tmp}/claude-statusline-payload.json"

command -v perl >/dev/null 2>&1 || { printf 'TokenBar: perl not found'; exit 0; }

# One perl pass flattens what we need into a TSV line. resets_at may arrive as
# ISO-8601 or epoch seconds, so both are normalised to epoch here, and the current
# time rides along so awk needs no clock of its own (POSIX awk has no systime()).
fields=$(printf '%s' "$payload" | perl -MJSON::PP -MTime::Local -0777 -ne '
sub stamp {
    my $v = shift;
    return -1 unless defined $v;
    return $v + 0 if $v =~ /^-?\d+(?:\.\d+)?$/;
    if ($v =~ /^(\d{4})-(\d\d)-(\d\d)[T ](\d\d):(\d\d):(\d\d)(?:\.\d+)?(Z|[+-]\d\d:?\d\d)?/) {
        my $t = Time::Local::timegm($6, $5, $4, $3, $2 - 1, $1);
        if (defined $7 && $7 ne "Z") {
            my ($sg, $oh, $om) = $7 =~ /^([+-])(\d\d):?(\d\d)$/;
            my $off = $oh * 3600 + $om * 60;
            $t -= ($sg eq "+" ? $off : -$off);
        }
        return $t;
    }
    return -1;
}
my $j  = eval { decode_json($_) } || {};
my $cw = $j->{context_window} || {};
my $rl = $j->{rate_limits}    || {};
my $f5 = $rl->{five_hour}     || {};
my $f7 = $rl->{seven_day}     || {};
my $ws = $j->{workspace}      || {};
print join("\t",
    time(),
    $j->{model}{display_name} // "",
    $ws->{current_dir} // $j->{cwd} // "",
    $cw->{context_window_size} // 0,
    defined $cw->{used_percentage} ? $cw->{used_percentage} : -1,
    defined $f5->{used_percentage} ? $f5->{used_percentage} : -1,
    stamp($f5->{resets_at}),
    defined $f7->{used_percentage} ? $f7->{used_percentage} : -1,
    stamp($f7->{resets_at})
), "\n";
') || exit 0

dir=$(printf '%s' "$fields" | cut -f3)

tint() { printf '%s[38;5;%sm%s%s[0m' "$ESC" "$1" "$2" "$ESC"; }

# Git needs subprocesses, so it happens here rather than inside awk. One
# porcelain=v2 call carries branch name, ahead/behind and per-file state at once;
# the line delta below is the only extra call.
#
# --no-optional-locks matters here. A plain `git status` refreshes the index stat
# cache, which rewrites .git/index and briefly takes .git/index.lock. A statusline
# runs on every render, so that would both touch the repo and race the user's own
# git commands ("Unable to create index.lock"). This flag exists for precisely this
# case: shell prompts and IDE statuslines.
branch=""
if [ "$SHOW_BRANCH" = "1" ] && [ -n "$dir" ] && [ -d "$dir" ]; then
    st=$(git -C "$dir" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null) || st=""
    if [ -n "$st" ]; then
        gb=$(printf '%s\n' "$st" | sed -n 's/^# branch\.head //p')
        ahead=0; behind=0
        ab=$(printf '%s\n' "$st" | awk '/^# branch\.ab /{gsub(/[+-]/,"",$3); gsub(/[+-]/,"",$4); printf "%d %d",$3,$4}')
        if [ -n "$ab" ]; then ahead=${ab%% *}; behind=${ab##* }; fi
        # No `|| echo 0` here: grep -c already prints 0 when it matches nothing,
        # and its exit status 1 would make the fallback append a second line.
        untracked=$(printf '%s\n' "$st" | grep -c '^? ' 2>/dev/null)
        dirty=$(printf '%s\n' "$st" | grep -c '^[12u] ' 2>/dev/null)
        [ -n "$untracked" ] || untracked=0
        [ -n "$dirty" ] || dirty=0

        add=0; del=0
        if [ "$SHOW_GITLINES" = "1" ]; then
            # Against HEAD, so staged and unstaged changes count together. Fails
            # silently on a repo with no commits yet; 0/0 is right there.
            stat=$(git -C "$dir" --no-optional-locks diff HEAD --shortstat 2>/dev/null) || stat=""
            # Parsed by field, not regex: a greedy ".*\([0-9]*\) insertion" would
            # capture only the last digit of "42 insertions".
            ad=$(printf '%s\n' "$stat" | awk 'BEGIN{a=0;d=0}
                {for(i=1;i<=NF;i++){if($i~/^insertion/)a=$(i-1)+0; if($i~/^deletion/)d=$(i-1)+0}}
                END{printf "%d %d",a,d}')
            add=${ad%% *}; del=${ad##* }
        fi

        if [ -n "$gb" ]; then
            # The * is redundant once the numbers are shown, so it only appears
            # when SHOW_GITLINES is switched off.
            mark=""
            [ "$SHOW_GITLINES" != "1" ] && [ "$dirty" -gt 0 ] && mark="*"
            branch=$(tint 150 "$gb$mark")
            if [ "$SHOW_GITAHEAD" = "1" ] && { [ "$ahead" -gt 0 ] || [ "$behind" -gt 0 ]; }; then
                abs=""
                [ "$ahead" -gt 0 ]  && abs="↑$ahead"
                [ "$behind" -gt 0 ] && abs="$abs↓$behind"
                branch="$branch $(tint 245 "$abs")"
            fi
            if [ "$SHOW_GITLINES" = "1" ] && { [ "$add" -gt 0 ] || [ "$del" -gt 0 ]; }; then
                branch="$branch $(tint 150 "+$add")$(tint 240 '/')$(tint 203 "-$del")"
            fi
            if [ "$SHOW_GITUNTRK" = "1" ] && [ "$untracked" -gt 0 ]; then
                branch="$branch $(tint 179 "?$untracked")"
            fi
        fi
    fi
fi

# Plugin mode badge from the flag file the plugin's own hooks write.
# Hardening: refuse symlinks and oversized files, strip everything outside
# [a-z0-9-], then whitelist-check. A flag pointed at another file would otherwise
# get its bytes — ANSI escape sequences included — rendered on every render.
badge() {
    f="$CFG/$1"; label="$2"; color="$3"; valid="$4"
    [ -f "$f" ] || return 0
    [ -L "$f" ] && return 0
    size=$(wc -c < "$f" 2>/dev/null | tr -d ' ') || return 0
    [ "$size" -gt 64 ] && return 0
    mode=$(head -n1 "$f" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
    [ "$mode" = "off" ] && return 0
    if [ -n "$mode" ]; then
        case " $valid " in *" $mode "*) ;; *) return 0 ;; esac
    fi
    if [ -z "$mode" ] || [ "$mode" = "full" ]; then
        printf '%s[38;5;%sm[%s]%s[0m' "$ESC" "$color" "$label" "$ESC"
    else
        up=$(printf '%s' "$mode" | tr '[:lower:]' '[:upper:]')
        printf '%s[38;5;%sm[%s:%s]%s[0m' "$ESC" "$color" "$label" "$up" "$ESC"
    fi
}

badges=""
if [ "$SHOW_CAVEMAN" = "1" ]; then
    b=$(badge .caveman-active CAVEMAN 172 "off lite full ultra wenyan-lite wenyan wenyan-full wenyan-ultra commit review compress")
    [ -n "$b" ] && badges="$b"
fi
if [ "$SHOW_PONYTAIL" = "1" ]; then
    b=$(badge .ponytail-active PONYTAIL 108 "off lite full ultra")
    [ -n "$b" ] && { [ -n "$badges" ] && badges="$badges$ESC[38;5;240m | $ESC[0m$b" || badges="$b"; }
fi

printf '%s' "$fields" | awk -F'\t' \
    -v esc="$ESC" -v badges="$badges" -v branch="$branch" \
    -v barw="$BAR_WIDTH" \
    -v s_model="$SHOW_MODEL" -v s_dir="$SHOW_DIR" -v s_ctx="$SHOW_CONTEXT" \
    -v s_q5="$SHOW_QUOTA5H" -v s_q7="$SHOW_QUOTA7D" -v s_pace="$SHOW_PACE" '
function paint(t)  { return esc "[" (BOLD ? "1;" : "") "38;5;" COL "m" t esc "[0m" }
function dim(t)    { return esc "[38;5;240m" t esc "[0m" }
function tint(c,t) { return esc "[38;5;" c "m" t esc "[0m" }

# --- ctx: thresholds tiered by window size. A flat 20%-is-yellow rule punishes
# small windows: 20% of 200k is 40k, which is nothing.
function ctx_style(p, w,   g, span, i) {
    if      (w <= 200000) { amber=50; red=70; purple=85 }
    else if (w <= 500000) { amber=40; red=60; purple=80 }
    else if (w <= 800000) { amber=30; red=55; purple=80 }
    else                  { amber=20; red=50; purple=80 }
    if      (p >= purple) { COL=201; BOLD=1; MARK=1 }
    else if (p >= red)    { COL=196; BOLD=1; MARK=0 }
    else if (p >= amber) {
        # Gradient spread evenly across [amber, red). On a 1M window this lands
        # on exactly 20/25/30/35/40/45.
        g[1]=226; g[2]=220; g[3]=214; g[4]=208; g[5]=202; g[6]=203
        span=(red-amber)/6
        i=int((p-amber)/span)+1; if (i>6) i=6
        COL=g[i]; BOLD=0; MARK=0
    }
    else { COL=108; BOLD=0; MARK=0 }
}

# --- 5h: five fixed bands. No pace rule — the window is only 5 hours, work
# arrives in bursts, and a pace figure over that span jitters too much to read.
function q5_style(p) {
    if      (p >= 95) { COL=201; BOLD=1; MARK=1 }
    else if (p >= 80) { COL=196; BOLD=1; MARK=0 }
    else if (p >= 60) { COL=226; BOLD=0; MARK=0 }
    else if (p >= 40) { COL=179; BOLD=0; MARK=0 }
    else              { COL=108; BOLD=0; MARK=0 }
}

# --- 7d: severity of burn pace vs the weekly allowance...
function sev_pace(x) { if (x >= 3) return 4; if (x >= 2) return 3; if (x >= 1) return 2; return 0 }
# ...and an absolute floor, because pace lies at the end of a window: 95% used on
# day 6.9 is pace 0.97 — "green" while almost nothing is left.
function sev_abs7(p) { if (p >= 95) return 4; if (p >= 85) return 3; return 0 }
function style_of_sev(s) {
    if      (s == 4) { COL=201; BOLD=1; MARK=1 }
    else if (s == 3) { COL=196; BOLD=1; MARK=0 }
    else if (s == 2) { COL=226; BOLD=0; MARK=0 }
    else if (s == 1) { COL=179; BOLD=0; MARK=0 }
    else             { COL=108; BOLD=0; MARK=0 }
}

# Eighth-block bar: 8 sub-steps per cell, so 10 cells resolve ~80 levels.
# Assigned one by one, not split() — mawk splits multi-byte chars into bytes.
function bar(p,   e, cells, nf, nr, fill, track, i, out) {
    if (p < 0) p = 0; if (p > 100) p = 100
    e[1]="▏"; e[2]="▎"; e[3]="▍"; e[4]="▌"; e[5]="▋"; e[6]="▊"; e[7]="▉"
    cells = p/100 * barw
    nf = int(cells)
    nr = int((cells - nf) * 8)
    fill = ""
    for (i = 0; i < nf; i++) fill = fill "█"
    if (nr > 0) fill = fill e[nr]
    track = ""
    for (i = 0; i < barw - nf - (nr > 0 ? 1 : 0); i++) track = track "░"
    # Percent padded to 3 columns so the line does not shift as digit count changes.
    out = paint(fill) tint(240, track) " " paint(sprintf("%3d%%", int(p + 0.5)))
    if (MARK) out = out paint(" ⚠")
    return out
}

# "4d3h" / "2h14m" / "18m" — minutes zero-padded so this field does not jitter either.
function fmtspan(sec,   d, h, m) {
    if (sec <= 0) return "now"
    d = int(sec/86400); h = int((sec % 86400)/3600); m = int((sec % 3600)/60)
    if (d >= 1) return d "d" h "h"
    if (h >= 1) return sprintf("%dh%02dm", h, m)
    return m "m"
}

{
    nowt = $1; model = $2; dir = $3; ctxw = $4 + 0; ctxp = $5 + 0
    q5p = $6 + 0; q5r = $7 + 0; q7p = $8 + 0; q7r = $9 + 0

    # ---- line 1: environment ----
    n1 = 0
    if (badges != "")                       l1[++n1] = badges
    if (s_model == "1" && model != "")      l1[++n1] = tint(111, model)
    if (s_dir == "1" && dir != "") {
        base = dir; sub(/\/+$/, "", base); sub(/^.*\//, "", base)
        if (base != "") l1[++n1] = tint(245, base)
    }
    if (branch != "")                       l1[++n1] = branch   # already coloured in shell

    # ---- line 2: usage bars ----
    n2 = 0
    if (s_ctx == "1" && ctxw > 0 && ctxp >= 0) {
        ctx_style(ctxp, ctxw)
        l2[++n2] = dim("ctx ") bar(ctxp)
    }
    if (s_q5 == "1" && q5p >= 0) {
        q5_style(q5p)
        seg = dim("5h ") bar(q5p)
        if (q5r > 0) seg = seg dim(" ↻" fmtspan(q5r - nowt))
        l2[++n2] = seg
    }
    if (s_q7 == "1" && q7p >= 0) {
        sev = sev_abs7(q7p)
        pace = -1
        if (q7r > 0) {
            # elapsed fraction of the assumed 7-day window; resets_at is its end
            elapsed = 1 - ((q7r - nowt) / (7*24*3600))
            if (elapsed < 0) elapsed = 0; if (elapsed > 1) elapsed = 1
            # Below 10% elapsed the divisor is too small to trust — 3% used in the
            # first hour would compute as 5x and flash purple.
            if (elapsed >= 0.10) {
                pace = q7p / (elapsed * 100)
                if (pace > 99.9) pace = 99.9
                ps = sev_pace(pace)
                if (ps > sev) sev = ps
            }
        }
        style_of_sev(sev)
        seg = dim("7d ") bar(q7p)
        if (q7r > 0) seg = seg dim(" ↻" fmtspan(q7r - nowt))
        if (s_pace == "1" && pace >= 0) seg = seg " " paint(sprintf("×%.1f", pace))
        l2[++n2] = seg
    }

    out = ""
    for (i = 1; i <= n1; i++) out = out (i > 1 ? dim(" | ") : "") l1[i]
    if (n1 > 0 && n2 > 0) out = out "\n"
    for (i = 1; i <= n2; i++) out = out (i > 1 ? dim("  ·  ") : "") l2[i]
    printf "%s", out
}'
