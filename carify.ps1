<#
.SYNOPSIS
    Convert a video so it plays from USB on a Uconnect head unit.
.DESCRIPTION
    Writes an MP4 with 8-bit H.264 video (Baseline/Main/High, level 4.1 or lower,
    fits 1280x720) and AAC stereo audio, moov atom first. Streams that already
    comply are copied, not re-encoded. If a drive labelled MOVIES is present the
    result is copied onto it.

    Environment: CARIFY_USB_DIR copies to that folder instead of looking for a
    MOVIES drive. CARIFY_THEME=dayshift for light terminals. NO_COLOR for plain output.

    https://github.com/Real-Fruit-Snacks/carify - MIT
.PARAMETER In
    Input video file.
.PARAMETER Out
    Output file. Defaults to <input-name>-car.mp4 next to the input.
.PARAMETER Force
    Overwrite the output file if it already exists.
.PARAMETER NoUsb
    Don't copy the result to a drive labelled MOVIES.
.PARAMETER MaxHeight
    Largest frame height to allow. Default 720. The width limit is MaxHeight x 16/9.
.PARAMETER Version
    Print the version and exit.
.EXAMPLE
    carify.ps1 movie.mkv
.EXAMPLE
    carify.ps1 movie.mkv D:\out.mp4 -Force
.EXAMPLE
    carify.ps1 movie.mkv -MaxHeight 1080
#>
[CmdletBinding(DefaultParameterSetName = 'Convert')]
param(
    [Parameter(ParameterSetName = 'Convert', Mandatory = $true, Position = 0)][string]$In,
    [Parameter(ParameterSetName = 'Convert', Position = 1)][string]$Out,
    [Parameter(ParameterSetName = 'Convert')][switch]$Force,
    [Parameter(ParameterSetName = 'Convert')][switch]$NoUsb,
    [Parameter(ParameterSetName = 'Convert')][ValidateRange(144, 4320)][int]$MaxHeight = 720,
    [Parameter(ParameterSetName = 'Version', Mandatory = $true)][switch]$Version
)

$CarifyVersion = '1.1.0'
if ($Version) { Write-Output "carify $CarifyVersion"; exit 0 }

# --- output ----------------------------------------------------------------
# Nightshift/Dayshift palette (RFS). Status goes to stderr. ANSI colour only
# where the console understands it (PowerShell 7, Windows Terminal, VS Code).
$esc = [char]27
$useColor = -not $env:NO_COLOR -and -not [Console]::IsErrorRedirected -and
    ($PSVersionTable.PSVersion.Major -ge 7 -or $env:WT_SESSION -or $env:TERM_PROGRAM)
$palette = @{
    nightshift = @{ tag = '255;106;61'; ok = '61;220;151'; warn = '255;194;71'; err = '255;110;122' }
    dayshift   = @{ tag = '196;63;17';  ok = '22;122;78';  warn = '149;99;0';   err = '176;32;48' }
}
$theme = if ($env:CARIFY_THEME -eq 'dayshift') { $palette.dayshift } else { $palette.nightshift }

function Write-Status([string]$Label, [string]$Text, [string]$Kind = 'tag') {
    $pad = $Label.PadRight(6)
    if ($useColor) { [Console]::Error.WriteLine("$esc[38;2;$($theme[$Kind])m$pad$esc[0m $Text") }
    else { [Console]::Error.WriteLine("$pad $Text") }
}
function Exit-Carify([string]$Text, [int]$Code = 1) { Write-Status 'error' $Text 'err'; exit $Code }

# --- arguments -------------------------------------------------------------
$MaxHeight = [int][math]::Floor($MaxHeight / 2) * 2
$MaxWidth = [int][math]::Floor(([math]::Floor($MaxHeight * 16 / 9) + 1) / 2) * 2

foreach ($tool in 'ffmpeg', 'ffprobe') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Exit-Carify "$tool not found. Install it with:  winget install Gyan.FFmpeg   (then open a new terminal)"
    }
}

if (-not (Test-Path -LiteralPath $In -PathType Leaf)) { Exit-Carify "file not found: $In" }
$In = (Resolve-Path -LiteralPath $In).ProviderPath
if (-not $Out) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($In)
    if (-not $stem) { $stem = [IO.Path]::GetFileName($In) }
    $Out = Join-Path ([IO.Path]::GetDirectoryName($In)) ($stem + '-car.mp4')
}
$Out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Out)
$outDir = [IO.Path]::GetDirectoryName($Out)
if (-not (Test-Path -LiteralPath $outDir -PathType Container)) { Exit-Carify "output folder does not exist: $outDir" }

$isWin = $env:OS -eq 'Windows_NT'
$cmp = if ($isWin) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
if ([string]::Equals($In, $Out, $cmp)) { Exit-Carify "output would overwrite the input: $Out" }
if ((Test-Path -LiteralPath $Out) -and -not $Force) {
    Exit-Carify "output already exists: $Out (use -Force to overwrite)"
}

# --- probe -----------------------------------------------------------------
# V (capital) skips cover art stored as a video stream. file: stops ffmpeg
# treating a name with colons as a protocol.
function Get-StreamInfo([string]$Select) {
    $lines = & ffprobe -v error -select_streams $Select `
        -show_entries 'stream=codec_name,pix_fmt,profile,level,width,height,color_transfer,channels' `
        -of 'default=noprint_wrappers=1' "file:$In" 2>$null
    if ($LASTEXITCODE -ne 0) { Exit-Carify "ffprobe could not read $In" }
    $info = @{}
    foreach ($line in @($lines)) {
        $k, $v = "$line" -split '=', 2
        if ($k -and -not $info.ContainsKey($k)) { $info[$k] = "$v".Trim() }
    }
    $info
}
function ConvertTo-Number($Value, [int]$Default) {
    $n = 0
    if ([int]::TryParse("$Value", [ref]$n) -and $n -ge 0) { $n } else { $Default }
}

$v = Get-StreamInfo 'V:0'
$a = Get-StreamInfo 'a:0'
$vcodec = $v['codec_name']; $vpix = $v['pix_fmt']; $vprof = $v['profile']
$vlevel = ConvertTo-Number $v['level'] 999
$vwidth = ConvertTo-Number $v['width'] 99999
$vheight = ConvertTo-Number $v['height'] 99999
$acodec = $a['codec_name']
$achan = ConvertTo-Number $a['channels'] 99

if (-not $vcodec) { Exit-Carify "no video stream found in $In" }
$aDesc = if ($acodec) { "$acodec ${achan}ch" } else { 'none' }
Write-Status 'probe' "video $vcodec/$vpix/$vprof ${vwidth}x${vheight}  audio $aDesc"

# --- decide ----------------------------------------------------------------
# Video is copied only if it's 8-bit 4:2:0 H.264 in a profile and level the
# head unit decodes, and the frame already fits the size box.
$goodProfiles = 'Constrained Baseline', 'Baseline', 'Main', 'High'
if ($vcodec -ne 'h264' -or $vpix -ne 'yuv420p' -or $vprof -notin $goodProfiles -or
    $vlevel -gt 41 -or $vwidth -gt $MaxWidth -or $vheight -gt $MaxHeight) {
    Write-Status 'video' "re-encode to H.264 High 8-bit, fits ${MaxWidth}x${MaxHeight} (slow)"
    $vopts = @('-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', '-profile:v', 'high',
        '-level:v', '4.1', '-pix_fmt', 'yuv420p', '-vf',
        "scale=w='min($MaxWidth,iw)':h='min($MaxHeight,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2")
}
else {
    Write-Status 'video' 'copy' 'ok'
    $vopts = @('-c:v', 'copy')
}
if ($v['color_transfer'] -in 'smpte2084', 'arib-std-b67') {
    Write-Status 'warn' "HDR source ($($v['color_transfer'])); colours will look washed out, carify does not tone-map" 'warn'
}

# Audio is copied only if it's AAC with at most two channels.
if (-not $acodec) {
    Write-Status 'warn' 'no audio stream; the output will be silent' 'warn'
    $aopts = @('-an')
}
elseif ($acodec -ne 'aac' -or $achan -gt 2) {
    Write-Status 'audio' 're-encode to AAC stereo 160k'
    $aopts = @('-map', '0:a:0', '-c:a', 'aac', '-ac', '2', '-b:a', '160k')
}
else {
    Write-Status 'audio' 'copy' 'ok'
    $aopts = @('-map', '0:a:0', '-c:a', 'copy')
}

# --- encode ----------------------------------------------------------------
# Write to a hidden temp file and rename, so an interrupted run never leaves
# a half-written movie-car.mp4 behind. finally runs on Ctrl+C too.
$tmp = Join-Path $outDir ('.' + [IO.Path]::GetFileName($Out) + '.part')
try {
    & ffmpeg -hide_banner -nostdin -loglevel warning -stats -y -i "file:$In" `
        -map '0:V:0' @vopts @aopts -sn -dn -map_metadata 0 `
        -movflags '+faststart' -f mp4 "file:$tmp"
    if ($LASTEXITCODE -ne 0) { Exit-Carify "ffmpeg failed (exit $LASTEXITCODE)" $LASTEXITCODE }
    Move-Item -LiteralPath $tmp -Destination $Out -Force -ErrorAction Stop
}
finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

$size = (Get-Item -LiteralPath $Out).Length
$human = if ($size -ge 1MB) { '{0} MB' -f [math]::Floor($size / 1MB) } else { '{0} KB' -f [math]::Floor($size / 1KB) }
Write-Status 'wrote' "$Out ($human)" 'ok'

# --- usb -------------------------------------------------------------------
if ($NoUsb) { exit 0 }

$dest = $null; $fs = $null
if ($env:CARIFY_USB_DIR) {
    if (Test-Path -LiteralPath $env:CARIFY_USB_DIR -PathType Container) { $dest = $env:CARIFY_USB_DIR }
    else { Write-Status 'warn' "CARIFY_USB_DIR is not a folder: $env:CARIFY_USB_DIR" 'warn' }
}
elseif ($isWin) {
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "VolumeName = 'MOVIES'" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($disk) { $dest = $disk.DeviceID + '\'; $fs = $disk.FileSystem }
}
else {
    $user = if ($env:USER) { $env:USER } else { & id -un }
    foreach ($p in "/run/media/$user/MOVIES", "/media/$user/MOVIES", '/media/MOVIES', '/Volumes/MOVIES') {
        if (Test-Path -LiteralPath $p -PathType Container) { $dest = $p; break }
    }
}
if (-not $dest) { exit 0 }

if ($fs -eq 'FAT32' -and $size -gt 4294967295) {
    Exit-Carify "$dest is FAT32, which caps files at 4 GB. Reformat the stick as exFAT or use a lower -MaxHeight"
}
Write-Status 'usb' "copying to $dest"
$target = Join-Path $dest ([IO.Path]::GetFileName($Out))
try { Copy-Item -LiteralPath $Out -Destination $target -Force -ErrorAction Stop }
catch {
    Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    Exit-Carify "copy to $dest failed: $($_.Exception.Message)"
}
Write-Status 'usb' 'done; eject the stick before removing it' 'ok'
