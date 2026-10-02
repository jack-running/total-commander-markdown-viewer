# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A single Windows PowerShell installer, `Install-MarkdownViewerTC.ps1`, that installs
a Markdown lister (WLX) plugin into Total Commander and registers it in `wincmd.ini`
so `F3` / `Ctrl+Q` render `.md` files. `README.md` is the user-facing doc. There is
no build, no test suite, no linter config, and no CI.

## Running / checking

The script targets Windows PowerShell 5.1+ and a real Total Commander install; it
cannot be meaningfully run on Linux (registry, `Get-Process TOTALCMD*`,
`LoadLibrary` of the `.wlx`/`.wlx64` DLLs).

```powershell
.\Install-MarkdownViewerTC.ps1                         # MDView (default)
.\Install-MarkdownViewerTC.ps1 -Renderer GitHubStyle
.\Install-MarkdownViewerTC.ps1 -TcPath 'D:\Portable\TotalCmd' -LeaveRunning
```

If `pwsh` is available, a syntax-only check is:

```sh
pwsh -NoProfile -Command '$e=$null; [System.Management.Automation.Language.Parser]::ParseFile("Install-MarkdownViewerTC.ps1",[ref]$null,[ref]$e) | Out-Null; $e'
```

The script self-verifies at runtime via `Assert-True` (throws on failure); new
behavior should add matching `Assert-True` checks rather than silent assumptions.

## Architecture of the installer

- **Renderer catalog (`$Plugins` hashtable)** drives everything per renderer:
  plugin dir name, GitHub repo, default version, release zip names + pinned
  SHA-256, 32/64-bit DLL names, the `N_detect` filter string, `Superseded` regexes
  (the *other* renderer's lines to retire), and DLL exports to verify. Adding or
  bumping a renderer should mostly be a catalog edit.
- **Steps run in order**: preconditions → close TC → download + hash check →
  extract/copy files → register in `wincmd.ini` → DLL export check → restart TC.
  TC must be closed before editing `wincmd.ini` because it rewrites the file on exit.
- **Downloads** are cached in `$env:TEMP\mdview-tc\` (also the offline-use path).
  Zip names embed the default version and are rewritten when `-Version` overrides
  it; hashes are only enforced for the default version.
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
    since `[ListerPlugins]` would prefix-match `[ListerPlugins64]`), creates it if
    missing, and appends at the next free numeric index.
- `wincmd.ini` is read/written with `[System.Text.Encoding]::Default` (system ANSI
  codepage, as TC writes it). Backups: `wincmd.ini.backup-<timestamp>` every run,
  `wincmd.ini.pre-md-plugin.bak` on first run only.
- Detect filters must stay markdown-only; the script asserts the result never
  claims `EXT="TXT"`.
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
