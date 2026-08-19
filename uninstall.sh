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
UPDATER="$CFG/tokenbar-update.sh"
USERCFG="$CFG/tokenbar-config.sh"
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
my $dirty = 0;
my $status = "absent";
if (defined $cmd && index($cmd, $script) >= 0) {
    delete $j->{statusLine};
    $dirty = 1; $status = "removed";
} elsif (defined $cmd) {
    $status = "kept\t$cmd";
}
# Drop only our own SessionStart entry. Other plugins keep theirs in the same
# array, and PreToolUse and friends live in the same object.
my @notes;
if (ref $j->{hooks} eq "HASH" && ref $j->{hooks}{SessionStart} eq "ARRAY") {
    my $ss = $j->{hooks}{SessionStart};
    my @keep = grep { !grep { ($_->{command} || "") =~ /tokenbar-update/ } @{ $_->{hooks} || [] } } @$ss;
    if (@keep != @$ss) {
        if (@keep) { $j->{hooks}{SessionStart} = \@keep }
        else {
            # An empty array is litter, and so is an empty hooks object once that
            # array was the only thing left in it.
            delete $j->{hooks}{SessionStart};
            delete $j->{hooks} unless keys %{ $j->{hooks} };
        }
        $dirty = 1; push @notes, "hook";
    }
}
if ($dirty) {
    open my $out, ">", $file or die "write $file: $!";
    print $out JSON::PP->new->pretty->canonical->encode($j);
    close $out;
}
print $status . (@notes ? "\n" . join(",", @notes) : "");
' "$SETTINGS" "$SCRIPT")

    notes=$(printf '%s' "$result" | sed -n 2p)
    result=$(printf '%s' "$result" | sed -n 1p)
    case "$result" in
        removed) echo "Removed    : statusLine from settings.json" ;;
        kept*)   echo "Kept       : statusLine points somewhere else, left untouched"
                 echo "             $(printf '%s' "$result" | cut -f2)" ;;
        *)       echo "Nothing    : no statusLine in settings.json" ;;
    esac
    case "$notes" in *hook*) echo "Removed    : auto-update hook from settings.json" ;; esac
else
    echo "Nothing    : no settings.json found"
fi

for f in "$SCRIPT" "$UPDATER" "$SCRIPT.bak" "$UPDATER.bak" \
         "$CFG/.tokenbar-state" "$CFG/.tokenbar-update.log" "$CFG/.tokenbar-noupdate"; do
    if [ -e "$f" ]; then rm -f "$f"; echo "Deleted    : ${f##*/}"; fi
done

# The overrides file is the one thing here that can hold work you did. It is only
# deleted when every line in it is still a comment, which means nothing was ever
# set and there is nothing to lose.
if [ -f "$USERCFG" ]; then
    # wc, not grep -c: grep prints 0 and *also* exits 1 when nothing matches, so a
    # `|| echo 0` fallback appends a second zero and the -gt test below blows up.
    live=$(grep -Ev '^[[:space:]]*(#|$)' "$USERCFG" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$live" -gt 0 ]; then
        echo "Kept       : tokenbar-config.sh has $live active line(s), left in place"
        echo "             $USERCFG"
    else
        rm -f "$USERCFG"
        echo "Deleted    : tokenbar-config.sh (nothing was overridden in it)"
    fi
fi

DUMP="${TMPDIR:-/tmp}/claude-statusline-payload.json"
if [ -f "$DUMP" ]; then rm -f "$DUMP"; echo "Deleted    : debug payload dump"; fi

echo
echo "Done. Restart Claude Code."
echo "Backups kept at $SETTINGS.bak.* if you need an earlier state."
