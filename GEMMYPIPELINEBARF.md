# Jim's Movie Maker Pipeline

What `Make-JimsMovie.ps1` does, step by step, with the exact ffmpeg and RAD commands, file names and output formats.

- `Make-JimsMovie.ps1`: makes the movie add-on
- `Make-MovieColors.ps1`: the screen glow colors, called by the maker
- `Make-JimsAudio.ps1`: other audio tracks players can switch to, called by the maker
- `Make-JimsCaptions.ps1`: caption tracks players can turn on, called by the maker

## What Gemmy thinks has to change for Linux

ffmpeg and ffprobe run natively. Everything Windows-only is in how the scripts launch RAD, ask questions and draw the window.

| Windows piece | Used for | Linux / Wine replacement |
|---|---|---|
| `radvideo64.exe` (RAD Video Tools) | The only Bink 2 encoder. No Linux build exists | `wine radvideo64.exe bink2c <in> <out> ...`. Paths it gets must be Windows-style; convert with `winepath -w` (they usually come out as `Z:\...`) |
| `WScript.Shell.Run(cmd, 7, $true)` | Starts RAD minimized without taking focus, waits for it | `subprocess.run(["wine", rad, ...])`. Window style doesn't matter there |
| CIM `Win32_Process.Create` | `-BinkJobs`: several RAD copies at once | `subprocess.Popen` per chunk and poll. Several RAD copies at once under Wine haven't been tried |
| `System.Drawing` | Captions only: sets pixel (0,0) of the first frame to alpha 1 | Pillow, or have ffmpeg draw the pixel |
| WinForms window, `Read-Host` prompts | The window and the `-Ask` questions | Command line arguments or any GUI toolkit |
| Looking in `Program Files (x86)\RADVideo`, `%APPDATA%\JimsMovieMaker` | Finding RAD, remembering paths | Look under the Wine prefix (`~/.wine/drive_c/Program Files (x86)/RADVideo`), save settings anywhere |

> **Two things that bite on any OS.** Bink width must be a multiple of 16 or the picture skews in game (height only has to be even). Every Lua and text file is written as plain UTF-8 with no BOM, and Lua strings must stay ASCII, since the game garbles non-ASCII in Lua string literals.

## Names and folders

Everything is derived from the movie name, or `-Id` when it's passed. The examples use the name `Night of the Living Dead`.

| Value | Rule | Example |
|---|---|---|
| Id | Name with everything but letters and digits removed | `NightoftheLivingDead` |
| movie id, mod id | `JimsMovies_<Id>` | `JimsMovies_NightoftheLivingDead` |
| file base | Id lowercased, used for bk2 and ogg names | `nightofthelivingdead` |
| file stem | `JimsMovies<Id>`, used for Lua and script names | `JimsMoviesNightoftheLivingDead` |
| mod folder | `<ModsDir>/JimsMovies_<Id>`, ModsDir defaults to `~/Zomboid/mods` | |
| Trailer run | movie id + `_Trailer`, file base + `_trailer`, file stem + `_Trailer`, same mod folder | `nightofthelivingdead_trailer.bk2` |

```text
JimsMovies_<Id>/
  42/mod.info
  42/jbm-addon-icon.png
  42/media/lua/shared/JimsMovies_<Id>/<fileStem>.lua           registration
  42/media/lua/shared/JimsMovies_<Id>/<fileStem>_Colors.lua    screen glow colors
  common/media/videos/<fileBase>_001.bk2 ...                    video chunks (or <fileBase>.bk2)
  common/media/sound/<fileBase>_001.ogg ...                     audio chunks (or <fileBase>.ogg)
  common/media/scripts/<fileStem>Sounds.txt                     sound script
  common/media/lua/shared/Translate/EN/IG_UI.json               menu name
```

## The steps

Defaults: 1280x720 (the window defaults to 240p, 432x240), 30 fps, 60 second video chunks, 10 second audio chunks with 0.3 seconds of overlap, Vorbis quality 4. Everything runs in a temp work folder that gets deleted at the end.

### 1. Burned-in subtitles (optional)

Only when subtitles get burned into the picture. Pull the chosen track out as ASS into the work folder. If that fails, the file is assumed to be CP1252 and it tries again.

```sh
ffmpeg -i <subs or video> -map 0:s:<track-1> -c:s ass <work>/burn.ass
ffmpeg -sub_charenc CP1252 -i <subs or video> -map 0:s:<track-1> -c:s ass <work>/burn.ass
```

The filter added to step 2 is `,subtitles=burn.ass`. Plain subtitles (anything but ass/ssa) also get `:force_style='FontSize=22,Outline=2,Shadow=0'`. A chosen font adds `FontName=...`. Use the bare file name and run ffmpeg from the work folder, because the subtitles filter chokes on full paths.

### 2. Silent working video

```sh
cd <work>
ffmpeg -hide_banner -loglevel error -stats -y -i <video> -an -sn -dn -map_chapters -1 \
  -vf "fps=30,scale=W:H:force_original_aspect_ratio=decrease,pad=W:H:(ow-iw)/2:(oh-ih)/2,setsar=1[,subtitles=...],format=yuv420p" \
  -c:v libx264 -crf 16 -preset fast video.mp4
```

The picture is letterboxed to the exact size. Chapters are dropped because they come through as a data track and RAD goes by the longest track.

### 3. Count frames, plan the chunks

```sh
ffprobe -v error -count_packets -select_streams v:0 -show_entries stream=nb_read_packets -of csv=p=0 video.mp4
```

`chunkFrames = VideoChunkSeconds * 30` (1800 by default). With more frames than one chunk, `count = ceil(frames / chunkFrames)`. Otherwise, or with `-VideoChunkSeconds 0`, it makes one bink for the whole movie.

### 4. Bink video

For each chunk `i` from 1: `start = (i-1) * chunkFrames`, `length = min(chunkFrames + 6, frames - start)`. So each chunk is its full 60 seconds plus 6 extra frames, 1806 frames by default (the last one is just whatever is left). The extra frames overlap the start of the next chunk, so the game can hand over to it while the old one is still showing.

```sh
ffmpeg -ss <start/30> -i video.mp4 -frames:v <length> -an -sn -dn -map_chapters -1 \
  -c:v libx264 -crf 16 -preset fast chunk_NNN.mp4
radvideo64.exe bink2c chunk_NNN.mp4 <mod>/common/media/videos/<fileBase>_NNN.bk2 /L-1 /O /#
```

`NNN` is zero-padded to 3. `/L-1` means no audio in the bink, `/O` overwrites, and `/#` runs unattended and exits when done. One bink instead: `bink2c video.mp4 <fileBase>.bk2 /L-1 /O /#`.

Then read each bink's header to check it. All fields are little-endian uint32:

| Offset | Field | Check |
|---|---|---|
| 0 | magic `KB2?` | first 3 bytes are `KB2` |
| 4 | file size minus 8 | + 8 equals the file's size, which catches a half-written bink |
| 8 | frame count | equals `length`. The last chunk may be 1 or 2 short, which is fine |
| 20, 24 | width, height | equal W and H |
| 28, 32 | fps numerator, denominator | used for the movie length |
| 36 | flags | `0x00100000` means it has an alpha plane (captions) |

Total frames are `(count - 1) * chunkFrames + last chunk's real frames`. The registration's `seconds` is `floor((frames / fps - 0.1) * 10) / 10`, a tenth under the real length so it stops before Bink loops back to frame 1.

`-ReuseBinks` keeps any chunk that already passes these checks and only remakes the rest. `-BinkJobs N` runs N RAD copies at once, cutting the next chunk while the others compress.

### 5. Audio

Skipped when the source has no audio, which makes a silent movie. Otherwise rip one WAV, then cut it, because seeking the source for every chunk is slow.

```sh
ffmpeg -i <video> -vn [-map 0:a:<track-1>] -ac 2 [-ar <rate>] [-af volume=<gain>dB] -c:a pcm_s16le audio.wav
ffprobe -v error -show_entries format=duration -of csv=p=0 audio.wav
# count = ceil(duration / 10), for each i:
ffmpeg -ss <(i-1)*10> -t 10.3 -i audio.wav -c:a libvorbis -q:a 4 <mod>/common/media/sound/<fileBase>_NNN.ogg
```

`-ac 1` for mono. `-SmallAudio` means mono at 22050 Hz. Each chunk runs 0.3 seconds over so the game can crossfade. With `-AudioChunkSeconds 0` it makes one ogg: `ffmpeg -i <video> -vn ... -c:a libvorbis -q:a 4 <fileBase>.ogg`. Sound names are `<movie id>_NNN`, or just the movie id for one ogg.

### 6. Screen glow colors (Make-MovieColors.ps1)

Averages each frame down to 4 pixels, at 30 a second, run on the original source video.

```sh
ffmpeg -hide_banner -loglevel error -y -i <video> -an -vf "fps=30,scale=4:1:flags=area" -f rawvideo -pix_fmt rgb24 <tmp>
```

The raw bytes go into `<fileStem>_Colors.lua`, 16 samples (192 numbers) per line:

```lua
-- Barfed out by Make-MovieColors.ps1 from <video>, <samples> samples at 30 FPS
require "JimsMovies/JimsMoviesAPI"

JimsMovies.registerMovieColors("<movie id>", 30, {
    r,g,b,r,g,b,r,g,b,r,g,b, ... ,
}, 4)
```

### 7. Mod files

`42/mod.info` (feature only, not trailer runs), with `jbm-addon-icon.png` copied next to it:

```ini
name=Jim's Movie Theater: <Name>
id=JimsMovies_<Id>
description=Movie add-on for Jim's Movie Theater.
require=JimsMovies
icon=jbm-addon-icon.png
```

`<fileStem>.lua`, the registration. A trailer run calls `registerTrailer("<feature movie id>", {` instead and has no name or genre lines:

```lua
require "JimsMovies/JimsMoviesAPI"

-- <frames> frames @ <fps> = <length> seconds
JimsMovies.registerMovie("<movie id>", {
    videoPrefix = "<fileBase>_",          -- or: video = "<fileBase>.bk2",
    videoCount = <count>,
    videoChunkSeconds = 60,
    width = <W>,
    height = <H>,
    seconds = <seconds>,
    soundPrefix = "<movie id>_",           -- or: sound = "<movie id>",  (or no sound line at all)
    soundCount = <audio chunks>,
    audioChunkSeconds = 10,
    audioChunkOverlap = 0.3,
    name = "IGUI_JimsMovies<Id>_Name",
    genre = "<genre>",                      -- only when one was picked
})
```

`common/media/scripts/<fileStem>Sounds.txt`, one entry per ogg:

```text
module Base
{
    sound <sound name>
    {
        category = World,
        is3D = false,
        clip
        {
            file = media/sound/<ogg file name>,
            distanceMax = 0,
            volume = 1.0,
        }
    }
}
```

`common/media/lua/shared/Translate/EN/IG_UI.json` (feature only), with the name's `\` and `"` escaped:

```json
{
    "IGUI_JimsMovies<Id>_Name": "<Name>"
}
```

### 8. Trailer (optional)

The script calls itself again on the trailer video with the trailer names from the table above and the same size and chunk settings. It goes through steps 2 to 7 into the same mod folder, minus `mod.info` and the JSON.

### 9. Other audio tracks (Make-JimsAudio.ps1, optional)

For each extra track, it matches the movie's own sound. It reads the sample rate and channels from its first ogg, and the chunk count, chunk length and overlap from the registration. Language codes are uppercase game codes like `EN` or `ES`.

```sh
ffmpeg -i <source> -vn -map 0:a:<track-1> -ac <channels> -ar <rate> [-af volume=...] -c:a pcm_s16le audio.wav
# exactly the same number of chunks as the movie. past the end of a shorter track, chunks are silence:
ffmpeg -ss <start> -t 10.3 -i audio.wav -af apad -c:a libvorbis -q:a 4 -t 10.3 <fileBase>_au_<CODE>_NNN.ogg
ffmpeg -f lavfi -i anullsrc=r=<rate>:cl=stereo -c:a libvorbis -q:a 4 -t 10.3 <fileBase>_au_<CODE>_NNN.ogg
```

Sound names are `<movie id>_au_<CODE>_NNN`. The sound script goes to `common/media/scripts/JimsMovies<Id>Sounds_<CODE>.txt`. The registration goes to `42/media/lua/shared/JimsMovies_<Id>/JimsMovies<Id>_Audio_<CODE>.lua`:

```lua
require "JimsMovies/JimsTheaterAudio"

if not JimsMovies.registerAudioTrack then return end
JimsMovies.registerAudioTrack("<movie id>", "<CODE>", {
    language = "<CODE>",
    label = "<track title>",              -- optional
    soundPrefix = "<movie id>_au_<CODE>_",
    soundCount = <audio chunks>,
})
```

### 10. Caption tracks (Make-JimsCaptions.ps1, optional)

See-through binks drawn over the movie, one per movie chunk, with the same frame counts. First the track is converted to `captions.ass`, the same way as step 1, with the same style override for plain subtitles. Then, for each movie chunk, it draws the subtitles on black and on white. The difference between the two gives the alpha.

```sh
cd <work>
ffmpeg -f lavfi -i color=c=black:s=WxH:r=30 -f lavfi -i color=c=white:s=WxH:r=30 -filter_complex \
 "[0:v]format=rgb24,setpts=PTS+<chunk start seconds>/TB,subtitles=captions.ass,split[color][onBlack];
  [1:v]format=rgb24,setpts=PTS+<chunk start seconds>/TB,subtitles=captions.ass[onWhite];
  [onBlack][onWhite]blend=all_mode=difference,format=gray,negate[alpha];
  [color][alpha]alphamerge,format=rgba,setpts=PTS-STARTPTS" \
 -fps_mode passthrough -frames:v <that chunk's bink frame count> frames/f%06d.png
```

- The chunk's frame count comes from the movie bink's header.
- The `setpts` back to 0 and `-fps_mode passthrough` matter. Without them ffmpeg pads the start of the chunk with copies of its first frame.
- Set pixel (0,0) of the first PNG to RGBA (0,0,0,1). RAD drops the alpha plane when it never changes, which a chunk with no captions would do.
- Write the PNG paths, one per line (CRLF, ASCII), to `frames.lst` and give RAD the list instead of a video:

```sh
radvideo64.exe bink2c frames.lst <fileBase>_cc_<CODE>_NNN.bk2 /Z1000 /F30 /L-1 /O /#
```

`/Z1000` keeps the alpha plane and `/F30` sets 30 fps. Under Wine, the paths inside `frames.lst` need to be Windows-style too. Then check the header: the frame count matches the movie chunk, the alpha flag is set, and the size matches. The registration goes to `JimsMovies<Id>_Captions_<CODE>.lua`:

```lua
require "JimsMovies/JimsTheaterCaptions"

if not JimsMovies.registerCaptionVideos then return end
JimsMovies.registerCaptionVideos("<movie id>", "<CODE>", {
    language = "<CODE>",
    label = "<track title>",              -- optional
    videoPrefix = "<fileBase>_cc_<CODE>_",  -- or: video = "<fileBase>_cc_<CODE>.bk2",
    videoCount = <count>,
})
```

## The calls, straight from the scripts

The exact PowerShell lines that run ffmpeg, ffprobe and RAD, copied out of the scripts with their line numbers. `@(...)` is an argument array, `$work` is the temp work folder and `$culture` keeps decimals as dots.

### `Make-JimsMovie.ps1`

The ffmpeg and RAD helpers. Every call below goes through these. ffmpeg always gets -hide_banner -loglevel error -y (lines 116-136):

```powershell
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
```

Start-Rad, the same RAD command without waiting, for -BinkJobs (lines 138-148):

```powershell
# same as Invoke-Rad but doesn't wait, so a few can run at once. WScript can't hand back the process,
# so this goes through Win32_Process which still takes window style 7 and leaves your focus alone
function Start-Rad($source, $target) {
    $startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]7 }
    $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine = "`"$Rad`" bink2c `"$source`" `"$target`" /L-1 /O /#"
        ProcessStartupInformation = $startup
    }
    if ($result.ReturnValue -ne 0) { throw "Couldn't start RAD Video Tools (Win32_Process error $($result.ReturnValue))" }
    return [int]$result.ProcessId
}
```

Step 1: subtitles to burn in, pulled out as burn.ass (lines 664-678):

```powershell
        # ffmpeg's filter options choke on windows paths, so they go into the work folder as burn.ass and get used by name
        $burnArguments = @("-i", $BurnSubtitles, "-map", "0:s:$($BurnTrack - 1)", "-c:s", "ass", (Join-Path $work "burn.ass"))
        # old subtitle files that aren't utf8 fail, those are nearly always CP1252
        try { Invoke-FfmpegQuiet $burnArguments }
        catch {
            Write-Host "  not utf8, trying CP1252" -ForegroundColor Yellow
            Invoke-FfmpegQuiet (@("-sub_charenc", "CP1252") + $burnArguments)
        }
        $burnCodec = (& $Ffprobe -v error -select_streams "s:$($BurnTrack - 1)" -show_entries stream=codec_name -of csv=p=0 $BurnSubtitles | Select-Object -First 1)
        $styles = @()
        if ($BurnFont) { $styles += "FontName=$($BurnFont -replace "[',]", '')" }
        # plain subtitles come out tiny and thin on a low res screen, .ass ones were styled on purpose so they're left alone
        if ($burnCodec -notin @("ass", "ssa")) { $styles += @("FontSize=$BURN_FONT_SIZE", "Outline=$BURN_OUTLINE", "Shadow=0") }
        $burnFilter = ",subtitles=burn.ass"
        if ($styles.Count -gt 0) { $burnFilter += ":force_style='$($styles -join ',')'" }
```

Step 2: the silent working video, run from the work folder so burn.ass works by name (lines 682-689):

```powershell
    Write-Step "Video: ${Width}x$Height at $FPS fps"
    $silent = Join-Path $work "video.mp4"
    # subtitles go on after the pad so they're sized to the finished picture and can sit down in the black bars
    $filter = "fps=$FPS,scale=${Width}:${Height}:force_original_aspect_ratio=decrease,pad=${Width}:${Height}:(ow-iw)/2:(oh-ih)/2,setsar=1$burnFilter,format=yuv420p"
    # chapters would come along as a data track and rad goes by the longest track
    Push-Location -LiteralPath $work
    try { Invoke-Ffmpeg @("-i", $Video, "-an", "-sn", "-dn", "-map_chapters", "-1", "-vf", $filter, "-c:v", "libx264", "-crf", "16", "-preset", "fast", $silent) }
    finally { Pop-Location }
```

Step 3: count frames and chunks (lines 695-700):

```powershell
    $videoChunkCount = 0
    $videoChunkFrames = $VideoChunkSeconds * $FPS
    if ($VideoChunkSeconds -gt 0) {
        $frames = [int](& $Ffprobe -v error -count_packets -select_streams v:0 -show_entries stream=nb_read_packets -of csv=p=0 $silent)
        if ($frames -gt $videoChunkFrames) { $videoChunkCount = [int][math]::Ceiling($frames / $videoChunkFrames) }
    }
```

Step 4: cut each chunk and compress it, one RAD at a time or several with -BinkJobs (lines 716-745):

```powershell
        for ($i = 1; $i -le $videoChunkCount; $i++) {
            $videoChunkStart = ($i - 1) * $videoChunkFrames
            # runs a little long so the next video chunk can take over while this one is still showing
            $videoChunkLength = [math]::Min($videoChunkFrames + $VIDEO_CHUNK_EXTRA_FRAMES, $frames - $videoChunkStart)
            $videoChunkBink = Join-Path $videoDir ("${fileBase}_" + $i.ToString("000") + ".bk2")
            $job = @{ Index = $i; Bink = $videoChunkBink; Length = $videoChunkLength; Mp4 = $null }

            if ($ReuseBinks) {
                $existing = Get-BinkInfo $videoChunkBink
                if ($existing -and (Test-VideoChunkFrames $i $existing.Frames $videoChunkLength)) {
                    Complete-VideoChunk $job $true
                    continue
                }
            }

            $job.Mp4 = Join-Path $work ("video_chunk_" + $i.ToString("000") + ".mp4")
            Invoke-FfmpegQuiet @("-ss", ($videoChunkStart / $FPS).ToString($culture), "-i", $silent, "-frames:v", "$videoChunkLength", "-an", "-sn", "-dn", "-map_chapters", "-1", "-c:v", "libx264", "-crf", "16", "-preset", "fast", $job.Mp4)
            if ($BinkJobs -le 1) {
                Invoke-Rad $job.Mp4 $videoChunkBink
                Complete-VideoChunk $job
                continue
            }
            # the next one gets cut while the others compress, then waits for a free spot
            Wait-RadJobs $BinkJobs
            $job.ProcessId = Start-Rad $job.Mp4 $videoChunkBink
            [void]$radJobs.Add($job)
        }
        Wait-RadJobs 1
        # the last video chunk can come up a frame short, go by what's really there
        $frames = ($videoChunkCount - 1) * $videoChunkFrames + $lastChunkFrames
```

Step 4: one bink for the whole movie instead (lines 748-754):

```powershell
        $binkInfo = if ($ReuseBinks) { Get-BinkInfo $bk2 } else { $null }
        if ($binkInfo) { Write-Host "  the bink was already done" -ForegroundColor DarkGray }
        else {
            Invoke-Rad $silent $bk2
            $binkInfo = Read-BinkHeader $bk2
        }
        $frames = $binkInfo.Frames
```

Step 5: the audio settings both audio paths use (lines 778-783):

```powershell
        $audioArgs = @()
        if ($AudioTrack -gt 0) { $audioArgs += @("-map", "0:a:$($AudioTrack - 1)") }
        $audioArgs += if ($Mono) { @("-ac", "1") } else { @("-ac", "2") }
        if ($SampleRate -gt 0) { $audioArgs += @("-ar", "$SampleRate") }
        if ($AudioGain -ne 0) { $audioArgs += @("-af", "volume=$($AudioGain.ToString([System.Globalization.CultureInfo]::InvariantCulture))dB") }
        $encode = @("-c:a", "libvorbis", "-q:a", "$AudioQuality")
```

Step 5: rip a wav, then cut it into ogg chunks (or one ogg) (lines 790-812):

```powershell
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
```

Step 6: screen glow colors, handed to Make-MovieColors.ps1 (lines 824-826):

```powershell
    Write-Step "Colors: $ColorFps a second"
    $colors = Join-Path $luaDir "${fileStem}_Colors.lua"
    & (Join-Path $PSScriptRoot "Make-MovieColors.ps1") -Video $Video -MovieId $movieId -Out $colors -Fps $ColorFps -Ffmpeg $Ffmpeg
```

### `Make-MovieColors.ps1`

Step 6: one row of 4 averaged pixels per frame, as raw RGB bytes (lines 24-27):

```powershell
$raw = [System.IO.Path]::GetTempFileName()
try {
    # a row of averaged pixels per sample, raw rgb bytes
    & $Ffmpeg -hide_banner -loglevel error -y -i $Video -an -vf "fps=$Fps,scale=${Slices}:1:flags=area" -f rawvideo -pix_fmt rgb24 $raw
```

### `Make-JimsAudio.ps1`

Step 9: other audio tracks, cut to the same chunk count as the movie (lines 186-218):

```powershell
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
```

### `Make-JimsCaptions.ps1`

Step 10: this script's own ffmpeg and RAD helpers. RAD gets /Z1000 /F30 for the alpha plane (lines 64-74):

```powershell
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
```

Step 10: the one see-through pixel so RAD keeps the alpha plane (lines 96-104):

```powershell
# RAD drops the alpha plane when it never changes, which a chunk with no captions in it would do
function Add-AlphaMarker($pngPath) {
    $image = [System.Drawing.Image]::FromFile($pngPath)
    $bitmap = New-Object System.Drawing.Bitmap($image)
    $image.Dispose()
    $bitmap.SetPixel(0, 0, [System.Drawing.Color]::FromArgb(1, 0, 0, 0))
    $bitmap.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
}
```

Step 10: the subtitle track pulled out as captions.ass, with the style override (lines 262-279):

```powershell
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
```

Step 10: draw on black and white per movie chunk, list the PNGs, compress the list (lines 296-324):

```powershell
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
```

## Not covered here

The `-Ask` questions, finding a trailer next to the movie, the window and the memory estimates are all interface. Picture-based subtitles (DVD and Blu-ray) are refused because libass only draws text. The reference is the scripts themselves, along with `readme.md` for every flag.
