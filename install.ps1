# Installs carify.ps1 to $HOME\bin and puts that folder on your user PATH.
#   irm https://raw.githubusercontent.com/Real-Fruit-Snacks/carify/main/install.ps1 | iex
# Offline, in the folder unzipped from a release's carify-<version>-offline.zip:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#   (run as a file next to carify.ps1, it installs that copy instead of downloading)
# $env:CARIFY_BIN = '<dir>'   install somewhere else
# $env:CARIFY_REF = 'v1.2.0'  install a tagged version instead of main
# $env:CARIFY_URL = '<url>'   download the script from a mirror
& {
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $ref = if ($env:CARIFY_REF) { $env:CARIFY_REF } else { 'main' }
    $bin = if ($env:CARIFY_BIN) { $env:CARIFY_BIN } else { Join-Path $HOME 'bin' }
    $bin = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($bin)
    $url = if ($env:CARIFY_URL) { $env:CARIFY_URL } else { "https://raw.githubusercontent.com/Real-Fruit-Snacks/carify/$ref/carify.ps1" }
    # $PSScriptRoot is this script's folder when it runs as a file, and empty when it is piped
    # to iex. CARIFY_URL or CARIFY_REF still mean download.
    $local = if ($PSScriptRoot -and -not $env:CARIFY_URL -and -not $env:CARIFY_REF) { Join-Path $PSScriptRoot 'carify.ps1' }
    $isWin = $env:OS -eq 'Windows_NT'

    New-Item -ItemType Directory -Force -Path $bin | Out-Null
    $dest = Join-Path $bin 'carify.ps1'
    if ($local -and [IO.File]::Exists($local)) {
        $from = $local
        Write-Host "using the carify.ps1 next to install.ps1: $local"
        $body = [IO.File]::ReadAllText($local)
    }
    else {
        $from = $url
        $body = (Invoke-WebRequest -UseBasicParsing -Uri $url).Content
        if ($body -is [byte[]]) { $body = [Text.Encoding]::UTF8.GetString($body) }
    }
    if ($body -notmatch '\$CarifyVersion = ') { throw "$from did not look like carify.ps1" }
    # Written from memory rather than downloaded or copied to disk, so there is no
    # Mark of the Web and RemoteSigned lets it run.
    [IO.File]::WriteAllText($dest, $body)
    Write-Host "installed: $dest"

    if ($isWin) {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $parts = @($userPath -split ';' | Where-Object { $_ })
        if ($parts -notcontains $bin) {
            [Environment]::SetEnvironmentVariable('Path', (($parts + $bin) -join ';'), 'User')
            Write-Host "added $bin to your user PATH (new terminals pick it up)"
        }
        if (($env:Path -split ';') -notcontains $bin) { $env:Path = "$env:Path;$bin" }

        $policy = Get-ExecutionPolicy
        if ($policy -in 'Restricted', 'Undefined') {
            try {
                Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
                Write-Host "set execution policy to RemoteSigned for your user (was $policy) so local scripts can run"
            }
            catch { Write-Host "note: execution policy is $policy and could not be changed: $($_.Exception.Message)" }
        }
        elseif ($policy -eq 'AllSigned') {
            Write-Host 'note: execution policy is AllSigned; carify.ps1 is not signed and will not run'
        }
    }
    elseif ((($env:PATH -split ':') -notcontains $bin)) {
        Write-Host "note: $bin is not on PATH"
    }

    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        Write-Host 'note: ffmpeg not found. Install it with:  winget install Gyan.FFmpeg   (then open a new terminal)'
    }
    Write-Host 'run: carify movie.mkv'
}
