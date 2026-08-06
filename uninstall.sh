#!/bin/sh
# ClaudeCodeCLI-TokenBar uninstaller (Linux / macOS)
#   curl -fsSL https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main/uninstall.sh | sh
# Removes only what the installer added. Backs up settings.json first, and leaves
# every settings.json.bak.* in place so an earlier state can still be restored.

set -eu

# Resolve the config dir from the environment - never a hardcoded user path.
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    CFG="$CLAUDE_CONFIG_DIR"
elif [ -n "${HOME:-}" ]; then
    CFG="$HOME/.claude"
else
    echo "Cannot locate your home directory. Set CLAUDE_CONFIG_DIR and retry." >&2
    exit 1
fi

command -v perl >/dev/null 2>&1 || { echo "perl is required (JSON::PP is a core module)." >&2; exit 1; }

SCRIPT="$CFG/statusline.sh"
SETTINGS="$CFG/settings.json"
echo "Config dir : $CFG"

if [ -f "$SETTINGS" ]; then
    i=1
    while [ -e "$SETTINGS.bak.$i" ]; do i=$((i + 1)); done
    cp "$SETTINGS" "$SETTINGS.bak.$i"
    echo "Backed up  : settings.json.bak.$i"

    # Only drop statusLine if it actually points at our script. Someone may have
    # switched to a different statusline since installing, and blowing that away
    # would be destroying config this tool never owned.
    result=$(perl -MJSON::PP -e '
my ($file, $script) = @ARGV;
open my $fh, "<", $file or die "read $file: $!";
local $/; my $c = <$fh>; close $fh;
$c =~ s/^\xEF\xBB\xBF//;
my $j = eval { JSON::PP->new->decode($c) } || {};
my $cmd = ref $j->{statusLine} eq "HASH" ? $j->{statusLine}{command} : undef;
if (defined $cmd && index($cmd, $script) >= 0) {
    delete $j->{statusLine};
    open my $out, ">", $file or die "write $file: $!";
    print $out JSON::PP->new->pretty->canonical->encode($j);
    close $out;
    print "removed";
} elsif (defined $cmd) {
    print "kept\t$cmd";
} else {
    print "absent";
}
' "$SETTINGS" "$SCRIPT")

    case "$result" in
        removed) echo "Removed    : statusLine from settings.json" ;;
        kept*)   echo "Kept       : statusLine points somewhere else, left untouched"
                 echo "             $(printf '%s' "$result" | cut -f2)" ;;
        *)       echo "Nothing    : no statusLine in settings.json" ;;
    esac
else
    echo "Nothing    : no settings.json found"
fi

if [ -f "$SCRIPT" ]; then
    rm -f "$SCRIPT"
    echo "Deleted    : statusline.sh"
fi

DUMP="${TMPDIR:-/tmp}/claude-statusline-payload.json"
if [ -f "$DUMP" ]; then rm -f "$DUMP"; echo "Deleted    : debug payload dump"; fi

echo
echo "Done. Restart Claude Code."
echo "Backups kept at $SETTINGS.bak.* if you need an earlier state."
