# Total Commander — Markdown viewer (F3 / Ctrl+Q)

> Reusable installer + docs for GitHub-style Markdown preview in Total Commander.
> Run `Install-MarkdownViewerTC.ps1` from this repo — details below.

GitHub-style Markdown preview inside Total Commander, via the
[Serg2000Mr `wlx-markdown-viewer-github-style`](https://github.com/Serg2000Mr/wlx-markdown-viewer-github-style)
lister plugin (Markdig + WebView2/Chromium, Native AOT — no .NET install needed).

- **Script:** `Install-MarkdownViewerTC.ps1` (same folder as this doc)
- **Target layout:** Total Commander installed at `C:\Utils\TotalCmd`
  (override with `-TcPath` for other locations)
- **Result:** `F3` on any `.md` / `.markdown` file renders a formatted page;
  `Ctrl+Q` shows the same live in the opposite panel.

## Requirements

- Windows 10/11 + Total Commander 9.0 or newer (32-bit, 64-bit, or both).
- Microsoft Edge **WebView2 Runtime** — preinstalled on current Windows 10/11.
  The script only *warns* if it is missing; if previews render blank, install it from
  <https://developer.microsoft.com/en-us/microsoft-edge/webview2/>.
- PowerShell 5.1+ with permission to write into the Total Commander folder
  (run elevated if TC lives under `Program Files`).
- Internet access to `github.com` for the plugin download
  (or pre-place the zips — see “Offline use”).

## Quick start

```powershell
# 1. Close Total Commander (important — it rewrites wincmd.ini on exit).
# 2. From this folder, run:
.\Install-MarkdownViewerTC.ps1
```

Custom TC location, or TC already closed manually:

```powershell
.\Install-MarkdownViewerTC.ps1 -TcPath 'D:\Portable\TotalCmd'
.\Install-MarkdownViewerTC.ps1 -TcPath 'D:\Portable\TotalCmd' -LeaveRunning
```

| Parameter      | Default              | Meaning                                                      |
|----------------|----------------------|--------------------------------------------------------------|
| `-TcPath`      | `C:\Utils\TotalCmd`  | TC folder (must contain `TOTALCMD.EXE`/`TOTALCMD64.EXE` + `wincmd.ini`) |
| `-Version`     | `v1.3.1`             | Plugin release tag to download                               |
| `-LeaveRunning`| off                  | Skip the close/restart of TC (you closed it yourself)        |

The script is **idempotent** — safe to re-run; it removes only its own previous
registration lines and re-adds them at the next free plugin index.

## What the script does

1. **Preconditions** — checks the TC folder, `wincmd.ini`, and WebView2 Runtime
   (registry `HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\*`).
2. **Closes TC** (`TOTALCMD64`/`TOTALCMD`), unless `-LeaveRunning`.
   This matters: TC rewrites `wincmd.ini` on exit and would silently drop the edit.
3. **Downloads** both release zips and verifies SHA-256:
   - `wlx-markdown-viewer-github-style-release-x64.zip`
     `D38BEFBAD0D70507CD131E3D1E4C624AABA89196BF53B6832379EBE83AFDAE88`
   - `wlx-markdown-viewer-github-style-release-x86.zip`
     `2B3105BEC6E972FB6C13640B97190C5E92E5AE58030F315F1C3A3DFD6C72D4B0`
4. **Installs files** to `<TcPath>\plugins\wlx\MarkdownViewGitHubStyle\`:
   the x64 set as-is, plus the x86 `MarkdownView.wlx`, `Markdown-x86.dll`,
   `dotnet-x86\` runtime (so 32-bit TC works with no .NET install) and
   `runtimes\win-x86\` — without overwriting the x64 root files.
5. **Patches `MarkdownView.ini`** — fixes the shipped ` MarkdownExtensions`
   (leading space) typo so the key parses, sets `[Translate] Enabled=0`
   (no auto Google Translate); GitHub CSS stays default:
   `[Renderer] CustomCSS=css\github.css`, `CustomCSSDark=css\github.dark.css`.
6. **Registers the lister plugin** — backs up `wincmd.ini`
   (`wincmd.ini.backup-<timestamp>` + first-run `wincmd.ini.pre-md-plugin.bak`),
   then adds entries to `[ListerPlugins]` (32-bit TC) and `[ListerPlugins64]`
   (64-bit TC), each with an `N_detect` filter covering
   `MD MARKDOWN MDOWN MDTEXT MDTXT MDWN MK MKD MKDN MKDOWN MDC` — never `.txt`.
7. **Verifies** — all files present, ini keys correct, detect filter set, and
   `ListLoad` exported from the DLL matching *this* PowerShell's bitness
   (64-bit PS \(\rightarrow\) `.wlx64`; to check the 32-bit `.wlx`, run the script from
   `C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe`).
8. **Restarts TC** (unless `-LeaveRunning`).

## Verify it works

- `F3` on any `.md` file → styled headings, aligned tables, highlighted code
  with copy button, images, task-list checkboxes, Mermaid diagram.
- `Ctrl+Q` on the same file → same rendering live in the opposite panel.
- `4` in Lister → cycles plugins if another viewer grabs `.md` first.
- `Ctrl+wheel` zooms, `Ctrl+0` resets; `ESC` closes.
- Negative check: rename a copy to `.txt` → the plugin must *not* claim it
  (extension scoping intact).

## Resulting configuration (reference)

`wincmd.ini`:

```ini
[ListerPlugins]
0=C:\Utils\TotalCmd\plugins\wlx\MarkdownViewGitHubStyle\MarkdownView.wlx
0_detect="EXT="MD" | EXT="MARKDOWN" | EXT="MDOWN" | EXT="MDTEXT" | EXT="MDTXT" | EXT="MDWN" | EXT="MK" | EXT="MKD" | EXT="MKDN" | EXT="MKDOWN" | EXT="MDC""
[ListerPlugins64]
0=C:\Utils\TotalCmd\plugins\wlx\MarkdownViewGitHubStyle\MarkdownView.wlx64
0_detect="EXT="MD" | EXT="MARKDOWN" | EXT="MDOWN" | EXT="MDTEXT" | EXT="MDTXT" | EXT="MDWN" | EXT="MK" | EXT="MKD" | EXT="MKDN" | EXT="MKDOWN" | EXT="MDC""
```

(`N` auto-adjusts to the next free index if other lister plugins exist.
`$checksum$` lines are TC's own bookkeeping — leave them alone.)

`MarkdownView.ini` (only file ever edited by hand):

```ini
[Renderer]
Extensions=common+advanced+emojis+mathematics+tasklists+diagrams
CustomCSS=css\github.css
CustomCSSDark=css\github.dark.css

[Translate]
Enabled=0

[FastFont]
Enabled=1
```

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Blank preview | WebView2 Runtime missing → install from the link above, restart TC. |
| Registration “vanishes” | TC was running during install and rewrote `wincmd.ini` on exit → close TC first (no `-LeaveRunning`), re-run. |
| Plugin not picked for `.md` | Another lister plugin has priority → press `4` in Lister to cycle. |
| Need a debug trace | Add `[Debug]` / `Log=1` to `MarkdownView.ini`, reproduce, read `MarkdownView_Log.ini` next to the DLL, then remove the `[Debug]` section again. |
| Roll back | Restore `wincmd.ini.pre-md-plugin.bak` (TC closed), optionally delete `plugins\wlx\MarkdownViewGitHubStyle\`. |

## Offline use

Pre-download both zips into `$env:TEMP\mdview-tc\`
(`wlx-markdown-viewer-github-style-release-x64.zip` and `-x86.zip`);
the script skips downloading files that are already there (hash still verified).

## Why this plugin

Fork of the most-starred `rg-software/wlx-markdown-viewer`, replacing the obsolete
IE engine with Markdig (GFM) + WebView2/Chromium: faithful GitHub rendering —
tables, task lists, code highlight + copy, emoji shortcodes, Mermaid, LaTeX math,
local images, intra-doc anchors — with 6 bundled CSS themes and x86 + x64 builds.
The original author himself points Windows 10/11 users at this WebView2 generation.
