# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A single Windows PowerShell installer, `Install-MarkdownViewerTC.ps1`, that installs
a Markdown lister (WLX) plugin into Total Commander and registers it in `wincmd.ini`
so `F3` / `Ctrl+Q` render `.md` files. `README.md` is the user-facing doc. There is
no build, no test suite, no linter config, and no CI.

## Running / checking

The script targets Windows PowerShell 5.1+ and a real Total Commander install.
Keep it ASCII-only: PS 5.1 reads BOM-less UTF-8 as ANSI.

```powershell
.\Install-MarkdownViewerTC.ps1                         # MDView (default)
.\Install-MarkdownViewerTC.ps1 -Renderer GitHubStyle
.\Install-MarkdownViewerTC.ps1 -TcPath 'D:\Portable\TotalCmd' -LeaveRunning
```

If `pwsh` is available, a syntax-only check is:

```sh
pwsh -NoProfile -Command '$e=$null; [System.Management.Automation.Language.Parser]::ParseFile("Install-MarkdownViewerTC.ps1",[ref]$null,[ref]$e) | Out-Null; $e'
```

On Linux, `pwsh` can run steps 1–5 against a fake TC folder (an empty
`TOTALCMD64.EXE` plus a sample `wincmd.ini`): it downloads, checks hashes,
copies files and edits the ini, then fails at the `LoadLibrary` export check,
which is expected. Set `TEMP` and pass `-LeaveRunning`. Use a fresh folder per
run. Paths TC stores with `\` (e.g. `%COMMANDER_PATH%\x.ini`) only resolve on
Windows; use `/` in Linux test data.

The script self-verifies at runtime via `Assert-True` (throws on failure); new
behavior should add matching `Assert-True` checks rather than silent assumptions.

## Architecture of the installer

- **Renderer catalog (`$Plugins` hashtable)** drives everything per renderer:
  plugin dir name, GitHub repo, default version, release zip names + pinned
  SHA-256, 32/64-bit DLL names, the `N_detect` filter string, `Superseded` regexes
  (the *other* renderer's lines to retire), and DLL exports to verify. Adding or
  bumping a renderer should mostly be a catalog edit.
- **Steps run in order**: preconditions (incl. locating the real `wincmd.ini`) →
  close TC → download + hash check → extract/copy files → register in
  `wincmd.ini` → DLL export check → restart TC. TC must be closed before editing
  `wincmd.ini` because it rewrites the file on exit; it is closed normally
  (`CloseMainWindow`) so it saves its own state first, and force-killed only
  after a timeout.
- **ini location** mirrors TC: `-IniPath` (used as given), else
  `UseIniInProgramDir` bit 1 in `<TcPath>\wincmd.ini`, else the registry
  `IniFileName`, else `<TcPath>\wincmd.ini`, else `%APPDATA%\GHISLER`;
  `AlternateUserIni` and per-section `RedirectSection=` are followed
  (`Expand-TcPath` handles `%COMMANDER_PATH%`/env vars).
- **Downloads** are cached in `$env:TEMP\mdview-tc\` (also the offline-use path).
  Zip names embed the default version and are rewritten when `-Version` overrides
  it; hashes are only enforced for the default version. A cached zip with a bad
  hash is downloaded again once.
- **GitHubStyle install** copies the x64 zip wholesale, then adds only the x86
  pieces side by side (`MarkdownView.wlx`, `Markdown-x86.dll`, `dotnet-x86`,
  `runtimes\win-x86`) — it must never overwrite x64 root files such as
  `WebView2Loader.dll`. It also patches the shipped `MarkdownView.ini`
  (leading-space ` MarkdownExtensions` typo, `[Translate] Enabled=0`).
- **`Register-Section`** is the idempotency core, applied to `[ListerPlugins]`
  (32-bit TC → `.wlx`) and `[ListerPlugins64]` (64-bit TC → `.wlx64`):
  - pass 1 drops this renderer's own lines, `Superseded` lines, their immediately
    following `N_detect` line, and TC junk `N=1` lines — never a foreign plugin's
    `N_detect`;
  - pass 2 locates the section by exact string (`IndexOf`/`-eq`, *not* `-match`,
    since `[ListerPlugins]` would prefix-match `[ListerPlugins64]`) and creates it
    if missing;
  - pass 3 makes our plugin entry `0` (TC uses the first matching plugin) and
    renumbers the others `1..n` in their old order, moving all `N=`/`N_*=` keys
    of an entry together. Use a plain hashtable for index groups: an `[ordered]`
    dictionary's int indexer is positional.
- `Get-IniEncoding` keeps the file's encoding: UTF-16 LE / UTF-8 if it has a BOM,
  else the ANSI codepage (`[Text.Encoding]::Default` is UTF-8 on PowerShell 7, so
  don't use it). Backups: `<ini>.backup-<timestamp>` every run,
  `<ini>.pre-md-plugin.bak` on first run only.
- Detect filters must stay markdown-only; the script asserts our `0_detect` never
  claims `EXT="TXT"` (other plugins may).
- The DLL export check only loads the DLL matching the current PowerShell's
  bitness.

## Keeping docs in sync

`README.md` duplicates facts from the script: default versions, zip names and
SHA-256 hashes, extension lists / detect strings, install paths, the
`MarkdownView.ini` patches, and the step list. When changing any of these in the
script, update the README's Renderers table, "What the script does", "Resulting
configuration", and "Offline use" sections too. The comment-based help block at
the top of the script also mirrors parameters and steps.

Key domain fact behind the two renderers: GitHubStyle cannot close Lister on `Esc`
(WebView2 runs out of process, so the plugin's `WH_KEYBOARD` hook never sees it;
upstream PR #7 unmerged), which is why MDView is the default.
