#!/bin/sh
# ClaudeCodeCLI-TokenBar installer (Linux / macOS)
#   curl -fsSL https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main/install.sh | sh
# Touches only files under the Claude config dir, and backs up settings.json first.

set -eu
REPO='https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main'

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
SCRIPT="$CFG/statusline.sh"
SETTINGS="$CFG/settings.json"

echo "Config dir : $CFG"
echo "Downloading statusline.sh ..."
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$REPO/statusline.sh" -o "$SCRIPT"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$SCRIPT" "$REPO/statusline.sh"
else
    echo "Need curl or wget." >&2; exit 1
fi
chmod +x "$SCRIPT"

# Back up before touching settings, to a name that never overwrites an older backup.
if [ -f "$SETTINGS" ]; then
    i=1
    while [ -e "$SETTINGS.bak.$i" ]; do i=$((i + 1)); done
    cp "$SETTINGS" "$SETTINGS.bak.$i"
    echo "Backed up  : settings.json.bak.$i"
fi

# Merge, don't overwrite: settings.json holds plugins, permissions and hooks that
# must survive. canonical+pretty keeps the file readable and diffable afterwards.
perl -MJSON::PP -e '
my ($file, $cmd) = @ARGV;
my $j = {};
if (-e $file) {
    open my $fh, "<", $file or die "read $file: $!";
    local $/; my $c = <$fh>; close $fh;
    $c =~ s/^\xEF\xBB\xBF//;
    $j = eval { JSON::PP->new->decode($c) } || {};
}
$j->{statusLine} = { type => "command", command => $cmd };
open my $out, ">", $file or die "write $file: $!";
print $out JSON::PP->new->pretty->canonical->encode($j);
close $out;
' "$SETTINGS" "$SCRIPT"
echo "Wired into : settings.json"

# Smoke test with a synthetic payload, so the install proves itself.
echo
echo "Preview:"
R5=$(perl -e 'my @t=gmtime(time+6420); printf "%04d-%02d-%02dT%02d:%02d:%02dZ",$t[5]+1900,$t[4]+1,$t[3],$t[2],$t[1],$t[0]')
R7=$(perl -e 'my @t=gmtime(time+453600); printf "%04d-%02d-%02dT%02d:%02d:%02dZ",$t[5]+1900,$t[4]+1,$t[3],$t[2],$t[1],$t[0]')
printf '{"cwd":"%s","model":{"id":"claude-opus-5[1m]","display_name":"Opus 5"},"workspace":{"current_dir":"%s"},"context_window":{"context_window_size":1000000,"used_percentage":38},"rate_limits":{"five_hour":{"used_percentage":66,"resets_at":"%s"},"seven_day":{"used_percentage":58,"resets_at":"%s"}}}' \
    "$PWD" "$PWD" "$R5" "$R7" | sh "$SCRIPT"
echo
echo
echo "Done. Restart Claude Code to see it."
echo "Customise: edit $SCRIPT — the toggle block is at the top."
