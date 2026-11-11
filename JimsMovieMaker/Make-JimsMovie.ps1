<#
    Turns an mp4 into a ready to go Jim's Movie Theater add-on mod.

      1. ffmpeg makes a 1280x720 (or -Width x -Height) 30fps silent video, black bars if the shape doesn't fit
      2. RAD Video Tools compresses that to a bk2 with no audio in it
      3. ffmpeg rips the audio out to oggs, 10 second audio chunks
      4. Make-MovieColors.ps1 makes the screen glow colors, 30 a second to match the bink
      5. it all gets laid out as a mod with the registration, sound script and translation

    The easy way is to put movie.mp4 and movie-trailer.mp4 in a folder and drag the movie.mp4 onto Make-JimsMovie.bat.
    It asks a few questions and makes the mod in that folder, the trailer is optional. Forgot the trailer? Drag
    movie-trailer.mp4 on its own and it offers to add just the trailer to the movie add-on in that folder. Or:

    .\Make-JimsMovie.ps1 -Video "D:\movies\nosferatu.mp4" -Name "Nosferatu"

    -Id          code name used for file names and ids, letters and numbers. defaults to the name squished
    -Trailer     makes this video the trailer for a movie add-on you already made, pass that movie's -Id
    -Genre       sets the moodle rewards: action, comedy, drama, horror, scifi. leave it off for the default mix
    -Mono        mono audio instead of stereo
    -SampleRate  audio sample rate, 22050 say. leave it off to keep the source's
    -SmallAudio  mono at 22050, about a quarter of the memory. the game decodes the whole ogg into memory
                 when it plays, so a 2 hour stereo movie is ~2.6 GB of RAM and a long freeze at Start Movie
    -AudioGain   makes the audio louder in dB, 18 say, negative turns it down. for quiet sources, 0 by default
    -TrailerAudioGain  the same thing for the trailer -Ask picks up
    -TrailerFile  a trailer video to make along with the movie, without -Ask finding it
    -AudioChunkSeconds  how long each audio chunk is, 10 by default. 0 makes one ogg for the whole movie
    -AudioChunkOverlap  seconds each audio chunk runs past its end so the mod can crossfade to the next, 0.3 by default
    -VideoChunkSeconds  cuts the bink into chunks this long so late comers can join at the next one, 60 by default.
                 0 makes one bink for the whole movie
    -Width       bink width, 1280 by default. has to be a multiple of 16 or the picture skews in game
    -Height      bink height, 720 by default. even numbers only
    -ModsDir     where the mod goes, defaults to the mods folder in Zomboid in your user folder
    -Ask         asks about anything that wasn't passed and makes the movie's -trailer video too if there is one.
                 the mod goes next to the video unless -ModsDir says otherwise
#>
param(
    [string]$Video,
    [switch]$Ask,
    [switch]$PartOfMovie,
    [string]$Name,
    [string]$Id,
    [string]$ModsDir = (Join-Path $env:USERPROFILE "Zomboid\mods"),
    [switch]$Trailer,
    [string]$Genre,
    [switch]$Mono,
    [int]$SampleRate = 0,
    [switch]$SmallAudio,
    [double]$AudioGain = 0,
    [double]$TrailerAudioGain = 0,
    [string]$TrailerFile,
    [double]$AudioChunkSeconds = 10,
    [double]$AudioChunkOverlap = 0.3,
    [int]$VideoChunkSeconds = 60,
    [int]$Width = 1280,
    [int]$Height = 720,
    [double]$ColorFps = 30,
    [int]$AudioQuality = 4,
    [string]$Rad,
    [string]$Ffmpeg = "ffmpeg",
    [string]$Ffprobe = "ffprobe"
)

$ErrorActionPreference = "Stop"
# the bink decoder pads its rows but the game reads them back unpadded, any other width comes out skewed
if ($Width % 16) { throw "-Width needs to be a multiple of 16, $Width skews in game. Closest: $([math]::Floor($Width / 16) * 16) or $([math]::Ceiling($Width / 16) * 16)" }
if ($Height % 2) { throw "-Height needs to be an even number" }
if ($VideoChunkSeconds -lt 0) { throw "-VideoChunkSeconds can't be negative" }
$FPS = 30
$VIDEO_CHUNK_EXTRA_FRAMES = 6

function Write-Step($text) { Write-Host ""; Write-Host "== $text" -ForegroundColor Cyan }

# ffmpeg prints its progress on stderr, which powershell 5 calls an error. only the exit code counts
# arguments go in as an array, loose ones get mangled (-c:v turns into "-c:" "v")
function Invoke-Ffmpeg([string[]]$Arguments) {
    $ErrorActionPreference = "Continue"
    & $Ffmpeg -hide_banner -loglevel error -stats -y @Arguments 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed" }
}

# same thing without the progress line, for running it hundreds of times
function Invoke-FfmpegQuiet([string[]]$Arguments) {
    $ErrorActionPreference = "Continue"
    & $Ffmpeg -hide_banner -loglevel error -nostats -y @Arguments 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed" }
}

# /L-1 no audio in the bink, /O overwrite, /# run unattended and close when it's done
# window style 7 starts it minimized and leaves focus where it is, so it can't catch your typing
function Invoke-Rad($source, $target) {
    $exitCode = (New-Object -ComObject WScript.Shell).Run("`"$Rad`" bink2c `"$source`" `"$target`" /L-1 /O /#", 7, $true)
    if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $target)) { throw "RAD Video Tools failed (exit code $exitCode)" }
}

# bink 2 header: KB2?, file size, frames, max frame size, ?, width, height, fps numerator, fps denominator
function Read-BinkHeader($path) {
    $header = New-Object byte[] 36
    $stream = [System.IO.File]::OpenRead($path)
    try { [void]$stream.Read($header, 0, 36) } finally { $stream.Close() }
    $binkWidth = [BitConverter]::ToUInt32($header, 20)
    $binkHeight = [BitConverter]::ToUInt32($header, 24)
    if ($binkWidth -ne $Width -or $binkHeight -ne $Height) { throw "Bink came out ${binkWidth}x$binkHeight, expected ${Width}x$Height" }
    return @{
        Frames = [BitConverter]::ToUInt32($header, 8)
        Fps = [BitConverter]::ToUInt32($header, 28) / [BitConverter]::ToUInt32($header, 32)
    }
}

function Write-TextFile($path, $text) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # no BOM, kahlua and the script parser don't want one
    [System.IO.File]::WriteAllText($path, $text + "`n", (New-Object System.Text.UTF8Encoding $false))
}

function Read-Answer($question, $default) {
    $answer = (Read-Host "$question [$default]").Trim()
    if ($answer) { return $answer }
    return $default
}

function Find-Video($folder, $baseName) {
    foreach ($extension in @(".mp4", ".mkv", ".mov", ".avi", ".webm", ".m4v")) {
        $path = Join-Path $folder "$baseName$extension"
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

# returns the number picked, Enter takes the default
function Read-Choice($question, [string[]]$options, [int]$default = 1) {
    Write-Host ""
    Write-Host $question
    for ($i = 0; $i -lt $options.Count; $i++) { Write-Host "  $($i + 1). $($options[$i])" }
    while ($true) {
        $answer = (Read-Host "Pick a number [$default]").Trim()
        if (-not $answer) { return $default }
        $picked = 0
        if ([int]::TryParse($answer, [ref]$picked) -and $picked -ge 1 -and $picked -le $options.Count) { return $picked }
        Write-Host "  That's not one of the choices"
    }
}

function Read-ExistingPath($question) {
    while ($true) {
        $answer = (Read-Host $question).Trim().Trim('"')
        if ($answer -and (Test-Path -LiteralPath $answer)) { return $answer }
        Write-Host "  Nothing there"
    }
}

function Read-Boost($question) {
    $boost = 0.0
    while ($true) {
        $answer = Read-Answer $question "0"
        if ([double]::TryParse($answer, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$boost)) { return $boost }
        Write-Host "  That needs to be a number"
    }
}

# movie add-ons already made in a folder, the ones a trailer can go into
function Find-MovieAddOns($folder) {
    if (-not (Test-Path -LiteralPath $folder)) { return @() }
    foreach ($dir in Get-ChildItem -LiteralPath $folder -Directory -Filter "JimsMovies_*") {
        $id = $dir.Name.Substring("JimsMovies_".Length)
        $registration = Join-Path $dir.FullName "42\media\lua\shared\$($dir.Name)\JimsMovies$id.lua"
        if ((Test-Path -LiteralPath $registration) -and (Get-Content -LiteralPath $registration -Raw) -match 'registerMovie\(') {
            [pscustomobject]@{ Id = $id; Dir = $dir.FullName; Registration = $registration }
        }
    }
}

function Format-Memory($sampleRate, $channels, $seconds) {
    $megabytes = $sampleRate * $channels * 2 * $seconds / 1MB
    if ($megabytes -ge 1024) { return "{0:N1} GB" -f ($megabytes / 1024) }
    return "{0:N0} MB" -f $megabytes
}

if (-not $Video) {
    if (-not $Ask) { throw "Need a -Video, or use -Ask to get asked for one" }
    $Video = (Read-Host "Video file (you can drag it into this window)").Trim().Trim('"')
}
if (-not (Test-Path -LiteralPath $Video)) { throw "No video at $Video" }
$Video = (Resolve-Path -LiteralPath $Video).Path
$defaultModsDir = Join-Path $env:USERPROFILE "Zomboid\mods"
if (-not $Ask -and -not $PSBoundParameters.ContainsKey("ModsDir") -and -not (Test-Path -LiteralPath (Split-Path -Parent $defaultModsDir))) {
    throw "No Zomboid folder at $(Split-Path -Parent $defaultModsDir), pass -ModsDir with where the mod should go"
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
if (-not $Rad -or -not (Test-Path -LiteralPath $Rad)) {
    $radMissing = "Can't find RAD Video Tools. It's a free download from https://www.radgametools.com/bnkdown.htm"
    if (-not $Ask) { throw "$radMissing, or pass -Rad with the path to radvideo64.exe" }
    Write-Host $radMissing
    $Rad = Read-ExistingPath "Path to radvideo64.exe once it's installed"
}
if (-not (Get-Command $Ffmpeg -ErrorAction SilentlyContinue)) {
    $ffmpegMissing = "Can't find ffmpeg. Get it from https://ffmpeg.org/download.html"
    if (-not $Ask) { throw "$ffmpegMissing and put it on the PATH, or pass -Ffmpeg and -Ffprobe with the full paths" }
    Write-Host $ffmpegMissing
    $Ffmpeg = Read-ExistingPath "Path to ffmpeg.exe once it's installed"
    $besideFfmpeg = Join-Path (Split-Path -Parent $Ffmpeg) "ffprobe.exe"
    if (Test-Path -LiteralPath $besideFfmpeg) { $Ffprobe = $besideFfmpeg }
}
if (-not (Get-Command $Ffprobe -ErrorAction SilentlyContinue)) {
    if (-not $Ask) { throw "Can't find ffprobe, it comes with ffmpeg. Pass -Ffprobe with the full path" }
    $Ffprobe = Read-ExistingPath "Path to ffprobe.exe, it comes with ffmpeg"
}

$trailerVideo = $null
if ($Ask) {
    if ($Trailer) { throw "-Trailer doesn't go with -Ask. Drag the movie, a trailer next to it gets picked up" }
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    if (-not $PSBoundParameters.ContainsKey("ModsDir")) { $ModsDir = Split-Path -Parent $Video }
    $videoFolder = Split-Path -Parent $Video
    $videoBase = [System.IO.Path]::GetFileNameWithoutExtension($Video)

    if ($videoBase -match '^(.+)-trailer$') {
        $movieBase = $Matches[1]
        $movieFile = Find-Video $videoFolder $movieBase
        # forgot the trailer? drag it on its own and it goes into the movie add-on that's already made
        $addOns = @(Find-MovieAddOns $ModsDir)
        if ($addOns.Count -gt 0) {
            $choices = @($addOns | ForEach-Object { "Add it to JimsMovies_$($_.Id)" })
            if ($movieFile) { $choices += "Make $([System.IO.Path]::GetFileName($movieFile)) again with this trailer" }
            Write-Host ""
            Write-Host "$([System.IO.Path]::GetFileName($Video)) looks like a trailer" -ForegroundColor Green
            $picked = Read-Choice "What should it do?" $choices
            if ($picked -le $addOns.Count) {
                $addOn = $addOns[$picked - 1]
                $Trailer = $true
                $Id = $addOn.Id
            }
        }
        if (-not $Trailer) {
            if (-not $movieFile) { throw "$([System.IO.Path]::GetFileName($Video)) looks like a trailer and there's no $movieBase video or movie add-on next to it" }
            $Video = $movieFile
            $videoBase = $movieBase
        }
    }
}

if ($Ask -and $Trailer) {
    # match the movie that's already there instead of asking again
    $registrationText = Get-Content -LiteralPath $addOn.Registration -Raw
    if (-not $PSBoundParameters.ContainsKey("Width") -and $registrationText -match 'width = (\d+)') { $Width = [int]$Matches[1] }
    if (-not $PSBoundParameters.ContainsKey("Height") -and $registrationText -match 'height = (\d+)') { $Height = [int]$Matches[1] }
    $movieSound = Get-ChildItem -LiteralPath (Join-Path $addOn.Dir "common\media\sound") -Filter "*.ogg" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '_trailer' } | Select-Object -First 1
    if ($movieSound -and -not $SmallAudio) {
        $audioInfo = (& $Ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate,channels -of csv=p=0 $movieSound.FullName) -split ','
        if ($SampleRate -le 0) { $SampleRate = [int]$audioInfo[0] }
        if (-not $Mono -and [int]$audioInfo[1] -eq 1) { $Mono = $true }
    }

    $audioText = ""
    if ($SampleRate -gt 0) { $audioText = ", $(if ($Mono) { 'mono' } else { 'stereo' }) $SampleRate Hz" }
    Write-Host ""
    Write-Host "Adding the trailer to JimsMovies_$Id at ${Width}x$Height$audioText, matching the movie" -ForegroundColor Green
    $trailerHasSound = [bool](& $Ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 $Video)
    if ($trailerHasSound -and -not $PSBoundParameters.ContainsKey("AudioGain")) { $AudioGain = Read-Boost "Trailer audio boost in dB" }

    if (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $addOn.Registration) "JimsMovies${Id}_Trailer.lua")) {
        Write-Host ""
        if ((Read-Answer "JimsMovies_$Id already has a trailer. Replace it? (y/n)" "n") -notmatch '^[Yy]') {
            Write-Host "Nothing made."
            exit 0
        }
    }
}
elseif ($Ask) {
    $trailerVideo = Find-Video $videoFolder "$videoBase-trailer"
    if (-not $trailerVideo) { $trailerVideo = Find-Video $videoFolder "movie-trailer" }

    $sourceSeconds = [double]::Parse((& $Ffprobe -v error -show_entries format=duration -of csv=p=0 $Video), $culture)
    $sourceSize = (& $Ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x $Video)
    $movieHasSound = [bool](& $Ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 $Video)
    $trailerHasSound = $trailerVideo -and [bool](& $Ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 $trailerVideo)
    $hasSound = $movieHasSound -or $trailerHasSound
    Write-Host ""
    Write-Host "Movie: $([System.IO.Path]::GetFileName($Video)), $sourceSize, $([timespan]::FromSeconds([math]::Round($sourceSeconds)).ToString())"
    if ($trailerVideo) { Write-Host "Found $([System.IO.Path]::GetFileName($trailerVideo)), it'll be the trailer" -ForegroundColor Green }
    else { Write-Host "No trailer found, it would be named $videoBase-trailer" -ForegroundColor Yellow }
    Write-Host ""

    if (-not $Name) { $Name = Read-Answer "Movie name for the menu" $videoBase }
    if (-not $Id) { $Id = ($Name -replace '[^A-Za-z0-9]', '') }
    while ($Id -notmatch '^[A-Za-z][A-Za-z0-9]*$') {
        $Id = (Read-Host "Short code name for the files, letters and numbers, starting with a letter").Trim()
    }

    if (-not $Genre) {
        $genres = @("", "action", "comedy", "drama", "horror", "scifi")
        $Genre = $genres[(Read-Choice "Genre?" @("None", "Action", "Comedy", "Drama", "Horror", "Sci-fi")) - 1]
    }

    if (-not $PSBoundParameters.ContainsKey("Width") -and -not $PSBoundParameters.ContainsKey("Height")) {
        $sizes = @(@(256, 144), @(432, 240), @(640, 360), @(848, 480), @(960, 540), @(1280, 720), @(1920, 1080))
        $sizeChoices = @($sizes | ForEach-Object { "$($_[1])p ($($_[0])x$($_[1]))" })
        $sizeChoices[1] += "  default"
        $size = $sizes[(Read-Choice "Movie size?" $sizeChoices 2) - 1]
        $Width, $Height = $size[0], $size[1]
    }

    if ($hasSound -and -not $SmallAudio) {
        if (-not $Mono -and (Read-Choice "Sound?" @("Stereo", "Mono")) -eq 2) { $Mono = $true }
        if ($SampleRate -le 0) {
            $channels = if ($Mono) { 1 } else { 2 }
            $rates = @(11025, 22050, 44100, 48000)
            $rateChoices = @($rates | ForEach-Object { "$_, up to $(Format-Memory $_ $channels $sourceSeconds) of memory" })
            $rateChoices[2] += "  default"
            $SampleRate = $rates[(Read-Choice "Sound quality?" $rateChoices 3) - 1]
        }
    }

    if ($hasSound) { Write-Host "" }
    if ($movieHasSound -and -not $PSBoundParameters.ContainsKey("AudioGain")) { $AudioGain = Read-Boost "Movie audio boost in dB" }
    if ($trailerHasSound -and -not $PSBoundParameters.ContainsKey("TrailerAudioGain")) { $TrailerAudioGain = Read-Boost "Trailer audio boost in dB" }

    $existing = Join-Path $ModsDir "JimsMovies_$Id"
    if (Test-Path -LiteralPath $existing) {
        Write-Host ""
        if ((Read-Answer "$existing is already there. Replace its files? (y/n)" "n") -notmatch '^[Yy]') {
            Write-Host "Nothing made."
            exit 0
        }
    }
}

if (-not $Ask -and $TrailerFile) {
    if (-not (Test-Path -LiteralPath $TrailerFile)) { throw "No trailer at $TrailerFile" }
    $trailerVideo = (Resolve-Path -LiteralPath $TrailerFile).Path
}

if (-not $Name -and -not $Trailer) {
    $default = [System.IO.Path]::GetFileNameWithoutExtension($Video)
    $Name = Read-Host "Movie name for the menu [$default]"
    if (-not $Name) { $Name = $default }
}
if (-not $Id) { $Id = ($Name -replace '[^A-Za-z0-9]', '') }
if (-not $Id -or $Id -notmatch '^[A-Za-z]') { throw "Need an -Id that starts with a letter, letters and numbers only" }

$movieId = "JimsMovies_$Id"
$modId = "JimsMovies_$Id"
$fileBase = $Id.ToLower()
$fileStem = "JimsMovies$Id"
$modDir = Join-Path $ModsDir $modId
if ($Trailer) {
    if (-not (Test-Path -LiteralPath $modDir)) { throw "No add-on at $modDir, make the movie first or check -Id" }
    $featureId = $movieId
    $movieId = "${movieId}_Trailer"
    $fileBase = "${fileBase}_trailer"
    $fileStem = "${fileStem}_Trailer"
}
$luaDir = Join-Path $modDir "42\media\lua\shared\$modId"
$mediaDir = Join-Path $modDir "common\media"
$bk2 = Join-Path $mediaDir "videos\$fileBase.bk2"
$ogg = Join-Path $mediaDir "sound\$fileBase.ogg"

Write-Host "Making $modId from $([System.IO.Path]::GetFileName($Video))"
if (-not $Trailer) { Write-Host "  menu name: $Name" }
Write-Host "  mod folder: $modDir"
if (-not $Trailer -and (Test-Path -LiteralPath $modDir)) { Write-Host "  that folder's already there, files in it get replaced" -ForegroundColor Yellow }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("jimsmovies_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    Write-Step "Video: ${Width}x$Height at $FPS fps"
    $silent = Join-Path $work "video.mp4"
    $filter = "fps=$FPS,scale=${Width}:${Height}:force_original_aspect_ratio=decrease,pad=${Width}:${Height}:(ow-iw)/2:(oh-ih)/2,setsar=1,format=yuv420p"
    # chapters would come along as a data track and rad goes by the longest track
    Invoke-Ffmpeg @("-i", $Video, "-an", "-sn", "-dn", "-map_chapters", "-1", "-vf", $filter, "-c:v", "libx264", "-crf", "16", "-preset", "fast", $silent)

    Write-Step "Bink: compressing (this will take ages)"
    $videoDir = Split-Path -Parent $bk2
    New-Item -ItemType Directory -Path $videoDir -Force | Out-Null
    # a rerun could leave the other layout or extra video chunks lying around
    Get-ChildItem -LiteralPath $videoDir -Filter "${fileBase}_???.bk2" -ErrorAction SilentlyContinue | Remove-Item
    Get-ChildItem -LiteralPath $videoDir -Filter "$fileBase.bk2" -ErrorAction SilentlyContinue | Remove-Item

    $videoChunkCount = 0
    $videoChunkFrames = $VideoChunkSeconds * $FPS
    if ($VideoChunkSeconds -gt 0) {
        $frames = [int](& $Ffprobe -v error -count_packets -select_streams v:0 -show_entries stream=nb_read_packets -of csv=p=0 $silent)
        if ($frames -gt $videoChunkFrames) { $videoChunkCount = [int][math]::Ceiling($frames / $videoChunkFrames) }
    }

    if ($videoChunkCount -gt 0) {
        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        for ($i = 1; $i -le $videoChunkCount; $i++) {
            $videoChunkStart = ($i - 1) * $videoChunkFrames
            # runs a little long so the next video chunk can take over while this one is still showing
            $videoChunkLength = [math]::Min($videoChunkFrames + $VIDEO_CHUNK_EXTRA_FRAMES, $frames - $videoChunkStart)
            $videoChunkFile = Join-Path $work "video_chunk.mp4"
            Invoke-FfmpegQuiet @("-ss", ($videoChunkStart / $FPS).ToString($culture), "-i", $silent, "-frames:v", "$videoChunkLength", "-an", "-sn", "-dn", "-map_chapters", "-1", "-c:v", "libx264", "-crf", "16", "-preset", "fast", $videoChunkFile)
            $videoChunkBink = Join-Path $videoDir ("${fileBase}_" + $i.ToString("000") + ".bk2")
            Invoke-Rad $videoChunkFile $videoChunkBink
            $binkInfo = Read-BinkHeader $videoChunkBink
            if ($binkInfo.Frames -ne $videoChunkLength) { throw "Video chunk $i came out with $($binkInfo.Frames) frames, expected $videoChunkLength" }
            Write-Host "  video chunk $i of $videoChunkCount"
        }
    }
    else {
        Invoke-Rad $silent $bk2
        $binkInfo = Read-BinkHeader $bk2
        $frames = $binkInfo.Frames
    }
    $binkFps = $binkInfo.Fps
    $length = $frames / $binkFps
    # a tenth under the real length so it stops before bink loops back to frame 1
    $seconds = [math]::Floor(($length - 0.1) * 10) / 10
    $lengthText = $length.ToString("0.###", [System.Globalization.CultureInfo]::InvariantCulture)
    $secondsText = $seconds.ToString("0.0", [System.Globalization.CultureInfo]::InvariantCulture)
    Write-Host "  $frames frames at $binkFps fps = $lengthText seconds"

    $hasAudio = (& $Ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 $Video | Measure-Object).Count -gt 0
    $soundNames = @()
    $soundFiles = @()
    if ($hasAudio) {
        $soundDir = Split-Path -Parent $ogg
        New-Item -ItemType Directory -Path $soundDir -Force | Out-Null
        # a rerun with a different length would leave old audio chunks lying around
        Get-ChildItem -LiteralPath $soundDir -Filter "${fileBase}_???.ogg" -ErrorAction SilentlyContinue | Remove-Item
        Get-ChildItem -LiteralPath $soundDir -Filter "$fileBase.ogg" -ErrorAction SilentlyContinue | Remove-Item

        if ($SmallAudio) {
            $Mono = $true
            if ($SampleRate -le 0) { $SampleRate = 22050 }
        }
        $audioArgs = if ($Mono) { @("-ac", "1") } else { @("-ac", "2") }
        if ($SampleRate -gt 0) { $audioArgs += @("-ar", "$SampleRate") }
        if ($AudioGain -ne 0) { $audioArgs += @("-af", "volume=$($AudioGain.ToString([System.Globalization.CultureInfo]::InvariantCulture))dB") }
        $encode = @("-c:a", "libvorbis", "-q:a", "$AudioQuality")

        if ($AudioChunkSeconds -gt 0) {
            Write-Step "Audio: ogg in $AudioChunkSeconds second audio chunks"
            $audioChunkText = $AudioChunkSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            $culture = [System.Globalization.CultureInfo]::InvariantCulture
            $overlapText = $AudioChunkOverlap.ToString($culture)
            # cut from a wav, seeking the mp4 for every audio chunk is painfully slow
            $wav = Join-Path $work "audio.wav"
            Invoke-Ffmpeg (@("-i", $Video, "-vn") + $audioArgs + @("-c:a", "pcm_s16le", $wav))
            $audioSeconds = [double]::Parse((& $Ffprobe -v error -show_entries format=duration -of csv=p=0 $wav), $culture)
            $count = [int][math]::Ceiling($audioSeconds / $AudioChunkSeconds)
            $takeText = ($AudioChunkSeconds + $AudioChunkOverlap).ToString($culture)
            # one ffmpeg per audio chunk, the segment muxer can't overlap them
            for ($i = 1; $i -le $count; $i++) {
                $number = $i.ToString("000")
                $file = "${fileBase}_$number.ogg"
                $startText = (($i - 1) * $AudioChunkSeconds).ToString($culture)
                Invoke-FfmpegQuiet (@("-ss", $startText, "-t", $takeText, "-i", $wav) + $encode + @((Join-Path $soundDir $file)))
                $soundNames += "${movieId}_$number"
                $soundFiles += $file
                if ($i % 50 -eq 0 -or $i -eq $count) { Write-Host "  $i of $count" }
            }
        }
        else {
            Write-Step "Audio: ogg"
            Invoke-Ffmpeg (@("-i", $Video, "-vn") + $audioArgs + $encode + @($ogg))
            $soundNames += $movieId
            $soundFiles += "$fileBase.ogg"
        }

        # what it'll cost in game: every audio chunk ends up decoded to 16 bit and cached
        $first = Join-Path $soundDir $soundFiles[0]
        $parts = ((& $Ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate,channels -of csv=p=0 $first) -join ",") -split ","
        $memoryMb = [double]$parts[0] * [double]$parts[1] * 2 * $length / 1MB
        Write-Host ("  {0} Hz, {1} channel(s), about {2:N0} MB of memory once the game's played it all" -f $parts[0], $parts[1], $memoryMb)
    }
    else {
        Write-Host "  no audio in the source, the movie will be silent" -ForegroundColor Yellow
    }

    Write-Step "Colors: $ColorFps a second"
    $colors = Join-Path $luaDir "${fileStem}_Colors.lua"
    & (Join-Path $PSScriptRoot "Make-MovieColors.ps1") -Video $Video -MovieId $movieId -Out $colors -Fps $ColorFps -Ffmpeg $Ffmpeg

    Write-Step "Mod files"
    if (-not $Trailer) {
    Write-TextFile (Join-Path $modDir "42\mod.info") @"
name=Jim's Movie Theater: $Name
id=$modId
description=Movie add-on for Jim's Movie Theater.
require=JimsMovies
icon=jbm-addon-icon.png
"@
    Copy-Item (Join-Path $PSScriptRoot "jbm-addon-icon.png") (Join-Path $modDir "42\jbm-addon-icon.png") -Force
    }

    $videoLines = "video = `"$fileBase.bk2`","
    if ($videoChunkCount -gt 0) {
        $videoLines = "videoPrefix = `"${fileBase}_`",`n    videoCount = $videoChunkCount,`n    videoChunkSeconds = $VideoChunkSeconds,"
    }

    $soundLine = ""
    if ($soundNames.Count -gt 1) {
        $soundLine = "`n    soundPrefix = `"${movieId}_`",`n    soundCount = $($soundNames.Count),`n    audioChunkSeconds = $audioChunkText,`n    audioChunkOverlap = $overlapText,"
    }
    elseif ($soundNames.Count -eq 1) {
        $soundLine = "`n    sound = `"$($soundNames[0])`","
    }
    $genreLine = if ($Genre) { "`n    genre = `"$Genre`"," } else { "" }
    $registerCall = if ($Trailer) { "registerTrailer(`"$featureId`"" } else { "registerMovie(`"$movieId`"" }
    $nameLine = if ($Trailer) { "" } else { "`n    name = `"IGUI_JimsMovies${Id}_Name`",$genreLine" }
    Write-TextFile (Join-Path $luaDir "$fileStem.lua") @"
require "JimsMovies/JimsMoviesAPI"

-- $frames frames @ $binkFps = $lengthText seconds
JimsMovies.$registerCall, {
    $videoLines
    width = $Width,
    height = $Height,
    seconds = $secondsText,$soundLine$nameLine
})
"@

    if ($hasAudio) {
        $entries = for ($i = 0; $i -lt $soundNames.Count; $i++) {
            @"
    sound $($soundNames[$i])
    {
        category = World,
        is3D = false,
        clip
        {
            file = media/sound/$($soundFiles[$i]),
            distanceMax = 0,
            volume = 1.0,
        }
    }
"@
        }
        Write-TextFile (Join-Path $mediaDir "scripts\${fileStem}Sounds.txt") ("module Base`n{`n" + ($entries -join "`n") + "`n}")
    }

    if (-not $Trailer) {
    $jsonName = $Name.Replace('\', '\\').Replace('"', '\"')
    Write-TextFile (Join-Path $mediaDir "lua\shared\Translate\EN\IG_UI.json") @"
{
    "IGUI_JimsMovies${Id}_Name": "$jsonName"
}
"@
    }

}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($trailerVideo) {
    $trailerSettings = @{
        Video = $trailerVideo
        Trailer = $true
        PartOfMovie = $true
        Id = $Id
        ModsDir = $ModsDir
        Mono = [bool]$Mono
        SmallAudio = [bool]$SmallAudio
        SampleRate = $SampleRate
        AudioGain = $TrailerAudioGain
        AudioChunkSeconds = $AudioChunkSeconds
        AudioChunkOverlap = $AudioChunkOverlap
        VideoChunkSeconds = $VideoChunkSeconds
        Width = $Width
        Height = $Height
        ColorFps = $ColorFps
        AudioQuality = $AudioQuality
        Rad = $Rad
        Ffmpeg = $Ffmpeg
        Ffprobe = $Ffprobe
    }
    & $PSCommandPath @trailerSettings
}

if ($Trailer -and -not $PartOfMovie) {
    Write-Host ""
    Write-Host "Added the trailer to $modDir" -ForegroundColor Green
}
elseif (-not $PartOfMovie) {
    Write-Host ""
    Write-Host "Made $modDir" -ForegroundColor Green
    if ([System.IO.Path]::GetFullPath($ModsDir).TrimEnd('\') -ne $defaultModsDir) {
        Write-Host "Move that folder into your Zomboid\mods folder or your workshop folder. See the PZWiki if you need help with this." -ForegroundColor Green
    }
    Write-Host "Enable $modId next to Jim's Movie Theater and it'll be in the Start Movie list." -ForegroundColor Green
}
