# .myharness

This document provides copy-pasteable scripts to download the `.agents` configuration folder and the `AGENTS.md` file from a public Git repository into any project folder.

By running any of these commands from your project root, a temporary sparse clone is created to fetch only the required `.agents` folder and `AGENTS.md` file, copying them over and cleaning up afterward without affecting your local Git configuration.

---

## 1. PowerShell (Windows)

For use in modern Windows PowerShell or PowerShell Core:

```powershell
git clone --depth 1 --sparse --filter=blob:none https://github.com/gnutnaux337/.myharness.git temp_harness; cd temp_harness; git sparse-checkout set .agents; Copy-Item -Path .agents -Destination ..\.agents -Recurse -Force; Copy-Item -Path AGENTS.md -Destination ..\AGENTS.md -Force; cd ..; Remove-Item -Path temp_harness -Recurse -Force
```

---

## 2. Command Prompt (Windows CMD)

For use in standard Windows CMD:

```cmd
git clone --depth 1 --sparse --filter=blob:none https://github.com/gnutnaux337/.myharness.git temp_harness && cd temp_harness && git sparse-checkout set .agents && xcopy /E /I /Y .agents ..\.agents && copy /Y AGENTS.md ..\AGENTS.md && cd .. && rmdir /S /Q temp_harness
```

---

## 3. Bash / Zsh (Linux & macOS)

For use in Linux or macOS terminal environments:

```bash
git clone --depth 1 --sparse --filter=blob:none https://github.com/gnutnaux337/.myharness.git temp_harness && cd temp_harness && git sparse-checkout set .agents && cp -r .agents ../.agents && cp AGENTS.md ../AGENTS.md && cd .. && rm -rf temp_harness
```
