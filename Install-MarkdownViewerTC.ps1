<#
.SYNOPSIS
  Installs the MDView Markdown lister plugin into Total Commander and
  registers it for .md/.markdown preview via F3 / Ctrl+Q.

.DESCRIPTION
  Reusable installer. Safe to re-run (idempotent): it removes only its own
  previous registration lines (plus the superseded MarkdownViewGitHubStyle
  lines, see notes) and re-adds its entry at the next free plugin index.

  Why MDView: the previous plugin (Serg2000Mr wlx-markdown-viewer-github-style
  v1.3.1) renders nicely but swallows the Esc key — WebView2 runs in a separate
  Chromium process that the plugin's WH_KEYBOARD hook never sees, so Esc never
  reaches Total Commander and the Lister window won't close. Upstream PR #7 has
  a fix but it was never merged. MDView (rweijnen/MDView) forwards Esc from the
  page to TC via WebMessage + WM_CLOSE, so Esc closes the viewer again.

  What it does:
    1. Checks Total Commander dir + WebView2 Runtime (warns only).
    2. Closes running TOTALCMD.EXE / TOTALCMD64.EXE (unless -LeaveRunning).
    3. Downloads MDView v0.2.4 zip from GitHub releases and verifies SHA-256.
    4. Copies mdview.wlx / mdview.wlx64 (+ mdview.exe standalone viewer) to
       <TcPath>\plugins\wlx\mdview\. Removes the superseded
       MarkdownViewGitHubStyle registration so only one Markdown WLX is active.
    5. Backs up wincmd.ini, then registers the plugin in [ListerPlugins]
       (32-bit TC) and [ListerPlugins64] (64-bit TC) with the detect filter
       taken verbatim from the plugin's ListGetDetectString
       (EXT="MD" | EXT="MARKDOWN") — never hijacks .txt.
    6. Verifies files, ini lines, and that ListLoad is exported from the
       DLL matching the PowerShell bitness. Restarts TC (unless -LeaveRunning).

.PARAMETER TcPath
  Total Commander install dir (must contain TOTALCMD.EXE or TOTALCMD64.EXE
  and wincmd.ini). Default 'C:\Utils\TotalCmd'.

.PARAMETER Version
  MDView release tag. Default 'v0.2.4'.

.PARAMETER LeaveRunning
  Do not close/restart Total Commander. Close it yourself first, otherwise
  TC overwrites wincmd.ini on exit and drops the registration.

.EXAMPLE
  .\Install-MarkdownViewerTC.ps1
  # standard install, TC in C:\Utils\TotalCmd

.EXAMPLE
  .\Install-MarkdownViewerTC.ps1 -TcPath 'D:\Portable\TotalCmd' -LeaveRunning
  # custom path, TC already closed manually
#>
[CmdletBinding()]
param(
  [string]$TcPath = 'C:\Utils\TotalCmd',
  [string]$Version = 'v0.2.4',
  [switch]$LeaveRunning
)

$ErrorActionPreference = 'Stop'

$PluginDirName = 'mdview'
$BaseUrl = "https://github.com/rweijnen/MDView/releases/download/$Version"
$ZipFile = "MDView-$Version.zip"
# SHA-256 of the release zip, verified at install time on 2026-09-15.
$ZipSha256 = 'A1EDFFFB810FED3821C283BEF66027CF70DDDE65D0380EDFB6FC535D523F4170'
# Detect filter MUST stay identical to ListGetDetectString in src/lib.rs.
$Detect = 'EXT="MD" | EXT="MARKDOWN"'
# Registration lines of the superseded plugin that this installer retires.
$Superseded = @('MarkdownViewGitHubStyle')

function Write-Step([string]$Msg) { Write-Host "`n==> $Msg" -ForegroundColor Cyan }
function Assert-True([bool]$Cond, [string]$Msg) {
  if ($Cond) { Write-Host "  [OK] $Msg" -ForegroundColor Green }
  else { Write-Host "  [FAIL] $Msg" -ForegroundColor Red; throw "Verification failed: $Msg" }
}

# ---------- 1. preconditions ----------
Write-Step "Checking preconditions (TcPath=$TcPath)"
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
Write-Step "Downloading MDView $Version"
$DlDir = Join-Path $env:TEMP 'mdview-tc'
New-Item -ItemType Directory -Force -Path $DlDir | Out-Null
$ZipPath = Join-Path $DlDir $ZipFile
if (-not (Test-Path $ZipPath)) {
  Invoke-WebRequest -Uri "$BaseUrl/$ZipFile" -OutFile $ZipPath
}
$hash = (Get-FileHash $ZipPath -Algorithm SHA256).Hash
Assert-True ($hash -eq $ZipSha256) "zip SHA-256 matches ($ZipFile)"

# ---------- 4. extract + copy files ----------
Write-Step 'Installing plugin files'
$Stage = Join-Path $DlDir 'stage'
Remove-Item -Recurse -Force $Stage -ErrorAction SilentlyContinue
Expand-Archive -Path $ZipPath -DestinationPath $Stage -Force

$Dest = Join-Path $TcPath "plugins\wlx\$PluginDirName"
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
Copy-Item "$Stage\mdview.wlx","$Stage\mdview.wlx64" $Dest -Force
if (Test-Path "$Stage\mdview.exe") { Copy-Item "$Stage\mdview.exe" $Dest -Force }

foreach ($f in 'mdview.wlx64','mdview.wlx') {
  Assert-True (Test-Path (Join-Path $Dest $f)) "installed: $f"
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
  # pass 1: drop our own stale lines (our dll path + its N_detect), the
  # superseded plugin's lines, and TC-written junk ('N=1') inside the section.
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

$lines = Register-Section $lines '[ListerPlugins]'   "$Dest\mdview.wlx"
$lines = Register-Section $lines '[ListerPlugins64]' "$Dest\mdview.wlx64"
[System.IO.File]::WriteAllLines($WincmdIni, $lines, $enc)

$final = [System.IO.File]::ReadAllText($WincmdIni, $enc)
Assert-True ($final -match '\[ListerPlugins\][^\[]*mdview\.wlx\r?\n\d+_detect=') '[ListerPlugins] has mdview.wlx + detect'
Assert-True ($final -match '\[ListerPlugins64\][^\[]*mdview\.wlx64\r?\n\d+_detect=') '[ListerPlugins64] has mdview.wlx64 + detect'
Assert-True ($final -notmatch 'MarkdownViewGitHubStyle') 'superseded plugin registration removed'
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
$dll = if ($bit64) { Join-Path $Dest 'mdview.wlx64' } else { Join-Path $Dest 'mdview.wlx' }
Write-Host "  powershell is $(if ($bit64) {'64-bit'} else {'32-bit'}), testing $dll (run the script in the other powershell to test the other DLL)"
$h = [WlxCheck]::LoadLibrary($dll)
Assert-True ($h -ne [IntPtr]::Zero) "LoadLibrary succeeds: $(Split-Path $dll -Leaf)"
Assert-True ([WlxCheck]::GetProcAddress($h, 'ListLoad') -ne [IntPtr]::Zero) 'ListLoad exported'
Assert-True ([WlxCheck]::GetProcAddress($h, 'ListGetDetectString') -ne [IntPtr]::Zero) 'ListGetDetectString exported'
[WlxCheck]::FreeLibrary($h) | Out-Null

# ---------- 7. restart ----------
if (-not $LeaveRunning) {
  Write-Step 'Starting Total Commander'
  Start-Process (if (Test-Path $TcExe64) { $TcExe64 } else { $TcExe32 })
}
Write-Step 'Done'
Write-Host 'Use: F3 on any .md = formatted view | Ctrl+Q = live preview | 4 = cycle plugins | ESC = close.'
