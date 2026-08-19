#!/bin/sh
# ClaudeCodeCLI-TokenBar installer (Linux / macOS)
#   curl -fsSL https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main/install.sh | sh
# Touches only files under the Claude config dir, and backs up settings.json first.

set -eu
OWNER=FanFantom9452
NAME=ClaudeCodeCLI-TokenBar

# Resolve the config dir from the environment — never a hardcoded user path.
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    CFG="$CLAUDE_CONFIG_DIR"
elif [ -n "${HOME:-}" ]; then
    CFG="$HOME/.claude"
else
    echo "Cannot locate your home directory. Set CLAUDE_CONFIG_DIR and retry." >&2
    exit 1
fi

command -v perl >/dev/null 2>&1 || { echo "perl is required (JSON::PP is a core module)." >&2; exit 1; }

mkdir -p "$CFG"

# Install from the latest release, the same ref the updater follows. Installing from
# main instead would hand you code newer than any release and then let the updater
# quietly walk you back to the older tag on its first run. No release yet means main
# is all there is, which is the honest fallback for a repo that has not cut one.
fetch_ref() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 15 -A 'ClaudeCodeCLI-TokenBar-installer'             "https://api.github.com/repos/$OWNER/$NAME/releases/latest" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout=15 -U 'ClaudeCodeCLI-TokenBar-installer'             "https://api.github.com/repos/$OWNER/$NAME/releases/latest" 2>/dev/null
    fi
}
REF=$(fetch_ref | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*//p' | head -n 1 || true)
[ -z "$REF" ] && REF=main
REPO="https://raw.githubusercontent.com/$OWNER/$NAME/$REF"

SCRIPT="$CFG/statusline.sh"
UPDATER="$CFG/tokenbar-update.sh"
USERCFG="$CFG/tokenbar-config.sh"
SETTINGS="$CFG/settings.json"

get() { # url dest
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" "$1"
    else
        echo "Need curl or wget." >&2; exit 1
    fi
}

echo "Config dir : $CFG"
if [ "$REF" = main ]; then
    echo "Version    : main (no tagged release published yet)"
else
    echo "Version    : $REF"
fi
echo "Downloading statusline.sh ..."
get "$REPO/statusline.sh" "$SCRIPT"
chmod +x "$SCRIPT"
get "$REPO/tokenbar-update.sh" "$UPDATER"
chmod +x "$UPDATER"

# Only when absent. This file is where thresholds get tuned, and the whole point of
# keeping it out of statusline.sh is that neither an upgrade nor a reinstall is
# allowed to overwrite it.
if [ -f "$USERCFG" ]; then
    echo "Kept       : tokenbar-config.sh (your overrides, left untouched)"
else
    get "$REPO/tokenbar-config.sh" "$USERCFG"
    echo "Created    : tokenbar-config.sh (all defaults, commented out)"
fi

# Back up before touching settings, to a name that never overwrites an older backup.
if [ -f "$SETTINGS" ]; then
    i=1
    while [ -e "$SETTINGS.bak.$i" ]; do i=$((i + 1)); done
    cp "$SETTINGS" "$SETTINGS.bak.$i"
    echo "Backed up  : settings.json.bak.$i"
fi

# An empty third argument tells the perl below to leave hooks alone entirely.
if [ -n "${TOKENBAR_NO_AUTOUPDATE:-}" ]; then HOOKARG=""; else HOOKARG="$UPDATER"; fi

# Merge, don't overwrite: settings.json holds plugins, permissions and hooks that
# must survive. canonical+pretty keeps the file readable and diffable afterwards.
perl -MJSON::PP -e '
my ($file, $cmd, $upd) = @ARGV;
$upd = "" unless defined $upd;
my $j = {};
if (-e $file) {
    open my $fh, "<", $file or die "read $file: $!";
    local $/; my $c = <$fh>; close $fh;
    $c =~ s/^\xEF\xBB\xBF//;
    $j = eval { JSON::PP->new->decode($c) } || {};
}
$j->{statusLine} = { type => "command", command => $cmd };
if (length $upd) {
    # hooks is a shared, nested structure - other plugins keep their own entries in
    # it - so it is merged rather than replaced, and any entry this installer added
    # before is dropped first so re-running does not stack a second copy.
    #
    # matcher startup only: resume, clear and compact all fire SessionStart too, and
    # there is nothing to gain from re-checking on every one of them.
    my $ss = $j->{hooks}{SessionStart} || [];
    $ss = [ grep { !grep { ($_->{command} || "") =~ /tokenbar-update/ } @{ $_->{hooks} || [] } } @$ss ];
    push @$ss, { matcher => "startup",
                 hooks => [ { type => "command", command => "sh \"$upd\"" } ] };
    $j->{hooks}{SessionStart} = $ss;
}
open my $out, ">", $file or die "write $file: $!";
print $out JSON::PP->new->pretty->canonical->encode($j);
close $out;
' "$SETTINGS" "$SCRIPT" "$HOOKARG"
echo "Wired into : settings.json"
if [ -n "${TOKENBAR_NO_AUTOUPDATE:-}" ]; then
    echo "Skipped    : auto-update hook (TOKENBAR_NO_AUTOUPDATE is set)"
else
    echo "Auto-update: on, once a day, tagged releases only"
fi

# Seed the updater's bookkeeping with what was just installed, so its first run does
# not re-download the very same release. Two lines: epoch, then tag.
if [ "$REF" != main ]; then
    printf '%s
%s
' "$(date +%s)" "$REF" > "$CFG/.tokenbar-state"
fi

# Smoke test with a synthetic payload, so the install proves itself.
echo
echo "Preview:"
R5=$(perl -e 'my @t=gmtime(time+6420); printf "%04d-%02d-%02dT%02d:%02d:%02dZ",$t[5]+1900,$t[4]+1,$t[3],$t[2],$t[1],$t[0]')
R7=$(perl -e 'my @t=gmtime(time+217800); printf "%04d-%02d-%02dT%02d:%02d:%02dZ",$t[5]+1900,$t[4]+1,$t[3],$t[2],$t[1],$t[0]')
printf '{"cwd":"%s","model":{"id":"claude-opus-5[1m]","display_name":"Opus 5"},"workspace":{"current_dir":"%s"},"context_window":{"context_window_size":1000000,"used_percentage":38},"rate_limits":{"five_hour":{"used_percentage":66,"resets_at":"%s"},"seven_day":{"used_percentage":58,"resets_at":"%s"}}}' \
    "$PWD" "$PWD" "$R5" "$R7" | sh "$SCRIPT"
echo
echo
echo "Done. Restart Claude Code to see it."
echo "Customise    : edit $USERCFG"
echo "               Everything is listed there, commented out. It survives updates."
echo "Stop updates : touch $CFG/.tokenbar-noupdate"
echo "Update log   : $CFG/.tokenbar-update.log (only written when one fails)"
