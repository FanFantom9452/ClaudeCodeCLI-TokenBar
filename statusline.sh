#!/bin/sh
# ClaudeCodeCLI-TokenBar — Claude Code statusline (Linux / macOS)
#
#   line 1  [CAVEMAN:FULL] [PONYTAIL:FULL] | Opus 5 | my-project | main ↑2 +42/-7 ?1
#   line 2  ctx ███▊░░░░░░  38%    ·    5h ██████▌░░░  66%   ↻ 1h 46m    ·    7d █████▊░░░░  58%   ↻ 2d 12h 30m    -6%
#
# The three bars are coloured by three different rules on purpose:
#   ctx  absolute %, thresholds tiered by the model's context window size
#   5h   absolute %, five fixed bands
#   7d   cumulative deviation from the even 1/7-per-day line, with a floor
#
# Needs perl (JSON::PP and Time::Local are core modules, so nothing to install)
# and awk. Payload schema verified against Claude Code 2.1.223.

# ---- toggles: 1 shows, 0 hides -------------------------------------------
SHOW_CAVEMAN=1     # [CAVEMAN:FULL] badge, if the caveman plugin is installed
SHOW_PONYTAIL=1    # [PONYTAIL]     badge, if the ponytail plugin is installed
SHOW_TOGGLES=1     # any other mode flag found in modes/<session_id>/
SHOW_MODEL=1       # Opus 5
SHOW_DIR=1         # current directory name
SHOW_BRANCH=1      # main   (gets a * only when SHOW_GITLINES is off)
SHOW_GITAHEAD=1    # ↑2 ↓1  commits not pushed / not pulled
SHOW_GITLINES=1    # +42/-7 uncommitted line delta vs HEAD
SHOW_GITUNTRK=1    # ?1     untracked files, which no diff would catch
SHOW_CONTEXT=1     # ctx bar
SHOW_QUOTA5H=1     # 5h bar
SHOW_QUOTA7D=1     # 7d bar
SHOW_DELTA=1       # +2% / -10% next to the 7d bar: quota points ahead of (or
                   # behind) the even 1/7-per-day line
BAR_WIDTH=10       # cells per bar; shared so the three compare by eye
FIELD_GAP="   "    # space between a bar's % and the ↻reset / ±delta that follow it.
                   # One space reads as glued to the number, since the % itself
                   # already sits two spaces off the bar.
SEG_GAP="    "     # space each side of the · between bars. Keep this wider than
                   # FIELD_GAP, or fields inside a segment look further apart than
                   # the segments themselves and the grouping reads backwards.
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
    if ($v =~ /^-?\d+(?:\.\d+)?$/) {
        # Past ~year 5138 in seconds it is really milliseconds.
        return abs($v) > 100000000000 ? $v / 1000 : $v + 0;
    }
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
# -2 for a quota block that is not in the payload at all, -1 for one that is
# there with a null number, and the number itself otherwise. awk has to tell
# those two apart: a block that is merely late gets a placeholder bar, one that
# is never coming gets no bar. Collapsing both to -1 here would throw away the
# only thing that separates them.
sub pct {
    my $o = shift;
    return -2 unless defined $o;
    return defined $o->{used_percentage} ? $o->{used_percentage} : -1;
}
my $j  = eval { decode_json($_) } || {};
my $cw = $j->{context_window} || {};
my $rl = $j->{rate_limits}    || {};
my $f5 = $rl->{five_hour};
my $f7 = $rl->{seven_day};
my $ws = $j->{workspace}      || {};
print join("\t",
    time(),
    $j->{model}{display_name} // "",
    $ws->{current_dir} // $j->{cwd} // "",
    $cw->{context_window_size} // 0,
    defined $cw->{used_percentage} ? $cw->{used_percentage} : -1,
    pct($f5),
    stamp(defined $f5 ? $f5->{resets_at} : undef),
    pct($f7),
    stamp(defined $f7 ? $f7->{resets_at} : undef),
    $j->{session_id} // ""
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

# Plugin badges. Each plugin keeps its own hue; brightness within that hue tracks
# the intensity tier, so the level reads at a glance instead of only from the text
# suffix. No flag file means the plugin isn't installed and nothing is drawn, which
# is what keeps these tags invisible for people who don't use the plugins.
CAVEMAN_COLORS="240 137 172 208"    # off / lite / full / ultra
PONYTAIL_COLORS="240 65 108 84"     # off / lite / full / ultra
# For any toggle this script has never heard of. Adding one is meant to cost nothing
# here: drop a flag file in modes/<session_id>/ and it renders. Give it a case below
# only when you want it off the neutral ramp and onto its own hue.
DEFAULT_COLORS="240 245 250 255"    # gray -> ... -> white

colors_for() {
    case "$1" in
        caveman)  printf '%s' "$CAVEMAN_COLORS" ;;
        ponytail) printf '%s' "$PONYTAIL_COLORS" ;;
        *)        printf '%s' "$DEFAULT_COLORS" ;;
    esac
}
# Modes each known plugin can legitimately be in. An unlisted name gets an empty
# list, meaning it is validated on shape alone — all it takes to keep escapes and
# control bytes off the line. 'review' is ponytail's one-shot mode, the counterpart
# of caveman's commit/review/compress.
valid_for() {
    case "$1" in
        caveman)  printf '%s' "off lite full ultra wenyan-lite wenyan wenyan-full wenyan-ultra commit review compress" ;;
        ponytail) printf '%s' "off lite full ultra review" ;;
        *)        printf '' ;;
    esac
}
gate_for() {
    case "$1" in
        caveman)  [ "$SHOW_CAVEMAN" = "1" ] ;;
        ponytail) [ "$SHOW_PONYTAIL" = "1" ] ;;
        *)        [ "$SHOW_TOGGLES" = "1" ] ;;
    esac
}

# Hardening: refuse symlinks and oversized files, strip everything outside
# [a-z0-9-], then whitelist-check. A flag pointed at another file would otherwise
# get its bytes — ANSI escape sequences included — rendered on every render.
badge() {
    f="$1"; name="$2"; colors=$(colors_for "$2"); valid=$(valid_for "$2")
    [ -f "$f" ] || return 0
    [ -L "$f" ] && return 0
    size=$(wc -c < "$f" 2>/dev/null | tr -d ' ') || return 0
    [ "$size" -gt 64 ] && return 0
    mode=$(head -n1 "$f" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
    # The mode is always spelled out, full included. Hiding the suffix for full
    # meant the state you sit in almost all the time was the one carrying no
    # information - a bare "[CAVEMAN]" never told you which tier was active.
    # An empty flag file means the plugin defaulted, which is full.
    [ -z "$mode" ] && mode=full
    if [ -n "$valid" ]; then
        case " $valid " in *" $mode "*) ;; *) return 0 ;; esac
    else
        [ ${#mode} -gt 16 ] && return 0
    fi
    # Match on the level word, not the whole mode name: caveman also has wenyan-lite
    # / wenyan-ultra and one-shot modes like commit, which all read as "full".
    set -- $colors
    case "$mode" in
        off)      color=$1 ;;
        *ultra*)  color=$4 ;;
        *lite*)   color=$2 ;;
        *)        color=$3 ;;
    esac
    upn=$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')
    upm=$(printf '%s' "$mode" | tr '[:lower:]' '[:upper:]')
    printf '%s[38;5;%sm[%s:%s]%s[0m' "$ESC" "$color" "$upn" "$upm" "$ESC"
}

badges=""
add_badge() {
    b=$(badge "$1" "$2")
    [ -n "$b" ] || return 0
    if [ -n "$badges" ]; then badges="$badges$ESC[38;5;240m | $ESC[0m$b"; else badges="$b"; fi
}

# Two flag layouts are read. Session-scoped flags live at modes/<session_id>/<name>,
# so each window carries its own level — that is what a plugin writes once it keys
# the flag by session id. The legacy layout is one global .<name>-active per plugin,
# which is what the stock caveman and ponytail write; there the badge necessarily
# shows whichever session changed it last, since the file has no way to say which
# one it meant. Session-scoped wins, so stock and session-keyed installs both render.
sid=$(printf '%s' "$fields" | cut -f10)
modedir=""
# The id lands in a path, so it is checked before it gets there rather than trusted
# for being ours. Stripping anything outside [0-9a-fA-F-] must be a no-op.
if [ -n "$sid" ] && [ ${#sid} -le 64 ] &&
   [ "$(printf '%s' "$sid" | tr -cd '0-9a-fA-F-')" = "$sid" ]; then
    [ -d "$CFG/modes/$sid" ] && modedir="$CFG/modes/$sid"
fi

# Fixed order — caveman, ponytail, then everything else alphabetically (the glob
# sorts) — so the line never reshuffles between renders just because a flag file
# was touched.
for n in caveman ponytail; do
    gate_for "$n" || continue
    if [ -n "$modedir" ] && [ -f "$modedir/$n" ]; then
        add_badge "$modedir/$n" "$n"
    else
        add_badge "$CFG/.$n-active" "$n"
    fi
done
if [ -n "$modedir" ] && [ "$SHOW_TOGGLES" = "1" ]; then
    for f in "$modedir"/*; do
        [ -f "$f" ] || continue
        n=${f##*/}
        case "$n" in
            caveman|ponytail) continue ;;
            [!a-z0-9]*)       continue ;;
            *[!a-z0-9-]*)     continue ;;
        esac
        add_badge "$f" "$n"
    done
fi

printf '%s' "$fields" | awk -F'\t' \
    -v esc="$ESC" -v badges="$badges" -v branch="$branch" \
    -v barw="$BAR_WIDTH" -v gap="$FIELD_GAP" -v seggap="$SEG_GAP" \
    -v s_model="$SHOW_MODEL" -v s_dir="$SHOW_DIR" -v s_ctx="$SHOW_CONTEXT" \
    -v s_q5="$SHOW_QUOTA5H" -v s_q7="$SHOW_QUOTA7D" -v s_delta="$SHOW_DELTA" '
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

# --- 5h: five fixed bands. No deviation figure — the window is only 5 hours,
# work arrives in bursts, and a rate over that span jitters too much to read.
function q5_style(p) {
    if      (p >= 95) { COL=201; BOLD=1; MARK=1 }
    else if (p >= 80) { COL=196; BOLD=1; MARK=0 }
    else if (p >= 60) { COL=226; BOLD=0; MARK=0 }
    else if (p >= 40) { COL=179; BOLD=0; MARK=0 }
    else              { COL=108; BOLD=0; MARK=0 }
}

# --- 7d: how many quota points you are ahead of the even 1/7-per-day line.
# Subtraction, not a ratio, so it stays well defined at the very start of a window
# and needs no grace period: 3% used in the first hour is simply +3, where a ratio
# would divide by almost zero and read as a 5x overspend.
function sev_dev(d,   ds) {
    ds = 100 / 7
    if (d >= 2 * ds) return 4      # two full days ahead
    if (d >= ds)     return 3      # a full day ahead
    if (d >= 1)      return 1      # over the line
    return 0                       # at or under it
}
# Deviation says nothing about headroom: +2 with 95% gone is "on budget" and also
# nearly empty. This floor is the worse-case override for the bar.
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

# The bar for a number that does not exist yet. rate_limits only shows up once
# there has been an API response, and used_percentage is null until the first
# message, so for the opening seconds of a session there is genuinely nothing to
# plot. Drawing nothing then reads as broken, and drawing bar(0) is worse: no
# data would render as a green, entirely believable 0%. An empty track and a
# literal --% hold the column width and cannot be mistaken for a measurement.
function bar_pending(   i, track) {
    track = ""
    for (i = 0; i < barw; i++) track = track "░"
    return tint(240, track) " " tint(240, sprintf("%3s%%", "--"))
}

# "0h 41m" for the 5h window, "5d 05h 20m" for the 7d one. Every unit is always
# printed, even at zero, so the field keeps a fixed width and the line does not
# shift as the clock ticks down.
function fmtspan(sec, units,   d, h, m, tot) {
    if (sec <= 0) return "now"
    tot = int(sec)
    m = int((tot % 3600) / 60)
    if (units == "dhm") {
        d = int(tot / 86400); h = int((tot % 86400) / 3600)
        return sprintf("%dd %02dh %02dm", d, h, m)
    }
    # Hours view: any whole days fold into the hour count rather than vanishing.
    return sprintf("%dh %02dm", int(tot / 3600), m)
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
    # rate_limits goes missing for two different reasons, and a single payload
    # only tells them apart indirectly. Before the first message it is simply not
    # there yet, and the context window own used_percentage is null for exactly
    # the same reason, so that transient gap is what bar_pending is for. But on
    # plans that do not report quotas it never arrives at all, and a placeholder
    # there is a permanent dead column promising a measurement that is never
    # coming. -2 is the block that was absent from the payload, -1 the one that
    # was present with a null number.
    quotacoming = (ctxp < 0)

    if (s_ctx == "1" && ctxw > 0) {
        if (ctxp < 0) {
            l2[++n2] = dim("ctx ") bar_pending()
        } else {
            ctx_style(ctxp, ctxw)
            l2[++n2] = dim("ctx ") bar(ctxp)
        }
    }
    if (s_q5 == "1" && (q5p >= 0 || q5p == -1 || quotacoming)) {
        if (q5p < 0) {
            l2[++n2] = dim("5h ") bar_pending()
        } else {
            q5_style(q5p)
            seg = dim("5h ") bar(q5p)
            # Space after the glyph: "↻41m" runs the icon into the number.
            if (q5r > 0) seg = seg dim(gap "↻ " fmtspan(q5r - nowt, "hm"))
            l2[++n2] = seg
        }
    }
    if (s_q7 == "1" && (q7p >= 0 || q7p == -1 || quotacoming)) {
        if (q7p < 0) {
            l2[++n2] = dim("7d ") bar_pending()
        } else {
            sev = sev_abs7(q7p)
            havedev = 0
            if (q7r > 0) {
                # elapsed fraction of the assumed 7-day window; resets_at is its end
                elapsed = 1 - ((q7r - nowt) / (7*24*3600))
                if (elapsed < 0) elapsed = 0; if (elapsed > 1) elapsed = 1
                raw = q7p - elapsed * 100
                # Round before choosing the colour so the shade always agrees with
                # the digits shown: +0.4 renders as ±0% and must not read as an
                # overrun.
                dev = int(raw + (raw >= 0 ? 0.5 : -0.5))
                devsev = sev_dev(dev)
                if (devsev > sev) sev = devsev
                havedev = 1
            }
            style_of_sev(sev)
            seg = dim("7d ") bar(q7p)
            if (q7r > 0) seg = seg dim(gap "↻ " fmtspan(q7r - nowt, "dhm"))
            if (s_delta == "1" && havedev) {
                # Painted with its own severity rather than the severity of the
                # bar. The bar can be purple for being nearly empty while the
                # deviation is only mildly over, and colouring the number purple
                # too would overstate what it measures. NOTE: no apostrophes
                # anywhere inside this awk program - it is single-quoted in the
                # shell, so one would end it here.
                style_of_sev(devsev)
                seg = seg gap paint(dev > 0 ? sprintf("+%d%%", dev) : (dev < 0 ? sprintf("%d%%", dev) : "±0%"))
            }
            l2[++n2] = seg
        }
    }

    out = ""
    for (i = 1; i <= n1; i++) out = out (i > 1 ? dim(" | ") : "") l1[i]
    if (n1 > 0 && n2 > 0) out = out "\n"
    for (i = 1; i <= n2; i++) out = out (i > 1 ? dim(seggap "·" seggap) : "") l2[i]
    printf "%s", out
}'
