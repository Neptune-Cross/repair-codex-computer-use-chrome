---
name: repair-codex-computer-use-chrome
description: Fast Windows repair workflow for Codex Desktop `computer-use@openai-bundled`, `chrome@openai-bundled`, and `browser@openai-bundled` failures. Use when Computer Use or Chrome plugins cannot install, show unavailable, lose `latest` junctions, miss Chrome Native Messaging state, `openai-bundled` points at a broken `.tmp` mirror, `codex://` opens the wrong package, or repeated repair takes several minutes.
---

# Repair Codex Computer Use Chrome

## Quick Start

Run the bundled script first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\repair-codex-computer-use-chrome\scripts\repair.ps1"
```

The script uses environment variables and local discovery instead of hard-coded user names:

- `$env:CODEX_HOME`, falling back to `$env:USERPROFILE\.codex`
- `$env:LOCALAPPDATA`
- the newest user-local `OpenAI\Codex\bin\*\codex.exe`
- the current `OpenAI.Codex_*` AppX package from registry or `C:\Program Files\WindowsApps`
- the bundled `scripts/install-computer-use-local.ps1` repair engine, with fallback to a locally installed `codex-windows-fast-patch` copy only if the bundled engine is missing

## Preconditions

- Windows Codex Desktop is installed for the current user.
- Chrome is installed.
- The Codex Chrome extension is already installed and enabled from the Chrome Web Store. The script repairs Native Messaging and local helper paths, but it does not install the browser extension from the store.
- The current user can write to `$env:USERPROFILE\.codex`, `$env:LOCALAPPDATA\OpenAI\extension`, and the relevant `HKCU` registry keys.

## Workflow

1. Run `scripts/repair.ps1`.
2. Trust the script output for the actual `codex.exe`, package id, plugin versions, backup path, and check results.
3. If strict verification already passes, do not rebuild caches.
4. If repair was needed, let the script regenerate Chrome Native Messaging and sync `codex://`.
5. Restart Codex Desktop or open a new conversation if the settings page still shows stale plugin state.

## What The Script Fixes

- Runs `install-computer-use-local.ps1 -StrictVerifyOnly`.
- On failure or `-ForceRepair`, runs `install-computer-use-local.ps1 -VerifyOnly`.
- Rebuilds or verifies `openai-bundled` marketplace/cache through the bundled repair engine.
- Ensures `computer-use`, `browser`, and `chrome` `latest` junctions point at stable cache directories.
- Regenerates the Chrome Native Messaging manifest under `$env:LOCALAPPDATA\OpenAI\extension`.
- Registers `HKCU\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension`.
- Pins the native-host executable and browser client paths to the concrete Chrome cache version instead of `latest`.
- Updates `HKCU\Software\Classes\codex` to the current `OpenAI.Codex_*` package.
- Verifies plugin marketplace/list output, Chrome native-host state, Chrome extension state, and Computer Use helper transport.

## Live Probes

When `mcp__node_repl` is available after the script passes:

1. Import `chrome/latest/scripts/browser-client.mjs`.
2. Call `setupBrowserRuntime({ globals: globalThis })`.
3. Run `agent.browsers.list()` and confirm a Chrome extension backend appears.
4. Import `computer-use/latest/scripts/computer-use-client.mjs`.
5. Call `setupComputerUseRuntime({ globals: globalThis })`.
6. Run read-only `sky.list_apps()` to confirm Computer Use can call the helper.

## Failure Routing

- `missing plugin manifest` under `.codex\.tmp\bundled-marketplaces`: run the script; it should resync the mirror from the installed AppX package.
- `Chrome native messaging manifest not found`: the script regenerates it from `chrome\latest\scripts\installManifest.mjs`.
- `manifest does not point at stable cache path`: the script rewrites it to the concrete Chrome cache version.
- `native pipe path is unavailable` after disk checks pass: restart Codex Desktop and retest in a fresh conversation before rebuilding files again.
- `Get-AppxPackage` is unavailable: the script uses registry and WindowsApps folder fallback discovery.
- Chrome extension check reports not installed or disabled: ask the user to install or enable the Codex extension from the Chrome Web Store, then rerun the script.
