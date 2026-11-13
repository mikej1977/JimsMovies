<#
    Makes see-through caption binks for a movie add-on you already made. The game draws them over the movie when
    captions are on, so they can be turned off and every language works.

      1. ffmpeg (libass) draws the subtitles twice, on black and on white. where those match is solid, where they
         don't is see-through, which gives each frame its alpha
      2. RAD compresses each chunk with its alpha plane, the same chunks and frame counts as the movie's own binks
      3. a small lua registers them under a game language code

    .\Make-JimsCaptions.ps1 -Subtitles "D:\movies\nosferatu.srt" -Id "Nosferatu"

    -Subtitles   the subtitle file (.srt, .ass, .ssa, .vtt) or a video with subtitle tracks
    -Track       which subtitle track when there's more than one, 1 is the first
    -Picks       several tracks at once, from one file or more, instead of -Subtitles: track*file joined by |, like
                 "1*D:\movies\akira.mkv|1*D:\movies\akira.srt". the movie maker's window passes this
    -AllTracks   one set of captions for every text track that says its language, instead of -Track. a second
                 track in the same language, like signs and songs, gets its own set named after the track
    -Label       a name for -Track's captions in the game's menu, like Signs & Songs. defaults to the track's title
    -Id          the movie add-on's code name, the part after JimsMovies_
    -Language    game language code, EN, ES, FR, RU, JP and so on. defaults to the track's language or EN
    -Offset      seconds to shift every caption, negative shows them sooner. for subtitles that are off
    -Charset     text encoding for old subtitle files that aren't utf8. it tries CP1252 on its own if utf8 fails
    -Font        font for plain subtitles, "Yu Gothic" say. .ass files keep their own unless you pass this
    -ModsDir     where the add-on is, defaults to the mods folder in Zomboid in your user folder
    -Replace     clears out the add-on's other caption tracks first, for when the movie gets made again
#>
param(
    [string]$Subtitles,
    [string]$Picks,
    [int]$Track = 0,
    [switch]$AllTracks,
    [Parameter(Mandatory = $true)][string]$Id,
    [string]$Language,
    [string]$Label,
    [switch]$Replace,
    [double]$Offset = 0,
    [string]$Charset,
    [string]$Font,
    [string]$ModsDir = (Join-Path $env:USERPROFILE "Zomboid\mods"),
    [string]$Rad,
    [string]$Ffmpeg = "ffmpeg",
    [string]$Ffprobe = "ffprobe"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$culture = [System.Globalization.CultureInfo]::InvariantCulture

# in 288ths of the picture height, the same as burned in subtitles
$FONT_SIZE = 22
$OUTLINE = 2
$IMAGE_SUBTITLE_CODECS = @("hdmv_pgs_subtitle", "dvd_subtitle", "dvb_subtitle", "xsub", "dvb_teletext")
# ffprobe gives 3 letter codes, the game wants its own
$LANGUAGE_CODES = @{
    eng = "EN"; spa = "ES"; fre = "FR"; fra = "FR"; ger = "DE"; deu = "DE"; ita = "IT"; por = "PT"
    rus = "RU"; pol = "PL"; jpn = "JP"; kor = "KO"; chi = "CN"; zho = "CN"; dut = "NL"; nld = "NL"
    tur = "TR"; ukr = "UA"; cze = "CS"; ces = "CS"; dan = "DA"; fin = "FI"; hun = "HU"; nor = "NO"
    nob = "NO"; rum = "RO"; ron = "RO"; tha = "TH"; ara = "AR"; ind = "ID"; cat = "CA"; fil = "PH"
}

function Write-Step($text) { Write-Host ""; Write-Host "== $text" -ForegroundColor Cyan }

# ffmpeg prints on stderr, which powershell 5 calls an error. only the exit code counts
function Invoke-Ffmpeg([string[]]$Arguments) {
    $ErrorActionPreference = "Continue"
    & $Ffmpeg -hide_banner -loglevel error -nostats -y @Arguments 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed" }
}

# window style 7 starts it minimized and leaves focus where it is
function Invoke-Rad($source, $target) {
    $exitCode = (New-Object -ComObject WScript.Shell).Run("`"$Rad`" bink2c `"$source`" `"$target`" /Z1000 /F30 /L-1 /O /#", 7, $true)
    if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $target)) { throw "RAD Video Tools failed (exit code $exitCode)" }
}

# bink 2 header: frames at 8, width at 20, height at 24, flags at 36 where 0x00100000 is the alpha plane
function Read-BinkHeader($path) {
    $header = New-Object byte[] 40
    $stream = [System.IO.File]::OpenRead($path)
    try { [void]$stream.Read($header, 0, 40) } finally { $stream.Close() }
    return @{
        Frames = [BitConverter]::ToUInt32($header, 8)
        Width = [BitConverter]::ToUInt32($header, 20)
        Height = [BitConverter]::ToUInt32($header, 24)
        HasAlpha = ([BitConverter]::ToUInt32($header, 36) -band 0x00100000) -ne 0
    }
}

function Write-TextFile($path, $text) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # no BOM, kahlua doesn't want one
    [System.IO.File]::WriteAllText($path, $text + "`n", (New-Object System.Text.UTF8Encoding $false))
}

# RAD drops the alpha plane when it never changes, which a chunk with no captions in it would do
function Add-AlphaMarker($pngPath) {
    $image = [System.Drawing.Image]::FromFile($pngPath)
    $bitmap = New-Object System.Drawing.Bitmap($image)
    $image.Dispose()
    $bitmap.SetPixel(0, 0, [System.Drawing.Color]::FromArgb(1, 0, 0, 0))
    $bitmap.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
}

if (-not $Subtitles -and -not $Picks) { throw "Need -Subtitles or -Picks" }
if ($Subtitles) {
    if (-not (Test-Path -LiteralPath $Subtitles)) { throw "No subtitles at $Subtitles" }
    $Subtitles = (Resolve-Path -LiteralPath $Subtitles).Path
}
foreach ($tool in @($Ffmpeg, $Ffprobe)) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Can't find $tool. Put ffmpeg on the PATH, or pass -Ffmpeg and -Ffprobe with the full paths" }
}
if (-not $Rad) {
    $radOnPath = Get-Command "radvideo64.exe" -ErrorAction SilentlyContinue
    if ($radOnPath) { $Rad = $radOnPath.Source }
}
if (-not $Rad) {
    foreach ($programFiles in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if ($programFiles -and (Test-Path -LiteralPath (Join-Path $programFiles "RADVideo\radvideo64.exe"))) {
            $Rad = Join-Path $programFiles "RADVideo\radvideo64.exe"
            break
        }
    }
}
if (-not $Rad -or -not (Test-Path -LiteralPath $Rad)) { throw "Can't find RAD Video Tools, pass -Rad with the path to radvideo64.exe" }

# what the movie add-on looks like, read back out of its registration
$movieId = "JimsMovies_$Id"
$modDir = Join-Path $ModsDir $movieId
$luaDir = Join-Path $modDir "42\media\lua\shared\$movieId"
$registration = Join-Path $luaDir "JimsMovies$Id.lua"
if (-not (Test-Path -LiteralPath $registration)) { throw "No movie add-on at $modDir, make the movie first or check -Id" }
$registrationText = Get-Content -LiteralPath $registration -Raw
if ($registrationText -notmatch 'width = (\d+)') { throw "Can't find the width in $registration" }
$width = [int]$Matches[1]
if ($registrationText -notmatch 'height = (\d+)') { throw "Can't find the height in $registration" }
$height = [int]$Matches[1]
$videoDir = Join-Path $modDir "common\media\videos"

# the movie's own binks, so every caption chunk gets exactly the frames its movie chunk has
$movieBinks = @()
if ($registrationText -match 'videoPrefix = "([^"]+)"') {
    $videoPrefix = $Matches[1]
    if ($registrationText -notmatch 'videoCount = (\d+)') { throw "Can't find videoCount in $registration" }
    $videoCount = [int]$Matches[1]
    if ($registrationText -notmatch 'videoChunkSeconds = ([\d.]+)') { throw "Can't find videoChunkSeconds in $registration" }
    $chunkSeconds = [double]::Parse($Matches[1], $culture)
    for ($i = 1; $i -le $videoCount; $i++) {
        $movieBinks += [pscustomobject]@{ Path = Join-Path $videoDir ($videoPrefix + $i.ToString("000") + ".bk2"); StartSeconds = ($i - 1) * $chunkSeconds }
    }
}
elseif ($registrationText -match 'video = "([^"]+)"') {
    $videoName = $Matches[1]
    $movieBinks += [pscustomobject]@{ Path = Join-Path $videoDir $videoName; StartSeconds = 0 }
}
else { throw "Can't find the movie's video in $registration" }

$probed = @{}
function Get-SubtitleStreams($path) {
    if (-not $probed.ContainsKey($path)) {
        $probe = (& $Ffprobe -v error -select_streams s -show_entries "stream=codec_name:stream_tags=language,title:stream_disposition=forced" -of json $path) -join "`n" | ConvertFrom-Json
        $probed[$path] = @($probe.streams | Where-Object { $_ })
    }
    return ,$probed[$path]
}

function Get-TrackLanguage($stream) {
    $tag = if ($stream.tags) { "$($stream.tags.language)".ToLower() } else { "" }
    if ($LANGUAGE_CODES.ContainsKey($tag)) { return $LANGUAGE_CODES[$tag] }
    return $null
}

# "Signs & Songs / English [group]" comes out Signs & Songs. ascii only, kahlua garbles anything else
function Get-TrackLabel($stream) {
    $title = if ($stream.tags) { "$($stream.tags.title)" } else { "" }
    $title = (($title -split ' / ')[0] -split ' \[')[0]
    $title = ($title -replace '[^\x20-\x7e]', '').Trim()
    if ($title) { return $title }
    return $null
}

# which tracks, as file and track number
$pairs = @()
if ($Picks) {
    foreach ($entry in ($Picks -split '\|' | Where-Object { $_.Trim() })) {
        $parts = $entry.Split([char[]]@('*'), 2)
        $number = 0
        if ($parts.Count -ne 2 -or -not [int]::TryParse($parts[0].Trim(), [ref]$number)) { throw "-Picks has $entry, it should be track*file" }
        $path = $parts[1].Trim()
        if (-not (Test-Path -LiteralPath $path)) { throw "No subtitles at $path" }
        $pairs += [pscustomobject]@{ Path = (Resolve-Path -LiteralPath $path).Path; Track = $number }
    }
}
elseif ($AllTracks) {
    $streams = Get-SubtitleStreams $Subtitles
    # full tracks first so the plain language code goes to them, forced ones like signs and songs get the numbers
    foreach ($forcedPass in @($false, $true)) {
        for ($i = 0; $i -lt $streams.Count; $i++) {
            $forced = [bool]($streams[$i].disposition -and $streams[$i].disposition.forced -eq 1)
            if ($forced -eq $forcedPass) { $pairs += [pscustomobject]@{ Path = $Subtitles; Track = $i + 1 } }
        }
    }
}
else {
    $streams = Get-SubtitleStreams $Subtitles
    if ($Track -le 0) {
        if ($streams.Count -gt 1) { throw "$([System.IO.Path]::GetFileName($Subtitles)) has $($streams.Count) subtitle tracks, pick one with -Track or use -AllTracks" }
        $Track = 1
    }
    $pairs += [pscustomobject]@{ Path = $Subtitles; Track = $Track }
}
if ($Language -and $pairs.Count -gt 1) { throw "-Language goes with a single -Track, more than one uses each track's own language" }

# one job per set of captions to make. Key names the files and the menu entry, EN, then EN2 for a second english
$jobs = @()
$perLanguage = @{}
foreach ($pair in $pairs) {
    $streams = Get-SubtitleStreams $pair.Path
    $fileName = [System.IO.Path]::GetFileName($pair.Path)
    if ($streams.Count -eq 0) { throw "No subtitle tracks in $fileName" }
    if ($pair.Track -lt 1 -or $pair.Track -gt $streams.Count) { throw "Track $($pair.Track) but $fileName only has $($streams.Count) subtitle track(s)" }
    $stream = $streams[$pair.Track - 1]
    if ($IMAGE_SUBTITLE_CODECS -contains $stream.codec_name) {
        if ($pairs.Count -eq 1) { throw "Track $($pair.Track) is picture subtitles, not text. Turn it into an srt with Subtitle Edit's OCR first" }
        Write-Host "  skipping track $($pair.Track) of $fileName, it's picture subtitles" -ForegroundColor Yellow
        continue
    }
    $code = if ($Language) { $Language.ToUpper() } else { Get-TrackLanguage $stream }
    if (-not $code) {
        if ($AllTracks) { Write-Host "  skipping track $($pair.Track), it doesn't say a language the game knows. make it by itself with -Track $($pair.Track) -Language XX" -ForegroundColor Yellow; continue }
        $code = "EN"
    }
    $trackLabel = if ($Label -and $pairs.Count -eq 1) { ($Label -replace '[^\x20-\x7e]', '').Trim() } else { Get-TrackLabel $stream }
    # a loose subtitle file with no title goes by its file name, so it can be told apart from the movie's own
    if (-not $trackLabel -and $pairs.Count -gt 1 -and @(Get-SubtitleStreams $pair.Path).Count -eq 1 -and $pair.Path -ne $pairs[0].Path) {
        $trackLabel = ([System.IO.Path]::GetFileNameWithoutExtension($pair.Path) -replace '[^\x20-\x7e]', '').Trim()
    }
    $perLanguage[$code] = 1 + $(if ($perLanguage.ContainsKey($code)) { $perLanguage[$code] } else { 0 })
    $key = if ($perLanguage[$code] -gt 1) { "$code$($perLanguage[$code])" } else { $code }
    $jobs += [pscustomobject]@{ Path = $pair.Path; Track = $pair.Track; Language = $code; Key = $key; Label = $trackLabel; Stream = $stream }
}
if ($jobs.Count -eq 0) { throw "No text subtitle tracks to make captions from" }
foreach ($job in $jobs) {
    if ($job.Language -notmatch '^[A-Z]{2,4}$') { throw "-Language should be a game language code like EN or PTBR" }
}

Write-Host "Making $(@($jobs | ForEach-Object { $_.Key }) -join ', ') captions for $movieId, ${width}x$height, $($movieBinks.Count) bink(s)"

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("jimscaptions_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
try {
  if ($Replace) {
      foreach ($old in @(Get-ChildItem -LiteralPath $videoDir -Filter "*_cc_*.bk2" -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $old.FullName }
      foreach ($old in @(Get-ChildItem -LiteralPath $luaDir -Filter "JimsMovies${Id}_Captions_*.lua" -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $old.FullName }
  }
  foreach ($job in $jobs) {
    $Track, $Language, $Key, $picked, $source = $job.Track, $job.Language, $job.Key, $job.Stream, $job.Path
    $labelText = if ($job.Label) { " ($($job.Label))" } else { "" }
    Write-Step "$Key subtitles$labelText"
    # ffmpeg's filter options choke on windows paths, so they go in the work folder as captions.ass and get used by name
    $convert = @()
    if ($Offset -ne 0) { $convert += @("-itsoffset", $Offset.ToString($culture)) }
    $convert += @("-i", $source, "-map", "0:s:$($Track - 1)", "-c:s", "ass", (Join-Path $work "captions.ass"))
    if ($Charset) { Invoke-Ffmpeg (@("-sub_charenc", $Charset) + $convert) }
    else {
        # old subtitle files that aren't utf8 fail, those are nearly always CP1252
        try { Invoke-Ffmpeg $convert }
        catch {
            Write-Host "  not utf8, trying CP1252" -ForegroundColor Yellow
            Invoke-Ffmpeg (@("-sub_charenc", "CP1252") + $convert)
        }
    }
    $styles = @()
    if ($Font) { $styles += "FontName=$($Font -replace "[',]", '')" }
    # plain subtitles come out tiny and thin on a low res screen, .ass ones were styled on purpose so they're left alone
    if ($picked.codec_name -notin @("ass", "ssa")) { $styles += @("FontSize=$FONT_SIZE", "Outline=$OUTLINE", "Shadow=0") }
    $subtitleFilter = "subtitles=captions.ass"
    if ($styles.Count -gt 0) { $subtitleFilter += ":force_style='$($styles -join ',')'" }
    Write-Host "  track $Track ($($picked.codec_name))"

    Write-Step "$Key caption binks"
    foreach ($old in Get-ChildItem -LiteralPath $videoDir -Filter "*_cc_${Key}_???.bk2" -ErrorAction SilentlyContinue) { Remove-Item -LiteralPath $old.FullName }
    foreach ($old in Get-ChildItem -LiteralPath $videoDir -Filter "*_cc_${Key}.bk2" -ErrorAction SilentlyContinue) { Remove-Item -LiteralPath $old.FullName }
    $captionNames = @()
    $chunkNumber = 0
    foreach ($movieBink in $movieBinks) {
        $chunkNumber++
        if (-not (Test-Path -LiteralPath $movieBink.Path)) { throw "Missing $($movieBink.Path)" }
        $movieHeader = Read-BinkHeader $movieBink.Path
        $frames = $movieHeader.Frames
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($movieBink.Path)
        $captionName = if ($movieBinks.Count -gt 1) { "$($videoPrefix)cc_${Key}_" + $chunkNumber.ToString("000") + ".bk2" } else { "${baseName}_cc_$Key.bk2" }

        $framesDir = Join-Path $work "frames"
        if (Test-Path -LiteralPath $framesDir) { Remove-Item -LiteralPath $framesDir -Recurse -Force }
        New-Item -ItemType Directory -Path $framesDir | Out-Null
        $shift = "setpts=PTS+$($movieBink.StartSeconds.ToString($culture))/TB"
        $drawn = "format=rgb24,$shift,$subtitleFilter"
        # back to 0 once they're drawn, or ffmpeg fills the gap before the chunk's start with copies of the first frame
        $graph = "[0:v]$drawn,split[color][onBlack];[1:v]$drawn[onWhite];[onBlack][onWhite]blend=all_mode=difference,format=gray,negate[alpha];[color][alpha]alphamerge,format=rgba,setpts=PTS-STARTPTS"
        Push-Location -LiteralPath $work
        try {
            Invoke-Ffmpeg @(
                "-f", "lavfi", "-i", "color=c=black:s=${width}x${height}:r=30",
                "-f", "lavfi", "-i", "color=c=white:s=${width}x${height}:r=30",
                "-filter_complex", $graph, "-fps_mode", "passthrough", "-frames:v", "$frames", (Join-Path $framesDir "f%06d.png")
            )
        }
        finally { Pop-Location }
        $pngs = @(Get-ChildItem -LiteralPath $framesDir -Filter "*.png" | Sort-Object Name)
        if ($pngs.Count -ne $frames) { throw "ffmpeg made $($pngs.Count) frames for chunk $chunkNumber, expected $frames" }
        Add-AlphaMarker $pngs[0].FullName
        $list = Join-Path $work "frames.lst"
        [System.IO.File]::WriteAllText($list, (($pngs | ForEach-Object { $_.FullName }) -join "`r`n"), [System.Text.Encoding]::ASCII)

        $captionPath = Join-Path $videoDir $captionName
        Invoke-Rad $list $captionPath
        $captionHeader = Read-BinkHeader $captionPath
        if ($captionHeader.Frames -ne $frames) { throw "$captionName came out with $($captionHeader.Frames) frames, its movie bink has $frames" }
        if (-not $captionHeader.HasAlpha) { throw "$captionName came out without its alpha plane" }
        if ($captionHeader.Width -ne $movieHeader.Width -or $captionHeader.Height -ne $movieHeader.Height) { throw "$captionName came out $($captionHeader.Width)x$($captionHeader.Height), its movie bink is $($movieHeader.Width)x$($movieHeader.Height)" }
        $captionNames += $captionName
        Write-Host ("  {0}, {1} frames, {2:N0} KB" -f $captionName, $frames, ((Get-Item -LiteralPath $captionPath).Length / 1KB))
    }

    Write-Step "$Key registration"
    $videoLines = if ($movieBinks.Count -gt 1) {
        "videoPrefix = `"$($videoPrefix)cc_${Key}_`",`n    videoCount = $($movieBinks.Count),"
    }
    else {
        "video = `"$($captionNames[0])`","
    }
    $labelLine = if ($job.Label) { "`n    label = `"$($job.Label.Replace('\', '\\').Replace('"', '\"'))`"," } else { "" }
    $captionsLua = Join-Path $luaDir "JimsMovies${Id}_Captions_$Key.lua"
    Write-TextFile $captionsLua @"
require "JimsMovies/JimsTheaterCaptions"

-- $Key captions from track $Track of $([System.IO.Path]::GetFileName($source) -replace '[^\x20-\x7e]', '?'), see-through binks drawn over the movie
if not JimsMovies.registerCaptionVideos then return end
JimsMovies.registerCaptionVideos("$movieId", "$Key", {
    language = "$Language",$labelLine
    $videoLines
})
"@
    Write-Host "  $captionsLua"
  }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Made $(@($jobs | ForEach-Object { $_.Key }) -join ', ') captions for $movieId" -ForegroundColor Green
