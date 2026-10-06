#Requires -Version 5.1
# Four-file bilingual whale + active Codex overlay. Stop DSH before changing files.
[CmdletBinding()]
param([ValidateSet('auto','desktop','web')][string]$Profile='auto', [string]$DshHome='', [switch]$Check, [switch]$Restore, [switch]$DryRun, [switch]$Force)
$ErrorActionPreference='Stop'
if ($Check -and $Restore) { throw 'Choose only one mode' }
$Root=Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Overlay=Join-Path $Root 'plugins/dsh-whale-widget-i18n'
$Payload=Join-Path $Overlay 'payload'
$m=Get-Content -Raw -Encoding UTF8 (Join-Path $Overlay 'manifest.json') | ConvertFrom-Json
$Files=@('assets/whale-widget.js','lib/index.js','lib/client.js','package.json')
$Keys=@('Assets','Lib','Client','Package')
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Value([string]$Key) { $v=$m.$Key; if ([string]::IsNullOrWhiteSpace($v)) { throw "Missing manifest field $Key" }; return [string]$v }
if ([string]::IsNullOrWhiteSpace($DshHome)) {
  if ($env:DSH_HOME) { $DshHome=$env:DSH_HOME } else { $DshHome=Join-Path $HOME '.dsh' }
}
if (-not (Test-Path -LiteralPath $DshHome -PathType Container)) { throw 'DSH_HOME missing' }
$Candidates=if ($Profile -eq 'auto') { @('desktop','web') } else { @($Profile) }
$Target=''; $Selected=''
foreach ($p in $Candidates) {
  $d=Join-Path $DshHome "profiles/$p/node_modules/dsh-whale-widget"
  if ((Test-Path -LiteralPath (Join-Path $d $Files[0]) -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $d $Files[1]) -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $d 'package.json') -PathType Leaf)) {
    $Target=(Resolve-Path -LiteralPath $d).Path; $Selected=$p; break
  }
}
if (-not $Target) { throw 'Plugin missing; install dsh-whale-widget first (web: dsh plugin --profile web add dsh-whale-widget; desktop: app plugin manager)' }
$BackupRoot=Join-Path $DshHome '.dshw-i18n-backups'
foreach ($rel in (@('assets','lib') + $Files)) {
  $path=Join-Path $Target $rel
  if (Test-Path -LiteralPath $path) {
    if (((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Refusing managed symlink/reparse point: $rel" }
  }
}
function Matches([string]$Prefix) {
  for ($i=0;$i -lt $Files.Count;$i++) {
    $expected=Value "$Prefix$($Keys[$i])Sha256"; $path=Join-Path $Target $Files[$i]
    if ($expected -eq 'absent') { if (Test-Path -LiteralPath $path) { return $false } }
    elseif (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    elseif ((Hash $path) -ne $expected) { return $false }
  }; return $true
}
function State { if (Matches 'payload') { 'patched' } elseif (Matches 'base') { 'pristine' } elseif (Matches 'previous') { 'previous-overlay' } elseif (Matches 'codex') { 'codex-overlay' } elseif (Matches 'compact') { 'compact-overlay' } elseif (Matches 'maid') { 'maid-overlay' } elseif (Matches 'quiet') { 'quiet-overlay' } else { 'unknown' } }
function UniqueBackup {
  $base=Join-Path $BackupRoot "$Selected-$(Get-Date -Format yyyyMMdd-HHmmss)"; $n=0
  while (Test-Path -LiteralPath "$base-$n") { $n++ }; return "$base-$n"
}
function Backup([string]$Dest) {
  New-Item -ItemType Directory -Path $Dest -Force | Out-Null
  foreach ($rel in $Files) {
    $src=Join-Path $Target $rel; $dst=Join-Path $Dest $rel
    New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
    if (Test-Path -LiteralPath $src -PathType Leaf) {
      Copy-Item -LiteralPath $src -Destination $dst -Force
      [IO.File]::WriteAllText("$dst.sha256",(Hash $dst))
    } elseif (-not (Test-Path -LiteralPath $src)) { [IO.File]::WriteAllText("$dst.absent",'') }
    else { throw "Not a regular file: $src" }
  }; [IO.File]::WriteAllText((Join-Path $Dest '.complete'),'')
}
function ValidateBackup([string]$b) {
  if (-not (Test-Path -LiteralPath (Join-Path $b '.complete'))) { throw 'Backup incomplete or legacy two-file backup; use original installer' }
  foreach ($rel in $Files) {
    $src=Join-Path $b $rel
    if (Test-Path -LiteralPath "$src.absent") { if (Test-Path -LiteralPath $src) { throw 'Ambiguous backup' } }
    elseif (-not (Test-Path -LiteralPath $src -PathType Leaf) -or -not (Test-Path -LiteralPath "$src.sha256" -PathType Leaf)) { throw "Backup missing $rel" }
    elseif ((Hash $src) -ne (Get-Content -Raw -LiteralPath "$src.sha256").Trim()) { throw "Corrupt backup $rel" }
  }
}
function ApplyBackup([string]$b) {
  foreach ($rel in $Files) {
    $src=Join-Path $b $rel; $dst=[IO.Path]::GetFullPath((Join-Path $Target $rel))
    # Only the four fixed allowlisted paths under resolved Target can be removed.
    $expected=[IO.Path]::GetFullPath((Join-Path $Target $rel))
    if ($dst -ne $expected -or -not $dst.StartsWith($Target + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected restore path' }
    if (Test-Path -LiteralPath "$src.absent") { if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force } }
    else { Copy-Item -LiteralPath $src -Destination $dst -Force }
  }
}
if ($Restore) {
  $dirs=@(Get-ChildItem -LiteralPath $BackupRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$Selected-*" -and (Test-Path -LiteralPath (Join-Path $_.FullName '.complete')) } | Sort-Object @{Expression={(Get-Item -LiteralPath (Join-Path $_.FullName '.complete')).LastWriteTimeUtc}},Name)
  if ($dirs.Count -eq 0) { throw 'No complete four-file backup found' }
  $b=$dirs[-1].FullName; ValidateBackup $b
  if ($DryRun) { Write-Host "Would restore $b"; exit 0 }
  $undo="$(UniqueBackup)-restore-safety"; Backup $undo
  try { ApplyBackup $b }
  catch { try { ApplyBackup $undo } catch { Write-Error "ROLLBACK FAILED; recover from $undo" }; throw }
  $marker=Join-Path $undo '.complete'
  if ([IO.Path]::GetFullPath($marker) -ne [IO.Path]::GetFullPath((Join-Path $undo '.complete'))) { throw 'Unexpected safety path' }
  Remove-Item -LiteralPath $marker -Force
  Write-Host 'Restored all four files, including originally absent client. Restart DSH and hard-refresh.'; exit 0
}
# Prevalidate every payload before backup or mutation, including check and dry run.
for ($i=0;$i -lt $Files.Count;$i++) {
  $src=Join-Path $Payload $Files[$i]; $expected=Value "payload$($Keys[$i])Sha256"
  if (-not (Test-Path -LiteralPath $src -PathType Leaf) -or (Hash $src) -ne $expected) { throw "Payload checksum mismatch: $($Files[$i])" }
}
$st=State; Write-Host "profile: $Selected`nstate: $st"
if ($Check) { if ($st -eq 'unknown') { exit 2 }; exit 0 }
if ($st -eq 'patched') { Write-Host 'Already up to date; no backup or copy needed.'; exit 0 }
if ($st -eq 'unknown' -and -not $Force) { Write-Warning 'Refusing drift: exact pristine, previous-overlay, codex-overlay, compact-overlay, maid-overlay, or quiet-overlay hashes required.'; exit 2 }
if ($DryRun) { Write-Host 'Would back up and replace all four allowlisted files.'; exit 0 }
$b=UniqueBackup; Backup $b
try {
  foreach ($rel in $Files) { Copy-Item -LiteralPath (Join-Path $Payload $rel) -Destination (Join-Path $Target $rel) -Force }
  if (-not (Matches 'payload')) { throw 'Installed checksum mismatch' }
} catch { try { ApplyBackup $b } catch { Write-Error "ROLLBACK FAILED; recover from $b" }; throw }
Write-Host "Installed. Backup: $b"
Write-Host 'Restart DSH (host + client registration), then hard-refresh. Stop DSH before -Restore.'
