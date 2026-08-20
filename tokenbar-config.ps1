# ClaudeCodeCLI-TokenBar — per-machine overrides (Windows / PowerShell)
#
# statusline.ps1 defines every value below as a default and then dot-sources this
# file, so whatever you set here wins. The updater replaces statusline.ps1 and
# never touches this file — that separation is the only reason a threshold you
# tune survives an upgrade.
#
# Everything is commented out. Uncomment a line to override it; leave it commented
# to keep the default. A syntax error here is swallowed rather than taking the
# statusline down with it, so if an edit seems to do nothing, run
#   powershell -NoProfile -File "$HOME\.claude\tokenbar-config.ps1"
# and read the error.

# ---- what to show -------------------------------------------------------
# $show.caveman  = $true
# $show.ponytail = $true
# $show.toggles  = $true
# $show.model    = $true
# $show.dir      = $true
# $show.branch   = $true
# $show.gitAhead = $true
# $show.gitLines = $true
# $show.gitUntrk = $true
# $show.context  = $true
# $show.quota5h  = $true
# $show.quota7d  = $true
# $show.delta    = $true

# ---- layout -------------------------------------------------------------
# $barWidth = 10      # cells per bar; shared so the three compare by eye
# $fieldGap = '  '         # between a bar's % and the reset/delta that follow it
# $segGap   = '  '         # each side of $segSep; separator plus both gaps should
#                          # stay wider than $fieldGap or the grouping reads backwards
# $segSep   = [char]0x2502 # what sits between two bars. [char]0xB7 is the mid-dot,
#                          # which needs a wider $segGap (4) to read as a separator

# ---- palette (256-colour indices) ---------------------------------------
# $GREEN = 108; $AMBER = 179; $YELLOW = 226; $RED = 196; $PURPLE = 201
# $CTRACK = 240; $DIM = 240

# ---- ctx: thresholds tiered by window size ------------------------------
# First tier whose maxWindow covers the model's window wins. A flat
# 20%-is-yellow rule punishes small windows: 20% of 200k is 40k, which is nothing.
# $ctxTiers = @(
#     @{ maxWindow =  200000; amber = 50; red = 70; purple = 85 }
#     @{ maxWindow =  500000; amber = 40; red = 60; purple = 80 }
#     @{ maxWindow =  800000; amber = 30; red = 55; purple = 80 }
#     @{ maxWindow = [double]::MaxValue; amber = 20; red = 50; purple = 80; marks = $ctxMarks }
# )
# $ctxGradient = @(226, 220, 214, 208, 202, 203)

# Glyph ladder. Only a tier carrying `marks` uses one; the rest keep a single
# warning at their purple threshold. Drop the `marks` entry above to turn the
# ladder off entirely, or redefine the rungs here.
# $ctxMarks = @(
#     @{ at = 50; glyph = "$WARN" }
#     @{ at = 60; glyph = "$SKULL" }
#     @{ at = 70; glyph = "$BOOM" }
#     @{ at = 80; glyph = "$BOOM$BOOM" }
#     @{ at = 90; glyph = "$BOOM$BOOM$BOOM" }
# )

# ---- 5h: five fixed bands ------------------------------------------------
# $ramp5h = @(
#     @{ at =  0; color = $GREEN;  sev = 0 }
#     @{ at = 40; color = $AMBER;  sev = 1 }
#     @{ at = 60; color = $YELLOW; sev = 2 }
#     @{ at = 80; color = $RED;    sev = 3; bold = $true }
#     @{ at = 95; color = $PURPLE; sev = 4; bold = $true; mark = "$WARN" }
# )

# ---- 7d: pace only -------------------------------------------------------
# The bar is coloured by deviation from the even 1/7-per-day line and by nothing
# else, so a 90% week that is still on pace stays green. Rebuild $devRamp if you
# change $dev7dPurple or $devGradient — it is computed, not declared.
# $dev7dPurple = 14
# $devGradient = @(40, 76, 112, 148, 184, 220, 214, 208, 202)
# $devRamp = @(@{ at = [double]::MinValue; color = $GREEN; sev = 0 })
# for ($i = 0; $i -lt $devGradient.Count; $i++) {
#     $devRamp += @{ at    = $i * ($dev7dPurple / $devGradient.Count)
#                    color = $devGradient[$i]
#                    sev   = 1 + ($i + 1) / ($devGradient.Count + 1) }
# }
# $devRamp += @{ at = $dev7dPurple; color = $PURPLE; sev = 4; bold = $true; mark = "$WARN" }

# No resets_at means no pace to judge. Grey, never green: "no reading" and
# "on budget" must not look alike.
# $dev7dUnknown = @{ color = 245; sev = 0 }

# The one absolute rule left on this bar. At 100% the quota is gone and the
# deviation has stopped meaning anything — spend exactly on the line all week and
# you arrive at 100% with a deviation of 0, which the ramp would paint green while
# you are locked out. $null switches the exception off.
# $hardStop7d  = 100
# $exhausted7d = @{ color = $PURPLE; sev = 4; bold = $true; mark = "$WARN" }

# ---- plugin badges -------------------------------------------------------
# $badgeColors.caveman  = @{ off = 240; lite = 137; full = 172; ultra = 208 }
# $badgeColors.ponytail = @{ off = 240; lite =  65; full = 108; ultra =  84 }
# $badgeColors.default  = @{ off = 240; lite = 245; full = 250; ultra = 255 }
