<#
===========================================================================
 install-whale-i18n.ps1 — add the bilingual (zh/en) interface to the
 dsh-whale-widget DSH plugin, on this machine, from this repo.

 The overlay carries both dictionaries inline, so installing needs no build
 step and no network: it copies two files over an existing plugin install and
 keeps a timestamped backup so it can be undone.

   .\scripts\install-whale-i18n.ps1                  # auto-pick the profile
   .\scripts\install-whale-i18n.ps1 -Profile web     # force a profile
   .\scripts\install-whale-i18n.ps1 -DryRun          # say what it would do
   .\scripts\install-whale-i18n.ps1 -Check           # verify only, no changes
   .\scripts\install-whale-i18n.ps1 -Restore         # roll the newest backup back

 Why a script at all: the desktop (Electron) profile is managed by the app and
 `dsh plugin` refuses it by design, and a plugin update replaces the whole
 package directory — so the overlay has to be re-applied, which this makes one
 command. See plugins\dsh-whale-widget-i18n\manifest.json for provenance.

 Note: if script execution is blocked, run it as
   powershell -ExecutionPolicy Bypass -File .\scripts\install-whale-i18n.ps1
===========================================================================
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
  [ValidateSet('auto', 'desktop', 'web')][string]$Profile = 'auto',
  [string]$DshHome = '',
  [switch]$Check,
  [switch]$Restore,
  [switch]$DryRun,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

$RepoDir    = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$PluginPkg  = 'dsh-whale-widget'
$OverlayDir = Join-Path $RepoDir 'plugins/dsh-whale-widget-i18n'
$PayloadDir = Join-Path $OverlayDir 'payload'
$Manifest   = Join-Path $OverlayDir 'manifest.json'

function Write-Info { param([string]$m) Write-Host $m }
function Write-Ok   { param([string]$m) Write-Host $m -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "warning: $m" -ForegroundColor Yellow }
function Die        { param([string]$m) Write-Host "error: $m" -ForegroundColor Red; exit 1 }

# --- manifest (single source of truth for markers and expected hashes) ------
if (-not (Test-Path $Manifest)) { Die "manifest missing: $Manifest" }
$m = Get-Content -Raw $Manifest | ConvertFrom-Json
$Marker          = $m.marker
$HostMarker      = $m.hostMarker
$BaseShaAssets   = $m.baseAssetsSha256
$BaseShaLib      = $m.baseLibSha256
$PayloadShaAssets = $m.payloadAssetsSha256
$PayloadShaLib   = $m.payloadLibSha256
foreach ($pair in @(@('marker', $Marker), @('hostMarker', $HostMarker), @('baseAssetsSha256', $BaseShaAssets),
                    @('baseLibSha256', $BaseShaLib), @('payloadAssetsSha256', $PayloadShaAssets), @('payloadLibSha256', $PayloadShaLib))) {
  if ([string]::IsNullOrWhiteSpace($pair[1])) { Die "manifest is missing a value for $($pair[0])" }
}

# --- locate DSH_HOME -------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($DshHome)) {
  if (-not [string]::IsNullOrWhiteSpace($env:DSH_HOME)) { $DshHome = $env:DSH_HOME }
  else { $DshHome = Join-Path $env:USERPROFILE '.dsh' }
}
if (-not (Test-Path $DshHome)) {
  Die "DSH_HOME not found: $DshHome (is DSH installed, or pass -DshHome?)"
}

function Get-PluginDir { param([string]$p)
  Join-Path (Join-Path (Join-Path (Join-Path $DshHome 'profiles') $p) 'node_modules') $PluginPkg
}

# --- pick the profile ------------------------------------------------------
switch ($Profile) {
  'desktop' { $candidates = @('desktop') }
  'web'     { $candidates = @('web') }
  default   { $candidates = @('desktop', 'web') }
}

$Target = ''
$TargetProfile = ''
foreach ($p in $candidates) {
  $d = Get-PluginDir $p
  if ((Test-Path (Join-Path $d 'assets/whale-widget.js')) -and (Test-Path (Join-Path $d 'lib/index.js'))) {
    $Target = $d; $TargetProfile = $p; break
  }
}

function Get-Sha { param([string]$f) (Get-FileHash -Algorithm SHA256 -Path $f).Hash.ToLower() }
function Test-Marker { param([string]$f, [string]$marker)
  if (-not (Test-Path $f)) { return $false }
  (Get-Content -Raw -Path $f).Contains($marker)
}

function Get-State { param([string]$dir)
  $wf = Join-Path $dir 'assets/whale-widget.js'
  $hf = Join-Path $dir 'lib/index.js'
  if ((Test-Marker $wf $Marker) -and (Test-Marker $hf $HostMarker)) { return 'patched' }
  if ((Get-Sha $wf) -eq $BaseShaAssets -and (Get-Sha $hf) -eq $BaseShaLib) { return 'pristine' }
  return 'unknown'
}

# Backups live under DSH_HOME, NOT inside node_modules: pnpm prunes unknown
# directories there, so a backup kept next to the plugin can disappear exactly
# when a plugin update makes it useful.
$BackupRoot = Join-Path $DshHome '.dshw-i18n-backups'
function Get-NewestBackup {
  if (-not (Test-Path $BackupRoot)) { return '' }
  $dirs = Get-ChildItem -Path $BackupRoot -Directory -Filter "$TargetProfile-*" -ErrorAction SilentlyContinue |
          Sort-Object -Property Name
  if ($null -eq $dirs -or $dirs.Count -eq 0) { return '' }
  return $dirs[$dirs.Count - 1].FullName
}

if ([string]::IsNullOrWhiteSpace($Target)) {
  Write-Host "error: the $PluginPkg plugin is not installed in any checked profile" -ForegroundColor Red
  Write-Host "       checked: $($candidates -join ' ')   (DSH_HOME=$DshHome)"
  Write-Host @"

Install it first, then re-run this script:

  web profile (CLI-managed, the supported route):
    dsh plugin --profile web add $PluginPkg

  desktop app (Electron) - the CLI refuses this profile by design:
    open a chat in the desktop app and ask DSH to install "$PluginPkg"
    (the app's own plugin manager is scoped to the desktop profile)

"@
  exit 1
}

Write-Info "repo      : $RepoDir"
Write-Info "DSH_HOME  : $DshHome"
Write-Info "profile   : $TargetProfile"
Write-Info "plugin    : $Target"
Write-Info "state     : $(Get-State $Target)"
$modeLabel = if ($Check) { 'check' } elseif ($Restore) { 'restore' } else { 'install' }
if ($DryRun) { $modeLabel = "$modeLabel (dry run)" }
Write-Info "mode      : $modeLabel"
Write-Host ''

# ---------------------------------------------------------------------------
# -Check: report only
# ---------------------------------------------------------------------------
if ($Check) {
  $wf = Join-Path $Target 'assets/whale-widget.js'
  $hf = Join-Path $Target 'lib/index.js'
  Write-Info "widget i18n markers : $(([regex]::Matches((Get-Content -Raw $wf), [regex]::Escape($Marker))).Count)"
  Write-Info "host   i18n markers : $(([regex]::Matches((Get-Content -Raw $hf), [regex]::Escape($HostMarker))).Count)"
  switch (Get-State $Target) {
    'patched'  {
      Write-Ok 'the bilingual overlay is installed.'
      Write-Info 'reminder: the widget half takes effect on a page refresh; the host half needs a DSH restart.'
    }
    'pristine' { Write-Warn 'the overlay is NOT installed (plugin files are pristine upstream).' }
    default    { Write-Warn 'the plugin files match neither pristine upstream nor this overlay (version drift, or already modified).' }
  }
  exit 0
}

# ---------------------------------------------------------------------------
# -Restore: put the newest backup back
# ---------------------------------------------------------------------------
if ($Restore) {
  $b = Get-NewestBackup
  if ([string]::IsNullOrWhiteSpace($b)) { Die "no backup found under $BackupRoot for profile '$TargetProfile' (nothing to restore)" }
  Write-Info "restoring from: $b"
  foreach ($rel in @('assets/whale-widget.js', 'lib/index.js')) {
    $src = Join-Path $b $rel
    if (-not (Test-Path $src)) { Die "backup is incomplete (missing $rel)" }
    if ($DryRun) { Write-Info "would restore $rel" }
    else {
      Copy-Item -Path $src -Destination (Join-Path $Target $rel) -Force
      Write-Info "restored $rel"
    }
  }
  if (-not $DryRun) { Write-Ok 'restored. Refresh the page and restart DSH.' }
  exit 0
}

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------
$state = Get-State $Target
switch ($state) {
  'pristine' { }
  'patched'  { Write-Info 'already patched - re-applying the overlay (idempotent).' }
  default {
    if (-not $Force) {
      Write-Warn @"
the installed plugin matches neither upstream $($m.upstreamVersion) (which this
         overlay was built against) nor this overlay. That usually means a
         different plugin version - do NOT force it here: the overlay would put
         older upstream code back. Rebuild against this version instead:

           copy "`$PLUGIN\assets\whale-widget.js" <src>\baseline\whale-widget.upstream.js
           copy "`$PLUGIN\lib\index.js"           <src>\baseline\index.upstream.js
           npm run build; npm run check           # in the source fork

         Or re-run with -Force if you are sure (a backup is still taken).
"@
      exit 2
    }
    Write-Warn 'forcing the overlay over unrecognised plugin files (a backup is still kept).'
  }
}

# If both files already equal the payload there is nothing to preserve and
# nothing to copy: skipping the backup here is what keeps -Restore meaningful
# (a second re-apply must not bury the pristine backup under a "patched" one).
$upToDate = ((Get-Sha (Join-Path $Target 'assets/whale-widget.js')) -eq $PayloadShaAssets) -and
            ((Get-Sha (Join-Path $Target 'lib/index.js')) -eq $PayloadShaLib)
if ($upToDate) {
  Write-Ok 'Already up to date - the installed files match the overlay payload exactly.'
  Write-Info 'nothing copied. Refresh the page if you have not since the last apply,'
  Write-Info 'and restart DSH for the host half. Undo with: -Restore'
  exit 0
}

# A unique directory per run: two re-applies inside the same second must not
# overwrite the older (pristine) backup, which is the one a rollback wants.
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Backup = Join-Path $BackupRoot "$TargetProfile-$stamp"
if (Test-Path $Backup) {
  $n = 2
  while (Test-Path "$Backup-$n") { $n++ }
  $Backup = "$Backup-$n"
}

if ($DryRun) {
  Write-Info 'would back up assets\whale-widget.js and lib\index.js to:'
  Write-Info "  $Backup"
  Write-Info '(backups live under DSH_HOME, not in node_modules, so a plugin update cannot prune them)'
  Write-Info 'would copy the overlay payload over those two files'
  exit 0
}

New-Item -ItemType Directory -Force -Path (Join-Path $Backup 'assets') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Backup 'lib')    | Out-Null
Copy-Item -Path (Join-Path $Target 'assets/whale-widget.js') -Destination (Join-Path $Backup 'assets/whale-widget.js') -Force
Copy-Item -Path (Join-Path $Target 'lib/index.js')           -Destination (Join-Path $Backup 'lib/index.js')           -Force
Write-Info "backup    : $Backup"

$rels = @{
  'assets/whale-widget.js' = $PayloadShaAssets
  'lib/index.js'           = $PayloadShaLib
}
foreach ($rel in $rels.Keys) {
  $want = $rels[$rel]
  $src  = Join-Path $PayloadDir $rel
  $got  = Get-Sha $src
  if ($want -ne $got) { Die "payload checksum mismatch for $rel (the repo copy is corrupted)" }
  Copy-Item -Path $src -Destination (Join-Path $Target $rel) -Force
  Write-Info "installed : $rel  ($((Get-Sha (Join-Path $Target $rel)).Substring(0,12))...)"
}

Write-Host ''
Write-Ok "Done. The bilingual overlay is installed for the '$TargetProfile' profile."
Write-Host @"

Next steps
  1. Refresh the DSH page (Ctrl+Shift+R). The widget half is re-read from disk
     per request, so that alone updates the UI and the menu switch.
  2. Restart DSH / the desktop app. Needed for the host half (lib\index.js):
     error and toast text plus the factory-default bubble content.

Verify
  .\scripts\install-whale-i18n.ps1 -Check
  curl.exe -s -o NUL -w "%{http_code}\n" http://127.0.0.1:<port>/dsh-whale/lang.json
      # 404 before the restart, 401 after (registered, needs auth)
  Get-Content "$DshHome\.dshw-lang.json"
      # appears after the next page load: the widget telling the host its language

Undo
  .\scripts\install-whale-i18n.ps1 -Restore
"@
