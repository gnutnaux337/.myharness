#!/usr/bin/env bash
# Install the bilingual whale + active Codex overlay; upstream plugin required.
# Options: --profile auto|desktop|web --dsh-home PATH --check --restore
#          --dry-run --force. Stop DSH before install/restore, restart afterwards.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY="$ROOT/plugins/dsh-whale-widget-i18n"
PAYLOAD="$OVERLAY/payload"; MANIFEST="$OVERLAY/manifest.json"
PROFILE=auto; MODE=install; DRY=0; FORCE=0; HOME_ARG=''
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --profile|--dsh-home) [ $# -ge 2 ] && [ -n "$2" ] || fail "$1 needs a value"; if [ "$1" = --profile ]; then PROFILE="$2"; else HOME_ARG="$2"; fi; shift 2 ;;
    --check|--restore) [ "$MODE" = install ] || fail 'choose only one mode'; MODE="${1#--}"; shift ;;
    --dry-run) DRY=1; shift ;; --force) FORCE=1; shift ;;
    -h|--help) printf '%s\n' 'Usage: install-whale-i18n.sh [--profile auto|desktop|web] [--dsh-home PATH] [--check|--restore] [--dry-run] [--force]'; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
case "$PROFILE" in auto|desktop|web) ;; *) fail 'invalid profile' ;; esac
DSH_HOME="${HOME_ARG:-${DSH_HOME:-$HOME/.dsh}}"
[ -d "$DSH_HOME" ] || fail "DSH_HOME missing: $DSH_HOME"
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"; else sha256sum "$1"; fi | awk '{print $1}'; }
get() { local value; value="$(sed -n "s/^[[:space:]]*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$MANIFEST")"; [ -n "$value" ] || fail "manifest missing $1"; printf '%s' "$value"; }
FILES=(assets/whale-widget.js lib/index.js lib/client.js package.json)
KEYS=(Assets Lib Client Package)
TARGET=''; SELECTED=''
if [ "$PROFILE" = auto ]; then CANDIDATES=(desktop web); else CANDIDATES=("$PROFILE"); fi
for p in "${CANDIDATES[@]}"; do
  d="$DSH_HOME/profiles/$p/node_modules/dsh-whale-widget"
  if [ -f "$d/assets/whale-widget.js" ] && [ -f "$d/lib/index.js" ] && [ -f "$d/package.json" ]; then TARGET="$(cd "$d" && pwd -P)"; SELECTED="$p"; break; fi
done
[ -n "$TARGET" ] || fail 'plugin missing; install dsh-whale-widget first (web: dsh plugin --profile web add dsh-whale-widget; desktop: app plugin manager)'
BACKUP_ROOT="$DSH_HOME/.dshw-i18n-backups"
# Package root can be a pnpm symlink, but managed files/directories cannot be.
for rel in assets lib "${FILES[@]}"; do [ ! -L "$TARGET/$rel" ] || fail "refusing managed symlink: $rel"; done
match() { local prefix="$1" i expected; for i in 0 1 2 3; do expected="$(get "${prefix}${KEYS[$i]}Sha256")"; if [ "$expected" = absent ]; then [ ! -e "$TARGET/${FILES[$i]}" ] || return 1; else [ -f "$TARGET/${FILES[$i]}" ] && [ "$(sha "$TARGET/${FILES[$i]}")" = "$expected" ] || return 1; fi; done; }
state() { if match payload; then echo patched; elif match base; then echo pristine; elif match previous; then echo previous-overlay; elif match codex; then echo codex-overlay; elif match compact; then echo compact-overlay; elif match maid; then echo maid-overlay; elif match quiet; then echo quiet-overlay; else echo unknown; fi; }
# Backup hashes + absent markers let restore prevalidate everything before writing.
backup_to() { local dest="$1" rel; mkdir -p "$dest"; for rel in "${FILES[@]}"; do mkdir -p "$(dirname "$dest/$rel")"; if [ -f "$TARGET/$rel" ]; then cp -p "$TARGET/$rel" "$dest/$rel"; sha "$dest/$rel" > "$dest/$rel.sha256"; elif [ ! -e "$TARGET/$rel" ]; then : > "$dest/$rel.absent"; else fail "not a regular file: $TARGET/$rel"; fi; done; : > "$dest/.complete"; }
validate_backup() { local b="$1" rel expected; [ -f "$b/.complete" ] || fail 'backup incomplete or legacy two-file backup (use its original installer)'; for rel in "${FILES[@]}"; do if [ -f "$b/$rel.absent" ]; then [ ! -e "$b/$rel" ] || fail 'ambiguous backup'; else [ -f "$b/$rel" ] && [ -f "$b/$rel.sha256" ] || fail "backup missing $rel"; read -r expected < "$b/$rel.sha256"; [ "$(sha "$b/$rel")" = "$expected" ] || fail "corrupt backup: $rel"; fi; done; }
apply_backup() { local b="$1" rel path; for rel in "${FILES[@]}"; do path="$TARGET/$rel"; if [ -f "$b/$rel.absent" ]; then # fixed allowlisted relative paths, physical TARGET checked above
    case "$path" in "$TARGET/assets/whale-widget.js"|"$TARGET/lib/index.js"|"$TARGET/lib/client.js"|"$TARGET/package.json") rm -f -- "$path" ;; *) return 1 ;; esac
  else cp -p "$b/$rel" "$path" || return 1; fi; done; }
unique_backup() { local b="$BACKUP_ROOT/$SELECTED-$(date +%Y%m%d-%H%M%S)" n=0 suffix; suffix="$(printf '%06d' "$n")"; while [ -e "$b-$suffix" ]; do n=$((n+1)); suffix="$(printf '%06d' "$n")"; done; printf '%s-%s' "$b" "$suffix"; }
if [ "$MODE" = restore ]; then
  b=''; newest=0
  for candidate in "$BACKUP_ROOT/$SELECTED"-*; do [ -d "$candidate" ] && [ -f "$candidate/.complete" ] || continue; t="$(date -r "$candidate/.complete" +%s 2>/dev/null || stat -c %Y "$candidate/.complete")"; if [ "$t" -ge "$newest" ]; then newest="$t"; b="$candidate"; fi; done
  [ -n "$b" ] || fail 'no complete four-file backup found'
  validate_backup "$b"
  [ "$DRY" = 0 ] || { echo "would restore $b"; exit 0; }
  undo="$(unique_backup)-restore-safety"; backup_to "$undo"
  rollback() { local status=$?; trap - EXIT; if [ "$status" != 0 ]; then apply_backup "$undo" || echo "ROLLBACK FAILED: recover from $undo" >&2; fi; exit "$status"; }
  trap rollback EXIT
  apply_backup "$b" || fail 'restore failed'
  # Restore safety is not an install backup; exclude it from future --restore.
  case "$undo/.complete" in "$BACKUP_ROOT/$SELECTED"-*/.complete) rm -f -- "$undo/.complete" ;; *) fail 'unexpected safety path' ;; esac
  trap - EXIT; echo 'Restored all four files (including originally absent client). Restart DSH and hard-refresh.'; exit 0
fi
# Validate ALL four payload files before any backup or target mutation, even --check.
[ -f "$MANIFEST" ] || fail 'manifest missing'
for i in 0 1 2 3; do rel="${FILES[$i]}"; expected="$(get "payload${KEYS[$i]}Sha256")"; [ -f "$PAYLOAD/$rel" ] && [ "$(sha "$PAYLOAD/$rel")" = "$expected" ] || fail "payload checksum mismatch: $rel"; done
ST="$(state)"; printf 'profile: %s\nstate: %s\n' "$SELECTED" "$ST"
if [ "$MODE" = check ]; then [ "$ST" != unknown ] || exit 2; exit 0; fi
[ "$ST" != patched ] || { echo 'Already up to date; no backup or copy needed.'; exit 0; }
if [ "$ST" = unknown ] && [ "$FORCE" = 0 ]; then echo 'Refusing drift: exact pristine, previous-overlay, codex-overlay, compact-overlay, maid-overlay, or quiet-overlay hashes required.' >&2; exit 2; fi
[ "$DRY" = 0 ] || { echo 'Would back up and replace all four allowlisted files.'; exit 0; }
b="$(unique_backup)"; backup_to "$b"
rollback() { local status=$?; trap - EXIT; if [ "$status" != 0 ]; then apply_backup "$b" || echo "ROLLBACK FAILED: recover from $b" >&2; fi; exit "$status"; }
trap rollback EXIT
for rel in "${FILES[@]}"; do cp "$PAYLOAD/$rel" "$TARGET/$rel"; done
match payload || fail 'installed checksum mismatch'
trap - EXIT
echo "Installed. Backup: $b"
echo 'Restart DSH (host + client registration), then hard-refresh the page. Stop DSH before --restore.'
