<#
.SYNOPSIS
  Installs the Serg2000Mr Markdown lister plugin (GitHub-style) into Total
  Commander and registers it for .md/.markdown preview via F3 / Ctrl+Q.

.DESCRIPTION
  Reusable installer. Safe to re-run (idempotent): it removes only its own
  previous registration lines and re-adds them at the next free plugin index.

  What it does:
    1. Checks Total Commander dir + WebView2 Runtime (warns only).
    2. Closes running TOTALCMD.EXE / TOTALCMD64.EXE (unless -LeaveRunning).
    3. Downloads wlx-markdown-viewer-github-style v1.3.1 (x64 + x86 zips)
       from GitHub releases and verifies SHA-256.
    4. Copies plugin files to <TcPath>\plugins\wlx\MarkdownViewGitHubStyle\
       (x64 set + x86 .wlx/.dll/dotnet-x86 runtime for 32-bit TC).
    5. Patches MarkdownView.ini: fixes " MarkdownExtensions" leading-space
       typo line, sets [Translate] Enabled=0 (GitHub CSS already default).
    6. Backs up wincmd.ini, then registers the plugin in [ListerPlugins]
       (32-bit TC) and [ListerPlugins64] (64-bit TC) with an EXT detect
       filter limited to markdown extensions (never hijacks .txt).
    7. Verifies files, ini lines, and that ListLoad is exported from the
       DLL matching the PowerShell bitness. Restarts TC (unless -LeaveRunning).

.PARAMETER TcPath
  Total Commander install dir (must contain TOTALCMD.EXE or TOTALCMD64.EXE
  and wincmd.ini). Default 'C:\Utils\TotalCmd'.

.PARAMETER Version
  Plugin release tag. Default 'v1.3.1'.

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
  [string]$Version = 'v1.3.1',
  [switch]$LeaveRunning
)

$ErrorActionPreference = 'Stop'

$PluginDirName = 'MarkdownViewGitHubStyle'
$BaseUrl   = "https://github.com/Serg2000Mr/wlx-markdown-viewer-github-style/releases/download/$Version"
$Assets    = @{
  x64 = @{ File = 'wlx-markdown-viewer-github-style-release-x64.zip'
            Sha256 = 'D38BEFBAD0D70507CD131E3D1E4C624AABA89196BF53B6832379EBE83AFDAE88' }
  x86 = @{ File = 'wlx-markdown-viewer-github-style-release-x86.zip'
            Sha256 = '2B3105BEC6E972FB6C13640B97190C5E92E5AE58030F315F1C3A3DFD6C72D4B0' }
}
# Extensions claimed inside the plugin AND in the TC detect filter.
$MdExts = @('MD','MARKDOWN','MDOWN','MDTEXT','MDTXT','MDWN','MK','MKD','MKDN','MKDOWN','MDC')

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
Write-Step "Downloading plugin $Version"
$DlDir = Join-Path $env:TEMP 'mdview-tc'
New-Item -ItemType Directory -Force -Path $DlDir | Out-Null
$Zips = @{}
foreach ($arch in 'x64','x86') {
  $dest = Join-Path $DlDir $Assets[$arch].File
  if (-not (Test-Path $dest)) {
    Invoke-WebRequest -Uri "$BaseUrl/$($Assets[$arch].File)" -OutFile $dest
  }
  $hash = (Get-FileHash $dest -Algorithm SHA256).Hash
  Assert-True ($hash -eq $Assets[$arch].Sha256) "$arch zip SHA-256 matches"
  $Zips[$arch] = $dest
}

# ---------- 4+5. extract + copy files ----------
Write-Step 'Installing plugin files'
$Stage64 = Join-Path $DlDir 'stage-x64'; $Stage86 = Join-Path $DlDir 'stage-x86'
Remove-Item -Recurse -Force $Stage64,$Stage86 -ErrorAction SilentlyContinue
Expand-Archive -Path $Zips.x64 -DestinationPath $Stage64 -Force
Expand-Archive -Path $Zips.x86 -DestinationPath $Stage86 -Force

$Dest = Join-Path $TcPath "plugins\wlx\$PluginDirName"
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
# x64 set (root files + assets). NOTE: root WebView2Loader.dll here is the x64 one.
Copy-Item "$Stage64\*" $Dest -Recurse -Force
# x86 additions only: ship side-by-side, do NOT overwrite the x64 root files.
Copy-Item "$Stage86\MarkdownView.wlx","$Stage86\Markdown-x86.dll" $Dest -Force
Copy-Item "$Stage86\dotnet-x86" $Dest -Recurse -Force
$Rt86 = Join-Path $Dest 'runtimes\win-x86'
New-Item -ItemType Directory -Force -Path $Rt86 | Out-Null
Copy-Item "$Stage86\runtimes\win-x86\*" $Rt86 -Recurse -Force

foreach ($f in 'MarkdownView.wlx64','MarkdownView.wlx','Markdown-x64.dll','MarkdigNative-x64.dll',
              'Markdown-x86.dll','WebView2Loader.dll','MarkdownView.ini',
              'css\github.css','css\github.dark.css','runtimes\win-x64\native\WebView2Loader.dll',
              'runtimes\win-x86\native\WebView2Loader.dll') {
  Assert-True (Test-Path (Join-Path $Dest $f)) "installed: $f"
}
Assert-True (Test-Path (Join-Path $Dest 'dotnet-x86\MarkdigNative-x86.dll')) 'installed: dotnet-x86 runtime (32-bit TC needs it, no .NET install required)'

# ---------- 6. patch MarkdownView.ini ----------
Write-Step 'Patching MarkdownView.ini'
$Ini = Join-Path $Dest 'MarkdownView.ini'
$t = [System.IO.File]::ReadAllText($Ini)
$t = $t -replace '(?m)^ MarkdownExtensions=', 'MarkdownExtensions='   # leading-space typo in shipped ini
$t = $t -replace '(?m)(^\[Translate\]\r?\nEnabled=)1', '${1}0'          # no auto Google Translate
[System.IO.File]::WriteAllText($Ini, $t)
$check = Get-Content $Ini
Assert-True ($check -contains 'MarkdownExtensions=md;markdown;mdown;mdtext;mdtxt;mdwn;mk;mkd;mkdn;mkdown;mdc') 'MarkdownExtensions key readable (no leading space)'
Assert-True ((($check -join "`n") -match '(?s)\[Translate\]\s*\r?\nEnabled=0')) '[Translate] Enabled=0'

# ---------- 7. register in wincmd.ini ----------
Write-Step 'Registering lister plugin in wincmd.ini'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item $WincmdIni "$WincmdIni.backup-$stamp" -Force
if (-not (Test-Path "$WincmdIni.pre-md-plugin.bak")) { Copy-Item $WincmdIni "$WincmdIni.pre-md-plugin.bak" -Force }
Write-Host "  backup: $WincmdIni.backup-$stamp"

$enc   = [System.Text.Encoding]::Default   # TC writes wincmd.ini in system ANSI codepage
$lines = [System.IO.File]::ReadAllLines($WincmdIni, $enc)

function Register-Section {
  param([string[]]$Lines, [string]$Section, [string]$DllFile)
  $detect = ($MdExts | ForEach-Object { 'EXT="' + $_ + '"' }) -join ' | '
  # pass 1: drop our own stale lines (our dll path + its N_detect) and
  # TC-written junk ('N=1') inside the section. Matched by literal dll path,
  # never by extension text, so a foreign plugin's N_detect is never touched.
  $out = New-Object System.Collections.Generic.List[string]
  $inSec = $false
  $skipNextDetect = $false
  foreach ($l in $Lines) {
    if ($l -match '^\[.*\]$') { $inSec = ($l -eq $Section); $skipNextDetect = $false }
    if ($inSec) {
      if ($l -match 'MarkdownViewGitHubStyle') { $skipNextDetect = $true; continue }
      if ($skipNextDetect -and $l -match '^\d+_detect=') { $skipNextDetect = $false; continue }
      $skipNextDetect = $false
      if ($l -match '^\d+=1$') { continue }
    }
    $out.Add($l)
  }
  $Lines = $out.ToArray()
  # pass 2: find section (create it if missing), pick next free index.
  # -match on section names: [ListerPlugins] otherwise also matches the
  # [ListerPlugins64] prefix, so compare with -eq / IndexOf (exact).
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
  $entry = @("$idx=$DllFile", "$idx`_detect=`"$detect`"")
  $head = $Lines[0..$si]
  $body = @(); if ($end - $si - 1 -gt 0) { $body = $Lines[($si+1)..($end-1)] }
  $tail = @(); if ($end -lt $Lines.Count) { $tail = $Lines[$end..($Lines.Count-1)] }
  return @($head + $body + $entry + $tail)
}

$lines = Register-Section $lines '[ListerPlugins]'   "$Dest\MarkdownView.wlx"
$lines = Register-Section $lines '[ListerPlugins64]' "$Dest\MarkdownView.wlx64"
[System.IO.File]::WriteAllLines($WincmdIni, $lines, $enc)

$final = [System.IO.File]::ReadAllText($WincmdIni, $enc)
Assert-True ($final -match '\[ListerPlugins\][^\[]*MarkdownView\.wlx\r?\n\d+_detect=') '[ListerPlugins] has .wlx + detect'
Assert-True ($final -match '\[ListerPlugins64\][^\[]*MarkdownView\.wlx64\r?\n\d+_detect=') '[ListerPlugins64] has .wlx64 + detect'
Assert-True ($final -notmatch 'EXT="TXT"') 'detect filter does not claim .txt'

# ---------- 8. DLL export sanity (bitness of THIS powershell) ----------
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
$dll = if ($bit64) { Join-Path $Dest 'MarkdownView.wlx64' } else { Join-Path $Dest 'MarkdownView.wlx' }
Write-Host "  powershell is $(if ($bit64) {'64-bit'} else {'32-bit'}), testing $dll (run the script in the other powershell to test the other DLL)"
$h = [WlxCheck]::LoadLibrary($dll)
Assert-True ($h -ne [IntPtr]::Zero) "LoadLibrary succeeds: $(Split-Path $dll -Leaf)"
Assert-True ([WlxCheck]::GetProcAddress($h, 'ListLoad') -ne [IntPtr]::Zero) 'ListLoad exported'
[WlxCheck]::FreeLibrary($h) | Out-Null

# ---------- 9. restart ----------
if (-not $LeaveRunning) {
  Write-Step 'Starting Total Commander'
  Start-Process (if (Test-Path $TcExe64) { $TcExe64 } else { $TcExe32 })
}
Write-Step 'Done'
Write-Host 'Use: F3 on any .md = formatted view | Ctrl+Q = live preview | 4 = cycle plugins | ESC = close.'
