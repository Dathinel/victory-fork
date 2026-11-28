<#
.SYNOPSIS
  Starts the title on a small card (measured on an RTX 3050 Laptop 4 GB, Series S profile).

.DESCRIPTION
  -Quality picks a preset; -TextureScale, -RenderScale and -TextureBudgetMB override it.

    low     textures at 0.25, render scale 0.5   (the set every measurement in the README uses)
    medium  textures at 0.5,  render scale 0.5
    high    textures at 1,    the title's own render size, 2,500 MB of textures (slow; a look, not a way to play)

  Texture scale is per side: 0.5 keeps a quarter of a texture's bytes, 0.25 a sixteenth
  (VICTORY_TEXTURE_DROP_MIPS 1 and 2). On a 4 GB card the layer lets title textures fill about
  840 MB and no more, so a smaller scale means more textures present, not only smaller ones.

  Render scale 0.5 uses the title's own upscaler. "native" leaves the Series S profile as it is
  (two thirds, FSR4). A full-size render does not exist on this profile: the title stops at its
  own render-target pool check.

  The sea's light (three compute programs that 32-lane cards refuse otherwise) is on by default:
  about 3 % of the frame on the RTX 3050 Laptop. -NoWaterLight leaves it out.

.EXAMPLE
  scripts\play-4gb.ps1 -Exe 'D:\Games\MyDump\game_scarlett_master.exe'
.EXAMPLE
  scripts\play-4gb.ps1 -Exe '...' -Quality low -TextureScale 0.5
.EXAMPLE
  scripts\play-4gb.ps1 -Exe '...' -Quality high -Show
#>
param(
    [Parameter(Mandatory)][string]$Exe,
    [ValidateSet('low', 'medium', 'high')][string]$Quality = 'low',
    [ValidateSet('1', '0.5', '0.25')][string]$TextureScale,
    [ValidateSet('0.5', 'native')][string]$RenderScale,
    [int]$TextureBudgetMB,
    # Leaves the water's transmission programs untranslated, as before (dark sea, about 3 % less frame).
    [switch]$NoWaterLight,
    # The layer's executable; target\release\victory.exe of this checkout if not given, else
    # target\diag\victory.exe. The release build has no diagnostics counters in it and is the
    # faster of the two here.
    [string]$Victory,
    # More switches, or other values for the ones set here: 'VICTORY_X=1', 'VICTORY_Y=' (empty: not set); several in one string with ";" between.
    [string[]]$More,
    # Prints the switches and starts nothing.
    [switch]$Show
)
if (-not $Victory) {
    $Victory = Join-Path $PSScriptRoot '..\target\release\victory.exe'
    if (-not (Test-Path $Victory)) { $Victory = Join-Path $PSScriptRoot '..\target\diag\victory.exe' }
}

$presets = @{
    low    = @{ Texture = '0.25'; Render = '0.5';    Budget = 0 }
    medium = @{ Texture = '0.5';  Render = '0.5';    Budget = 0 }
    high   = @{ Texture = '1';    Render = 'native'; Budget = 2500 }
}
$p = $presets[$Quality]
if ($TextureScale) { $p.Texture = $TextureScale }
if ($RenderScale) { $p.Render = $RenderScale }
if ($PSBoundParameters.ContainsKey('TextureBudgetMB')) { $p.Budget = $TextureBudgetMB }

$set = [ordered]@{
    VICTORY_LEVELS_ON_DEMAND  = '1'
    VICTORY_TEXTURE_NO_WAIT   = '1'
    VICTORY_AMBIENT           = '0.8'
    VICTORY_AMBIENT_AIR       = '1.5'
    VICTORY_AMBIENT_SETTLE    = '250,3'
    VICTORY_AMBIENT_MARCH     = '3'
    VICTORY_FILL_TITLE        = '1'
    VICTORY_RELAY_COPY        = '1'
    VICTORY_CARD_REHASH_RUNS  = '1'
    VICTORY_JOIN_COPIES       = '1'
    VICTORY_INDIRECT_WINDOW   = '1'
    VICTORY_INDIRECT_BATCH    = '2'
    VICTORY_NAN_SCRUB         = '1'
    VICTORY_BAKE_SOURCES      = 'full'
    VICTORY_TEXTURE_DROP_MIPS = @{ '1' = '0'; '0.5' = '1'; '0.25' = '2' }[$p.Texture]
}
if ($p.Render -eq '0.5') {
    $set.VICTORY_UPSCALER = '6'
    $set.VICTORY_RENDER_SCALE = '0.5'
}
# The three water transmission programs (the light through the sea, and underwater) translate on
# 32-lane cards only with the wave-wide form tried last. Without them the sea is a dark grey-blue.
if (-not $NoWaterLight) { $set.VICTORY_WAVE_WIDE = 'last' }
if ($p.Budget -gt 0) { $set.VICTORY_TEXTURE_BUDGET_MB = "$($p.Budget)" }
# rt_off_hashes.txt: the ray-tracing resolves (trustno1-coder's list). rt_work_off_hashes.txt: work done
# only for ray tracing, which does not run here: the 41 bvh_skinning programs (about 22 ms of card
# time a frame), the probes' CS_Primary_GatherCopy (about 50 ms) and three more passes of the light
# probes (GatherVBuffer, ShadeCopy, RegisterAllocationRequests: about 19 ms), whose light the ambient
# stand-in already replaces.
$skip = 'rt_off_hashes.txt', 'rt_work_off_hashes.txt' | ForEach-Object { Join-Path $PSScriptRoot $_ } |
    Where-Object { Test-Path $_ } | ForEach-Object { (Get-Content $_ -Raw) -replace '\s', '' }
# VICTORY_LEAVE_OUT, not VICTORY_SKIP_PIPELINES: the latter exists in diagnostics builds only.
if ($skip) { $set.VICTORY_LEAVE_OUT = $skip -join ',' }
# -More wins over everything above; an empty value takes the switch out.
foreach ($pair in ($More | ForEach-Object { "$_" -split ";" } | Where-Object { $_.Trim() })) {
    $name, $value = "$pair".Split('=', 2)
    $name = $name.Trim()
    if ($name -notmatch '^VICTORY_[A-Z0-9_]+$') { throw "-More expects VICTORY_NAME=value, not '$pair'" }
    if ($value) { $set[$name] = $value.Trim() } else { $set.Remove($name) }
}

"quality ${Quality}: textures at $($p.Texture), render scale $($p.Render)" + $(if ($p.Budget) { ", $($p.Budget) MB of textures" })
if ($Show) {
    $set.GetEnumerator() | ForEach-Object {
        $v = $_.Value; if ($v.Length -gt 60) { $v = $v.Substring(0, 40) + "... ($($v.Length) characters)" }
        "$($_.Key)=$v"
    }
    return
}
if (-not (Test-Path $Victory)) { throw "no ${Victory}: build it first (cargo build --release -p victory)" }
if (-not (Test-Path $Exe)) { throw "no $Exe" }
$set.GetEnumerator() | ForEach-Object { Set-Item "env:$($_.Key)" $_.Value }
& $Victory run $Exe --console series-s --execute
