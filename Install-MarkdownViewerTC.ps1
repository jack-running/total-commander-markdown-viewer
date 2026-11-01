<#
.SYNOPSIS
  Installs a Markdown lister plugin into Total Commander and registers it
  for .md/.markdown preview via F3 / Ctrl+Q.

.DESCRIPTION
  Reusable installer with a renderer choice. Safe to re-run (idempotent):
  it removes only its own previous registration lines (plus the *other*
  renderers' lines, so exactly one Markdown WLX stays active) and re-adds
  its entry as plugin #0, so TC tries it before any other lister plugin.

  Renderers (pick with -Renderer):
    MDView       - rweijnen/MDView. Forwards Esc from the page to TC, so Esc
                   closes the viewer again. GFM tables/task lists, dark mode
                   follows TC's dark mode. No Mermaid, LaTeX math, or emoji shortcodes.
    GitHubStyle  - Serg2000Mr wlx-markdown-viewer-github-style. Rich GitHub
                   rendering (Mermaid, LaTeX math, emoji, code copy button,
                   6 CSS themes) but swallows the Esc key: WebView2 runs in a
                   separate Chromium process the plugin's WH_KEYBOARD hook
                   never sees (upstream PR #7 unmerged in v1.3.1).
    EdgeViewer   - rg-software wlx-edge-viewer. General-purpose WebView2 viewer,
                   registered here for .md/.markdown only. GitHub CSS (light/dark),
                   highlight.js, MathJax, Mermaid, alerts, all bundled (offline).
                   Moves keyboard focus into the page and relays keys to TC, so
                   Esc closes Lister and PgUp/PgDn scroll without a click first.

  What it does:
    1. Checks the Total Commander dir, finds the wincmd.ini TC really uses,
       checks the WebView2 Runtime (warns only).
    2. Closes running TOTALCMD.EXE / TOTALCMD64.EXE normally, so TC saves its
       settings first (forced only if it does not exit; skipped with -LeaveRunning).
    3. Downloads the release zip(s) from GitHub and verifies SHA-256
       (a corrupt cached zip is downloaded again once).
    4. Copies plugin files to <TcPath>\plugins\wlx\<plugindir>\.
       GitHubStyle additionally patches MarkdownView.ini (leading-space typo
       fix, [Translate] Enabled=0). EdgeViewer keeps an existing edgeviewer.ini.
    5. Backs up wincmd.ini, retires the other renderers' registrations, then
       registers the plugin as entry 0 in [ListerPlugins] (32-bit TC) and
       [ListerPlugins64] (64-bit TC) with a markdown-only EXT detect filter
       (never hijacks .txt). Other plugins keep their order, shifted by one.
    6. Verifies files, ini lines, and that ListLoad is exported from the
       DLL matching the PowerShell bitness. Restarts TC (unless -LeaveRunning).

.PARAMETER TcPath
  Total Commander install dir (must contain TOTALCMD.EXE or TOTALCMD64.EXE).
  Default 'C:\Utils\TotalCmd'.

.PARAMETER IniPath
  wincmd.ini to edit. Default: auto-detected the way TC does it
  (UseIniInProgramDir in <TcPath>\wincmd.ini, else the IniFileName registry
  value, else <TcPath>\wincmd.ini, else %APPDATA%\GHISLER\wincmd.ini;
  AlternateUserIni and RedirectSection are followed). Pass it when TC is
  started with /i=<file>; it is then used as given (RedirectSection is
  still followed).

.PARAMETER Renderer
  'MDView' (default, Esc works), 'GitHubStyle' (richer rendering, Esc broken)
  or 'EdgeViewer' (rich rendering, Esc and PgUp/PgDn work).

.PARAMETER Version
  Release tag of the chosen renderer. Defaults: MDView 'v0.2.4',
  GitHubStyle 'v1.3.1', EdgeViewer 'v1.2.11'.

.PARAMETER LeaveRunning
  Do not close/restart Total Commander. Close it yourself first: the script
  refuses to run while TC is running, because TC overwrites wincmd.ini on exit.

.EXAMPLE
  .\Install-MarkdownViewerTC.ps1
  # MDView into TC in C:\Utils\TotalCmd (Esc closes the viewer)

.EXAMPLE
  .\Install-MarkdownViewerTC.ps1 -Renderer GitHubStyle
  # rich GitHub rendering instead (Mermaid/math/emoji), Esc won't close Lister

.EXAMPLE
  .\Install-MarkdownViewerTC.ps1 -Renderer EdgeViewer
  # rich rendering (Mermaid/math/highlighting) with working Esc and PgUp/PgDn

.EXAMPLE
  .\Install-MarkdownViewerTC.ps1 -TcPath 'D:\Portable\TotalCmd' -LeaveRunning
  # custom path, TC already closed manually
#>
[CmdletBinding()]
param(
  [string]$TcPath = 'C:\Utils\TotalCmd',
  [string]$IniPath,
  [ValidateSet('MDView','GitHubStyle','EdgeViewer')]
  [string]$Renderer = 'MDView',
  [string]$Version,
  [switch]$LeaveRunning
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # PS 5.1's progress bar slows Invoke-WebRequest down a lot
# PS 5.1 on older .NET may not offer TLS 1.2 by default; github.com requires it.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Per-renderer catalog. Detect filters mirror each plugin's own claim:
# MDView's ListGetDetectString (src/lib.rs); GitHubStyle's MarkdownExtensions ini key;
# EdgeViewer's [Extensions] Markdown= key.
# Match finds a renderer's registration in [ListerPlugins*] (regex on the dll
# path; [\\/] also matches Linux test paths). Exclusive renderers are
# Markdown-only plugins, so any registration of them is ours to replace.
# EdgeViewer is a general viewer the user may have registered for other types
# too: only an entry carrying its markdown Detect string is treated as ours.
$Plugins = @{
  MDView = @{
    DirName = 'mdview'
    Repo    = 'rweijnen/MDView'
    DefaultVersion = 'v0.2.4'
    Zips = @(
      @{ File = 'MDView-v0.2.4.zip'; Sha256 = 'A1EDFFFB810FED3821C283BEF66027CF70DDDE65D0380EDFB6FC535D523F4170' }
    )
    Dll32 = 'mdview.wlx'; Dll64 = 'mdview.wlx64'
    Detect = 'EXT="MD" | EXT="MARKDOWN"'
    Match = '[\\/]mdview\.wlx(64)?$'; Exclusive = $true
    Exports = @('ListLoad','ListGetDetectString')
  }
  GitHubStyle = @{
    DirName = 'MarkdownViewGitHubStyle'
    Repo    = 'Serg2000Mr/wlx-markdown-viewer-github-style'
    DefaultVersion = 'v1.3.1'
    Zips = @(
      @{ File = 'wlx-markdown-viewer-github-style-release-x64.zip'; Sha256 = 'D38BEFBAD0D70507CD131E3D1E4C624AABA89196BF53B6832379EBE83AFDAE88' },
      @{ File = 'wlx-markdown-viewer-github-style-release-x86.zip'; Sha256 = '2B3105BEC6E972FB6C13640B97190C5E92E5AE58030F315F1C3A3DFD6C72D4B0' }
    )
    Dll32 = 'MarkdownView.wlx'; Dll64 = 'MarkdownView.wlx64'
    Detect = 'EXT="MD" | EXT="MARKDOWN" | EXT="MDOWN" | EXT="MDTEXT" | EXT="MDTXT" | EXT="MDWN" | EXT="MK" | EXT="MKD" | EXT="MKDN" | EXT="MKDOWN" | EXT="MDC"'
    Match = '[\\/]MarkdownViewGitHubStyle[\\/]'; Exclusive = $true
    Exports = @('ListLoad')
  }
  EdgeViewer = @{
    DirName = 'EdgeViewer'
    Repo    = 'rg-software/wlx-edge-viewer'
    DefaultVersion = 'v1.2.11'
    Zips = @(
      @{ File = 'wlx-edge-viewer-v1.2.11-Windows.zip'; Sha256 = '1AB56C88FC2DECD1304797C5DE81663B27FBE20514FABF10D40620B894BDAF80' }
    )
    Dll32 = 'EdgeViewer.wlx'; Dll64 = 'EdgeViewer.wlx64'
    Detect = 'EXT="MD" | EXT="MARKDOWN"'
    Match = '[\\/]EdgeViewer\.wlx(64)?$'; Exclusive = $false
    Exports = @('ListLoad','ListLoadNext','ListGetDetectString')
  }
}

$P = $Plugins[$Renderer]
if (-not $Version) { $Version = $P.DefaultVersion }
$PluginDirName = $P.DirName
$Detect = $P.Detect
$BaseUrl = "https://github.com/$($P.Repo)/releases/download/$Version"

function Write-Step([string]$Msg) { Write-Host "`n==> $Msg" -ForegroundColor Cyan }
function Assert-True([bool]$Cond, [string]$Msg) {
  if ($Cond) { Write-Host "  [OK] $Msg" -ForegroundColor Green }
  else { Write-Host "  [FAIL] $Msg" -ForegroundColor Red; throw "Verification failed: $Msg" }
}

# ---------- ini helpers ----------
# TC writes wincmd.ini in the system ANSI codepage unless the file starts with a
# BOM (UTF-16 / UTF-8 ini files are allowed too); keep whatever the file uses.
function Get-IniEncoding([string]$File) {
  $b = [byte[]]::new(3)
  $fs = [System.IO.File]::OpenRead($File)
  try { $n = $fs.Read($b, 0, 3) } finally { $fs.Dispose() }
  if ($n -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { return [System.Text.UnicodeEncoding]::new($false, $true) }
  if ($n -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return [System.Text.UTF8Encoding]::new($true) }
  # [Text.Encoding]::Default is UTF-8 on PowerShell 7, so ask for the ANSI codepage explicitly.
  try { return [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage) }
  catch { return [System.Text.Encoding]::Default }
}

function Get-IniValue([string]$File, [string]$Section, [string]$Key) {
  if (-not (Test-Path -LiteralPath $File)) { return $null }
  $inSec = $false
  foreach ($l in [System.IO.File]::ReadAllLines($File, (Get-IniEncoding $File))) {
    if ($l -match '^\s*\[(.*)\]\s*$') { $inSec = ($Matches[1] -eq $Section); continue }
    if ($inSec -and $l -match "^\s*$([regex]::Escape($Key))\s*=(.*)$") { return $Matches[1].Trim() }
  }
  return $null
}

# Paths in TC settings may use %COMMANDER_PATH% and other environment variables;
# relative ones are taken relative to $BaseDir.
function Expand-TcPath([string]$Path, [string]$BaseDir) {
  $p = $Path.Trim().Trim('"')
  $p = $p -ireplace '%COMMANDER_PATH%', $TcPath.TrimEnd('\')
  $p = [Environment]::ExpandEnvironmentVariables($p)
  if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $BaseDir $p }
  return $p
}

# Lines of one section (without its header); empty if the section is missing.
function Get-SectionLines([string[]]$Lines, [string]$Section) {
  $si = [Array]::IndexOf($Lines, $Section)
  if ($si -lt 0) { return @() }
  $out = @()
  for ($i = $si + 1; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match '^\[.*\]$') { break }
    $out += $Lines[$i]
  }
  return $out
}

# ---------- 1. preconditions ----------
Write-Step "Checking preconditions (TcPath=$TcPath, Renderer=$Renderer $Version)"
Assert-True (Test-Path $TcPath) "TC directory exists: $TcPath"
$TcExe64 = Join-Path $TcPath 'TOTALCMD64.EXE'
$TcExe32 = Join-Path $TcPath 'TOTALCMD.EXE'
Assert-True ((Test-Path $TcExe64) -or (Test-Path $TcExe32)) 'TOTALCMD64.EXE or TOTALCMD.EXE present'

# Locate the wincmd.ini TC actually uses (TC help, "wincmd.ini" / "Configuration").
$ProgIni = Join-Path $TcPath 'wincmd.ini'
if ($IniPath) {
  $WincmdIni = $IniPath; $IniSource = '-IniPath'
} elseif ((Test-Path $ProgIni) -and (([int](Get-IniValue $ProgIni 'Configuration' 'UseIniInProgramDir')) -band 1)) {
  $WincmdIni = $ProgIni; $IniSource = 'UseIniInProgramDir in program dir'
} else {
  $RegIni = $null
  foreach ($hive in 'HKCU:','HKLM:') {
    try { $RegIni = (Get-ItemProperty "$hive\Software\Ghisler\Total Commander" -Name IniFileName -ErrorAction Stop).IniFileName } catch {}
    if ($RegIni) { $IniSource = "registry $hive\Software\Ghisler\Total Commander\IniFileName"; break }
  }
  if ($RegIni) { $WincmdIni = Expand-TcPath $RegIni $TcPath }
  elseif (Test-Path $ProgIni) { $WincmdIni = $ProgIni; $IniSource = 'program dir' }
  else { $WincmdIni = Join-Path $env:APPDATA 'GHISLER\wincmd.ini'; $IniSource = '%APPDATA% default' }
}
$AltIni = if (-not $IniPath) { Get-IniValue $WincmdIni 'Configuration' 'AlternateUserIni' }
if ($AltIni) {
  $WincmdIni = Expand-TcPath $AltIni $TcPath; $IniSource += ' -> AlternateUserIni'
}
Assert-True (Test-Path $WincmdIni) "wincmd.ini found: $WincmdIni ($IniSource)"

# WebView2 Runtime registers under its EdgeUpdate client GUID, per machine
# (64-bit / 32-bit Windows) or per user; 'pv' is empty or 0.0.0.0 when removed.
$Wv2Guid = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
$Wv2Ver = $null
foreach ($k in "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$Wv2Guid",
               "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$Wv2Guid",
               "HKCU:\Software\Microsoft\EdgeUpdate\Clients\$Wv2Guid") {
  try { $v = (Get-ItemProperty $k -Name pv -ErrorAction Stop).pv } catch { $v = $null }
  if ($v -and $v -ne '0.0.0.0') { $Wv2Ver = $v; break }
}
if ($Wv2Ver) { Write-Host "  [OK] WebView2 Runtime found ($Wv2Ver)" -ForegroundColor Green }
else { Write-Warning 'WebView2 Runtime not found in registry. Plugin will show a blank page until you install it: https://developer.microsoft.com/en-us/microsoft-edge/webview2/' }

if ($Renderer -eq 'GitHubStyle') {
  Write-Warning 'GitHubStyle swallows the Esc key (upstream PR #7 unmerged): click Lister X or Alt+F4 to close. Use -Renderer MDView for working Esc.'
}

# ---------- 2. close TC (it rewrites wincmd.ini on exit) ----------
# Close it normally so it saves its own settings (tabs, history) first; the
# ini is edited only after it has exited.
$TcRunningExe = $null
if (-not $LeaveRunning) {
  Write-Step 'Closing Total Commander'
  foreach ($p in @(Get-Process TOTALCMD64,TOTALCMD -ErrorAction SilentlyContinue)) {
    if (-not $TcRunningExe) { try { $TcRunningExe = $p.Path } catch {} }
    if ($p.CloseMainWindow()) { Write-Host "  asked $($p.ProcessName) (pid $($p.Id)) to close" }
    else { Write-Warning "$($p.ProcessName) (pid $($p.Id)) has no main window (minimized to tray?), forcing it closed"; $p | Stop-Process -Force }
  }
  $deadline = (Get-Date).AddSeconds(20)
  while ((Get-Process TOTALCMD64,TOTALCMD -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
  $left = Get-Process TOTALCMD64,TOTALCMD -ErrorAction SilentlyContinue
  if ($left) {
    Write-Warning 'Total Commander did not exit within 20 s (confirmation dialog open?), forcing it closed; its unsaved settings from this session are lost.'
    $left | Stop-Process -Force
    Start-Sleep 2
  }
  Assert-True (-not (Get-Process TOTALCMD64,TOTALCMD -ErrorAction SilentlyContinue)) 'no TC process left'
} else {
  Assert-True (-not (Get-Process TOTALCMD64,TOTALCMD -ErrorAction SilentlyContinue)) 'LeaveRunning: Total Commander is closed (it would overwrite wincmd.ini on exit)'
}

# ---------- 3. download + hash check ----------
Write-Step "Downloading $Renderer $Version"
$DlDir = Join-Path $env:TEMP 'mdview-tc'
New-Item -ItemType Directory -Force -Path $DlDir | Out-Null
function Save-Download([string]$Url, [string]$Dest) {
  # Download to a .part file first so an interrupted transfer never looks like a cached zip.
  $part = "$Dest.part"
  Invoke-WebRequest -Uri $Url -OutFile $part -UseBasicParsing
  Move-Item -LiteralPath $part -Destination $Dest -Force
}
$ZipPaths = @()
foreach ($z in $P.Zips) {
  # Zip file names embed the default version; rebuild them when -Version overrides it.
  $file = $z.File -replace [regex]::Escape($P.DefaultVersion.TrimStart('v')), $Version.TrimStart('v')
  $dest = Join-Path $DlDir $file
  if (-not (Test-Path $dest)) { Save-Download "$BaseUrl/$file" $dest }
  $hash = (Get-FileHash $dest -Algorithm SHA256).Hash
  if ($Version -eq $P.DefaultVersion) {
    if ($hash -ne $z.Sha256) {
      Write-Warning "cached $file has the wrong SHA-256 (corrupt or replaced), downloading it again"
      Remove-Item -LiteralPath $dest -Force
      Save-Download "$BaseUrl/$file" $dest
      $hash = (Get-FileHash $dest -Algorithm SHA256).Hash
    }
    Assert-True ($hash -eq $z.Sha256) "$file SHA-256 matches"
  } else {
    Write-Warning "custom -Version, recorded hash does not apply; downloaded $file SHA-256 = $hash"
  }
  $ZipPaths += $dest
}

# ---------- 4. extract + copy files ----------
Write-Step 'Installing plugin files'
$Dest = Join-Path $TcPath "plugins\wlx\$PluginDirName"
New-Item -ItemType Directory -Force -Path $Dest | Out-Null

if ($Renderer -eq 'MDView') {
  $Stage = Join-Path $DlDir 'stage'
  Remove-Item -Recurse -Force $Stage -ErrorAction SilentlyContinue
  Expand-Archive -Path $ZipPaths[0] -DestinationPath $Stage -Force
  Copy-Item "$Stage\mdview.wlx","$Stage\mdview.wlx64" $Dest -Force
  if (Test-Path "$Stage\mdview.exe") { Copy-Item "$Stage\mdview.exe" $Dest -Force }
  foreach ($f in 'mdview.wlx64','mdview.wlx') {
    Assert-True (Test-Path (Join-Path $Dest $f)) "installed: $f"
  }
} elseif ($Renderer -eq 'EdgeViewer') {
  $Stage = Join-Path $DlDir 'stage-edge'
  Remove-Item -Recurse -Force $Stage -ErrorAction SilentlyContinue
  Expand-Archive -Path $ZipPaths[0] -DestinationPath $Stage -Force
  # Everything but the TC auto-install file. The zip ships only
  # edgeviewer.ini.sample, so a user's own edgeviewer.ini is never overwritten.
  Get-ChildItem $Stage | Where-Object { $_.Name -ne 'pluginst.inf' } | Copy-Item -Destination $Dest -Recurse -Force
  foreach ($f in 'EdgeViewer.wlx64','EdgeViewer.wlx','edgeviewer.ini.sample',
                'assets\markdown','assets\highlight_js','assets\mathjax','assets\mermaid') {
    Assert-True (Test-Path (Join-Path $Dest $f)) "installed: $f"
  }
} else {
  $Stage64 = Join-Path $DlDir 'stage-x64'; $Stage86 = Join-Path $DlDir 'stage-x86'
  Remove-Item -Recurse -Force $Stage64,$Stage86 -ErrorAction SilentlyContinue
  Expand-Archive -Path $ZipPaths[0] -DestinationPath $Stage64 -Force
  if ($ZipPaths.Count -gt 1) {
    Expand-Archive -Path $ZipPaths[1] -DestinationPath $Stage86 -Force
  } else {
    $Stage86 = $Stage64  # single-zip fallback (e.g. custom -Version with one asset)
  }
  # x64 set (root files + assets). NOTE: root WebView2Loader.dll here is the x64 one.
  Copy-Item "$Stage64\*" $Dest -Recurse -Force
  # x86 additions only: ship side-by-side, do NOT overwrite the x64 root files.
  Copy-Item "$Stage86\MarkdownView.wlx","$Stage86\Markdown-x86.dll" $Dest -Force
  if (Test-Path "$Stage86\dotnet-x86") { Copy-Item "$Stage86\dotnet-x86" $Dest -Recurse -Force }
  if (Test-Path "$Stage86\runtimes\win-x86") {
    $Rt86 = Join-Path $Dest 'runtimes\win-x86'
    New-Item -ItemType Directory -Force -Path $Rt86 | Out-Null
    Copy-Item "$Stage86\runtimes\win-x86\*" $Rt86 -Recurse -Force
  }
  foreach ($f in 'MarkdownView.wlx64','MarkdownView.wlx','Markdown-x64.dll','MarkdigNative-x64.dll',
                'Markdown-x86.dll','WebView2Loader.dll','MarkdownView.ini',
                'css\github.css','css\github.dark.css','runtimes\win-x64\native\WebView2Loader.dll',
                'runtimes\win-x86\native\WebView2Loader.dll') {
    Assert-True (Test-Path (Join-Path $Dest $f)) "installed: $f"
  }
  Assert-True (Test-Path (Join-Path $Dest 'dotnet-x86\MarkdigNative-x86.dll')) 'installed: dotnet-x86 runtime (32-bit TC needs it, no .NET install required)'

  # Patch MarkdownView.ini: fix shipped " MarkdownExtensions" leading-space typo,
  # disable auto Google Translate (GitHub CSS stays default).
  Write-Step 'Patching MarkdownView.ini'
  $Ini = Join-Path $Dest 'MarkdownView.ini'
  $t = [System.IO.File]::ReadAllText($Ini)
  $t = $t -replace '(?m)^ MarkdownExtensions=', 'MarkdownExtensions='
  $t = $t -replace '(?m)(^\[Translate\]\r?\nEnabled=)1', '${1}0'
  [System.IO.File]::WriteAllText($Ini, $t)
  $check = Get-Content $Ini
  Assert-True ($check -contains 'MarkdownExtensions=md;markdown;mdown;mdtext;mdtxt;mdwn;mk;mkd;mkdn;mkdown;mdc') 'MarkdownExtensions key readable (no leading space)'
  Assert-True ((($check -join "`n") -match '(?s)\[Translate\]\s*\r?\nEnabled=0')) '[Translate] Enabled=0'
}

# ---------- 5. register in wincmd.ini ----------
Write-Step 'Registering lister plugin in wincmd.ini'

# Is entry 'N=<dll>' (followed by $NextLine) a registration of one of our
# renderers, i.e. ours to drop and re-add? See Match/Exclusive in the catalog.
function Test-OurEntry([string]$Index, [string]$Dll, [string]$NextLine) {
  foreach ($r in $Plugins.Values) {
    if ($Dll -notmatch $r.Match) { continue }
    if ($r.Exclusive -or $NextLine -eq "$Index`_detect=`"$($r.Detect)`"") { return $true }
  }
  return $false
}

function Register-Section {
  param([string[]]$Lines, [string]$Section, [string]$DllFile)
  # pass 1: drop every registration of our renderers (this one and the others,
  # so only one Markdown WLX stays) together with its N_detect line, plus
  # TC-written junk ('N=1') inside the section. Only the N_detect line with the
  # same N directly after the dll line goes with it, so a foreign plugin's
  # N_detect is never touched.
  $out = New-Object System.Collections.Generic.List[string]
  $inSec = $false
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    $l = $Lines[$i]
    if ($l -match '^\[.*\]$') { $inSec = ($l -eq $Section) }
    if ($inSec -and $l -match '^(\d+)=(.*)$') {
      $n = $Matches[1]; $val = $Matches[2]
      $nextLine = if ($i + 1 -lt $Lines.Count) { $Lines[$i + 1] } else { '' }
      if (Test-OurEntry $n $val $nextLine) {
        if ($nextLine -match "^$n`_detect=") { $i++ }
        continue
      }
      if ($val -eq '1') { continue }
    }
    $out.Add($l)
  }
  $Lines = $out.ToArray()
  # pass 2: find section (create it if missing).
  # Compare section names with -eq / IndexOf (exact): -match on
  # '[ListerPlugins]' would also match the '[ListerPlugins64]' prefix.
  $si = [Array]::IndexOf($Lines, $Section)
  if ($si -lt 0) {
    $anchor = [Array]::IndexOf($Lines, '[ListerPlugins64]')
    if ($Section -eq '[ListerPlugins]' -and $anchor -ge 0) {
      $head = @(); if ($anchor -gt 0) { $head = $Lines[0..($anchor-1)] }
      $Lines = @($head + @($Section) + $Lines[$anchor..($Lines.Count-1)])
      $si = $anchor
    } else { $Lines = $Lines + $Section; $si = $Lines.Count - 1 }
  }
  $end = $Lines.Count
  for ($i = $si + 1; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match '^\[.*\]$') { $end = $i; break } }
  $body = @(); if ($end - $si - 1 -gt 0) { $body = $Lines[($si+1)..($end-1)] }
  # pass 3: TC uses the first plugin (lowest index) whose detect string matches,
  # so ours becomes entry 0. The other plugins keep their relative order and are
  # renumbered 1..n (all keys of one entry, N= and N_*=, move together); lines
  # without an index stay in front, blank lines at the end.
  $groups = @{}   # not [ordered]: its int indexer means position, not key
  $other = @(); $blank = @()
  foreach ($l in $body) {
    if ($l -match '^(\d+)((?:_[^=]*)?=.*)$') {
      $n = [int]$Matches[1]
      if (-not $groups.Contains($n)) { $groups[$n] = New-Object System.Collections.Generic.List[string] }
      $groups[$n].Add($Matches[2])
    } elseif ($l.Trim() -eq '') { $blank += $l }
    else { $other += $l }
  }
  $entries = @("0=$DllFile", "0_detect=`"$Detect`"")
  $next = 1
  foreach ($n in ($groups.Keys | Sort-Object)) {
    foreach ($rest in $groups[$n]) { $entries += "$next$rest" }
    $next++
  }
  $head = $Lines[0..$si]
  $tail = @(); if ($end -lt $Lines.Count) { $tail = $Lines[$end..($Lines.Count-1)] }
  return @($head + $other + $entries + $blank + $tail)
}

# A section may live in another file via 'RedirectSection=<file>' inside it.
$Targets = [ordered]@{}
$Dll32 = "$Dest\$($P.Dll32)"; $Dll64 = "$Dest\$($P.Dll64)"
foreach ($t in @(@{ Name = 'ListerPlugins'; Dll = $Dll32 }, @{ Name = 'ListerPlugins64'; Dll = $Dll64 })) {
  $file = $WincmdIni
  $redir = Get-IniValue $WincmdIni $t.Name 'RedirectSection'
  if ($redir) {
    $file = Expand-TcPath $redir (Split-Path $WincmdIni -Parent)
    Write-Host "  [$($t.Name)] is redirected to $file"
    Assert-True (Test-Path $file) "redirected ini exists: $file"
  }
  if (-not $Targets.Contains($file)) { $Targets[$file] = @() }
  $Targets[$file] += $t
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
foreach ($file in $Targets.Keys) {
  Copy-Item $file "$file.backup-$stamp" -Force
  if (-not (Test-Path "$file.pre-md-plugin.bak")) { Copy-Item $file "$file.pre-md-plugin.bak" -Force }
  Write-Host "  backup: $file.backup-$stamp"

  $enc   = Get-IniEncoding $file
  $lines = [System.IO.File]::ReadAllLines($file, $enc)
  foreach ($t in $Targets[$file]) { $lines = Register-Section $lines "[$($t.Name)]" $t.Dll }
  [System.IO.File]::WriteAllLines($file, $lines, $enc)

  $final = [System.IO.File]::ReadAllLines($file, $enc)
  foreach ($t in $Targets[$file]) {
    $sec = @(Get-SectionLines $final "[$($t.Name)]")
    $idx = @($sec | Where-Object { $_ -match '^\d+=' })
    Assert-True ($idx.Count -gt 0 -and $idx[0] -eq "0=$($t.Dll)" -and $sec -contains "0_detect=`"$Detect`"") "[$($t.Name)] entry 0 is $(Split-Path $t.Dll -Leaf) + detect"
    $nums = @($idx | ForEach-Object { [int]($_ -replace '=.*$', '') })
    Assert-True (-not (Compare-Object $nums @(0..($nums.Count-1)) -SyncWindow 0)) "[$($t.Name)] plugin indices are 0..$($nums.Count-1)"
    $ours = @(for ($i = 0; $i -lt $sec.Count; $i++) {
      if ($sec[$i] -match '^(\d+)=(.*)$' -and $Matches[1] -ne '0') {
        $n = $Matches[1]; $val = $Matches[2]
        $nextLine = if ($i + 1 -lt $sec.Count) { $sec[$i + 1] } else { '' }
        if (Test-OurEntry $n $val $nextLine) { $sec[$i] }
      }
    })
    Assert-True ($ours.Count -eq 0) "[$($t.Name)] other Markdown renderers retired"
    $kept = @($sec | Where-Object { $_ -match '^[1-9]\d*=' -and ($_ -replace '^\d+=', '') -match $P.Match })
    if ($kept) { Write-Host "  [$($t.Name)] kept your own $Renderer registration for other file types: $($kept -join ', ')" }
    Assert-True (-not ($sec -match 'EXT="TXT"' | Where-Object { $_ -match '^0_detect=' })) "[$($t.Name)] detect filter does not claim .txt"
  }
}

# ---------- 6. DLL export sanity (bitness of THIS powershell) ----------
Write-Step 'Verifying plugin DLL exports'
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class WlxCheck {
  [DllImport("kernel32", CharSet=CharSet.Unicode)] public static extern IntPtr LoadLibrary(string p);
  [DllImport("kernel32")] public static extern IntPtr GetProcAddress(IntPtr h, string n);
  [DllImport("kernel32")] public static extern bool FreeLibrary(IntPtr h);
}
'@
$bit64 = ([IntPtr]::Size -eq 8)
$dll = if ($bit64) { Join-Path $Dest $P.Dll64 } else { Join-Path $Dest $P.Dll32 }
Write-Host "  powershell is $(if ($bit64) {'64-bit'} else {'32-bit'}), testing $dll (run the script in the other powershell to test the other DLL)"
$h = [WlxCheck]::LoadLibrary($dll)
Assert-True ($h -ne [IntPtr]::Zero) "LoadLibrary succeeds: $(Split-Path $dll -Leaf)"
foreach ($exp in $P.Exports) {
  Assert-True ([WlxCheck]::GetProcAddress($h, $exp) -ne [IntPtr]::Zero) "$exp exported"
}
[WlxCheck]::FreeLibrary($h) | Out-Null

# ---------- 7. restart ----------
if (-not $LeaveRunning) {
  Write-Step 'Starting Total Commander'
  # Restart the edition that was running; otherwise prefer 64-bit.
  $exe = if ($TcRunningExe -and (Test-Path $TcRunningExe)) { $TcRunningExe } elseif (Test-Path $TcExe64) { $TcExe64 } else { $TcExe32 }
  Start-Process $exe
}
Write-Step 'Done'
if ($Renderer -ne 'GitHubStyle') {
  Write-Host 'Use: F3 on any .md = formatted view | Ctrl+Q = live preview | 4 = cycle plugins | ESC = close.'
} else {
  Write-Host 'Use: F3 on any .md = formatted view | Ctrl+Q = live preview | 4 = cycle plugins. NOTE: Esc is swallowed by this renderer: close Lister with X or Alt+F4.'
}
