<#
.SYNOPSIS
    Make a video play on a Chrysler/Jeep/Dodge/Ram Uconnect head unit.
.DESCRIPTION
    Produces an MP4 with 8-bit H.264 video (720p or smaller) and AAC stereo audio,
    with the moov atom at the front. Streams that already comply are copied, not re-encoded.
.PARAMETER In
    Input video file.
.PARAMETER Out
    Output file. Defaults to <input-name>-car.mp4 next to the input.
.PARAMETER Force
    Overwrite the output file if it already exists.
.PARAMETER NoUsb
    Don't copy the result to a USB stick labelled MOVIES.
.EXAMPLE
    carify.ps1 movie.mkv
.EXAMPLE
    carify.ps1 movie.mkv D:\out.mp4 -Force
#>
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$In,
    [Parameter(Position = 1)][string]$Out,
    [switch]$Force,
    [switch]$NoUsb
)

foreach ($tool in 'ffmpeg', 'ffprobe') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "$tool not found. Install it with:  winget install Gyan.FFmpeg   (then open a new terminal)"
        exit 1
    }
}

if (-not (Test-Path -LiteralPath $In -PathType Leaf)) { Write-Host "file not found: $In"; exit 1 }
$In = (Resolve-Path -LiteralPath $In).Path
if (-not $Out) {
    $Out = Join-Path ([IO.Path]::GetDirectoryName($In)) ([IO.Path]::GetFileNameWithoutExtension($In) + '-car.mp4')
}
if ((Test-Path -LiteralPath $Out) -and -not $Force) {
    Write-Host "output already exists: $Out (use -Force to overwrite)"; exit 1
}

function Get-Stream($sel, $entry) {
    $v = & ffprobe -v error -select_streams $sel -show_entries "stream=$entry" -of csv=p=0 $In 2>$null | Select-Object -First 1
    if ($v) { "$v".Trim() } else { '' }
}

$vcodec = Get-Stream v:0 codec_name
$vpix   = Get-Stream v:0 pix_fmt
$vprof  = Get-Stream v:0 profile
$vwidth = Get-Stream v:0 width
$acodec = Get-Stream a:0 codec_name
$achan  = Get-Stream a:0 channels
if (-not $vcodec) { Write-Host "no video stream found in $In"; exit 1 }
if (-not $acodec) { Write-Host "no audio stream found in $In"; exit 1 }
Write-Host "probed: video=$vcodec/$vpix/$vprof ${vwidth}px  audio=$acodec ${achan}ch"

# Video is fine as-is only if it's 8-bit H.264 in a profile the car decodes, at 720p or less.
$goodProfiles = 'Constrained Baseline', 'Baseline', 'Main', 'High'
$vopts = @('-c:v', 'copy')
if ($vcodec -ne 'h264' -or $vpix -ne 'yuv420p' -or [int]$vwidth -gt 1280 -or $vprof -notin $goodProfiles) {
    Write-Host "video needs re-encode -> H.264 8-bit 720p (this one takes a while)"
    $vopts = @('-c:v', 'libx264', '-preset', 'veryfast', '-profile:v', 'high', '-pix_fmt', 'yuv420p',
               '-vf', "scale='min(1280,iw)':-2", '-crf', '20')
}

# Audio is fine as-is only if it's AAC with at most two channels.
$aopts = @('-c:a', 'copy')
if ($acodec -ne 'aac' -or [int]$achan -gt 2) {
    Write-Host "audio needs re-encode -> AAC stereo"
    $aopts = @('-c:a', 'aac', '-ac', '2', '-b:a', '160k')
}

& ffmpeg -hide_banner -y -i $In -map 0:v:0 -map 0:a:0 @vopts @aopts -movflags +faststart $Out
if ($LASTEXITCODE -ne 0) { Write-Host "ffmpeg failed (exit $LASTEXITCODE)"; exit $LASTEXITCODE }
Write-Host "wrote: $Out"

# Copy onto a USB stick whose volume label is MOVIES.
if (-not $NoUsb) {
    $stick = Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.FileSystemLabel -eq 'MOVIES' -and $_.DriveLetter } |
        Select-Object -First 1
    if ($stick) {
        $dest = "$($stick.DriveLetter):\"
        Write-Host "copying to USB stick: $dest"
        Copy-Item -LiteralPath $Out -Destination $dest
    }
}
