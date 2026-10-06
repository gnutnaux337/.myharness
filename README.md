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

## 4. dsh-whale-widget — bilingual (Chinese/English) interface

Adds an English interface with a language switch to the `dsh-whale-widget` DSH
plugin (upstream is Chinese-only). Both dictionaries are inlined in the overlay,
so installing needs no build step and no network.

### Getting it onto a new machine

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
2. backs up `assets/whale-widget.js` and `lib/index.js` to
   `$DSH_HOME/.dshw-i18n-backups/<profile>-<timestamp>/` (deliberately **not** in
   `node_modules`, which pnpm prunes);
3. copies the overlay over those two files, verifying payload checksums;
4. prints what to do next and how to verify.

Options: `--profile desktop|web`, `--dsh-home <path>`/`-DshHome`, `--dry-run`/`-DryRun`,
`--force`/`-Force`.

Then **refresh the page** (the widget half is re-read from disk per request) and
**restart DSH** (the host half only loads at startup).

Verify it is live:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:<port>/dsh-whale/lang.json
#   404 -> the host half is not loaded yet;  401 -> loaded (registered, needs auth)
cat "$DSH_HOME/.dshw-lang.json"
#   appears after the first page load: the widget telling the host its language
```

Notes:

- The overlay was built against upstream **0.3.18**. If the installed plugin is a
  different version the installer **refuses** (exit 2) rather than putting older
  upstream code back; rebuild against that version instead — see the source fork's
  README ("Re-applying after an upstream update") — or use `--force`/`-Force`.
- The plugin menu gets an **Interface language / 界面语言** row with `中文` and
  `English`. With no saved choice, the language follows DSH / the browser on first
  run, falling back to Chinese.
- User data (bubble content, custom roles and audio, the language file) is never
  touched. Provenance for the overlay files: `plugins/dsh-whale-widget-i18n/manifest.json`.
- The **`.sh` installer is tested** (dry-run, install, re-apply, restore, version
  drift, missing plugin, bad arguments). The **`.ps1` twin has only been reviewed,
  not executed** — on Windows run it with `-DryRun` first, which changes nothing
  and prints exactly what it would do.
