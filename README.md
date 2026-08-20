# ClaudeCodeCLI-TokenBar

Two-line Claude Code statusline. Context window and account quota as usage bars.

```
[CAVEMAN:FULL] | [PONYTAIL:FULL] | Opus 5 | my-project | main ↑2 +42/-7 ?1
ctx ███▊░░░░░░  38%  │  5h ██████▌░░░  66%  ↻ 1h 46m  │  7d █████▊░░░░  58%  ↻ 2d 12h 30m   -6%
```

## Install

**Windows** — one command, works in both CMD and PowerShell:

```
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main/install.ps1 | iex"
```

**Linux / macOS**:

```sh
curl -fsSL https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main/install.sh | sh
```

Already in PowerShell and want it shorter? `irm <the install.ps1 URL> | iex` does the
same thing. The longer form is listed first because it's the one that works wherever
you happen to be — CMD, PowerShell, or a `Win+R` box — without you having to check
which shell you're in first.

Restart Claude Code afterwards. The installer finds your home directory itself,
backs up `settings.json` before merging, and prints a preview to prove it works.

The bootstrap URL points at `main` because it has to point at something stable, but
what it *installs* is the **latest tagged release** — the installer asks GitHub for
that tag first and downloads the statusline from it. That is the same ref
[auto-update](#auto-update) follows, so a fresh install and an updated one land on
the same code. Until a release exists it falls back to `main` and says so in its
`Version :` line.

Prefer to read before running? `curl -fsSL <the install.sh URL> -o install.sh`, read it, then `sh install.sh`.

## Uninstall

**Windows** — CMD or PowerShell:

```
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main/uninstall.ps1 | iex"
```

**Linux / macOS:**

```sh
curl -fsSL https://raw.githubusercontent.com/FanFantom9452/ClaudeCodeCLI-TokenBar/main/uninstall.sh | sh
```

Removes the script, the updater, its `statusLine` entry and its `SessionStart` hook —
nothing else. Other plugins' hooks in the same arrays are left alone. If you've since
pointed `statusLine` at a different tool, it says so and leaves it alone rather than
deleting config it never owned. `tokenbar-config.*` survives if you actually set
something in it. Backups stay at `settings.json.bak.*`.

## Line 1: git state

```
main                  clean
main +42/-7           42 lines added, 7 removed, not committed yet
main ?1               one untracked file
main ↑2               two commits not pushed
main ↑2 +42/-7 ?1     all of it
```

`+42/-7` is `git diff HEAD` — staged and unstaged together, so it answers "what
would I lose right now". Untracked files show separately as `?1` because no diff
counts them, and a new file you haven't `git add`ed would otherwise look like a
clean tree.

Deliberately **not** the session's line count that Claude Code reports. That number
covers everything changed this session including work already committed, and it
resets when the session does. This one tracks what's still uncommitted, which is
the thing that can actually bite you.

There's no cost figure on purpose. On a subscription plan the payload's
`total_cost_usd` is a notional API-equivalent price, not money being charged, and
putting a `$` on screen reads like a meter running.

### It does not touch your repo

Both git calls use `--no-optional-locks`. Without it, a plain `git status` refreshes
the index stat cache — which rewrites `.git/index` and briefly holds
`.git/index.lock`. Harmless once; run on every statusline render it means the tool
is writing to your repo constantly and can race your own git commands with
`Unable to create index.lock`. The flag exists for exactly this use case.

Verified: rendering both versions against a repo leaves `.git/index` mtime unchanged
and no lock file behind.

Two subprocesses per render. On a very large repo `git status` is the slow part —
set `branch` to `$false` (`SHOW_BRANCH=0`) and the statusline makes no git calls at all.

## What the three bars mean

Each bar is coloured by a different rule, because each one means something different.

| Bar | Rule | Why |
|---|---|---|
| `ctx` | absolute %, thresholds tiered by window size | 20% of a 1M window is roomy; 20% of 200k is not |
| `5h` | absolute % | 5-hour window, work comes in bursts — a rate figure would just jitter |
| `7d` | how far **ahead of or behind** the even 1/7-per-day line you are — the percentage does not colour it at all | tells you if you're on track to survive the week, not just how much is gone |

`ctx` can go back down (`/compact`, new session). Quotas only climb until they reset —
that's why the `↻` countdown sits on the quota bars, not on `ctx`.

### One green, three bars

All three walk the same path through the 256-colour cube, so the colour means the
same thing wherever you see it:

```
 46  →  83  →  120  →  157  →  194  →  yellow  →  red  →  201
deep green ....... palest green         heating          the gate
```

The greens are one line through the cube: `46` is `r0 g5 b0`, the most saturated
green there is, and each step adds equal red and blue, walking it toward white
without letting the hue drift. **Deep green is room to spare. Palest green is
exactly on budget.** What differs between the bars is only *where* along that path
each percentage lands.

### ctx

Each window size carries its own ramp, because the same percentage means different
things: 20% of a 1M window is 200k — a whole small window — while 20% of 200k is
nothing.

| Window | palest green | yellow | red | purple |
|---|---|---|---|---|
| ≤200k | 40% | 50% | 70% | 85% |
| ≤500k | 32% | 40% | 60% | 80% |
| ≤800k | 24% | 30% | 55% | 80% |
| >800k | 20% | 40% | 50% | 80% |

Between those points the ramp fills in every step, so the bar shades continuously
rather than jumping between four states.

**Glyph ladder, windows over 800k only:**

| ≥50% | ≥65% | ≥75% | ≥85% | ≥90% |
|---|---|---|---|---|
| ⚠ | 💥 | 💥💥 | 💥💥💥 | 💀 |

Smaller windows keep a single ⚠ at their purple threshold. On a 1M window 50% is half
a million tokens and everything after it gets expensive fast, so the escalation earns
its noise. On a 200k window those same percentages are small absolute numbers, and a
skull there would be crying wolf.

### 5h

Same shape, thresholds at palest green 40% · yellow 60% · **red 80%** ·
**purple 95% ⚠**. No deviation figure: the window is only five hours, work arrives in
bursts, and a rate over that span jitters too much to read.

### 7d deviation

The `+2%` / `-10%` beside the bar is how many quota points you're ahead of, or
behind, spending the week evenly:

```
deviation = used% − (elapsed fraction of the window × 100)
```

A week split evenly is 100/7 = **14.3 points per day**. So `-10%` means you've
banked ten points, `±0%` is dead on the line, and `+35%` means you're two and a
half days' worth ahead of schedule.

This bar is coloured by that number and by nothing else — how full it is does not
enter into it. Banked time gets the deep greens, `±0` is the palest, and above the
line it heats up:

| deviation | | |
|---|---|---|
| `+7` | ⚠ | half a day burned ahead of the line — easing off for an afternoon stops being enough |
| `+10` | 💥 | most of a day |
| `+14` | 💀 | a full day ahead of a pace you cannot sustain. Purple, and the gate |

The glyph rides with the `±%` figure rather than the bar's `used%`, because that is
the number it is about.

It's cumulative, not per-day, and that's the point: a heavy Monday followed by
frugal days walks the number back toward zero. A single-day figure would keep
shouting about Monday forever.

Subtraction rather than a ratio also means it needs no special case at the start of
a window. 3% used in the first hour is simply `+3`; a ratio would divide by almost
zero and scream about a 5× overspend.

**There is almost no absolute-percentage rule on this bar**, and that is deliberate.
90% used with twelve hours left and a deviation of `-3` is a week that went exactly to
plan; painting it red for the size of the number tells you nothing the number was not
already telling you. The bar and the `±%` share one colour, because they are the same
reading.

The one exception is **95%**. Past there the deviation has stopped carrying
information: with under a twentieth of the quota left, whether you are marginally
ahead or behind no longer changes what you can do. Spend exactly on the line all week
and you arrive at 95% with a deviation of `0`, which the ramp would paint palest green
while you are nearly locked out. So 95% and up is purple regardless. Set `$hardStop7d`
/ `HARD_STOP_7D` empty to drop even that.

## Customise

Edit `~/.claude/tokenbar-config.ps1` (or `tokenbar-config.sh`). Every threshold,
colour, glyph and toggle is listed there, commented out, with its default. Uncomment
what you want to change.

That file is separate from the statusline for one reason: **the updater overwrites
`statusline.ps1` and never touches your config**. Tune a threshold in the statusline
itself and the next update erases it.

Flip a segment off, change `barWidth`, move a threshold, redefine a colour ramp,
delete the glyph ladder.

### Seeing an edit before you live with it

```
powershell -NoProfile -File preview.ps1     # Windows
sh preview.sh                               # Linux / macOS
```

Renders the real statusline against synthetic payloads across every band — each ctx
tier swept end to end in 5% steps, the same for 5h, every 7d deviation from -14 to
+14, the special cases, and four full lines. It runs the *installed* script, so it
picks your config up exactly as Claude Code would; pass `-Script` / a path argument
to preview a working copy first.

Handy because the states you most want to check are the ones you cannot summon on
demand — nobody wants to burn 90% of a weekly quota to find out whether they like
the colour.

Segments: `caveman` `ponytail` `toggles` `model` `dir` `branch` `gitAhead` `gitLines`
`gitUntrk` `context` `quota5h` `quota7d` `delta`
(shell script uses the same names as `SHOW_CAVEMAN`, `SHOW_GITLINES`, …)

Every git segment hides itself when there's nothing to say, so a clean tree on an
up-to-date branch renders as just `main`. Turn `gitLines` off and the old `main*`
dirty marker comes back instead.

## Auto-update

The installer adds a `SessionStart` hook that keeps the statusline current. It checks
**once a day at most**, and only ever follows **tagged releases** — never `main`.

The hook process itself does nothing but read a local timestamp. Only when a check is
actually due does it detach a worker for the network part, so starting a session never
waits on GitHub.

Before anything replaces a working statusline the download has to clear three gates:
big enough to be the script, recognisably the script, and syntactically valid. The old
file is kept as `statusline.ps1.bak` either way.

| | |
|---|---|
| Turn it off | `touch ~/.claude/.tokenbar-noupdate` |
| Never install it | set `TOKENBAR_NO_AUTOUPDATE=1` before running the installer |
| See why one failed | `~/.claude/.tokenbar-update.log` — only written when something goes wrong |
| Roll back | `~/.claude/statusline.ps1.bak` |

Auto-update is a channel for code to run on your machine. Requiring a deliberate tag
means a half-finished push cannot reach you on its own, and the config file staying
separate means an update cannot quietly revert your thresholds. It is not signed —
the threat model here is a bad commit, not a compromised account. If that is not the
threat model you want, turn it off with the opt-out file above.

The updater replaces `statusline.ps1` only. If the updater itself changes, re-run the
installer.

### Cutting a release

Auto-update reads GitHub's `releases/latest`, which a pushed tag alone does **not**
satisfy — a tag is not a release. Publish one and every installed copy picks it up
within a day:

```sh
git tag -a v1.1.0 -m "what changed"
git push origin v1.1.0
gh release create v1.1.0 --title v1.1.0 --notes "what changed"   # or the web UI
```

Nothing reaches anyone until that last line runs. That is the point of following
releases rather than `main`: publishing is a separate, deliberate act, so a pushed
commit — or a pushed tag you meant to reconsider — cannot ship itself.

## Requirements

- Claude Code 2.x
- Windows: PowerShell 5.1+ (built in)
- Linux/macOS: `perl` (`JSON::PP` and `Time::Local` are core — nothing to install) and `awk`
- A font with eighth-block glyphs `▏▎▍▌▋▊▉` — Cascadia Code, JetBrains Mono, any Nerd Font

## Notes

`rate_limits` is only in the payload on plans that report quotas. Without it the 5h and
7d bars simply don't render — no fake zeros. To see what your build sends, set
`CLAUDE_STATUSLINE_DEBUG=1` and read the payload dump from your temp dir.

The 7d deviation assumes the weekly window is 7 days long and `resets_at` is its end.
If your plan uses a rolling window instead, the elapsed-fraction figure will be off.

The `[CAVEMAN]` and `[PONYTAIL]` badges are for the
[caveman](https://github.com/JuliusBrussee/caveman) and
[ponytail](https://github.com/DietrichGebert/ponytail) plugins. They're read from the
flag file each plugin writes, so if you don't have the plugins there's no flag file
and no badge — you'll never see a tag for something you didn't install.

Each plugin keeps its own hue and the brightness tracks the intensity tier, so the
level reads without parsing the text:

| Tier | caveman | ponytail |
|---|---|---|
| `off` | gray | gray |
| `lite` | tan | dim sage |
| `full` | orange | sage |
| `ultra` | bright orange | bright mint |

caveman's `wenyan-lite` / `wenyan-ultra` map to the lite/ultra tiers. One-shot modes
read as full on both sides — caveman's `commit` / `review` / `compress`, ponytail's
`review`.

### Where the flags are read from

Two layouts, session-scoped first:

```
~/.claude/modes/<session_id>/caveman     ← this window's level
~/.claude/.caveman-active                ← whichever window set it last
```

The stock plugins only write the second one. It has no session key and both plugins
rewrite it to their configured default on every `SessionStart`, so with several
windows open the badge tracks whichever session most recently started or switched
mode — not the one you're looking at. Setting `defaultMode` in each plugin's own
`config.json` at least keeps every window agreeing on the same level.

The first path is what a plugin writes once it keys the flag by session id. When
it's there it wins outright, with no fall back to the global file even if the value
is unreadable: falling back would put another session's level on this window's line,
which is the exact confusion the session-scoped layout exists to end.

### Toggles other than these two

Any file in `modes/<session_id>/` renders as a badge. The filename is the label, the
contents are the level:

```sh
echo ultra > ~/.claude/modes/$SESSION_ID/redteam    # → [REDTEAM:ULTRA]
```

Names outside `[a-z0-9-]`, values longer than 16 characters, symlinks, and files over
64 bytes are all ignored, so a flag can't smuggle escape sequences onto the line.
caveman and ponytail additionally have to name a mode those plugins actually have.

Unknown toggles use a neutral gray-to-white ramp. Give one its own hue by adding an
entry to `$badgeColors` / `colors_for` in the installed script. Turn them all off
with the `toggles` segment; `caveman` and `ponytail` keep their own switches.
