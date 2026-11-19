<#
    Run it on the same source video the bk2 was made from
    ffmpeg crams the shit down to a row of -Slices pixels 30 FPS and this writes them out as txt files, one per
    -ChunkSeconds, so the mod only has to read the bit of the movie that's playing. one sample per line,
    r,g,b for each slice. files come out as <Prefix>001.txt, <Prefix>002.txt and so on in -OutDir

    ffmpeg has to be on the PATH, or pass -ffmpeg with the full path to ffmpeg.exe

    .\Make-MovieColors.ps1 -Video "D:\movies\5element.mp4" -OutDir "...\common\media\colors" -Prefix "5element_"

    the registration needs these to find them, Make-JimsMovie.ps1 writes them for you:
        colorPrefix = "media/colors/5element_",
        colorMod = "JimsMovies_5Element",
        colorCount = <last file number>,
        colorChunkSeconds = 60,
        colorFps = 30,
        colorSlices = 4,
#>
param(
    [Parameter(Mandatory = $true)][string]$Video,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [Parameter(Mandatory = $true)][string]$Prefix,
    [double]$ChunkSeconds = 60,
    [double]$Fps = 30,
    [int]$Slices = 4,
    [string]$Ffmpeg = "ffmpeg",
    # "w:h" from the middle of the frame, to leave black bars out of the average
    [string]$Crop
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Video)) { throw "No video at $Video" }
if ($ChunkSeconds -le 0) { throw "-ChunkSeconds has to be over 0" }

$raw = [System.IO.Path]::GetTempFileName()
try {
    # a row of averaged pixels per sample, raw rgb bytes
    $cropFilter = if ($Crop) { "crop=$Crop," } else { "" }
    & $Ffmpeg -hide_banner -loglevel error -y -i $Video -an -vf "fps=$Fps,${cropFilter}scale=${Slices}:1:flags=area" -f rawvideo -pix_fmt rgb24 $raw
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed with exit code $LASTEXITCODE" }

    $bytes = [System.IO.File]::ReadAllBytes($raw)
    $sampleBytes = 3 * $Slices
    $samples = [math]::Floor($bytes.Length / $sampleBytes)
    if ($samples -lt 1) { throw "ffmpeg didn't give back any frames" }

    if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
    # a rerun with a different length would leave old chunks lying around
    Get-ChildItem -LiteralPath $OutDir -Filter "$Prefix???.txt" -ErrorAction SilentlyContinue | Remove-Item

    # same rounding the mod does
    $perChunk = [math]::Max(1, [math]::Floor($ChunkSeconds * $Fps + 0.5))
    $count = [int][math]::Ceiling($samples / $perChunk)
    $encoding = New-Object System.Text.UTF8Encoding $false
    for ($chunk = 1; $chunk -le $count; $chunk++) {
        $builder = New-Object System.Text.StringBuilder
        $first = ($chunk - 1) * $perChunk
        $last = [math]::Min($first + $perChunk, $samples) - 1
        for ($sample = $first; $sample -le $last; $sample++) {
            $at = $sample * $sampleBytes
            [void]$builder.Append($bytes[$at])
            for ($i = 1; $i -lt $sampleBytes; $i++) { [void]$builder.Append(',').Append($bytes[$at + $i]) }
            [void]$builder.Append("`n")
        }
        [System.IO.File]::WriteAllText((Join-Path $OutDir ($Prefix + $chunk.ToString("000") + ".txt")), $builder.ToString(), $encoding)
    }

    $minutes = [math]::Round($samples / $Fps / 60, 1)
    Write-Host "  $samples colors ($minutes minutes) in $count file(s) to $OutDir"
    # Make-JimsMovie.ps1 needs it for colorCount
    return $count
}
finally {
    Remove-Item -LiteralPath $raw -ErrorAction SilentlyContinue
}
