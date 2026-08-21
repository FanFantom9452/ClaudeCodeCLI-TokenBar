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
# Only the two ends are named; every ramp below spells its colours out as cube
# indices, so changing these two moves only the gates.
# $RED = 196; $PURPLE = 201
# $CTRACK = 240; $DIM = 240

# ---- ctx: thresholds tiered by window size ------------------------------
# First tier whose maxWindow covers the model's window wins. A flat
# 20%-is-yellow rule punishes small windows: 20% of 200k is 40k, which is nothing.
# $ctxTiers = @(
#     @{ maxWindow = 200000; purple = 85; steps = @(
#         @{ at =   0; color =  46 }
#         @{ at =  10; color =  83 }
#         @{ at =  20; color = 120 }
#         @{ at =  30; color = 157 }
#         @{ at =  40; color = 194 }
#         @{ at =  45; color = 190 }
#         @{ at =  50; color = 226 }
#         @{ at =  55; color = 220 }
#         @{ at =  60; color = 214 }
#         @{ at =  65; color = 208 }
#         @{ at =  70; color = 196; bold = $true }
#         @{ at =  75; color = 198; bold = $true }
#         @{ at =  80; color = 200; bold = $true }
#     ) }
#     @{ maxWindow = 500000; purple = 80; steps = @(
#         @{ at =   0; color =  46 }
#         @{ at =   8; color =  83 }
#         @{ at =  16; color = 120 }
#         @{ at =  24; color = 157 }
#         @{ at =  32; color = 194 }
#         @{ at =  36; color = 190 }
#         @{ at =  40; color = 226 }
#         @{ at =  45; color = 220 }
#         @{ at =  50; color = 214 }
#         @{ at =  55; color = 208 }
#         @{ at =  60; color = 196; bold = $true }
#         @{ at =  65; color = 198; bold = $true }
#         @{ at =  70; color = 199; bold = $true }
#         @{ at =  75; color = 200; bold = $true }
#     ) }
#     @{ maxWindow = 800000; purple = 80; steps = @(
#         @{ at =   0; color =  46 }
#         @{ at =   6; color =  83 }
#         @{ at =  12; color = 120 }
#         @{ at =  18; color = 157 }
#         @{ at =  24; color = 194 }
#         @{ at =  27; color = 190 }
#         @{ at =  30; color = 226 }
#         @{ at =  36; color = 220 }
#         @{ at =  42; color = 214 }
#         @{ at =  48; color = 208 }
#         @{ at =  55; color = 196; bold = $true }
#         @{ at =  62; color = 198; bold = $true }
#         @{ at =  70; color = 199; bold = $true }
#         @{ at =  75; color = 200; bold = $true }
#     ) }
#     @{ maxWindow = [double]::MaxValue; purple = 80; marks = $ctxMarks; steps = @(
#         @{ at =   0; color =  46 }
#         @{ at =   5; color =  83 }
#         @{ at =  10; color = 120 }
#         @{ at =  15; color = 157 }
#         @{ at =  20; color = 194 }
#         @{ at =  25; color = 193 }
#         @{ at =  30; color = 192 }
#         @{ at =  35; color = 190 }
#         @{ at =  40; color = 226 }
#         @{ at =  45; color = 214 }
#         @{ at =  50; color = 196; bold = $true }
#         @{ at =  55; color = 197; bold = $true }
#         @{ at =  60; color = 198; bold = $true }
#         @{ at =  65; color = 199; bold = $true }
#         @{ at =  70; color = 200; bold = $true }
#         @{ at =  75; color = 201; bold = $true }
#     ) }
# )

# Glyph ladder. Only a tier carrying `marks` uses one; the rest keep a single
# warning at their purple threshold. Drop the `marks` entry above to turn the
# ladder off entirely, or redefine the rungs here.
# $ctxMarks = @(
#     @{ at = 50; glyph = "$WARN" }
#     @{ at = 65; glyph = "$BOOM" }
#     @{ at = 75; glyph = "$BOOM$BOOM" }
#     @{ at = 85; glyph = "$BOOM$BOOM$BOOM" }
#     @{ at = 90; glyph = "$SKULL" }
# )

# ---- 5h: five fixed bands ------------------------------------------------
# $ramp5h = @(
#     @{ at =   0; color =  46; sev = 0.0 }
#     @{ at =  10; color =  83; sev = 0.2 }
#     @{ at =  20; color = 120; sev = 0.4 }
#     @{ at =  30; color = 157; sev = 0.6 }
#     @{ at =  40; color = 194; sev = 0.8 }
#     @{ at =  45; color = 193; sev = 1.0 }
#     @{ at =  50; color = 192; sev = 1.2 }
#     @{ at =  55; color = 190; sev = 1.4 }
#     @{ at =  60; color = 226; sev = 1.6 }
#     @{ at =  65; color = 220; sev = 1.8 }
#     @{ at =  70; color = 214; sev = 2.0 }
#     @{ at =  75; color = 208; sev = 2.2 }
#     @{ at =  80; color = 196; bold = $true; sev = 2.4 }
#     @{ at =  85; color = 197; bold = $true; sev = 2.6 }
#     @{ at =  90; color = 199; bold = $true; sev = 2.8 }
#     @{ at =  95; color = $PURPLE; sev = 4; bold = $true; mark = "$WARN" }
# )

# ---- 7d: pace only -------------------------------------------------------
# The bar is coloured by deviation from the even 1/7-per-day line and by nothing
# else, so a 90% week that is still on pace stays green. Both halves gradient:
# saturated green when a day is banked, palest green on the line, then yellow,
# red from +7, reddening into the purple gate. $devRamp is rebuilt from
# $devSteps below it — override $devSteps and the rebuild loop together.
# $dev7dPurple = 14
# $devSteps = @(
#     @{ at = [double]::MinValue; color =  46 }
#     @{ at = -10; color =  83 }
#     @{ at =  -7; color = 120 }
#     @{ at =  -3; color = 157 }
#     @{ at =   0; color = 194 }
#     @{ at =   1; color = 193 }
#     @{ at =   2; color = 192 }
#     @{ at =   3; color = 191 }
#     @{ at =   4; color = 190 }
#     @{ at =   5; color = 226 }
#     @{ at =   6; color = 214 }
#     @{ at =   7; color = 202 }
#     @{ at =   8; color = 196 }
#     @{ at =   9; color = 197 }
#     @{ at =  10; color = 198 }
#     @{ at =  11; color = 199 }
#     @{ at =  12; color = 200 }
#     @{ at =  13; color = 201 }
# )
# $devRamp = @()
# foreach ($s in $devSteps) {
#     $sev = 0
#     if ($s.at -ge 0) { $sev = 1 + $s.at / ($dev7dPurple + 1) }
#     $devRamp += @{ at = $s.at; color = $s.color; sev = $sev }
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
#
# A palette may carry extra keys named for the exact mode word, which is how a
# plugin whose flag holds a state rather than a level gets a colour that moves.
# The exact word wins; the four tiers stay as the fallback for anything else.
# $badgeColors.review = @{ off = 240; lite = 245; full = 250; ultra = 255
#                          draft = 60; ready = 75; blocked = 196 }

# ---- the lead line -------------------------------------------------------
# An optional third line above everything, owned by one plugin. Nothing renders
# unless $leadPlugin names one AND that plugin has written
# modes/<session_id>/<name>.lead, so leaving this empty costs one Test-Path.
#
# The colour comes from that plugin's own palette below, keyed by the word, so a
# stage ramp configured once serves both the lead line and the badge. A plugin
# that owns the lead line does not also get a badge on line 1.
#
# $leadPlugin = 'review'
# $leadStyle  = 'bar'     # bar -> |REVIEW DRAFT ... ; badge -> [REVIEW:DRAFT] ...
# $leadTitle  = 48        # cells the title column occupies; longer titles are cut
