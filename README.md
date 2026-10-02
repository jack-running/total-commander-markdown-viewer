# Total Commander — Markdown viewer (F3 / Ctrl+Q)

> Reusable installer + docs for Markdown preview in Total Commander.
> Run `Install-MarkdownViewerTC.ps1` from this repo — details below.

Markdown preview inside Total Commander with a **renderer choice**:
`Esc` that closes the viewer, or richer GitHub-style rendering.

- **Script:** `Install-MarkdownViewerTC.ps1` (same folder as this doc)
- **Target layout:** Total Commander installed at `C:\Utils\TotalCmd`
  (override with `-TcPath` for other locations)
- **Result:** `F3` on any `.md` / `.markdown` file renders a formatted page;
  `Ctrl+Q` shows the same live in the opposite panel.

## Renderers

| | `MDView` (default) | `GitHubStyle` |
|---|---|---|
| Plugin | [`rweijnen/MDView`](https://github.com/rweijnen/MDView) v0.2.4 | [Serg2000Mr `wlx-markdown-viewer-github-style`](https://github.com/Serg2000Mr/wlx-markdown-viewer-github-style) v1.3.1 |
| Engine | pulldown-cmark + WebView2 | Markdig (GFM) + WebView2, Native AOT (no .NET install) |
| `Esc` closes Lister | **yes** (page → WebMessage → `WM_CLOSE`) | **no** — WebView2 runs out-of-process, the plugin's `WH_KEYBOARD` hook never sees Esc (upstream PR #7 unmerged) |
| Extras | dark mode follows TC's dark mode, clickable `.md` links, standalone `mdview.exe` | Mermaid diagrams, LaTeX math, emoji shortcodes, code copy button, 6 CSS themes |
| Extensions claimed | `MD MARKDOWN` | `MD MARKDOWN MDOWN MDTEXT MDTXT MDWN MK MKD MKDN MKDOWN MDC` |

Only one Markdown WLX is active at a time — switching renderers retires the
other one's registration automatically.

## Requirements

- Windows 10/11 + Total Commander 9.0 or newer (32-bit, 64-bit, or both).
- Microsoft Edge **WebView2 Runtime** — preinstalled on current Windows 10/11.
  The script only *warns* if it is missing (checked per machine and per user); if previews render blank, install it from
  <https://developer.microsoft.com/en-us/microsoft-edge/webview2/>.
- PowerShell 5.1+ with permission to write into the Total Commander folder
  (run elevated if TC lives under `Program Files`).
- Internet access to `github.com` for the plugin download
  (or pre-place the zips — see “Offline use”).

## Quick start

```powershell
# 1. Close Total Commander (important — it rewrites wincmd.ini on exit).
# 2. From this folder, run:
.\Install-MarkdownViewerTC.ps1                        # MDView, Esc works
.\Install-MarkdownViewerTC.ps1 -Renderer GitHubStyle  # rich rendering, Esc broken
```

Custom TC location, or TC already closed manually:

```powershell
.\Install-MarkdownViewerTC.ps1 -TcPath 'D:\Portable\TotalCmd'
.\Install-MarkdownViewerTC.ps1 -TcPath 'D:\Portable\TotalCmd' -LeaveRunning
```

| Parameter      | Default              | Meaning                                                      |
|----------------|----------------------|--------------------------------------------------------------|
| `-Renderer`    | `MDView`             | `MDView` (working Esc) or `GitHubStyle` (Mermaid/math/emoji) |
| `-TcPath`      | `C:\Utils\TotalCmd`  | TC folder (must contain `TOTALCMD.EXE`/`TOTALCMD64.EXE`)     |
| `-IniPath`     | auto-detected        | `wincmd.ini` to edit, used as given; needed only when TC is started with `/i=<file>` |
| `-Version`     | per renderer         | Release tag (`v0.2.4` / `v1.3.1`); custom tags skip the hash check with a warning |
| `-LeaveRunning`| off                  | Skip the close/restart of TC (you closed it yourself; the script stops if TC still runs) |

The script is **idempotent** — safe to re-run and to switch renderers back and
forth; it removes only its own plus the other renderer's registration lines and
re-adds its entry as plugin `0`, so TC tries it before any other lister plugin.

## What the script does

1. **Preconditions** — checks the TC folder, finds the `wincmd.ini` TC really
   uses (`UseIniInProgramDir` in `<TcPath>\wincmd.ini`, else the registry value
   `HKCU`/`HKLM\Software\Ghisler\Total Commander\IniFileName`, else
   `<TcPath>\wincmd.ini`, else `%APPDATA%\GHISLER\wincmd.ini`; `AlternateUserIni`
   is followed), and checks the WebView2 Runtime (EdgeUpdate client
   `{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}`, per machine or per user).
2. **Closes TC** (`TOTALCMD64`/`TOTALCMD`) normally, so it saves its own settings
   (tabs, history) first; it is forced closed only if it has not exited after
   20 s. Skipped with `-LeaveRunning`. This matters: TC rewrites `wincmd.ini` on
   exit and would silently drop the edit.
3. **Downloads** the release zip(s) (via a `.part` file, so an interrupted
   download is never cached) and verifies SHA-256 (pinned versions); a cached
   zip with the wrong hash is downloaded again once:
   - MDView `MDView-v0.2.4.zip`
     `A1EDFFFB810FED3821C283BEF66027CF70DDDE65D0380EDFB6FC535D523F4170`
   - GitHubStyle `wlx-markdown-viewer-github-style-release-x64.zip`
     `D38BEFBAD0D70507CD131E3D1E4C624AABA89196BF53B6832379EBE83AFDAE88`
   - GitHubStyle `wlx-markdown-viewer-github-style-release-x86.zip`
     `2B3105BEC6E972FB6C13640B97190C5E92E5AE58030F315F1C3A3DFD6C72D4B0`
4. **Installs files** — MDView to `<TcPath>\plugins\wlx\mdview\`
   (`.wlx` + `.wlx64` + standalone `mdview.exe`); GitHubStyle to
   `<TcPath>\plugins\wlx\MarkdownViewGitHubStyle\` (x64 set plus side-by-side
   x86 `.wlx`/bridge/`dotnet-x86` runtime and `runtimes\win-x86`, without
   overwriting the x64 root files). GitHubStyle additionally patches
   `MarkdownView.ini` (leading-space ` MarkdownExtensions` typo fix,
   `[Translate] Enabled=0`; GitHub CSS stays default).
5. **Registers the lister plugin** — backs up `wincmd.ini`
   (`wincmd.ini.backup-<timestamp>` + first-run `wincmd.ini.pre-md-plugin.bak`),
   retires the other renderer's lines, then puts the plugin as entry `0` into
   `[ListerPlugins]` (32-bit TC) and `[ListerPlugins64]` (64-bit TC), each with a
   markdown-only `0_detect` filter — never `.txt`. Other lister plugins keep their
   order and are renumbered `1..n`. A section moved elsewhere with
   `RedirectSection=` is edited in that file (backed up the same way). The file's
   encoding (ANSI, or UTF-16/UTF-8 with BOM) is kept.
6. **Verifies** — files present, plugin is entry `0` with its detect filter,
   indices contiguous, other renderer gone, and `ListLoad` (+ MDView's `ListGetDetectString`) exported from
   the DLL matching *this* PowerShell's bitness (64-bit PS → `.wlx64`; to check
   the 32-bit `.wlx`, run from
   `C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe`).
7. **Restarts TC** — the edition that was running (unless `-LeaveRunning`).

## Verify it works

- `F3` on any `.md` file → formatted page (MDView: tables, task lists,
  strikethrough, code blocks, clickable `.md` links; GitHubStyle additionally:
  Mermaid, math, emoji, copy button).
- `Ctrl+Q` on the same file → same rendering live in the opposite panel.
- MDView: **`Esc` closes the viewer**. GitHubStyle: close with Lister `X` or
  `Alt+F4` (Esc is swallowed — known limitation). In Quick View (`Ctrl+Q`) the
  file panel keeps the focus, so Esc and PgUp/PgDn act on the panel there.
- `PgUp`/`PgDn` scroll the page. GitHubStyle moves keyboard focus into the page
  as soon as it opens; MDView does not, so it may need one click into the page
  before PgUp/PgDn scroll (Esc works either way).
- `4` in Lister → cycles plugins (the script makes the Markdown plugin entry `0`,
  so it is tried first).
- Negative check: rename a copy to `.txt` → the plugin must *not* claim it
  (extension scoping intact).

## Resulting configuration (reference)

MDView (`-Renderer MDView`):

```ini
[ListerPlugins]
0=C:\Utils\TotalCmd\plugins\wlx\mdview\mdview.wlx
0_detect="EXT="MD" | EXT="MARKDOWN""
[ListerPlugins64]
0=C:\Utils\TotalCmd\plugins\wlx\mdview\mdview.wlx64
0_detect="EXT="MD" | EXT="MARKDOWN""
```

GitHubStyle (`-Renderer GitHubStyle`):

```ini
[ListerPlugins]
0=C:\Utils\TotalCmd\plugins\wlx\MarkdownViewGitHubStyle\MarkdownView.wlx
0_detect="EXT="MD" | EXT="MARKDOWN" | EXT="MDOWN" | EXT="MDTEXT" | EXT="MDTXT" | EXT="MDWN" | EXT="MK" | EXT="MKD" | EXT="MKDN" | EXT="MKDOWN" | EXT="MDC""
[ListerPlugins64]
0=C:\Utils\TotalCmd\plugins\wlx\MarkdownViewGitHubStyle\MarkdownView.wlx64
0_detect="EXT="MD" | EXT="MARKDOWN" | EXT="MDOWN" | EXT="MDTEXT" | EXT="MDTXT" | EXT="MDWN" | EXT="MK" | EXT="MKD" | EXT="MKDN" | EXT="MKDOWN" | EXT="MDC""
```

(The Markdown plugin is always `0`; other lister plugins follow as `1..n` in
their previous order.
`$checksum$` lines are TC's own bookkeeping — leave them alone.
GitHubStyle's `MarkdownView.ini`: `[Renderer] CustomCSS=css\github.css`,
`CustomCSSDark=css\github.dark.css`, `[Translate] Enabled=0`,
`[FastFont] Enabled=1`.)

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Blank preview | WebView2 Runtime missing → install from the link above, restart TC. |
| Registration “vanishes” | TC was running during install and rewrote `wincmd.ini` on exit → re-run without `-LeaveRunning`. If TC is started with `/i=<file>`, pass that file with `-IniPath`. |
| Plugin not picked for `.md` | Another plugin was moved back in front (e.g. via Configuration → Plugins) → re-run the script, or press `4` in Lister to cycle. |
| Esc doesn't close (GitHubStyle) | Expected — upstream limitation, not a config error. Switch with `.\Install-MarkdownViewerTC.ps1 -Renderer MDView`. |
| Roll back | Restore `wincmd.ini.pre-md-plugin.bak` (TC closed), optionally delete `plugins\wlx\mdview\` and/or `plugins\wlx\MarkdownViewGitHubStyle\`. |

## Offline use

Pre-download the zip(s) into `$env:TEMP\mdview-tc\`
(`MDView-v0.2.4.zip`, or the two `wlx-markdown-viewer-github-style-*.zip` files);
the script skips downloading files that are already there (hash still verified
for pinned versions).

## Why two renderers

First pick was Serg2000Mr `wlx-markdown-viewer-github-style` v1.3.1 for its
faithful GitHub rendering — but it **swallows Esc** (separate Chromium process,
unmerged upstream PR #7; verified absent from the shipped binary and its HTML),
which broke the close-L popped-viewer habit. MDView handles Esc properly via
page → WebMessage → `WM_CLOSE`. Since the rendering difference is real
(Mermaid/math/emoji vs. plain GFM), both stay one `-Renderer` flag apart instead
of forcing the trade-off.

Upstream status: PR #7 in `Serg2000Mr/wlx-markdown-viewer-github-style`
("Fix hotkey handling within WebView frame", opened April 2026) forwards Esc and
other TC hotkeys from WebView2 to the plugin window. It is still unmerged and
still applies cleanly to upstream `master`. Once a release contains it, bump
GitHubStyle's version and hashes in the script and make it the default.
