# Sets up a carify dev kit (carify-<version>-dev, unzipped from carify-<version>-dev-windows-x64.zip)
# with no network: checks the toolchains it needs and says what is missing, makes .venv from the
# Python wheels in offline\python, loads PSScriptAnalyzer from offline\powershell, and prints the
# commands for the tests, the lint and the art check. Run it in Windows PowerShell 5.1 or PowerShell 7:
#   powershell -ExecutionPolicy Bypass -File offline\setup.ps1
# offline\README.md lists the toolchains with their installers. The source of this file is
# tools/dev-kit/setup.ps1, copied into the kit by tools/build-dev-kit.ps1.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$offline = $PSScriptRoot
$kit = Split-Path -Parent $offline
$missing = New-Object System.Collections.Generic.List[string]

function Show([string]$state, [string]$what, [string]$detail) {
    Write-Host ('{0,-9}{1,-20}{2}' -f $state, $what, $detail)
}

# Run a program and return its output lines, or nothing if it can't be started or exits non-zero.
function Get-Output([string]$exe, [string[]]$arguments) {
    $ErrorActionPreference = 'Continue'
    try { $out = & $exe @arguments 2>$null }
    catch { return }
    if ($LASTEXITCODE -eq 0) { return $out }
}

# Run a program, showing its output; throw if it fails.
function Invoke-Tool([string]$exe, [string[]]$arguments) {
    $ErrorActionPreference = 'Continue'
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "$exe $($arguments -join ' ') failed (exit $LASTEXITCODE)" }
}

function Get-App([string]$name) {
    Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Quote([string]$s) { "'" + ($s -replace "'", "''") + "'" }

# The versions CI uses, from the repo's tools\versions.env
$pins = @{}
foreach ($line in [IO.File]::ReadAllLines((Join-Path $kit 'tools\versions.env'))) {
    if ($line -match '^([A-Z0-9_]+)=(.+)$') { $pins[$Matches[1]] = $Matches[2].Trim() }
}
$pyPin = $pins['PYTHON_VERSION']
$pyMinor = ($pyPin.Split('.')[0..1]) -join '.'
$pssaPin = $pins['PSSCRIPTANALYZER_VERSION']
$ffPin = $pins['FFMPEG_CHOCO_VERSION']
$scPin = $pins['SHELLCHECK_VERSION']
$psd1 = Join-Path $offline "powershell\PSScriptAnalyzer\$pssaPin\PSScriptAnalyzer.psd1"
$venv = Join-Path $kit '.venv'
$venvPython = Join-Path $venv 'Scripts\python.exe'

Write-Host "carify dev kit: $kit"
Write-Host "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
Write-Host ''

# Files unzipped from a download carry the Mark of the Web, and Windows PowerShell won't load a
# module that has it. The kit is on this machine now, so clear it.
$files = Get-ChildItem -LiteralPath $kit -Force | Where-Object { $_.Name -ne '.venv' } | ForEach-Object {
    if ($_.PSIsContainer) { Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force } else { $_ }
}
$marked = @($files | Where-Object { Get-Item -LiteralPath $_.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue })
if ($marked.Count) {
    $marked | Unblock-File
    Show 'ok' 'Mark of the Web' "cleared from $($marked.Count) files"
}

# --- toolchains --------------------------------------------------------------

# Windows PowerShell 5.1: tests/run.sh powershell
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if ($PSVersionTable.PSEdition -ne 'Core') { $v51 = "$($PSVersionTable.PSVersion)" }
else { $v51 = Get-Output $ps51 @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()') | Select-Object -First 1 }
if ($v51 -and [version]$v51 -ge [version]'5.1') { Show 'ok' 'Windows PowerShell' "$v51  $ps51" }
else { Show 'missing' 'Windows PowerShell' '5.1 not found; it is part of Windows 10 and 11'; $missing.Add('Windows PowerShell 5.1') }

# PowerShell 7: tests/run.sh pwsh and the lint. PSScriptAnalyzer says which 7.x it needs.
$pwshMin = '7.0'
$psm1 = [IO.Path]::ChangeExtension($psd1, '.psm1')
if (Test-Path -LiteralPath $psm1) {
    $m = Select-String -LiteralPath $psm1 -Pattern "minimumPowerShellCoreVersion = '([0-9.]+)'" | Select-Object -First 1
    if ($m) { $pwshMin = $m.Matches[0].Groups[1].Value }
}
$pwsh = $null; $v7 = $null
if ($PSVersionTable.PSEdition -eq 'Core') {
    $pwsh = (Get-Process -Id $PID).Path; $v7 = "$($PSVersionTable.PSVersion)"
}
else {
    $app = Get-App 'pwsh'
    if ($app) { $pwsh = $app.Source; $v7 = Get-Output $pwsh @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()') | Select-Object -First 1 }
}
if ($v7 -and [version]($v7 -replace '-.*$', '') -ge [version]$pwshMin) { Show 'ok' 'PowerShell 7' "$v7  $pwsh" }
elseif ($v7) { Show 'missing' 'PowerShell 7' "$v7 is too old; PSScriptAnalyzer $pssaPin needs $pwshMin or later"; $missing.Add("PowerShell $pwshMin or later") }
else { Show 'missing' 'PowerShell 7' 'pwsh not found'; $missing.Add('PowerShell 7') }

# Git Bash (Git for Windows) runs tests/run.sh. Not WSL's bash: carify.ps1 has to run in Windows.
$bash = $null
$candidates = New-Object System.Collections.Generic.List[string]
$git = Get-App 'git'
if ($git) {
    # git.exe is in Git\cmd, Git\bin or Git\mingw64\bin
    $up1 = Split-Path -Parent (Split-Path -Parent $git.Source)
    $up2 = if ($up1) { Split-Path -Parent $up1 }
    foreach ($d in @($up1, $up2)) { if ($d) { $candidates.Add((Join-Path $d 'bin\bash.exe')) } }
}
foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
    if ($base) { $candidates.Add((Join-Path $base 'Git\bin\bash.exe')); $candidates.Add((Join-Path $base 'Programs\Git\bin\bash.exe')) }
}
foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c) {
        $line = Get-Output $c @('--version') | Select-Object -First 1
        if ($line -match 'msys|cygwin') { $bash = $c; break }
    }
}
if ($bash) {
    $gitVersion = if ($git) { (Get-Output $git.Source @('--version') | Select-Object -First 1) -replace '^git version ', 'Git ' } else { '' }
    Show 'ok' 'Git Bash' "$gitVersion  $bash"
}
else { Show 'missing' 'Git Bash' 'not found; it comes with Git for Windows'; $missing.Add('Git for Windows (Git Bash)') }

# Python for docs/art/make-art.py: the wheels in offline\python are built for one CPython minor.
$python = $null; $otherPython = $null
$tries = New-Object System.Collections.Generic.List[object]
foreach ($n in 'python', 'python3') {
    foreach ($c in @(Get-Command $n -CommandType Application -All -ErrorAction SilentlyContinue)) { $tries.Add(@($c.Source)) }
}
$app = Get-App 'py'
if ($app) { $tries.Add(@($app.Source, "-$pyMinor")); $tries.Add(@($app.Source)) }
foreach ($t in $tries) {
    $first = @($t | Select-Object -Skip 1)
    $out = @(Get-Output $t[0] ($first + @('-c', "import sys;print(sys.executable);print('.'.join(map(str,sys.version_info[:3])))")))
    if ($out.Count -ge 2) {
        $found = [pscustomobject]@{ Exe = $out[0]; Version = $out[1] }
        if ($found.Version -like "$pyMinor.*") { $python = $found; break }
        if (-not $otherPython) { $otherPython = $found }
    }
}
if ($python) {
    $note = if ($python.Version -ne $pyPin) { "  (CI uses $pyPin)" } else { '' }
    Show 'ok' 'Python' "$($python.Version)  $($python.Exe)$note"
}
else {
    $seen = if ($otherPython) { "; found $($otherPython.Version) at $($otherPython.Exe)" } else { '' }
    Show 'missing' 'Python' "$pyMinor not found (the wheels in offline\python are for $pyMinor)$seen"
    $missing.Add("Python $pyMinor")
}

# ffmpeg and ffprobe, with the encoders the test clips use
$ffmpeg = Get-App 'ffmpeg'; $ffprobe = Get-App 'ffprobe'
if ($ffmpeg -and $ffprobe) {
    $head = Get-Output $ffmpeg.Source @('-hide_banner', '-version') | Select-Object -First 1
    $ffVersion = if ($head -match 'version (\S+)') { $Matches[1] } else { '?' }
    $encoders = @(Get-Output $ffmpeg.Source @('-hide_banner', '-encoders'))
    $lacking = @('libx264', 'libx265', 'ac3' | Where-Object { -not ($encoders -match "\s$_\s") })
    $note = if ($ffVersion -notlike "$ffPin*") { "  (CI uses $ffPin)" } else { '' }
    if ($lacking.Count) { Show 'missing' 'ffmpeg' "$ffVersion has no $($lacking -join ', ') encoder; use a gpl build"; $missing.Add("ffmpeg with $($lacking -join ', ')") }
    else { Show 'ok' 'ffmpeg' "$ffVersion  $($ffmpeg.Source)$note" }
}
else { Show 'missing' 'ffmpeg' 'ffmpeg and ffprobe are not both on PATH'; $missing.Add('ffmpeg and ffprobe') }

# ShellCheck for the shell lint
$shellcheck = Get-App 'shellcheck'
if ($shellcheck) {
    $scVersion = (Get-Output $shellcheck.Source @('--version') | Where-Object { $_ -match '^version:' } | Select-Object -First 1) -replace '^version:\s*', ''
    $note = if ($scVersion -ne $scPin) { "  (CI uses $scPin)" } else { '' }
    Show 'ok' 'ShellCheck' "$scVersion  $($shellcheck.Source)$note"
}
else { Show 'missing' 'ShellCheck' 'shellcheck is not on PATH'; $missing.Add('ShellCheck') }

# --- from the kit ------------------------------------------------------------

# .venv with the art script's packages, installed from offline\python only
if ($python) {
    try {
        $have = $null
        if (Test-Path -LiteralPath $venvPython) { $have = Get-Output $venvPython @('-c', "import sys;print('.'.join(map(str,sys.version_info[:3])))") | Select-Object -First 1 }
        if ($have -ne $python.Version) {
            if (Test-Path -LiteralPath $venv) { Remove-Item -LiteralPath $venv -Recurse -Force }
            Invoke-Tool $python.Exe @('-m', 'venv', $venv)
        }
        Invoke-Tool $venvPython @('-m', 'pip', 'install', '--quiet', '--disable-pip-version-check', '--no-index',
            '--find-links', (Join-Path $offline 'python'), '-r', (Join-Path $kit 'docs\art\requirements.txt'))
        $got = Get-Output $venvPython @('-c', "import fontTools,brotli;print(fontTools.version)") | Select-Object -First 1
        if (-not $got) { throw 'fontTools and brotli did not import' }
        Show 'ok' '.venv' "Python $($python.Version), fonttools $got, from offline\python  $venv"
    }
    catch { Show 'missing' '.venv' "$_"; $missing.Add('.venv (see the error above)') }
}

# PSScriptAnalyzer from offline\powershell at the pinned version; the kit's modules come first
# on PSModulePath in this window
$modules = Join-Path $offline 'powershell'
if (($env:PSModulePath -split ';') -notcontains $modules) { $env:PSModulePath = "$modules;$env:PSModulePath" }
try {
    $pssa = Import-Module -Name $psd1 -Force -PassThru
    if ($pssa.Version -ne [version]$pssaPin) { throw "loaded version $($pssa.Version), wanted $pssaPin" }
    Show 'ok' 'PSScriptAnalyzer' "$($pssa.Version) from the kit  $($pssa.ModuleBase)"
}
catch { Show 'missing' 'PSScriptAnalyzer' "$_"; $missing.Add("PSScriptAnalyzer $pssaPin from offline\powershell") }

# --- next --------------------------------------------------------------------

$bashCmd = if ($bash) { Quote $bash } else { Quote 'C:\Program Files\Git\bin\bash.exe' }
Write-Host ''
if ($missing.Count) {
    Write-Host "Missing: $($missing -join '; ')."
    Write-Host 'offline\README.md lists each toolchain with its installer. Install them, open a new terminal and run setup.ps1 again.'
    Write-Host 'Then, in PowerShell (5.1 or 7):'
}
else {
    Write-Host 'Ready. Next, in PowerShell (5.1 or 7):'
}
Write-Host @"

  Set-Location $(Quote $kit)
  `$env:Path = $(Quote "$venv\Scripts;") + `$env:Path

  # Tests: clips made with ffmpeg, run through carify.ps1 (about a minute each)
  & $bashCmd tests/run.sh pwsh
  & $bashCmd tests/run.sh powershell

  # Lint: no output from Invoke-ScriptAnalyzer means no findings
  shellcheck carify install.sh tests/run.sh
  Import-Module $(Quote $psd1)
  'carify.ps1', 'install.ps1' | ForEach-Object { Invoke-ScriptAnalyzer -Path `$_ -Severity Warning,Error -ExcludeRule PSAvoidUsingWriteHost }

  # Art: redraws the README cluster, docs/runs.js and the art:* parts of docs/index.html and
  # README.md from docs/art/runs.json; if you haven't changed those, no file changes
  & $(Quote $venvPython) docs/art/make-art.py

"@
if ($missing.Count) { exit 1 }
