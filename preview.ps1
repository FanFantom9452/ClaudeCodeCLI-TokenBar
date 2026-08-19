# ClaudeCodeCLI-TokenBar preview (Windows)
#
#   powershell -NoProfile -File preview.ps1
#
# Feeds synthetic payloads through the real statusline and prints what comes back,
# so a threshold or colour edited in tokenbar-config.ps1 can be checked without
# waiting to burn through an actual quota to see it.
#
# It runs the installed script by default, which means it picks up your config file
# exactly as Claude Code would. Point -Script at a working copy to preview an edit
# before installing it.
param(
    [string]$Script,
    [int]$Throttle = 8
)

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$e = [char]27

$Cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
if (-not $Script) {
    $local = Join-Path $PSScriptRoot 'statusline.ps1'
    $Script = if (Test-Path -LiteralPath $local) { $local } else { Join-Path $Cfg 'statusline.ps1' }
}
if (-not (Test-Path -LiteralPath $Script)) { Write-Host "Not found: $Script"; exit 1 }
$Script  = (Resolve-Path -LiteralPath $Script).Path
$UserCfg = Join-Path $Cfg 'tokenbar-config.ps1'

# Same host that is running this, so the preview cannot disagree with the real thing
# by having been rendered on a different PowerShell.
$exe = try { [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { 'powershell.exe' }
$week = 7 * 24 * 3600
$root = $PSScriptRoot

# One payload per row. Rendering means launching the statusline once, which costs
# most of a second, so they are all built first and then run concurrently — the
# difference between a preview you re-run while tweaking and one you avoid.
$samples = New-Object System.Collections.ArrayList
function Add-Sample($section, $label, $note, $ctxSize, $ctxPct, $q5, $q7, $dev) {
    $body = @{
        cwd = $root
        model = @{ id = 'claude-opus-5[1m]'; display_name = 'Opus 5' }
        workspace = @{ current_dir = $root }
        context_window = @{ context_window_size = $ctxSize; used_percentage = $ctxPct }
    }
    $rl = @{}
    if ($null -ne $q5) {
        $rl.five_hour = @{ used_percentage = $q5; resets_at = [datetime]::UtcNow.AddMinutes(106).ToString('o') }
    }
    if ($null -ne $q7) {
        # resets_at is derived from the deviation being asked for: the elapsed
        # fraction is whatever makes used% - elapsed% land on $dev.
        $left = $week * (1 - ($q7 - $dev) / 100)
        $rl.seven_day = @{ used_percentage = $q7; resets_at = [datetime]::UtcNow.AddSeconds($left).ToString('o') }
    }
    if ($rl.Count) { $body.rate_limits = $rl }
    [void]$samples.Add([pscustomobject]@{
        i = $samples.Count; section = $section; label = $label; note = $note
        json = ($body | ConvertTo-Json -Depth 10 -Compress)
    })
}

foreach ($t in @(@{n='200k';w=200000}, @{n='500k';w=500000}, @{n='800k';w=800000}, @{n='1M';w=1000000})) {
    foreach ($p in 10,40,50,55,60,70,80,85,90,95,100) {
        Add-Sample "ctx $($t.n) window" "$($t.n)  $p%" '' $t.w $p $null $null 0
    }
}
foreach ($p in 20,39,40,59,60,79,80,94,95,100) { Add-Sample '5h' "5h  $p%" '' 200000 10 $p $null 0 }
foreach ($c in @(
    @{p=30;  d=-14; n='a full day banked'}
    @{p=45;  d= -5; n='comfortably under'}
    @{p=90;  d= -3; n='90% used, still on pace'}
    @{p=55;  d=  0; n='dead on the line'}
    @{p=50;  d=  3; n='slightly over'}
    @{p=48;  d=  7; n='half a day ahead'}
    @{p=60;  d= 11; n='nearly a day ahead'}
    @{p=70;  d= 14; n='a full day ahead'}
    @{p=62;  d= 20; n='well past sustainable'}
    @{p=97;  d= -1; n='nearly empty, on pace'}
    @{p=100; d=  0; n='quota gone (hard stop)'}
)) { Add-Sample '7d' ("7d  {0}%  dev {1}" -f $c.p, $c.d) $c.n 200000 10 $null $c.p $c.d }
Add-Sample 'full line' 'quiet'    '' 1000000 22 30 25   2
Add-Sample 'full line' 'mid-week' '' 1000000 48 66 58  -6
Add-Sample 'full line' 'pressed'  '' 1000000 72 88 71  15
Add-Sample 'full line' 'critical' '' 1000000 93 97 96   8

Write-Host ''
Write-Host " script  : $Script"
if (Test-Path -LiteralPath $UserCfg) {
    $live = @(Get-Content -LiteralPath $UserCfg | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
    Write-Host " config  : $UserCfg  ($($live.Count) active line(s))"
} else {
    Write-Host " config  : none at $UserCfg - showing defaults"
}
Write-Host " samples : $($samples.Count), rendering ..."

# -Parallel only exists on PowerShell 7. Results stream back as they finish, so
# every row carries its index and the whole set is re-sorted before printing.
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $done = $samples | ForEach-Object -ThrottleLimit $Throttle -Parallel {
        $s = $_
        $out = $s.json | & $using:exe -NoProfile -ExecutionPolicy Bypass -File $using:Script
        [pscustomobject]@{ i = $s.i; text = (($out -split "`n")[-1]) }
    } | Sort-Object i
} else {
    $done = $samples | ForEach-Object {
        $out = $_.json | & $exe -NoProfile -ExecutionPolicy Bypass -File $Script
        [pscustomobject]@{ i = $_.i; text = (($out -split "`n")[-1]) }
    }
}
$text = @{}
foreach ($d in $done) { $text[$d.i] = $d.text }

$section = ''
foreach ($s in $samples) {
    if ($s.section -ne $section) {
        $section = $s.section
        Write-Host ''
        Write-Host "$e[1m  $section$e[0m"
        Write-Host ''
    }
    $line = "  {0,-22} {1}" -f $s.label, $text[$s.i]
    if ($s.note) { $line += "  $e[38;5;240m$($s.note)$e[0m" }
    Write-Host $line
}
Write-Host ''
