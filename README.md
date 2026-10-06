# .myharness

This document provides copy-pasteable scripts to download the `.agents` configuration folder from a public Git repository into any project folder.

By running any of these commands from your project root, a temporary sparse clone is created to fetch only the required `.agents` folder (including rules like `.agents/rules/AGENTS.md`, skills, and configs), copying it over and cleaning up afterward without affecting your local Git configuration.

---

## 1. PowerShell (Windows)

For use in modern Windows PowerShell or PowerShell Core:

```powershell
git clone --depth 1 --sparse --filter=blob:none https://github.com/gnutnaux337/.myharness.git temp_harness; cd temp_harness; git sparse-checkout set .agents; Copy-Item -Path .agents -Destination ..\.agents -Recurse -Force; cd ..; Remove-Item -Path temp_harness -Recurse -Force
```

---

## 2. Command Prompt (Windows CMD)

For use in standard Windows CMD:

```cmd
git clone --depth 1 --sparse --filter=blob:none https://github.com/gnutnaux337/.myharness.git temp_harness && cd temp_harness && git sparse-checkout set .agents && xcopy /E /I /Y .agents ..\.agents && cd .. && rmdir /S /Q temp_harness
```

---

## 3. Bash / Zsh (Linux & macOS)

For use in Linux or macOS terminal environments:

```bash
git clone --depth 1 --sparse --filter=blob:none https://github.com/gnutnaux337/.myharness.git temp_harness && cd temp_harness && git sparse-checkout set .agents && cp -r .agents ../.agents && cd .. && rm -rf temp_harness
```

---

## 4. dsh-whale-widget — bilingual interface and active Codex usage

Adds an English interface with a language switch to the `dsh-whale-widget` DSH
plugin (upstream is Chinese-only). Both dictionaries are inlined in the overlay,
so installing needs no build step and no network.

The whale also follows the active chat's Codex/ChatGPT provider and displays
subscription usage windows supplied by the **default Codex subscription account**.
This does not identify the account selected by a routing pool for a particular
request. Missing/stale quota is labelled rather than treated as unlimited;
API-key usage is not a ChatGPT subscription balance. Local token fallback is not
implemented in this release. Switching back to DeepSeek keeps its existing
balance display. No credentials or account state are shipped in this repo.

### Included display and startup behavior

- Centered, responsive maid-style quota text: **At your service, Sir ♡**.
- Shows remaining five-hour and weekly allowances with live reset countdowns
  (for example, `3h 56m` or `6d 10h 50m`), using the default Codex account.
- Clearly marks stale values as last known and expired resets as awaiting refreshed quota.
- Suppresses **only the DeepSeek low-balance popup at startup**. An already-low
  initial balance stays quiet; after recovery above the configured threshold,
  a later drop below it triggers the normal reminder. Budget reminders and the
  maid widget remain enabled. No extra setting is required.

### Quick start — existing local copy

The latest overlay is saved in this repository. No build is needed. Install the
upstream `dsh-whale-widget` plugin first; for subscription quota, also make sure
`dsh-plugin-subscriptions` is available and your Codex account is logged in.

**Quit DSH before installing**, then run from this repository's root:

```bash
# macOS / Linux — desktop app
bash scripts/install-whale-i18n.sh --profile desktop --check
bash scripts/install-whale-i18n.sh --profile desktop --dry-run
bash scripts/install-whale-i18n.sh --profile desktop
# Verify the installed files; expected state: patched
bash scripts/install-whale-i18n.sh --profile desktop --check
```

```powershell
# Windows — desktop app (PowerShell installer is reviewed, not runtime-tested)
.\scripts\install-whale-i18n.ps1 -Profile desktop -Check
.\scripts\install-whale-i18n.ps1 -Profile desktop -DryRun
.\scripts\install-whale-i18n.ps1 -Profile desktop
.\scripts\install-whale-i18n.ps1 -Profile desktop -Check
```

For the web profile, substitute `web` for `desktop`. Restart DSH after installation
and hard-refresh the page. Open a Codex chat to see the maid-style quota display.
Reopening the app with an already-low DeepSeek balance should no longer show its
startup low-balance popup.

To undo the latest installation, quit DSH and restore the newest backup:

```bash
bash scripts/install-whale-i18n.sh --profile desktop --restore
```

```powershell
.\scripts\install-whale-i18n.ps1 -Profile desktop -Restore
```

Then restart DSH and hard-refresh again. Restore reverses the most recent overlay
installation; it does not necessarily return to pristine upstream if that backup
was an earlier overlay.

### Getting it onto a new machine

The GitHub commands below retrieve the latest overlay only after its commit has
been pushed. A local commit alone does not publish it; the installer never commits
or pushes changes.

The `.agents` snippets in sections 1–3 fetch only `.agents`; this installer also
needs `scripts` and `plugins`, so set the sparse-checkout accordingly:

```bash
git clone --depth 1 --sparse --filter=blob:none https://github.com/gnutnaux337/.myharness.git temp_harness
cd temp_harness && git sparse-checkout set scripts plugins
./scripts/install-whale-i18n.sh
```

The upstream plugin itself must already be installed on that machine — this repo
ships only the overlay, not the plugin:

```bash
dsh plugin --profile web add dsh-whale-widget
# desktop app: ask DSH in a chat to install "dsh-whale-widget"; the CLI refuses
# that profile by design, so there is no command for it
```

The installer says exactly this if it cannot find the plugin. Then continue with
the refresh/restart/verify steps below.

### Running it

Run from the repo root (or call the script by its path):

```bash
./scripts/install-whale-i18n.sh           # auto-detect the profile
./scripts/install-whale-i18n.sh --check   # report only
./scripts/install-whale-i18n.sh --restore # undo (restores the newest backup)
```

```powershell
.\scripts\install-whale-i18n.ps1
.\scripts\install-whale-i18n.ps1 -Check
.\scripts\install-whale-i18n.ps1 -Restore
```

What it does:

1. finds the plugin under `$DSH_HOME/profiles/{desktop,web}/node_modules/dsh-whale-widget`
   (auto prefers `desktop`, because `dsh plugin` refuses that profile by design);
2. validates all four payload checksums before changing anything and accepts
   only exact upstream or supported earlier overlay hashes (bilingual, Codex,
   compact quota, and maid-style releases; not marker text);
3. backs up `assets/whale-widget.js`, `lib/index.js`, `lib/client.js`, and
   `package.json` under `$DSH_HOME/.dshw-i18n-backups/`, recording originally absent
   files so restore can remove the newly added client loader;
4. copies the four-file overlay, rolling back the entire set if copying fails.

The packaged `package.json` is derived from the pristine installed upstream
manifest, adding only client exports and `dsh.client` registration. Fork-only
build scripts and development dependencies are not copied into your install.
Restore validates every backup before writing, and retains a separate recovery
snapshot if restore itself fails. Legacy two-file backups must be restored with
the previous installer; this installer never guesses missing metadata.

Options: `--profile desktop|web`, `--dsh-home <path>`/`-DshHome`, `--dry-run`/`-DryRun`,
`--force`/`-Force`.

**Stop DSH before install or restore. Restart DSH afterwards, then hard-refresh
the page**. Restart is compulsory for both the host half and the new client-plugin
registration; refreshing alone cannot register it.

For ChatGPT subscription quota, `dsh-plugin-subscriptions` must be available and
the relevant account logged in. If the account/provider supplies no quota, the
widget labels it unavailable instead of substituting another account's limits.

Verify it is live:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:<port>/dsh-whale/lang.json
#   404 -> the host half is not loaded yet;  401 -> loaded (registered, needs auth)
cat "$DSH_HOME/.dshw-lang.json"
#   appears after the first page load: the widget telling the host its language
```

Notes:

- The overlay was built against upstream **0.3.18**. Compatibility requires exact
  hashes of all four files (the original client is absent), or the exact previous
  bilingual overlay. Drift is refused with exit 2. `--force`/`-Force` bypasses that
  safety check and may downgrade code; avoid it for a newer upstream version.
- An exact re-apply is a no-op and creates no backup, preserving useful restore
  history. `--check` verifies checksums, not just translation markers.
- The plugin menu gets an **Interface language / 界面语言** row with `中文` and
  `English`. With no saved choice, the language follows DSH / the browser on first
  run, falling back to Chinese.
- User data (bubble content, custom roles and audio, the language file) is never
  touched. Provenance for the overlay files: `plugins/dsh-whale-widget-i18n/manifest.json`.
- The **`.sh` installer is tested** (dry-run, install, re-apply, restore, version
  drift, missing plugin, bad arguments). The **`.ps1` twin has only been reviewed,
  not executed** — on Windows run it with `-DryRun` first, which changes nothing
  and prints exactly what it would do.
