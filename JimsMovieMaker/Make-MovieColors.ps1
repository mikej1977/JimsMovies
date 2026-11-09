<#
    Run it on the same source video the bk2 was made from
    ffmpeg crams the shit down to a row of -Slices pixels 30 FPS and this turns that into a lua file that registers the colors for your
    movie id. Drop the output lua in your mod 42/media/lua/shared folder

    ffmpeg has to be on the PATH, or pass -ffmpeg with the full path to ffmpeg.exe

    .\Make-MovieColors.ps1 -Video "D:\movies\5element.mp4" -MovieId "JimsMovies_5Element" -Out "...\JimsMovies5Element_Colors.lua"
    
#>
param(
    [Parameter(Mandatory = $true)][string]$Video,
    [Parameter(Mandatory = $true)][string]$MovieId,
    [Parameter(Mandatory = $true)][string]$Out,
    [double]$Fps = 30,
    [int]$Slices = 4,
    [string]$Ffmpeg = "ffmpeg"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Video)) { throw "No video at $Video" }

$raw = [System.IO.Path]::GetTempFileName()
try {
    # a row of averaged pixels per sample, raw rgb bytes
    & $Ffmpeg -hide_banner -loglevel error -y -i $Video -an -vf "fps=$Fps,scale=${Slices}:1:flags=area" -f rawvideo -pix_fmt rgb24 $raw
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed with exit code $LASTEXITCODE" }

    $bytes = [System.IO.File]::ReadAllBytes($raw)
    $sampleBytes = 3 * $Slices
    $samples = [math]::Floor($bytes.Length / $sampleBytes)
    if ($samples -lt 1) { throw "ffmpeg didn't give back any frames" }

    $builder = New-Object System.Text.StringBuilder
    $fpsText = $Fps.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    [void]$builder.AppendLine("-- Barfed out by Make-MovieColors.ps1 from $([System.IO.Path]::GetFileName($Video)), $samples samples at $fpsText FPS")
    [void]$builder.AppendLine('require "JimsMovies/JimsMoviesAPI"')
    [void]$builder.AppendLine("")
    [void]$builder.AppendLine("JimsMovies.registerMovieColors(`"$MovieId`", $fpsText, {")

    $perLine = 16
    for ($sample = 0; $sample -lt $samples; $sample += $perLine) {
        $last = [math]::Min($sample + $perLine, $samples) - 1
        $values = for ($i = $sample * $sampleBytes; $i -lt ($last + 1) * $sampleBytes; $i++) { $bytes[$i] }
        [void]$builder.AppendLine("    " + ($values -join ",") + ",")
    }
    [void]$builder.AppendLine("}, $Slices)")

    $outDir = Split-Path -Parent $Out
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
    # plain utf8 no BOM cuz Kahlua things
    [System.IO.File]::WriteAllText($Out, $builder.ToString(), (New-Object System.Text.UTF8Encoding $false))

    $minutes = [math]::Round($samples / $Fps / 60, 1)
    Write-Host "Wrote $samples colors ($minutes minutes) for $MovieId to $Out"
}
finally {
    Remove-Item -LiteralPath $raw -ErrorAction SilentlyContinue
}
