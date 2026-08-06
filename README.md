# ClaudeCodeCLI-TokenBar

Two-line Claude Code statusline. Context window and account quota as usage bars.

```
[CAVEMAN] | [PONYTAIL] | Opus 5 | my-project | main ↑2 +42/-7 ?1
ctx ███▊░░░░░░  38%    ·    5h ██████▌░░░  66%   ↻ 1h 46m    ·    7d █████▊░░░░  58%   ↻ 5d 05h 12m   ×2.3
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

Removes the script and its `statusLine` entry, nothing else. If you've since
pointed `statusLine` at a different tool, it says so and leaves it alone rather
than deleting config it never owned. Backups stay at `settings.json.bak.*`.

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
| `5h` | absolute %, five fixed bands | 5-hour window, work comes in bursts — a rate figure would just jitter |
| `7d` | burn **pace** vs the weekly allowance | tells you if you're on track to survive the week, not just how much is gone |

`ctx` can go back down (`/compact`, new session). Quotas only climb until they reset —
that's why the `↻` countdown sits on the quota bars, not on `ctx`.

### ctx thresholds

| Window | yellow | red | purple |
|---|---|---|---|
| ≤200k | 50% | 70% | 85% |
| ≤500k | 40% | 60% | 80% |
| ≤800k | 30% | 55% | 80% |
| >800k | 20% | 50% | 80% |

Between yellow and red, six gradient steps. On a 1M window those land on 20/25/30/35/40/45%.

### 5h bands

green <40% · amber 40% · yellow 60% · **red 80%** · **purple 95% ⚠**

### 7d pace

`×2.1` next to the bar is the multiplier driving the colour:

```
pace = used% / (elapsed fraction of the window × 100)
```

`×1.0` means dead on the 1/7-per-day allowance. green ≤1× · yellow >1× · **red >2×** · **purple >3× ⚠**

Two corrections built in, because pace alone lies at both ends of a window:

- **First 10% elapsed**: no pace colour. The divisor is too small — 3% used in the first hour computes as ×5 and would flash purple for nothing.
- **Absolute floor**: ≥85% used is at least red, ≥95% purple, whatever the pace says. 95% used on day 6.9 is a respectable ×0.97, and also almost nothing left.

## Customise

Toggle block sits at the top of the installed script — `~/.claude/statusline.ps1` or
`~/.claude/statusline.sh`. Flip a segment off, change `barWidth`, move a threshold,
edit the colour ramps.

Segments: `caveman` `ponytail` `model` `dir` `branch` `gitAhead` `gitLines` `gitUntrk`
`context` `quota5h` `quota7d` `pace`
(shell script uses the same names as `SHOW_CAVEMAN`, `SHOW_GITLINES`, …)

Every git segment hides itself when there's nothing to say, so a clean tree on an
up-to-date branch renders as just `main`. Turn `gitLines` off and the old `main*`
dirty marker comes back instead.

## Requirements

- Claude Code 2.x
- Windows: PowerShell 5.1+ (built in)
- Linux/macOS: `perl` (`JSON::PP` and `Time::Local` are core — nothing to install) and `awk`
- A font with eighth-block glyphs `▏▎▍▌▋▊▉` — Cascadia Code, JetBrains Mono, any Nerd Font

## Notes

`rate_limits` is only in the payload on plans that report quotas. Without it the 5h and
7d bars simply don't render — no fake zeros. To see what your build sends, set
`CLAUDE_STATUSLINE_DEBUG=1` and read the payload dump from your temp dir.

The 7d pace math assumes the weekly window is 7 days long and `resets_at` is its end.
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

caveman's `wenyan-lite` / `wenyan-ultra` map to the lite/ultra tiers; its one-shot
modes (`commit`, `review`, `compress`) read as full.
