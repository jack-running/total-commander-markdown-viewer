<#
.SYNOPSIS
  Installs a Markdown lister plugin into Total Commander and registers it
  for .md/.markdown preview via F3 / Ctrl+Q.

.DESCRIPTION
  Reusable installer with a renderer choice. Safe to re-run (idempotent):
  it removes only its own previous registration lines (plus the *other*
  renderer's lines, so exactly one Markdown WLX stays active) and re-adds
  its entry at the next free plugin index.

  Renderers (pick with -Renderer):
    MDView       - rweijnen/MDView. Forwards Esc from the page to TC, so Esc
                   closes the viewer again. GFM tables/task lists, dark mode
                   follows Windows. No Mermaid, LaTeX math, or emoji shortcodes.
    GitHubStyle  - Serg2000Mr wlx-markdown-viewer-github-style. Rich GitHub
                   rendering (Mermaid, LaTeX math, emoji, code copy button,
                   6 CSS themes) but swallows the Esc key: WebView2 runs in a
                   separate Chromium process the plugin's WH_KEYBOARD hook
                   never sees (upstream PR #7 unmerged in v1.3.1).

  What it does:
    1. Checks Total Commander dir + WebView2 Runtime (warns only).
    2. Closes running TOTALCMD.EXE / TOTALCMD64.EXE (unless -LeaveRunning).
    3. Downloads the release zip(s) from GitHub and verifies SHA-256.
    4. Copies plugin files to <TcPath>\plugins\wlx\<plugindir>\.
       GitHubStyle additionally patches MarkdownView.ini (leading-space typo
       fix, [Translate] Enabled=0).
    5. Backs up wincmd.ini, retires the other renderer's registration, then
       registers the plugin in [ListerPlugins] (32-bit TC) and [ListerPlugins64]
       (64-bit TC) with a markdown-only EXT detect filter (never hijacks .txt).
    6. Verifies files, ini lines, and that ListLoad is exported from the
       DLL matching the PowerShell bitness. Restarts TC (unless -LeaveRunning).

.PARAMETER TcPath
  Total Commander install dir (must contain TOTALCMD.EXE or TOTALCMD64.EXE
  and wincmd.ini). Default 'C:\Utils\TotalCmd'.

.PARAMETER Renderer
  'MDView' (default, Esc works) or 'GitHubStyle' (richer rendering, Esc broken).

.PARAMETER Version
  Release tag of the chosen renderer. Defaults: MDView 'v0.2.4',
  GitHubStyle 'v1.3.1'.

.PARAMETER LeaveRunning
  Do not close/restart Total Commander. Close it yourself first, otherwise
  TC overwrites wincmd.ini on exit and drops the registration.

.EXAMPLE
  .\Install-MarkdownViewerTC.ps1
  # MDView into TC in C:\Utils\TotalCmd (Esc closes the viewer)

.EXAMPLE
  .\Install-MarkdownViewerTC.ps1 -Renderer GitHubStyle
  # rich GitHub rendering instead (Mermaid/math/emoji), Esc won't close Lister

.EXAMPLE
  .\Install-MarkdownViewerTC.ps1 -TcPath 'D:\Portable\TotalCmd' -LeaveRunning
  # custom path, TC already closed manually
#>
[CmdletBinding()]
param(
  [string]$TcPath = 'C:\Utils\TotalCmd',
  [ValidateSet('MDView','GitHubStyle')]
  [string]$Renderer = 'MDView',
  [string]$Version,
  [switch]$LeaveRunning
)

$ErrorActionPreference = 'Stop'

# Per-renderer catalog. Detect filters mirror each plugin's own claim:
# MDView's ListGetDetectString (src/lib.rs); GitHubStyle's MarkdownExtensions ini key.
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
    Superseded = @('MarkdownViewGitHubStyle')
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
    Superseded = @('wlx\\mdview\\','mdview\.wlx')
    Exports = @('ListLoad')
  }
}

$P = $Plugins[$Renderer]
if (-not $Version) { $Version = $P.DefaultVersion }
$PluginDirName = $P.DirName
$Detect = $P.Detect
$Superseded = $P.Superseded
$BaseUrl = "https://github.com/$($P.Repo)/releases/download/$Version"

function Write-Step([string]$Msg) { Write-Host "`n==> $Msg" -ForegroundColor Cyan }
function Assert-True([bool]$Cond, [string]$Msg) {
  if ($Cond) { Write-Host "  [OK] $Msg" -ForegroundColor Green }
  else { Write-Host "  [FAIL] $Msg" -ForegroundColor Red; throw "Verification failed: $Msg" }
}

# ---------- 1. preconditions ----------
Write-Step "Checking preconditions (TcPath=$TcPath, Renderer=$Renderer $Version)"
Assert-True (Test-Path $TcPath) "TC directory exists: $TcPath"
$TcExe64 = Join-Path $TcPath 'TOTALCMD64.EXE'
$TcExe32 = Join-Path $TcPath 'TOTALCMD.EXE'
Assert-True ((Test-Path $TcExe64) -or (Test-Path $TcExe32)) 'TOTALCMD64.EXE or TOTALCMD.EXE present'
$WincmdIni = Join-Path $TcPath 'wincmd.ini'
Assert-True (Test-Path $WincmdIni) 'wincmd.ini present next to the exe'

$wv = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\*' -ErrorAction SilentlyContinue |
      Where-Object { $_.name -match 'WebView2' } | Select-Object -First 1
if ($wv) { Write-Host "  [OK] WebView2 Runtime found ($($wv.pv))" -ForegroundColor Green }
else { Write-Warning 'WebView2 Runtime not found in registry. Plugin will show a blank page until you install it: https://developer.microsoft.com/en-us/microsoft-edge/webview2/' }

if ($Renderer -eq 'GitHubStyle') {
  Write-Warning 'GitHubStyle swallows the Esc key (upstream PR #7 unmerged): click Lister X or Alt+F4 to close. Use -Renderer MDView for working Esc.'
}

# ---------- 2. close TC (it rewrites wincmd.ini on exit) ----------
if (-not $LeaveRunning) {
  Write-Step 'Closing Total Commander'
  foreach ($n in 'TOTALCMD64','TOTALCMD') {
    $p = Get-Process $n -ErrorAction SilentlyContinue
    if ($p) { $p | Stop-Process -Force; Write-Host "  closed $n" }
  }
  Start-Sleep 2
  Assert-True (-not (Get-Process TOTALCMD64,TOTALCMD -ErrorAction SilentlyContinue)) 'no TC process left'
} else {
  Write-Warning 'LeaveRunning: make sure Total Commander is CLOSED, or it will overwrite wincmd.ini on exit.'
}

# ---------- 3. download + hash check ----------
Write-Step "Downloading $Renderer $Version"
$DlDir = Join-Path $env:TEMP 'mdview-tc'
New-Item -ItemType Directory -Force -Path $DlDir | Out-Null
$ZipPaths = @()
foreach ($z in $P.Zips) {
  # Zip file names embed the default version; rebuild them when -Version overrides it.
  $file = $z.File -replace [regex]::Escape($P.DefaultVersion.TrimStart('v')), $Version.TrimStart('v')
  $dest = Join-Path $DlDir $file
  if (-not (Test-Path $dest)) {
    Invoke-WebRequest -Uri "$BaseUrl/$file" -OutFile $dest
  }
  $hash = (Get-FileHash $dest -Algorithm SHA256).Hash
  if ($Version -eq $P.DefaultVersion) {
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
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item $WincmdIni "$WincmdIni.backup-$stamp" -Force
if (-not (Test-Path "$WincmdIni.pre-md-plugin.bak")) { Copy-Item $WincmdIni "$WincmdIni.pre-md-plugin.bak" -Force }
Write-Host "  backup: $WincmdIni.backup-$stamp"

$enc   = [System.Text.Encoding]::Default   # TC writes wincmd.ini in system ANSI codepage
$lines = [System.IO.File]::ReadAllLines($WincmdIni, $enc)

function Register-Section {
  param([string[]]$Lines, [string]$Section, [string]$DllFile)
  # pass 1: drop our own stale lines (our dll path + its N_detect), the other
  # renderer's lines, and TC-written junk ('N=1') inside the section.
  # The detect line is dropped only when it directly follows one of those dll
  # lines, so a foreign plugin's N_detect is never touched.
  $out = New-Object System.Collections.Generic.List[string]
  $inSec = $false
  $skipNextDetect = $false
  foreach ($l in $Lines) {
    if ($l -match '^\[.*\]$') { $inSec = ($l -eq $Section); $skipNextDetect = $false }
    if ($inSec) {
      $own = $l -match [regex]::Escape($DllFile)
      $old = $false
      foreach ($s in $Superseded) { if ($l -match $s) { $old = $true; break } }
      if ($own -or $old) { $skipNextDetect = $true; continue }
      if ($skipNextDetect -and $l -match '^\d+_detect=') { $skipNextDetect = $false; continue }
      $skipNextDetect = $false
      if ($l -match '^\d+=1$') { continue }
    }
    $out.Add($l)
  }
  $Lines = $out.ToArray()
  # pass 2: find section (create it if missing), pick next free index.
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
  $used = @()
  for ($i = $si + 1; $i -lt $end; $i++) { if ($Lines[$i] -match '^(\d+)=') { $used += [int]$Matches[1] } }
  $idx = 0; while ($used -contains $idx) { $idx++ }
  $entry = @("$idx=$DllFile", "$idx`_detect=`"$Detect`"")
  $head = $Lines[0..$si]
  $body = @(); if ($end - $si - 1 -gt 0) { $body = $Lines[($si+1)..($end-1)] }
  $tail = @(); if ($end -lt $Lines.Count) { $tail = $Lines[$end..($Lines.Count-1)] }
  return @($head + $body + $entry + $tail)
}

$Dll32 = "$Dest\$($P.Dll32)"; $Dll64 = "$Dest\$($P.Dll64)"
$lines = Register-Section $lines '[ListerPlugins]'   $Dll32
$lines = Register-Section $lines '[ListerPlugins64]' $Dll64
[System.IO.File]::WriteAllLines($WincmdIni, $lines, $enc)

$final = [System.IO.File]::ReadAllText($WincmdIni, $enc)
$esc32 = [regex]::Escape($P.Dll32); $esc64 = [regex]::Escape($P.Dll64)
Assert-True ($final -match "\[ListerPlugins\][^\[]*$esc32\r?\n\d+_detect=") "[ListerPlugins] has $($P.Dll32) + detect"
Assert-True ($final -match "\[ListerPlugins64\][^\[]*$esc64\r?\n\d+_detect=") "[ListerPlugins64] has $($P.Dll64) + detect"
foreach ($s in $Superseded) {
  Assert-True ($final -notmatch $s) "other renderer retired ($s)"
}
Assert-True ($final -notmatch 'EXT="TXT"') 'detect filter does not claim .txt'

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
  Start-Process (if (Test-Path $TcExe64) { $TcExe64 } else { $TcExe32 })
}
Write-Step 'Done'
if ($Renderer -eq 'MDView') {
  Write-Host 'Use: F3 on any .md = formatted view | Ctrl+Q = live preview | 4 = cycle plugins | ESC = close.'
} else {
  Write-Host 'Use: F3 on any .md = formatted view | Ctrl+Q = live preview | 4 = cycle plugins. NOTE: Esc is swallowed by this renderer — close Lister with X or Alt+F4.'
}
