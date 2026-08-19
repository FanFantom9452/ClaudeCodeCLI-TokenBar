# ClaudeCodeCLI-TokenBar — per-machine overrides (Linux / macOS)
#
# statusline.sh defines every value below as a default and then sources this file,
# so whatever you set here wins. The updater replaces statusline.sh and never
# touches this file — that separation is the only reason a threshold you tune
# survives an upgrade.
#
# Everything is commented out. Uncomment a line to override it; leave it commented
# to keep the default. This is sourced by /bin/sh, so keep it POSIX.

# ---- what to show -------------------------------------------------------
# SHOW_CAVEMAN=1
# SHOW_PONYTAIL=1
# SHOW_TOGGLES=1
# SHOW_MODEL=1
# SHOW_DIR=1
# SHOW_BRANCH=1
# SHOW_GITAHEAD=1
# SHOW_GITLINES=1
# SHOW_GITUNTRK=1
# SHOW_CONTEXT=1
# SHOW_QUOTA5H=1
# SHOW_QUOTA7D=1
# SHOW_DELTA=1

# ---- layout -------------------------------------------------------------
# BAR_WIDTH=10
# FIELD_GAP="   "
# SEG_GAP="    "

# ---- ctx: thresholds tiered by window size ------------------------------
# maxwindow:amber:red:purple, first tier covering the window wins. A flat
# 20%-is-yellow rule punishes small windows: 20% of 200k is 40k, which is nothing.
# CTX_TIERS="200000:50:70:85,500000:40:60:80,800000:30:55:80,999999999:20:50:80"
# CTX_GRADIENT="226,220,214,208,202,203"

# Glyph ladder, applied only to windows larger than CTX_MARK_MINWINDOW. Smaller
# windows keep a single warning glyph at their purple threshold. Set CTX_MARKS
# empty to turn the ladder off, or raise CTX_MARK_MINWINDOW out of reach.
# CTX_MARKS="50:⚠,60:💀,70:💥,80:💥💥,90:💥💥💥"
# CTX_MARK_MINWINDOW=800000

# ---- 5h: five fixed bands, at:colour:bold --------------------------------
# RAMP_5H="0:108:0,40:179:0,60:226:0,80:196:1,95:201:1"
# RAMP_5H_MARK=95

# ---- 7d: pace only -------------------------------------------------------
# The bar is coloured by deviation from the even 1/7-per-day line and by nothing
# else, so a 90% week that is still on pace stays green.
# DEV_GRADIENT="40,76,112,148,184,220,214,208,202"
# DEV_7D_PURPLE=14      # a day's share of the week, rounded to where digits flip
# DEV_7D_UNKNOWN=245    # no resets_at means no pace to judge: grey, never green

# The one absolute rule left on this bar. At 100% the quota is gone and the
# deviation has stopped meaning anything. Set empty to switch the exception off.
# HARD_STOP_7D=100

# PURPLE_COL=201
# WARN_GLYPH="⚠"
