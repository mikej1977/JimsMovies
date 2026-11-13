<#
    Adds audio tracks players can switch to, other languages or a commentary say, to a movie add-on you already
    made. They get cut into the same audio chunks as the movie's own sound so they switch over cleanly.

      1. ffmpeg pulls the track out at the same sample rate and channels as the movie's own oggs
      2. it gets cut into the same audio chunks, with the same overlap for the crossfade
      3. a sound script and a small lua register it under a game language code

    .\Make-JimsAudio.ps1 -Source "D:\movies\akira.mkv" -Id "Akira" -Tracks "2,3"

    -Source      the video or audio file with the tracks, usually the movie itself
    -Track       which audio track, 1 is the first
    -Tracks      several audio tracks at once, "2,3,5". a second track in the same language gets its own entry
                 named after the track, EN2 and so on
    -AllTracks   every audio track that says its language, instead of -Track or -Tracks
    -SkipTrack   an audio track to leave out, the one the movie already plays. the movie maker passes this
    -Language    game language code for -Track, EN, ES, JP and so on. defaults to the track's language
    -Label       a name for -Track in the game's menu, like Commentary. defaults to the track's title
    -Replace     clears out the add-on's other audio tracks first, for when the movie gets made again
    -AudioGain   makes it louder in dB, 18 say, negative turns it down
    -Id          the movie add-on's code name, the part after JimsMovies_
    -ModsDir     where the add-on is, defaults to the mods folder in Zomboid in your user folder
#>
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [int]$Track = 0,
    [string]$Tracks,
    [switch]$AllTracks,
    [int]$SkipTrack = 0,
    [string]$Language,
    [string]$Label,
    [switch]$Replace,
    [double]$AudioGain = 0,
    [Parameter(Mandatory = $true)][string]$Id,
    [string]$ModsDir = (Join-Path $env:USERPROFILE "Zomboid\mods"),
    [int]$AudioQuality = 4,
    [string]$Ffmpeg = "ffmpeg",
    [string]$Ffprobe = "ffprobe"
)

$ErrorActionPreference = "Stop"
$culture = [System.Globalization.CultureInfo]::InvariantCulture

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

function Write-TextFile($path, $text) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    # no BOM, kahlua and the script parser don't want one
    [System.IO.File]::WriteAllText($path, $text + "`n", (New-Object System.Text.UTF8Encoding $false))
}

function Get-TrackLanguage($stream) {
    $tag = if ($stream.tags) { "$($stream.tags.language)".ToLower() } else { "" }
    if ($LANGUAGE_CODES.ContainsKey($tag)) { return $LANGUAGE_CODES[$tag] }
    return $null
}

# "English Opus 5.1 @ 320 kb/s" comes out English Opus 5.1. ascii only, kahlua garbles anything else
function Get-TrackLabel($stream) {
    $title = if ($stream.tags) { "$($stream.tags.title)" } else { "" }
    $title = ((($title -split ' / ')[0] -split ' \[')[0] -split ' @ ')[0]
    $title = ($title -replace '[^\x20-\x7e]', '').Trim()
    if ($title) { return $title }
    return $null
}

if (-not (Test-Path -LiteralPath $Source)) { throw "Nothing at $Source" }
$Source = (Resolve-Path -LiteralPath $Source).Path
foreach ($tool in @($Ffmpeg, $Ffprobe)) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Can't find $tool. Put ffmpeg on the PATH, or pass -Ffmpeg and -Ffprobe with the full paths" }
}

# what the movie add-on's own sound looks like, read back out of its registration
$movieId = "JimsMovies_$Id"
$fileBase = $Id.ToLower()
$modDir = Join-Path $ModsDir $movieId
$luaDir = Join-Path $modDir "42\media\lua\shared\$movieId"
$registration = Join-Path $luaDir "JimsMovies$Id.lua"
if (-not (Test-Path -LiteralPath $registration)) { throw "No movie add-on at $modDir, make the movie first or check -Id" }
$registrationText = Get-Content -LiteralPath $registration -Raw
$soundDir = Join-Path $modDir "common\media\sound"
$chunkCount = 0
if ($registrationText -match 'soundCount = (\d+)') {
    $chunkCount = [int]$Matches[1]
    if ($registrationText -notmatch 'audioChunkSeconds = ([\d.]+)') { throw "Can't find audioChunkSeconds in $registration" }
    $chunkSeconds = [double]::Parse($Matches[1], $culture)
    $overlap = 0
    if ($registrationText -match 'audioChunkOverlap = ([\d.]+)') { $overlap = [double]::Parse($Matches[1], $culture) }
    $firstOgg = Join-Path $soundDir "${fileBase}_001.ogg"
}
elseif ($registrationText -match 'sound = "') {
    $firstOgg = Join-Path $soundDir "$fileBase.ogg"
}
else { throw "The movie in $registration has no sound of its own to match" }
if (-not (Test-Path -LiteralPath $firstOgg)) { throw "Can't find the movie's own sound at $firstOgg" }
$format = ((& $Ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate,channels -of csv=p=0 $firstOgg) -join ",") -split ","
$sampleRate, $channels = $format[0], $format[1]

# which tracks
$probe = (& $Ffprobe -v error -select_streams a -show_entries "stream=codec_name,channels:stream_tags=language,title" -of json $Source) -join "`n" | ConvertFrom-Json
$audioStreams = @($probe.streams | Where-Object { $_ })
if ($audioStreams.Count -eq 0) { throw "No audio tracks in $([System.IO.Path]::GetFileName($Source))" }

# which track numbers
$picked = @()
if ($Tracks) {
    foreach ($part in ($Tracks -split '[,\s]+' | Where-Object { $_ })) {
        $number = 0
        if (-not [int]::TryParse($part, [ref]$number) -or $number -lt 1 -or $number -gt $audioStreams.Count) { throw "-Tracks has $part, there are audio tracks 1 to $($audioStreams.Count)" }
        if ($number -ne $SkipTrack -and $picked -notcontains $number) { $picked += $number }
    }
}
elseif ($AllTracks) {
    for ($i = 1; $i -le $audioStreams.Count; $i++) {
        if ($i -eq $SkipTrack) { continue }
        if (-not (Get-TrackLanguage $audioStreams[$i - 1])) { Write-Host "  skipping audio track $i, it doesn't say a language the game knows. add it by itself with -Track $i -Language XX" -ForegroundColor Yellow; continue }
        $picked += $i
    }
}
else {
    if ($Track -le 0) {
        if ($audioStreams.Count -gt 1) { throw "$([System.IO.Path]::GetFileName($Source)) has $($audioStreams.Count) audio tracks, pick with -Track, -Tracks or -AllTracks" }
        $Track = 1
    }
    if ($Track -gt $audioStreams.Count) { throw "-Track $Track but there's only $($audioStreams.Count) audio track(s)" }
    $picked = @($Track)
}
if ($picked.Count -eq 0) { throw "No other audio tracks to add from $([System.IO.Path]::GetFileName($Source))" }
if ($Language -and $picked.Count -gt 1) { throw "-Language goes with a single -Track, more than one uses each track's own language" }

# one job per track. Key names its files and its menu entry, EN, then EN2 for a second english
$jobs = @()
$perLanguage = @{}
foreach ($number in $picked) {
    $stream = $audioStreams[$number - 1]
    $code = if ($Language) { $Language.ToUpper() } else { Get-TrackLanguage $stream }
    $trackLabel = if ($Label -and $picked.Count -eq 1) { ($Label -replace '[^\x20-\x7e]', '').Trim() } else { Get-TrackLabel $stream }
    if (-not $code) {
        # checked by hand with no language, it still goes in under its title
        $code = "UND"
        if (-not $trackLabel) { $trackLabel = "Track $number" }
    }
    $perLanguage[$code] = 1 + $(if ($perLanguage.ContainsKey($code)) { $perLanguage[$code] } else { 0 })
    $key = if ($perLanguage[$code] -gt 1) { "$code$($perLanguage[$code])" } else { $code }
    $jobs += [pscustomobject]@{ Track = $number; Language = $code; Key = $key; Label = $trackLabel }
}
foreach ($job in $jobs) {
    if ($job.Language -notmatch '^[A-Z]{2,4}$') { throw "-Language should be a game language code like EN or PTBR" }
}

$chunkText = if ($chunkCount -gt 0) { "$chunkCount audio chunks" } else { "one ogg" }
Write-Host "Adding $(@($jobs | ForEach-Object { $_.Key }) -join ', ') audio to $movieId from $([System.IO.Path]::GetFileName($Source)), $sampleRate Hz, $channels channel(s), $chunkText"

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("jimsaudio_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    if ($Replace) {
        foreach ($old in @(Get-ChildItem -LiteralPath $soundDir -Filter "${fileBase}_au_*.ogg" -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $old.FullName }
        foreach ($old in @(Get-ChildItem -LiteralPath (Join-Path $modDir "common\media\scripts") -Filter "JimsMovies${Id}Sounds_*.txt" -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $old.FullName }
        foreach ($old in @(Get-ChildItem -LiteralPath $luaDir -Filter "JimsMovies${Id}_Audio_*.lua" -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $old.FullName }
    }
    foreach ($job in $jobs) {
        $code = $job.Key
        $labelText = if ($job.Label) { " ($($job.Label))" } else { "" }
        Write-Step "$code audio$labelText, track $($job.Track)"
        $prefix = "${fileBase}_au_${code}"
        foreach ($old in @(Get-ChildItem -LiteralPath $soundDir -Filter "${prefix}_???.ogg" -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $old.FullName }
        foreach ($old in @(Get-ChildItem -LiteralPath $soundDir -Filter "$prefix.ogg" -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $old.FullName }

        $pull = @("-i", $Source, "-vn", "-map", "0:a:$($job.Track - 1)", "-ac", $channels, "-ar", $sampleRate)
        if ($AudioGain -ne 0) { $pull += @("-af", "volume=$($AudioGain.ToString($culture))dB") }
        $encode = @("-c:a", "libvorbis", "-q:a", "$AudioQuality")
        $soundNames = @()
        $soundFiles = @()
        if ($chunkCount -gt 0) {
            # cut from a wav, seeking the movie for every audio chunk is painfully slow
            $wav = Join-Path $work "audio.wav"
            Invoke-Ffmpeg ($pull + @("-c:a", "pcm_s16le", $wav))
            $takeText = ($chunkSeconds + $overlap).ToString($culture)
            $wavSeconds = [double]::Parse((& $Ffprobe -v error -show_entries format=duration -of csv=p=0 $wav), $culture)
            $layout = if ([int]$channels -eq 1) { "mono" } else { "stereo" }
            # the same count as the movie's own audio chunks, so chunk N lines up whatever this track's length is
            for ($i = 1; $i -le $chunkCount; $i++) {
                $number = $i.ToString("000")
                $file = "${prefix}_$number.ogg"
                $start = ($i - 1) * $chunkSeconds
                # a shorter track runs out early, the rest of its chunks are silence so the count still matches
                $chunkInput = if ($start -lt $wavSeconds) { @("-ss", $start.ToString($culture), "-t", $takeText, "-i", $wav, "-af", "apad") }
                    else { @("-f", "lavfi", "-i", "anullsrc=r=${sampleRate}:cl=$layout") }
                Invoke-Ffmpeg ($chunkInput + $encode + @("-t", $takeText, (Join-Path $soundDir $file)))
                $soundNames += "${movieId}_au_${code}_$number"
                $soundFiles += $file
                if ($i % 50 -eq 0 -or $i -eq $chunkCount) { Write-Host "  $i of $chunkCount" }
            }
            Remove-Item -LiteralPath $wav
        }
        else {
            $file = "$prefix.ogg"
            Invoke-Ffmpeg ($pull + $encode + @((Join-Path $soundDir $file)))
            $soundNames += "${movieId}_au_$code"
            $soundFiles += $file
        }

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
        Write-TextFile (Join-Path $modDir "common\media\scripts\JimsMovies${Id}Sounds_$code.txt") ("module Base`n{`n" + ($entries -join "`n") + "`n}")

        $soundLine = if ($chunkCount -gt 0) { "soundPrefix = `"${movieId}_au_${code}_`",`n    soundCount = $chunkCount," } else { "sound = `"${movieId}_au_$code`"," }
        $labelLine = if ($job.Label) { "`n    label = `"$($job.Label.Replace('\', '\\').Replace('"', '\"'))`"," } else { "" }
        Write-TextFile (Join-Path $luaDir "JimsMovies${Id}_Audio_$code.lua") @"
require "JimsMovies/JimsTheaterAudio"

-- $code audio, track $($job.Track) of $([System.IO.Path]::GetFileName($Source) -replace '[^\x20-\x7e]', '?')
if not JimsMovies.registerAudioTrack then return end
JimsMovies.registerAudioTrack("$movieId", "$code", {
    language = "$($job.Language)",$labelLine
    $soundLine
})
"@
        Write-Host "  $($soundNames.Count) ogg(s), sound script and registration"
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Added $(@($jobs | ForEach-Object { $_.Key }) -join ', ') audio to $movieId" -ForegroundColor Green
