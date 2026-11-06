<#
.SYNOPSIS
Builds carify-<version>-dev-windows-x64.zip: the repo plus every package dependency, for working
on carify on a Windows x64 machine with no network.

.DESCRIPTION
The zip unzips to one folder, carify-<version>-dev: the repo at -Ref (git archive, so no .git;
text files as committed, .ps1 files CRLF as .gitattributes says) plus offline\ with
  setup.ps1     tools\dev-kit\setup.ps1, which sets the kit up with no network
  README.md     tools\dev-kit\README.md.in, with the toolchain versions and download links
  powershell\   PSScriptAnalyzer at PSSCRIPTANALYZER_VERSION (Save-Module output)
  python\       wheels for docs\art\requirements.txt, for CPython PYTHON_VERSION on win_amd64
  licences\     the licence and notices of each of those
Versions come from tools\versions.env and docs\art\requirements.txt at -Ref, the files CI reads.
The kit names the toolchains but doesn't carry them. The PowerShell 7 and Git for Windows versions
it names are the ones on the machine that builds it (in CI, a windows-latest runner like the one
that then tests it); the rest are pinned in versions.env. Each download link is checked.

Needs Windows, git, PowerShellGet, the network, and a Python with pip (-Python; any version, as
pip downloads the wheels for the pinned one). CI runs this in .github/workflows/offline.yml.

.EXAMPLE
pwsh tools/build-dev-kit.ps1
Builds from HEAD into dist\.

.EXAMPLE
pwsh tools/build-dev-kit.ps1 -Ref v1.2.0 -OutDir C:\kits -Python C:\Python313\python.exe
#>
[CmdletBinding()]
param(
    [string]$Ref = 'HEAD',
    [string]$OutDir,
    [string]$Python = 'python'
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Build the Windows dev kit on Windows.' }
$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $repo 'dist' }
$OutDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

# Run a program; throw if it fails. With -Capture, return its output instead of showing it.
function Invoke-Tool([string]$exe, [string[]]$arguments, [switch]$Capture) {
    $ErrorActionPreference = 'Continue'
    if ($Capture) { $out = & $exe @arguments } else { & $exe @arguments | Out-Host }
    if ($LASTEXITCODE -ne 0) { throw "$exe $($arguments -join ' ') failed (exit $LASTEXITCODE)" }
    if ($Capture) { $out }
}

# The PowerShell Gallery and the other hosts are flaky from CI: 5 tries, 15/30/45/60 s apart.
function Invoke-Retry([string]$what, [scriptblock]$action) {
    for ($try = 1; $true; $try++) {
        try { return (& $action) }
        catch {
            if ($try -ge 5) { throw }
            Write-Warning "$what failed (try $try): $_"
            Start-Sleep -Seconds (15 * $try)
        }
    }
}

function Assert-Download([string]$url) {
    Invoke-Retry "checking $url" {
        $r = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -MaximumRedirection 10
        if ($r.StatusCode -ne 200) { throw "$url answered $($r.StatusCode)" }
    } | Out-Null
    Write-Host "link ok: $url"
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('carify-dev-kit-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    # --- the repo at $Ref ------------------------------------------------------
    $commit = Invoke-Tool git @('-C', $repo, 'rev-parse', '--verify', "$Ref^{commit}") -Capture | Select-Object -First 1
    $archive = Join-Path $work 'repo.zip'
    Invoke-Tool git @('-C', $repo, '-c', 'core.autocrlf=false', '-c', 'core.eol=lf', 'archive', '--format=zip', '-o', $archive, $commit)
    $tree = Join-Path $work 'tree'
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $tree)

    $script = [IO.File]::ReadAllText((Join-Path $tree 'carify'))
    if ($script -notmatch '(?m)^CARIFY_VERSION="([^"]+)"') { throw "carify at $Ref has no CARIFY_VERSION" }
    $version = $Matches[1]
    $name = "carify-$version-dev"
    $kit = Join-Path $work $name
    Move-Item -LiteralPath $tree -Destination $kit
    $offline = Join-Path $kit 'offline'
    New-Item -ItemType Directory -Path $offline | Out-Null
    Write-Host "carify $version at $commit"

    $pins = @{}
    $versionsFile = Join-Path $kit 'tools\versions.env'
    if (-not (Test-Path -LiteralPath $versionsFile)) { throw "tools/versions.env is not in $Ref" }
    foreach ($line in [IO.File]::ReadAllLines($versionsFile)) {
        if ($line -match '^([A-Z0-9_]+)=(.+)$') { $pins[$Matches[1]] = $Matches[2].Trim() }
    }
    foreach ($k in 'PSSCRIPTANALYZER_VERSION', 'PYTHON_VERSION', 'FFMPEG_CHOCO_VERSION', 'SHELLCHECK_VERSION') {
        if (-not $pins[$k]) { throw "tools/versions.env has no $k" }
    }

    # --- PowerShell modules ----------------------------------------------------
    $pssa = $pins['PSSCRIPTANALYZER_VERSION']
    $modules = Join-Path $offline 'powershell'
    New-Item -ItemType Directory -Path $modules | Out-Null
    Invoke-Retry "Save-Module PSScriptAnalyzer $pssa" {
        if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) { Register-PSRepository -Default }
        Save-Module -Name PSScriptAnalyzer -RequiredVersion $pssa -Repository PSGallery -Path $modules -Force
    }
    $pssaDir = Join-Path $modules "PSScriptAnalyzer\$pssa"
    if (-not (Test-Path -LiteralPath (Join-Path $pssaDir 'PSScriptAnalyzer.psd1'))) { throw "Save-Module did not write $pssaDir" }
    $saved = @(Get-ChildItem -LiteralPath $modules | ForEach-Object Name)
    if ($saved.Count -ne 1) { throw "expected only PSScriptAnalyzer in offline\powershell, got $($saved -join ', ')" }

    # --- Python wheels -----------------------------------------------------------
    $pyMinor = ($pins['PYTHON_VERSION'].Split('.')[0..1]) -join '.'
    $abi = 'cp' + $pyMinor.Replace('.', '')
    $wheels = Join-Path $offline 'python'
    $requirements = Join-Path $kit 'docs\art\requirements.txt'
    $reqs = @([IO.File]::ReadAllLines($requirements) | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ })
    foreach ($r in $reqs) {
        if ($r -notmatch '^[A-Za-z0-9._-]+==[A-Za-z0-9._-]+$') { throw "docs/art/requirements.txt: '$r' is not pinned as name==version" }
    }
    $pipConfig = $env:PIP_CONFIG_FILE
    $env:PIP_CONFIG_FILE = 'NUL'   # no pip.ini from this machine
    try {
        Invoke-Retry 'pip download' {
            Invoke-Tool $Python @('-I', '-m', 'pip', 'download', '--no-cache-dir', '--disable-pip-version-check',
                '--only-binary=:all:', '--platform', 'win_amd64', '--python-version', $pyMinor, '--implementation', 'cp',
                '--abi', $abi, '--dest', $wheels, '-r', $requirements)
        }
    }
    finally { $env:PIP_CONFIG_FILE = $pipConfig }
    $got = @(Get-ChildItem -LiteralPath $wheels -Filter *.whl)
    $norm = { param($s) ($s -replace '[-_.]+', '-').ToLowerInvariant() }
    foreach ($r in $reqs) {
        $rn, $rv = $r -split '=='
        $hit = $got | Where-Object { $p = $_.Name -split '-'; (& $norm $p[0]) -eq (& $norm $rn) -and $p[1] -eq $rv }
        if (-not $hit) { throw "pip downloaded no wheel for $r" }
    }
    # Every package pinned: a dependency pip pulled in that requirements.txt doesn't name would not be
    if ($got.Count -ne $reqs.Count) { throw "pip downloaded $($got.Count) wheels for $($reqs.Count) requirements: $($got.Name -join ', ')" }

    # --- licences ------------------------------------------------------------------
    $licences = Join-Path $offline 'licences'
    $dest = Join-Path $licences "PSScriptAnalyzer-$pssa"
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $files = @('LICENSE', 'ThirdPartyNotices.txt' | ForEach-Object { Join-Path $pssaDir $_ } | Where-Object { Test-Path -LiteralPath $_ })
    if (-not ($files -like '*LICENSE')) { throw "PSScriptAnalyzer $pssa has no LICENSE" }
    Copy-Item -LiteralPath $files -Destination $dest
    foreach ($whl in $got) {
        $p = $whl.Name -split '-'
        $dest = Join-Path $licences "$($p[0])-$($p[1])"
        $zip = [IO.Compression.ZipFile]::OpenRead($whl.FullName)
        try {
            $entries = @($zip.Entries | Where-Object { $_.Name -and $_.FullName -match '^[^/]+\.dist-info/(licenses/.+|(LICEN[CS]E|COPYING|NOTICE|AUTHORS)[^/]*)$' })
            if (-not $entries.Count) { throw "$($whl.Name) has no licence file" }
            foreach ($e in $entries) {
                $out = Join-Path $dest (($e.FullName -replace '^[^/]+\.dist-info/(licenses/)?', '') -replace '/', '\')
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out) | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $out, $true)
            }
        }
        finally { $zip.Dispose() }
    }

    # --- toolchains: named, not bundled ------------------------------------------
    if ($PSVersionTable.PSEdition -eq 'Core') { $pwshVersion = "$($PSVersionTable.PSVersion)" }
    else { $pwshVersion = Invoke-Tool pwsh @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()') -Capture | Select-Object -First 1 }
    $pwshFile = "PowerShell-$pwshVersion-win-x64.msi"
    $pwshMin = '7.0'
    $m = Select-String -LiteralPath (Join-Path $pssaDir 'PSScriptAnalyzer.psm1') -Pattern "minimumPowerShellCoreVersion = '([0-9.]+)'" | Select-Object -First 1
    if ($m) { $pwshMin = $m.Matches[0].Groups[1].Value }

    $gitLine = Invoke-Tool git @('--version') -Capture | Select-Object -First 1
    if ($gitLine -notmatch '(\d+\.\d+\.\d+)\.windows\.(\d+)') { throw "'$gitLine' is not Git for Windows" }
    $gitBase = $Matches[1]; $gitN = [int]$Matches[2]
    $gitFile = if ($gitN -eq 1) { "Git-$gitBase-64-bit.exe" } else { "Git-$gitBase.$gitN-64-bit.exe" }

    $py = $pins['PYTHON_VERSION']; $ff = $pins['FFMPEG_CHOCO_VERSION']; $sc = $pins['SHELLCHECK_VERSION']
    $fill = [ordered]@{
        VERSION                  = $version
        COMMIT                   = $commit
        PSSCRIPTANALYZER_VERSION = $pssa
        PYTHON_MINOR             = $pyMinor
        WHEELS                   = ($got | ForEach-Object { $p = $_.Name -split '-'; "$($p[0]) $($p[1])" }) -join ', '
        PWSH_VERSION             = $pwshVersion
        PWSH_FILE                = $pwshFile
        PWSH_URL                 = "https://github.com/PowerShell/PowerShell/releases/download/v$pwshVersion/$pwshFile"
        PWSH_MIN                 = $pwshMin
        GIT_VERSION              = if ($gitN -eq 1) { $gitBase } else { "$gitBase.$gitN" }
        GIT_FILE                 = $gitFile
        GIT_URL                  = "https://github.com/git-for-windows/git/releases/download/v$gitBase.windows.$gitN/$gitFile"
        PYTHON_VERSION           = $py
        PYTHON_FILE              = "python-$py-amd64.exe"
        PYTHON_URL               = "https://www.python.org/ftp/python/$py/python-$py-amd64.exe"
        FFMPEG_VERSION           = $ff
        FFMPEG_FILE              = "ffmpeg-$ff-essentials_build.zip"
        FFMPEG_URL               = "https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-$ff-essentials_build.zip"
        SHELLCHECK_VERSION       = $sc
        SHELLCHECK_FILE          = "shellcheck-v$sc.zip"
        SHELLCHECK_URL           = "https://github.com/koalaman/shellcheck/releases/download/v$sc/shellcheck-v$sc.zip"
    }
    foreach ($k in 'PWSH_URL', 'GIT_URL', 'PYTHON_URL', 'FFMPEG_URL', 'SHELLCHECK_URL') { Assert-Download $fill[$k] }

    # --- offline\setup.ps1 and offline\README.md -----------------------------------
    Copy-Item -LiteralPath (Join-Path $kit 'tools\dev-kit\setup.ps1') -Destination (Join-Path $offline 'setup.ps1')
    $readme = [IO.File]::ReadAllText((Join-Path $kit 'tools\dev-kit\README.md.in'))
    foreach ($k in $fill.Keys) { $readme = $readme.Replace("{{$k}}", [string]$fill[$k]) }
    if ($readme -match '\{\{\w+\}\}') { throw "tools/dev-kit/README.md.in has an unfilled $($Matches[0])" }
    [IO.File]::WriteAllText((Join-Path $offline 'README.md'), $readme)

    # --- the zip ---------------------------------------------------------------------
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $zipPath = Join-Path $OutDir "$name-windows-x64.zip"
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath }
    [IO.Compression.ZipFile]::CreateFromDirectory($kit, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $true)
    Write-Host ''
    Get-ChildItem -LiteralPath $offline -Recurse -File | Where-Object { $_.DirectoryName -notlike "$pssaDir*" } |
        ForEach-Object { '  offline\' + $_.FullName.Substring($offline.Length + 1) } | Out-Host
    Write-Host "  offline\powershell\PSScriptAnalyzer\$pssa\ ($(@(Get-ChildItem -LiteralPath $pssaDir -Recurse -File).Count) files)"
    Write-Host "wrote $zipPath ($([math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 1)) MB)"
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
