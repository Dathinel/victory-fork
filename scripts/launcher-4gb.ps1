<#
.SYNOPSIS
  A small window in front of play-4gb.ps1: pick the game, a profile and extra switches, then start.

.DESCRIPTION
  Everything it does goes through play-4gb.ps1 in this folder, so the profiles are that script's.
  The choices are remembered in launcher-4gb.json beside this script (your own paths: not for git).
  Double-click Launch-4GB.cmd in the repository root, or: powershell -File scripts\launcher-4gb.ps1
#>
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$play = Join-Path $PSScriptRoot 'play-4gb.ps1'
$memory = Join-Path $PSScriptRoot 'launcher-4gb.json'
$saved = @{ Exe = ''; Quality = 'low'; Texture = '(profile)'; Render = '(profile)'; Water = $true; Extra = '' }
if (Test-Path $memory) {
    try { (Get-Content $memory -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $saved[$_.Name] = $_.Value } } catch {}
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'VIctory on a 4 GB card'
$form.ClientSize = New-Object System.Drawing.Size 560, 470
$form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false; $form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font 'Segoe UI', 9

function Add-Label($text, $y) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point 12, ($y + 3); $l.AutoSize = $true
    $form.Controls.Add($l)
}
function Add-Combo($y, $items, $value) {
    $c = New-Object System.Windows.Forms.ComboBox
    $c.DropDownStyle = 'DropDownList'; $c.Location = New-Object System.Drawing.Point 150, $y; $c.Width = 160
    $c.Items.AddRange($items); $c.SelectedItem = $value
    if ($c.SelectedIndex -lt 0) { $c.SelectedIndex = 0 }
    $form.Controls.Add($c); $c
}

Add-Label 'Game executable' 14
$exe = New-Object System.Windows.Forms.TextBox
$exe.Location = New-Object System.Drawing.Point 150, 12; $exe.Width = 310; $exe.Text = $saved.Exe
$form.Controls.Add($exe)
$browse = New-Object System.Windows.Forms.Button
$browse.Text = 'Browse...'; $browse.Location = New-Object System.Drawing.Point 468, 10; $browse.Width = 80
$browse.Add_Click({
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Filter = 'Game executable (*.exe)|*.exe'
    if ($d.ShowDialog() -eq 'OK') { $exe.Text = $d.FileName }
})
$form.Controls.Add($browse)

Add-Label 'Profile' 50
$quality = Add-Combo 48 @('low', 'medium', 'high') $saved.Quality
Add-Label 'Texture scale' 82
$texture = Add-Combo 80 @('(profile)', '1', '0.5', '0.25') $saved.Texture
Add-Label 'Render scale' 114
$render = Add-Combo 112 @('(profile)', '0.5', 'native') $saved.Render

$water = New-Object System.Windows.Forms.CheckBox
$water.Text = "The sea's light (about 3 % of the frame)"; $water.Checked = [bool]$saved.Water
$water.Location = New-Object System.Drawing.Point 150, 146; $water.AutoSize = $true
$form.Controls.Add($water)

Add-Label 'Extra switches' 180
$hint = New-Object System.Windows.Forms.Label
$hint.Text = "NAME=value,`none a line.`nEmpty value:`nswitch off."
$hint.Location = New-Object System.Drawing.Point 12, 204; $hint.Size = New-Object System.Drawing.Size 132, 72
$hint.ForeColor = [System.Drawing.SystemColors]::GrayText
$form.Controls.Add($hint)
$extra = New-Object System.Windows.Forms.TextBox
$extra.Multiline = $true; $extra.ScrollBars = 'Vertical'; $extra.AcceptsReturn = $true
$extra.Location = New-Object System.Drawing.Point 150, 180; $extra.Size = New-Object System.Drawing.Size 398, 90
$extra.Font = New-Object System.Drawing.Font 'Consolas', 9; $extra.Text = $saved.Extra
$form.Controls.Add($extra)

$out = New-Object System.Windows.Forms.TextBox
$out.Multiline = $true; $out.ReadOnly = $true; $out.ScrollBars = 'Vertical'
$out.Location = New-Object System.Drawing.Point 12, 282; $out.Size = New-Object System.Drawing.Size 536, 140
$out.Font = New-Object System.Drawing.Font 'Consolas', 9
$form.Controls.Add($out)

# The arguments for play-4gb.ps1 from what the window holds.
function Get-Arguments([switch]$Show) {
    $a = @{ Exe = $exe.Text.Trim('" '); Quality = [string]$quality.SelectedItem }
    if ($texture.SelectedItem -ne '(profile)') { $a.TextureScale = [string]$texture.SelectedItem }
    if ($render.SelectedItem -ne '(profile)') { $a.RenderScale = [string]$render.SelectedItem }
    if (-not $water.Checked) { $a.NoWaterLight = $true }
    $pairs = @($extra.Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($pairs) { $a.More = $pairs }
    if ($Show) { $a.Show = $true }
    $a
}
function Save-Choices {
    @{ Exe = $exe.Text; Quality = [string]$quality.SelectedItem; Texture = [string]$texture.SelectedItem
       Render = [string]$render.SelectedItem; Water = $water.Checked; Extra = $extra.Text } |
        ConvertTo-Json | Set-Content $memory -Encoding UTF8
}

$show = New-Object System.Windows.Forms.Button
$show.Text = 'Show switches'; $show.Location = New-Object System.Drawing.Point 12, 432; $show.Width = 120
$show.Add_Click({
    $a = Get-Arguments -Show
    if (-not $a.Exe) { $a.Exe = 'game.exe' }
    try { $out.Text = (& $play @a | Out-String) } catch { $out.Text = "$_" }
})
$form.Controls.Add($show)

$start = New-Object System.Windows.Forms.Button
$start.Text = 'Start'; $start.Location = New-Object System.Drawing.Point 428, 432; $start.Width = 120
$start.Add_Click({
    $a = Get-Arguments
    if (-not (Test-Path $a.Exe)) { $out.Text = "No game executable at '$($a.Exe)'. Use Browse."; return }
    Save-Choices
    # A console of its own, so the layer's log stays readable and the window can close.
    $line = "& '$play'" + (($a.GetEnumerator() | ForEach-Object {
        if ($_.Value -is [bool]) { " -$($_.Key)" }
        elseif ($_.Value -is [array]) { " -$($_.Key) " + (($_.Value | ForEach-Object { "'$($_ -replace "'", "''")'" }) -join ',') }
        else { " -$($_.Key) '$($_.Value -replace "'", "''")'" }
    }) -join '')
    Start-Process powershell -ArgumentList '-NoExit', '-ExecutionPolicy', 'Bypass', '-Command', $line
    $form.Close()
})
$form.Controls.Add($start)
$form.AcceptButton = $start

[void]$form.ShowDialog()
