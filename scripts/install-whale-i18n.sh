#!/usr/bin/env bash
# ===========================================================================
# install-whale-i18n.sh — add the bilingual (zh/en) interface to the
# dsh-whale-widget DSH plugin, on this machine, from this repo.
# ---------------------------------------------------------------------------
# The overlay carries both dictionaries inline, so installing needs no build
# step and no network: it copies two files over an existing plugin install and
# keeps a timestamped backup so it can be undone.
#
#   ./scripts/install-whale-i18n.sh                 # auto-pick the profile
#   ./scripts/install-whale-i18n.sh --profile web   # force a profile
#   ./scripts/install-whale-i18n.sh --dry-run       # say what it would do
#   ./scripts/install-whale-i18n.sh --check         # verify only, change nothing
#   ./scripts/install-whale-i18n.sh --restore       # roll the newest backup back
#
# Why a script at all: the desktop (Electron) profile is managed by the app and
# `dsh plugin` refuses it by design, and a plugin update replaces the whole
# package directory — so the overlay has to be re-applied, which this makes one
# command. See plugins/dsh-whale-widget-i18n/manifest.json for provenance.
# ===========================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_PKG="dsh-whale-widget"
OVERLAY_DIR="$REPO_DIR/plugins/dsh-whale-widget-i18n"
PAYLOAD_DIR="$OVERLAY_DIR/payload"
MANIFEST="$OVERLAY_DIR/manifest.json"

PROFILE="auto"
DSH_HOME_ARG=""
MODE="install"          # install | restore | check
DRY_RUN=0
FORCE=0

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }
ok() { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }

usage() { sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --dsh-home) DSH_HOME_ARG="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force) FORCE=1; shift ;;
    --check) MODE="check"; shift ;;
    --restore) MODE="restore"; shift ;;
    -h|--help) usage ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

case "$PROFILE" in auto|desktop|web) ;; *) die "--profile must be auto, desktop or web" ;; esac

# --- locate DSH_HOME --------------------------------------------------------
DSH_HOME="${DSH_HOME_ARG:-${DSH_HOME:-$HOME/.dsh}}"
[ -d "$DSH_HOME" ] || die "DSH_HOME not found: $DSH_HOME (is DSH installed, or pass --dsh-home?)"
[ -f "$MANIFEST" ] || die "manifest missing: $MANIFEST"

# --- pick the profile -------------------------------------------------------
# A profile "has" the plugin when its package directory exists. Prefer desktop:
# that is the Electron app, where an in-place overlay is the only route.
plugin_dir_for() { printf '%s/profiles/%s/node_modules/%s' "$DSH_HOME" "$1" "$PLUGIN_PKG"; }

CANDIDATES=()
case "$PROFILE" in
  desktop) CANDIDATES=(desktop) ;;
  web) CANDIDATES=(web) ;;
  auto) CANDIDATES=(desktop web) ;;
esac

TARGET=""; TARGET_PROFILE=""
for p in "${CANDIDATES[@]}"; do
  d="$(plugin_dir_for "$p")"
  if [ -f "$d/assets/whale-widget.js" ] && [ -f "$d/lib/index.js" ]; then
    TARGET="$d"; TARGET_PROFILE="$p"; break
  fi
done

# --- helpers ----------------------------------------------------------------
sha() { # portable across macOS (shasum) and Linux (sha256sum)
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256sum "$1" | awk '{print $1}'; fi
}

# Flat JSON scalars are read with grep/sed so the script needs no jq/python.
manifest_get() { # manifest_get <key>
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$MANIFEST" | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//'
}

MARKER="$(manifest_get marker)"
HOST_MARKER="$(manifest_get hostMarker)"
BASE_SHA_ASSETS="$(manifest_get baseAssetsSha256)"
BASE_SHA_LIB="$(manifest_get baseLibSha256)"
PAYLOAD_SHA_ASSETS="$(manifest_get payloadAssetsSha256)"
PAYLOAD_SHA_LIB="$(manifest_get payloadLibSha256)"
for v in MARKER HOST_MARKER BASE_SHA_ASSETS BASE_SHA_LIB PAYLOAD_SHA_ASSETS PAYLOAD_SHA_LIB; do
  [ -n "${!v}" ] || die "manifest is missing a value for $v ($MANIFEST)"
done

state_of() { # pristine | patched | unknown
  local dir="$1"
  if grep -q "$MARKER" "$dir/assets/whale-widget.js" 2>/dev/null &&
     grep -q "$HOST_MARKER" "$dir/lib/index.js" 2>/dev/null; then
    echo patched; return
  fi
  if [ "$(sha "$dir/assets/whale-widget.js")" = "$BASE_SHA_ASSETS" ] && \
     [ "$(sha "$dir/lib/index.js")" = "$BASE_SHA_LIB" ]; then
    echo pristine; return
  fi
  echo unknown
}

# Backups live under DSH_HOME, NOT inside node_modules: pnpm prunes unknown
# directories there, so a backup kept next to the plugin can disappear exactly
# when a plugin update makes it useful.
BACKUP_ROOT="$DSH_HOME/.dshw-i18n-backups"
newest_backup() { ls -1d "$BACKUP_ROOT/$TARGET_PROFILE"-* 2>/dev/null | sort | tail -1; }

if [ -z "$TARGET" ]; then
  cat >&2 <<EOF
$(printf '\033[31merror:\033[0m') the $PLUGIN_PKG plugin is not installed in any checked profile
       checked: ${CANDIDATES[*]}   (DSH_HOME=$DSH_HOME)

Install it first, then re-run this script:

  web profile (CLI-managed, the supported route):
    dsh plugin --profile web add $PLUGIN_PKG

  desktop app (Electron) — the CLI refuses this profile by design:
    open a chat in the desktop app and ask DSH to install "$PLUGIN_PKG"
    (the app's own plugin manager is scoped to the desktop profile)

EOF
  exit 1
fi

info "repo      : $REPO_DIR"
info "DSH_HOME  : $DSH_HOME"
info "profile   : $TARGET_PROFILE"
info "plugin    : $TARGET"
info "state     : $(state_of "$TARGET")"
info "mode      : $MODE$([ "$DRY_RUN" = 1 ] && echo ' (dry run)')"
echo

# ---------------------------------------------------------------------------
# --check: report only, change nothing
# ---------------------------------------------------------------------------
if [ "$MODE" = check ]; then
  st="$(state_of "$TARGET")"
  info "widget i18n markers : $(grep -c "$MARKER" "$TARGET/assets/whale-widget.js" || true)"
  info "host   i18n markers : $(grep -c "$HOST_MARKER" "$TARGET/lib/index.js" || true)"
  case "$st" in
    patched)
      ok "the bilingual overlay is installed."
      info "reminder: the widget half takes effect on a page refresh; the host half needs a DSH restart."
      ;;
    pristine) warn "the overlay is NOT installed (plugin files are pristine upstream)." ;;
    *) warn "the plugin files match neither pristine upstream nor this overlay (version drift, or already modified)." ;;
  esac
  exit 0
fi

# ---------------------------------------------------------------------------
# --restore: put the newest backup back
# ---------------------------------------------------------------------------
if [ "$MODE" = restore ]; then
  b="$(newest_backup)"
  [ -n "$b" ] || die "no backup found under $BACKUP_ROOT for profile '$TARGET_PROFILE' (nothing to restore)"
  info "restoring from: $b"
  for rel in assets/whale-widget.js lib/index.js; do
    src="$b/$rel"
    [ -f "$src" ] || die "backup is incomplete (missing $rel)"
    if [ "$DRY_RUN" = 1 ]; then
      info "would restore $rel"
    else
      cp "$src" "$TARGET/$rel"
      info "restored $rel"
    fi
  done
  [ "$DRY_RUN" = 1 ] || ok "restored. Refresh the page and restart DSH."
  exit 0
fi

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------
ST="$(state_of "$TARGET")"
case "$ST" in
  pristine) : ;;
  patched) info "already patched — re-applying the overlay (idempotent)." ;;
  *)
    if [ "$FORCE" != 1 ]; then
      cat >&2 <<EOF
$(printf '\033[33mwarning:\033[0m') the installed plugin matches neither upstream v0.3.18 (which this
         overlay was built against) nor this overlay. That usually means a
         different plugin version — do NOT force it here: the overlay would put
         older upstream code back. Rebuild against this version instead:

           cp "\$PLUGIN/assets/whale-widget.js" <src>/baseline/whale-widget.upstream.js
           cp "\$PLUGIN/lib/index.js"           <src>/baseline/index.upstream.js
           npm run build && npm run check      # in the source fork

         Or re-run with --force if you are sure (a backup is still taken).

EOF
      exit 2
    fi
    warn "forcing the overlay over unrecognised plugin files (a backup is still kept)."
    ;;
esac

# Unique per run: two re-applies inside the same second must not overwrite the
# older (pristine) backup, which is the one a rollback actually wants.
# If both files already equal the payload there is nothing to preserve and
# nothing to copy: skipping the backup here is what keeps --restore meaningful
# (a second re-apply must not bury the pristine backup under a "patched" one).
UP_TO_DATE=1
[ "$(sha "$TARGET/assets/whale-widget.js")" = "$PAYLOAD_SHA_ASSETS" ] || UP_TO_DATE=0
[ "$(sha "$TARGET/lib/index.js")" = "$PAYLOAD_SHA_LIB" ] || UP_TO_DATE=0
if [ "$UP_TO_DATE" = 1 ]; then
  ok "Already up to date — the installed files match the overlay payload exactly."
  info "nothing copied. Refresh the page if you have not since the last apply,"
  info "and restart DSH for the host half. Undo with: $0 --restore"
  exit 0
fi

BACKUP="$BACKUP_ROOT/$TARGET_PROFILE-$(date +%Y%m%d-%H%M%S)"
if [ -e "$BACKUP" ]; then
  n=2
  while [ -e "$BACKUP-$n" ]; do n=$((n + 1)); done
  BACKUP="$BACKUP-$n"
fi
if [ "$DRY_RUN" = 1 ]; then
  info "would back up assets/whale-widget.js and lib/index.js to:"
  info "  $BACKUP"
  info "(backups live under DSH_HOME, not in node_modules, so a plugin update cannot prune them)"
  info "would copy the overlay payload over those two files"
  exit 0
fi

mkdir -p "$BACKUP/assets" "$BACKUP/lib"
cp "$TARGET/assets/whale-widget.js" "$BACKUP/assets/whale-widget.js"
cp "$TARGET/lib/index.js" "$BACKUP/lib/index.js"
info "backup    : $BACKUP"

for rel in assets/whale-widget.js lib/index.js; do
  case "$rel" in
    assets/whale-widget.js) want="$PAYLOAD_SHA_ASSETS" ;;
    lib/index.js) want="$PAYLOAD_SHA_LIB" ;;
  esac
  got="$(sha "$PAYLOAD_DIR/$rel")"
  [ "$want" = "$got" ] || die "payload checksum mismatch for $rel (the repo copy is corrupted)"
  cp "$PAYLOAD_DIR/$rel" "$TARGET/$rel"
  info "installed : $rel  ($(sha "$TARGET/$rel" | cut -c1-12)…)"
done

echo
ok "Done. The bilingual overlay is installed for the '$TARGET_PROFILE' profile."
cat <<EOF

Next steps
  1. Refresh the DSH page (Cmd/Ctrl+Shift+R). The widget half is re-read from
     disk per request, so that alone updates the UI and the menu switch.
  2. Restart DSH / the desktop app. Needed for the host half (lib/index.js):
     error and toast text plus the factory-default bubble content.

Verify
  ./scripts/install-whale-i18n.sh --check
  curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:<port>/dsh-whale/lang.json
      # 404 before the restart, 401 after (registered, needs auth)
  cat "$DSH_HOME/.dshw-lang.json"
      # appears after the next page load: the widget telling the host its language

Undo
  ./scripts/install-whale-i18n.sh --restore
EOF
