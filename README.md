# Total Commander — Markdown viewer (F3 / Ctrl+Q)

> Reusable installer + docs for Markdown preview in Total Commander.
> Run `Install-MarkdownViewerTC.ps1` from this repo — details below.

GitHub-style Markdown preview inside Total Commander via the
[`rweijnen/MDView`](https://github.com/rweijnen/MDView) lister plugin
(WebView2/Chromium, single small DLL, no .NET install needed).

- **Script:** `Install-MarkdownViewerTC.ps1` (same folder as this doc)
- **Target layout:** Total Commander installed at `C:\Utils\TotalCmd`
  (override with `-TcPath` for other locations)
- **Result:** `F3` on any `.md` / `.markdown` file renders a formatted page;
  `Ctrl+Q` shows the same live in the opposite panel; **`Esc` closes the viewer**.

## Requirements

- Windows 10/11 + Total Commander 9.0 or newer (32-bit, 64-bit, or both).
- Microsoft Edge **WebView2 Runtime** — preinstalled on current Windows 10/11.
  The script only *warns* if it is missing; if previews render blank, install it from
  <https://developer.microsoft.com/en-us/microsoft-edge/webview2/>.
- PowerShell 5.1+ with permission to write into the Total Commander folder
  (run elevated if TC lives under `Program Files`).
- Internet access to `github.com` for the plugin download
  (or pre-place the zip — see “Offline use”).

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
| `-Version`     | `v0.2.4`             | MDView release tag to download                               |
| `-LeaveRunning`| off                  | Skip the close/restart of TC (you closed it yourself)        |

The script is **idempotent** — safe to re-run; it removes only its own previous
registration lines (plus the retired `MarkdownViewGitHubStyle` ones) and re-adds
its entry at the next free plugin index.

## What the script does

1. **Preconditions** — checks the TC folder, `wincmd.ini`, and WebView2 Runtime
   (registry `HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\*`).
2. **Closes TC** (`TOTALCMD64`/`TOTALCMD`), unless `-LeaveRunning`.
   This matters: TC rewrites `wincmd.ini` on exit and would silently drop the edit.
3. **Downloads** the release zip and verifies SHA-256:
   - `MDView-v0.2.4.zip`
     `A1EDFFFB810FED3821C283BEF66027CF70DDDE65D0380EDFB6FC535D523F4170`
4. **Installs files** to `<TcPath>\plugins\wlx\mdview\`:
   `mdview.wlx` (32-bit TC), `mdview.wlx64` (64-bit TC), plus the standalone
   `mdview.exe` viewer.
5. **Registers the lister plugin** — backs up `wincmd.ini`
   (`wincmd.ini.backup-<timestamp>` + first-run `wincmd.ini.pre-md-plugin.bak`),
   retires any `MarkdownViewGitHubStyle` lines (only one Markdown WLX at a time),
   then adds entries to `[ListerPlugins]` (32-bit TC) and `[ListerPlugins64]`
   (64-bit TC), each with the detect filter taken verbatim from the plugin's
   `ListGetDetectString` (`EXT="MD" | EXT="MARKDOWN"`) — never `.txt`.
6. **Verifies** — files present, ini lines correct, old plugin gone, detect filter
   set, and `ListLoad` + `ListGetDetectString` exported from the DLL matching
   *this* PowerShell's bitness (64-bit PS → `.wlx64`; to check the 32-bit `.wlx`,
   run the script from `C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe`).
7. **Restarts TC** (unless `-LeaveRunning`).

## Verify it works

- `F3` on any `.md` file → tables, task lists, strikethrough, code blocks,
  clickable `.md` links; dark mode follows Windows.
- `Ctrl+Q` on the same file → same rendering live in the opposite panel.
- **`Esc` closes the viewer** (also in Quick View).
- `4` in Lister → cycles plugins if another viewer grabs `.md` first.
- Negative check: rename a copy to `.txt` → the plugin must *not* claim it
  (extension scoping intact).

## Resulting configuration (reference)

`wincmd.ini`:

```ini
[ListerPlugins]
0=C:\Utils\TotalCmd\plugins\wlx\mdview\mdview.wlx
0_detect="EXT="MD" | EXT="MARKDOWN""
[ListerPlugins64]
0=C:\Utils\TotalCmd\plugins\wlx\mdview\mdview.wlx64
0_detect="EXT="MD" | EXT="MARKDOWN""
```

(`N` auto-adjusts to the next free index if other lister plugins exist.
`$checksum$` lines are TC's own bookkeeping — leave them alone.)

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Blank preview | WebView2 Runtime missing → install from the link above, restart TC. |
| Registration “vanishes” | TC was running during install and rewrote `wincmd.ini` on exit → close TC first (no `-LeaveRunning`), re-run. |
| Plugin not picked for `.md` | Another lister plugin has priority → press `4` in Lister to cycle. |
| Roll back | Restore `wincmd.ini.pre-md-plugin.bak` (TC closed), optionally delete `plugins\wlx\mdview\`. |

## Offline use

Pre-download the zip into `$env:TEMP\mdview-tc\`
(`MDView-v0.2.4.zip`); the script skips downloading when the file is already
there (hash still verified).

## Why this plugin

The previous pick (Serg2000Mr `wlx-markdown-viewer-github-style` v1.3.1) renders
beautifully but **swallows Esc**: WebView2 runs in a separate Chromium process
the plugin's `WH_KEYBOARD` hook never sees, so Esc never reaches Total Commander
and the Lister won't close (upstream PR #7 fixes this via
`add_AcceleratorKeyPressed` forwarding, but it was closed unmerged — the shipped
`MarkdownView.wlx64` contains no `AcceleratorKeyPressed` handler and its rendered
HTML has no Esc listener at all). MDView handles it properly: the page posts an
Esc message that the plugin turns into `WM_CLOSE` to TC's Lister window.
Trade-off: MDView is pulldown-cmark based — solid GFM tables/task lists but no
Mermaid diagrams, LaTeX math, or emoji shortcodes. Esc that actually exits won
over the richer rendering.
