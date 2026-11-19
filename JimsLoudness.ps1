<#
    Two pass loudness for Make-JimsMovie.ps1 and Make-JimsAudio.ps1, ffmpeg's loudnorm.
    Pass one listens to the whole track and measures it, pass two evens it out with what pass one found.
    Dot source it, then put what Get-LoudnessFilter returns in -af where the audio gets pulled out.
#>

# the broadcast standard, where most movies already sit. quiet ones come up, hot ones come down
$LOUDNESS_TARGET = -24
# true peak in dB. the ogg can overshoot a little when it's compressed, this keeps that from clipping
$LOUDNESS_PEAK = -1.5
# how far apart quiet and loud get to be in LU. bigger keeps more of the movie's punch
$LOUDNESS_RANGE = 11

# pass one. returns the filter for pass two, or nothing when the track's silent
# downmixes first so it measures what actually ends up in the ogg, and goes back to the sample rate after
# since loudnorm works at 192 kHz
function Get-LoudnessFilter([string]$Ffmpeg, [string[]]$InputArgs, [int]$Channels, [int]$SampleRate) {
    $layout = if ($Channels -eq 1) { "mono" } else { "stereo" }
    $settings = "I=${LOUDNESS_TARGET}:TP=${LOUDNESS_PEAK}:LRA=$LOUDNESS_RANGE"
    $ErrorActionPreference = "Continue"
    $output = & $Ffmpeg -hide_banner -nostats @InputArgs -vn -af "aformat=channel_layouts=$layout,loudnorm=${settings}:print_format=json" -f null - 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg couldn't measure the loudness" }
    $text = ($output | ForEach-Object { "$_" }) -join "`n"
    $found = [regex]::Match($text, '\{[^{}]*"input_i"[^{}]*\}')
    if (-not $found.Success) { throw "ffmpeg didn't say how loud it is" }
    $measured = $found.Value | ConvertFrom-Json
    if ("$($measured.input_i)" -match 'inf') {
        Write-Host "  It's silent, leaving it be"
        return $null
    }
    Write-Host "  Measured $($measured.input_i) LUFS, peaks at $($measured.input_tp) dB, range $($measured.input_lra) LU. Evening it out to $LOUDNESS_TARGET LUFS"
    $use = "measured_I=$($measured.input_i):measured_TP=$($measured.input_tp):measured_LRA=$($measured.input_lra):measured_thresh=$($measured.input_thresh):offset=$($measured.target_offset)"
    return "aformat=channel_layouts=$layout,loudnorm=${settings}:${use}:linear=true,aresample=$SampleRate"
}
