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
# FIELD_GAP="  "
# SEG_GAP="  "     # each side of SEG_SEP; separator plus both gaps should stay
#                  # wider than FIELD_GAP or the grouping reads backwards
# SEG_SEP="│"      # what sits between two bars. "·" needs a wider SEG_GAP (4)
#                  # to read as a separator

# ---- ctx: thresholds tiered by window size ------------------------------
# Pipe separated tiers of maxwindow;purple;ramp, ramp being used%:colour or
# used%:colour:bold, lowest first. First tier covering the window wins. A flat
# 20%-is-yellow rule punishes small windows: 20% of 200k is 40k, which is nothing.
# CTX_TIERS="200000;85;0:46,10:83,20:120,30:157,40:194,45:190,50:226,55:220,60:214,65:208,70:196:1,75:198:1,80:200:1|500000;80;0:46,8:83,16:120,24:157,32:194,36:190,40:226,45:220,50:214,55:208,60:196:1,65:198:1,70:199:1,75:200:1|800000;80;0:46,6:83,12:120,18:157,24:194,27:190,30:226,36:220,42:214,48:208,55:196:1,62:198:1,70:199:1,75:200:1|999999999;80;0:46,5:83,10:120,15:157,20:194,25:193,30:192,35:190,40:226,45:214,50:196:1,55:197:1,60:198:1,65:199:1,70:200:1,75:201:1"

# Glyph ladder, applied only to windows larger than CTX_MARK_MINWINDOW. Smaller
# windows keep a single warning glyph at their purple threshold. Set CTX_MARKS
# empty to turn the ladder off, or raise CTX_MARK_MINWINDOW out of reach.
# CTX_MARKS="50:⚠,65:💥,75:💥💥,85:💥💥💥,90:💀"
# CTX_MARK_MINWINDOW=800000

# ---- 5h: five fixed bands, at:colour:bold --------------------------------
# RAMP_5H="0:46:0,10:83:0,20:120:0,30:157:0,40:194:0,45:193:0,50:192:0,55:190:0,60:226:0,65:220:0,70:214:0,75:208:0,80:196:1,85:197:1,90:199:1,95:201:1"
# RAMP_5H_MARK=95

# ---- 7d: pace only -------------------------------------------------------
# The bar is coloured by deviation from the even 1/7-per-day line and by nothing
# else, so a 90% week that is still on pace stays green. deviation:colour pairs,
# lowest first: saturated green when a day is banked, palest green on the line,
# then yellow, red from +7, reddening into the purple gate.
# DEV_RAMP="-999:46,-10:83,-7:120,-3:157,0:194,1:193,2:192,3:191,4:190,5:226,6:214,7:202,8:196,9:197,10:198,11:199,12:200,13:201"
# DEV_7D_PURPLE=14      # a day's share of the week, rounded to where digits flip
# DEV_7D_UNKNOWN=245    # no resets_at means no pace to judge: grey, never green

# The one absolute rule left on this bar. At 100% the quota is gone and the
# deviation has stopped meaning anything. Set empty to switch the exception off.
# HARD_STOP_7D=100

# PURPLE_COL=201
# WARN_GLYPH="⚠"

# ---- plugin badges -------------------------------------------------------
# Colours keyed by the exact mode word, as name:word=color triples. This is how a
# plugin whose flag holds a state rather than a level gets a colour that moves;
# the four-tier ramps stay as the fallback for anything not listed here.
# WORD_COLORS="review:draft=60 review:ready=75 review:blocked=196"
