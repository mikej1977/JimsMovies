<#
    Turns subtitles into a captions lua file for a Jim's Movie Theater add-on you already made.

    The easy way is to drag the subtitles or the mkv onto Make-JimsCaptions.bat. It finds the add-on next to it
    or in your Zomboid\mods folder and asks about anything it can't figure out. Or:

    .\Make-JimsCaptions.ps1 -Subtitles "D:\movies\nosferatu.srt" -Id "Nosferatu"

    -Subtitles   the subtitle file, or a video with subtitle tracks in it
    -Track       which subtitle track to use when there's more than one, 1 is the first
    -Id          the movie add-on's code name, the part after JimsMovies_
    -Language    game language code, EN, ES, FR, DE and so on. defaults to the track's language or EN
    -Offset      seconds to shift every caption by, negative makes them show up sooner. for subtitles that are off
    -Charset     the text encoding for old subtitle files that aren't utf8, CP1252 say. it tries CP1252 on its own if utf8 fails
    -ModsDir     where the add-on is, defaults to the mods folder in Zomboid in your user folder
    -OutDir      a different mod folder to put the captions in, like your own language pack. the movie add-on by default
    -Ask         asks about anything that wasn't passed
#>
param(
    [string]$Subtitles,
    [switch]$Ask,
    [int]$Track = 0,
    [string]$Id,
    [string]$Language,
    [double]$Offset = 0,
    [string]$Charset,
    [string]$ModsDir = (Join-Path $env:USERPROFILE "Zomboid\mods"),
    [string]$OutDir,
    [switch]$ListTracks,
    [string]$Ffmpeg = "ffmpeg",
    [string]$Ffprobe = "ffprobe"
)

$ErrorActionPreference = "Stop"

# the window shows whatever comes out here, so just the message and not powershell's whole error dump
trap {
    if (-not $ListTracks) { break }
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
$culture = [System.Globalization.CultureInfo]::InvariantCulture

$IMAGE_CODECS = @("hdmv_pgs_subtitle", "dvd_subtitle", "dvb_subtitle", "xsub", "dvb_teletext")

# ffprobe gives 3 letter codes, the game wants its own
$LANGUAGE_CODES = @{
    eng = "EN"; spa = "ES"; fre = "FR"; fra = "FR"; ger = "DE"; deu = "DE"; ita = "IT"; por = "PT"
    rus = "RU"; pol = "PL"; jpn = "JP"; kor = "KO"; chi = "CN"; zho = "CN"; dut = "NL"; nld = "NL"
    tur = "TR"; ukr = "UA"; cze = "CS"; ces = "CS"; dan = "DA"; fin = "FI"; hun = "HU"; nor = "NO"
    nob = "NO"; rum = "RO"; ron = "RO"; tha = "TH"; ara = "AR"; ind = "ID"; cat = "CA"; fil = "PH"
}

function Read-Answer($question, $default) {
    $answer = (Read-Host "$question [$default]").Trim()
    if ($answer) { return $answer }
    return $default
}

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

function Find-MovieAddOns($folder) {
    if (-not (Test-Path -LiteralPath $folder)) { return @() }
    foreach ($dir in Get-ChildItem -LiteralPath $folder -Directory -Filter "JimsMovies_*") {
        $addOnId = $dir.Name.Substring("JimsMovies_".Length)
        $registration = Join-Path $dir.FullName "42\media\lua\shared\$($dir.Name)\JimsMovies$addOnId.lua"
        if ((Test-Path -LiteralPath $registration) -and (Get-Content -LiteralPath $registration -Raw) -match 'registerMovie\(') {
            [pscustomobject]@{ Id = $addOnId; Dir = $dir.FullName; Registration = $registration }
        }
    }
}

function Format-Time([double]$seconds) {
    return [timespan]::FromSeconds([math]::Max(0, [math]::Round($seconds))).ToString()
}

function Get-GameLanguage($track) {
    if ($track.Language -and $LANGUAGE_CODES.ContainsKey($track.Language.ToLower())) { return $LANGUAGE_CODES[$track.Language.ToLower()] }
    return "EN"
}

function Get-TrackLabel($track) {
    $parts = @()
    $parts += if ($track.Language) { $track.Language } else { "unknown language" }
    if ($track.Title) { $parts += $track.Title }
    if ($track.Forced) { $parts += "forced, only the foreign bits" }
    $parts += if ($IMAGE_CODECS -contains $track.Codec) { "picture subtitles, can't use" } else { $track.Codec }
    return $parts -join ", "
}

# ffmpeg does the hard part, every text format comes out as ass. ass keeps the tags, so drawings and
# placement can be told apart from the words
function Convert-ToAss($source, [int]$trackIndex, $target, $encoding) {
    $arguments = @("-hide_banner", "-loglevel", "error", "-y")
    if ($encoding) { $arguments += @("-sub_charenc", $encoding) }
    $arguments += @("-i", $source, "-map", "0:s:$trackIndex", "-c:s", "ass", $target)
    $ErrorActionPreference = "Continue"
    $output = & $Ffmpeg @arguments 2>&1 | ForEach-Object { "$_" }
    return [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0); Output = ($output -join "`n") }
}

function Get-AssSeconds([string]$time) {
    $parts = $time.Trim() -split ':'
    return [int]$parts[0] * 3600 + [int]$parts[1] * 60 + [double]::Parse($parts[2], $culture)
}

# alignment is numpad style, 7 8 9 is the top row. \p1 and up means what follows is a drawing, not words
function Convert-AssText([string]$text, [int]$alignment) {
    $builder = New-Object System.Text.StringBuilder
    $drawing = $false
    foreach ($piece in [regex]::Split($text, '(\{[^}]*\})')) {
        if ($piece.StartsWith('{') -and $piece.EndsWith('}')) {
            foreach ($tag in [regex]::Matches($piece, '\\(an|a|p)(\d+)')) {
                $number = [int]$tag.Groups[2].Value
                switch ($tag.Groups[1].Value) {
                    "an" { $alignment = $number }
                    # the old ssa numbering, 5 6 7 is its top row
                    "a" { $alignment = if ($number -ge 5 -and $number -le 7) { 8 } else { 2 } }
                    "p" { $drawing = $number -gt 0 }
                }
            }
            continue
        }
        if (-not $drawing) { [void]$builder.Append($piece) }
    }
    $plain = $builder.ToString() -replace '\\N', "`n" -replace '\\[nh]', ' ' -replace '</?(i|b|u|s|font)\b[^>]*>', ''
    $kept = foreach ($line in ($plain -split "`n")) {
        $line = ($line -replace '\s+', ' ').Trim()
        if ($line) { $line }
    }
    return [pscustomobject]@{ Text = (@($kept) -join "`n"); Top = $alignment -ge 7 }
}

function Split-AssFields([string]$values, [string[]]$format) {
    $fields = @{}
    $parts = $values.Split([char[]]@(','), $format.Count)
    for ($i = 0; $i -lt $parts.Count; $i++) { $fields[$format[$i]] = $parts[$i] }
    return $fields
}

function ConvertTo-LuaString([string]$text) {
    $escaped = $text.Replace('\', '\\').Replace('"', '\"').Replace("`n", '\n')
    $escaped = $escaped -replace '[\x00-\x1f]', ''
    return "`"$escaped`""
}

if (-not $Subtitles) {
    if (-not $Ask) { throw "Need -Subtitles, or use -Ask to get asked for them" }
    $Subtitles = (Read-Host "Subtitle file or video with subtitles (you can drag it into this window)").Trim().Trim('"')
}
if (-not (Test-Path -LiteralPath $Subtitles)) { throw "Nothing at $Subtitles" }
$Subtitles = (Resolve-Path -LiteralPath $Subtitles).Path

foreach ($tool in @($Ffmpeg, $Ffprobe)) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Can't find $tool. Get ffmpeg from https://ffmpeg.org/download.html and put it on the PATH, or pass -Ffmpeg and -Ffprobe with the full paths"
    }
}

$probeText = (& $Ffprobe -v error -select_streams s -show_entries "stream=codec_name:stream_tags=language,title:stream_disposition=forced" -of json $Subtitles) -join "`n"
if ($LASTEXITCODE -ne 0 -or -not $probeText.Trim()) { throw "ffprobe can't read $([System.IO.Path]::GetFileName($Subtitles)), is it a subtitle file or a video?" }
$probe = $probeText | ConvertFrom-Json
$tracks = @(foreach ($stream in @($probe.streams)) {
    if (-not $stream) { continue }
    [pscustomobject]@{
        Codec = $stream.codec_name
        Language = if ($stream.tags) { $stream.tags.language } else { $null }
        Title = if ($stream.tags) { $stream.tags.title } else { $null }
        Forced = $stream.disposition -and $stream.disposition.forced -eq 1
    }
})
if ($tracks.Count -eq 0) {
    throw "No subtitle tracks in $([System.IO.Path]::GetFileName($Subtitles)). If you see captions when it plays, they're painted on the picture and can't be pulled out"
}

# for the window, so it can fill in its track list
if ($ListTracks) {
    $list = @($tracks | ForEach-Object {
        [pscustomobject]@{ Label = Get-TrackLabel $_; Usable = $IMAGE_CODECS -notcontains $_.Codec; Language = Get-GameLanguage $_ }
    })
    ConvertTo-Json -InputObject $list -Compress
    exit 0
}

if ($Track -gt 0) {
    if ($Track -gt $tracks.Count) { throw "-Track $Track but there's only $($tracks.Count) subtitle track(s)" }
    $trackIndex = $Track - 1
}
elseif ($tracks.Count -eq 1) {
    $trackIndex = 0
}
elseif ($Ask) {
    $trackIndex = (Read-Choice "Which subtitles?" @($tracks | ForEach-Object { Get-TrackLabel $_ })) - 1
}
else {
    $list = for ($i = 0; $i -lt $tracks.Count; $i++) { "  $($i + 1). $(Get-TrackLabel $tracks[$i])" }
    throw "There's $($tracks.Count) subtitle tracks, pick one with -Track:`n$($list -join "`n")"
}
$picked = $tracks[$trackIndex]
if ($IMAGE_CODECS -contains $picked.Codec) {
    throw "Those are picture subtitles ($($picked.Codec)), not text. Turn them into an srt with Subtitle Edit's OCR first, it's free"
}

$modDir = $null
$registration = $null
if ($Id) {
    $modDir = Join-Path $ModsDir "JimsMovies_$Id"
    $registration = Join-Path $modDir "42\media\lua\shared\JimsMovies_$Id\JimsMovies$Id.lua"
    if (-not (Test-Path -LiteralPath $registration)) {
        # a language pack doesn't need the movie add-on, just its id
        if (-not $OutDir) { throw "No movie add-on at $modDir, check -Id and -ModsDir" }
        $modDir = $null
        $registration = $null
    }
}
else {
    if (-not $Ask) { throw "Need the add-on's -Id, the part after JimsMovies_" }
    $folders = @(Split-Path -Parent $Subtitles)
    if ($folders -notcontains $ModsDir) { $folders += $ModsDir }
    $addOns = @(foreach ($folder in $folders) { Find-MovieAddOns $folder })
    if ($addOns.Count -eq 0) {
        Write-Host ""
        Write-Host "No movie add-on next to the subtitles or in $ModsDir" -ForegroundColor Yellow
        while ($Id -notmatch '^[A-Za-z][A-Za-z0-9]*$') {
            $Id = (Read-Host "The movie's code name, the part after JimsMovies_").Trim()
        }
    }
    else {
        $addOn = $addOns[0]
        if ($addOns.Count -gt 1) {
            $addOn = $addOns[(Read-Choice "Which movie are these for?" @($addOns | ForEach-Object { "JimsMovies_$($_.Id)  ($($_.Dir))" })) - 1]
        }
        $Id = $addOn.Id
        $modDir = $addOn.Dir
        $registration = $addOn.Registration
    }
}

if (-not $OutDir -and $Ask) {
    $choices = @("In another mod folder, like a language pack")
    if ($modDir) { $choices = @("In the movie add-on") + $choices }
    if ((Read-Choice "Where should the captions go?" $choices) -eq $choices.Count) {
        $OutDir = (Read-Host "Mod folder (you can drag it into this window)").Trim().Trim('"')
    }
}
if (-not $OutDir) {
    if (-not $modDir) { throw "Can't find the movie add-on, pass -OutDir with the mod folder the captions should go in" }
    $OutDir = $modDir
}
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path.TrimEnd('\')

if (-not $Language) {
    $Language = Get-GameLanguage $picked
    if ($Ask) { $Language = Read-Answer "Game language code for these" $Language }
}
$Language = $Language.ToUpper()
if ($Language -notmatch '^[A-Z]{2,4}$') { throw "-Language should be a game language code like EN or PTBR" }

$movieId = "JimsMovies_$Id"
# named after the mod folder so two language packs can't stomp on each other's files
$luaFolder = Split-Path -Leaf $OutDir
$out = Join-Path $OutDir "42\media\lua\shared\$luaFolder\JimsMovies${Id}_Captions_$Language.lua"
if ((Test-Path -LiteralPath $out) -and $Ask) {
    Write-Host ""
    if ((Read-Answer "$luaFolder already has $Language captions for $movieId. Replace them? (y/n)" "n") -notmatch '^[Yy]') {
        Write-Host "Nothing made."
        exit 0
    }
}

Write-Host ""
Write-Host "Making $Language captions for $movieId from $([System.IO.Path]::GetFileName($Subtitles))"

$ass = Join-Path ([System.IO.Path]::GetTempPath()) ("jimscaptions_" + [guid]::NewGuid().ToString("N") + ".ass")
try {
    $converted = Convert-ToAss $Subtitles $trackIndex $ass $Charset
    if (-not $converted.Ok -and -not $Charset) {
        Write-Host "  not utf8, trying it as CP1252" -ForegroundColor Yellow
        $converted = Convert-ToAss $Subtitles $trackIndex $ass "CP1252"
    }
    if (-not $converted.Ok) { throw "ffmpeg couldn't read the subtitles:`n$($converted.Output)" }
    $assText = [System.IO.File]::ReadAllText($ass, [System.Text.Encoding]::UTF8)
}
finally {
    Remove-Item -LiteralPath $ass -ErrorAction SilentlyContinue
}

$section = ""
$styleFormat = @()
$eventFormat = @("Layer", "Start", "End", "Style", "Name", "MarginL", "MarginR", "MarginV", "Effect", "Text")
$styleAlignments = @{}
$cues = New-Object System.Collections.Generic.List[object]
foreach ($line in ($assText -split "\r?\n")) {
    if ($line -match '^\s*\[(.+)\]\s*$') {
        $section = $Matches[1]
    }
    elseif ($line -match '^Format:\s*(.*)$') {
        $format = @($Matches[1].Split(',') | ForEach-Object { $_.Trim() })
        if ($section -like "*Styles*") { $styleFormat = $format } elseif ($section -eq "Events") { $eventFormat = $format }
    }
    elseif ($section -like "*Styles*" -and $line -match '^Style:\s*(.*)$' -and $styleFormat.Count -gt 0) {
        $fields = Split-AssFields $Matches[1] $styleFormat
        $styleAlignments[$fields["Name"].Trim()] = [int]$fields["Alignment"]
    }
    elseif ($section -eq "Events" -and $line -match '^Dialogue:\s*(.*)$') {
        $fields = Split-AssFields $Matches[1] $eventFormat
        $style = $fields["Style"].Trim()
        $alignment = if ($styleAlignments.ContainsKey($style)) { $styleAlignments[$style] } else { 2 }
        $parsed = Convert-AssText $fields["Text"] $alignment
        $start = (Get-AssSeconds $fields["Start"]) + $Offset
        $end = (Get-AssSeconds $fields["End"]) + $Offset
        if ($parsed.Text -and $end -gt 0 -and $end -gt $start) {
            $cues.Add([pscustomobject]@{ Index = $cues.Count; Start = [math]::Max(0.0, $start); End = $end; Text = $parsed.Text; Top = $parsed.Top })
        }
    }
}

# signs come in layers and moving ones get a line per frame, so the same words that touch or overlap become one caption
$captions = New-Object System.Collections.Generic.List[object]
$lastByText = New-Object 'System.Collections.Generic.Dictionary[string,object]'
foreach ($cue in ($cues | Sort-Object Start, Index)) {
    $key = "$($cue.Top)|$($cue.Text)"
    $previous = $null
    if ($lastByText.TryGetValue($key, [ref]$previous) -and $cue.Start -le $previous.End + 0.1) {
        $previous.End = [math]::Max($previous.End, $cue.End)
        continue
    }
    $captions.Add($cue)
    $lastByText[$key] = $cue
}
if ($captions.Count -eq 0) { throw "Didn't find any captions in there" }
$mergedCount = $cues.Count - $captions.Count
$countText = if ($captions.Count -eq 1) { "1 caption" } else { "$($captions.Count) captions" }

$builder = New-Object System.Text.StringBuilder
[void]$builder.AppendLine("-- Made by Make-JimsCaptions.ps1 from $([System.IO.Path]::GetFileName($Subtitles)), $countText")
[void]$builder.AppendLine('require "JimsMovies/JimsMoviesAPI"')
[void]$builder.AppendLine("")
[void]$builder.AppendLine("JimsMovies.registerCaptions(`"$movieId`", `"$Language`", {")
foreach ($caption in $captions) {
    $start = $caption.Start.ToString("0.###", $culture)
    $end = $caption.End.ToString("0.###", $culture)
    $topText = if ($caption.Top) { ", top = true" } else { "" }
    [void]$builder.AppendLine("    { start = $start, stop = $end, text = $(ConvertTo-LuaString $caption.Text)$topText },")
}
[void]$builder.AppendLine("})")

$luaDir = Split-Path -Parent $out
if (-not (Test-Path -LiteralPath $luaDir)) { New-Item -ItemType Directory -Path $luaDir -Force | Out-Null }
# no BOM, kahlua doesn't want one
[System.IO.File]::WriteAllText($out, $builder.ToString(), (New-Object System.Text.UTF8Encoding $false))

$first = $captions[0]
$last = $captions[$captions.Count - 1]
Write-Host "  $countText, first at $(Format-Time $first.Start), last one ends at $(Format-Time $last.End)"
if ($mergedCount -gt 0) { Write-Host "  merged $mergedCount repeated line(s), the same words in layers or a line per frame" }
if (-not $registration) {
    Write-Host "  couldn't find the movie add-on to check the length, make sure $movieId is the right movie" -ForegroundColor Yellow
}
elseif ((Get-Content -LiteralPath $registration -Raw) -match '(?m)^\s*seconds = ([\d.]+)') {
    $movieSeconds = [double]::Parse($Matches[1], $culture)
    if ($last.End -gt $movieSeconds + 5) {
        Write-Host "  the movie's only $(Format-Time $movieSeconds) long, wrong subtitles or they need an -Offset?" -ForegroundColor Yellow
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $OutDir "42\mod.info"))) {
    Write-Host "  $OutDir doesn't have a 42\mod.info yet, the game won't load it until it does" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Wrote $out" -ForegroundColor Green
