# JimsMovies
Jim's Movies for Project Zomboid 42.22+

# Jim's Movie Maker

**The Movie Maker tools were barfed out by Gemmy and are provided as a courtesy. If you aren't comfortable reading or running random power shell scripts you found on the internet, then don't run it.**

Turns an mp4 (or anything ffmpeg can read) into a complete movie add-on for Jim's Movie Theater.

## What you need

**These tools were made for Windows since RAD Video Tools is a Windows only program**

- [Download the Jim's Movie Maker Tools zip file and unzip it somewhere](https://github.com/mikej1977/JimsMovies/releases/latest/download/JimsMovieMaker.zip)
- **ffmpeg** On your PATH, or point the tool at it. If you need to install ffmpeg, you can open a command prompt and type `winget install -e --id Gyan.FFmpeg` 
- **RAD Video Tools** for Windows, free from https://www.radgametools.com/bnkdown.htm. It's the only thing that encodes Bink 2. The tool looks on PATH, then `Program Files (x86)\RADVideo` and `Program Files\RADVideo`, and asks you where it is if it can't find it.
- Windows only.

## Three ways to run it

### 1. Drag and drop (easiest)

Put `<name>.mp4` in a folder, and `<name>-trailer.mp4` next to it if you have one (`<name>-trailer` and `movie-trailer` both get picked up). Drag the movie onto `Make-JimsMovie.bat`. It asks for the name, genre, size, audio track if there's more than one and which other tracks players can switch to (type the numbers, like 2,3), audio and audio boosts, and subtitles if it finds some in the movie or a `<name>.srt` (or `.ass`, `.ssa`, `.vtt`) next to it, and makes the add-on in that folder. Subtitles can be burned into the video, which can't be turned off, or made into caption tracks players turn on from **Captions** in the movie window, as many as you want (type the numbers, like 1,2). Any language works either way.

Movies should be in .mp4 .mkv .mov .avi .webm or .m4v formats

- **Forgot the trailer?** Drag the trailer onto the bat by itself. It offers to add it to the `JimsMovies_<Id>` add-on in that folder, matches that add-on's size and audio, and asks before replacing a trailer that's already there.
- Anything after the video goes straight to the script:

  ```
  Make-JimsMovie.bat "D:\movies\nosferatu.mp4" -Genre horror -ModsDir "D:\mods"
  ```

### 2. The window

Double-click `Make-JimsMovie-Window.bat`. Pick the movie and a trailer if you want one, then the name, genre, size, stereo or mono, audio quality, audio boosts, audio track, which other audio tracks players can switch to (check as many as you want), subtitles (one burned in, or check as many caption tracks as you want) and output folder, and hit **Make Movie**. The build runs in its own console so you can watch ffmpeg and RAD. Close that console when it's done. The window remembers your last folder and where ffmpeg and RAD are, in `%APPDATA%\JimsMovieMaker`.

### 3. Command line

```
powershell -NoProfile -ExecutionPolicy Bypass -File Make-JimsMovie.ps1 -Video "D:\movies\nosferatu.mp4" -Name "Nosferatu"
```

## What it does

1. ffmpeg makes a silent 30 fps video at your size, with black bars if the shape doesn't fit, and burns in subtitles if you picked that
2. RAD compresses it to Bink chunks, 60 seconds each by default, so people who show up late can join at the next one
3. ffmpeg rips the audio out to 10 second ogg chunks
4. Make-MovieColors makes the screen glow colors
5. it all gets laid out as a mod called `JimsMovies_<Id>` with `42/mod.info`, the registration lua, `_Colors.lua`, sound scripts, oggs, bk2s and the name translations
6. if you picked other audio tracks, Make-JimsAudio cuts each one into the same audio chunks as the movie's own sound
7. if you picked caption tracks, Make-JimsCaptions makes see-through caption videos for each one, matched to the movie's chunks. This takes roughly half the movie's length for each track

Enable the add-on along with Jim's Movie Theater. Keep it in your local `Zomboid\mods`, not on the workshop. You are responsible for making sure you abide by the laws in your country in regards to copyright, public domain, etc. 

The add-on doesn't come with a poster or a workshop preview. Add your own if you want them, `preview.png` in this folder is there if you want to use it.

## Make-JimsMovie.ps1 flags

| Flag | Default | What it does |
|---|---|---|
| `-Video` | | The movie file, or the trailer file with `-Trailer` |
| `-Ask` | off | Asks about anything you didn't pass and finds the trailer next to the movie. The mod goes next to the video unless you pass `-ModsDir`. It defaults to **240p** and **44100 Hz** |
| `-Name` | | Name shown in game |
| `-Id` | the squished name | Code name for files and ids, letters and numbers only |
| `-ModsDir` | `%USERPROFILE%\Zomboid\mods` | Where the add-on folder goes |
| `-Genre` | default mix | Moodle rewards: `action`, `comedy`, `drama`, `horror`, `scifi` |
| `-Trailer` | off | Makes `-Video` the trailer for an add-on you already made. Needs `-Id`, can't be used with `-Ask` |
| `-TrailerFile` | | A trailer to make along with the movie without `-Ask` |
| `-BurnSubtitles` | | Subtitles to burn into the picture, an `.srt`, `.ass`, `.ssa` or `.vtt`, or a video with subtitle tracks. It can be the movie itself. Works for any language, Chinese, Japanese, Russian, Arabic and so on, but they can't be turned off in game. Picture subtitles (Blu-ray PGS, DVD VobSub) don't work, turn them into an `.srt` with Subtitle Edit's OCR first |
| `-BurnTrack` | | Which subtitle track to burn in when there's more than one, 1 is the first |
| `-BurnFont` | Arial, or the `.ass` file's own | Font for burned in subtitles and caption tracks, like `"Yu Gothic"`. Letters a font doesn't have get drawn with one that does |
| `-Captions` | | Subtitles to make caption tracks from, same kinds of files as `-BurnSubtitles`. Players turn them on in the movie window. Make-JimsCaptions.ps1 does the work once the movie's done |
| `-CaptionTrack` | | Which subtitle track when there's more than one, 1 is the first |
| `-CaptionLanguage` | the track's language or EN | Game language code for the caption track, EN, ES, RU and so on |
| `-AllCaptions` | off | A caption track for every language in the `-Captions` file instead of one `-CaptionTrack` |
| `-CaptionPicks` | | Caption tracks from one file or more, `track*file` joined by `\|`, like `"1*D:\a.mkv\|2*D:\a.mkv\|1*D:\a.srt"`. The window passes this. A second track in the same language, like Signs & Songs, gets its own entry named after the track |
| `-Mono` | stereo | Mono audio |
| `-SampleRate` | 0 (keep the source's) | Audio sample rate, 22050 or 44100 say |
| `-SmallAudio` | off | Mono at 22050, about a quarter of the memory. The game decodes the whole ogg into memory when it plays, so a 2 hour stereo movie is ~2.6 GB of RAM and a long freeze at Start Movie |
| `-AudioTrack` | ffmpeg picks | Which audio track when the movie has more than one, 1 is the first |
| `-ExtraAudioTrack` | | Another audio track players can switch to from **Audio** in the movie window, another language say. Make-JimsAudio.ps1 does the work once the movie's done |
| `-ExtraAudioLanguage` | the track's language | Game language code for that track, EN, ES, JP and so on |
| `-AllAudio` | off | Every other audio track that says its language becomes one players can switch to, instead of one `-ExtraAudioTrack` |
| `-AudioTracks` | | The audio tracks players can switch to, like `"2,3,5"`. Same language tracks each get their own entry named after the track |
| `-AudioGain` | 0 | Makes the movie louder in dB, 18 say. Negative turns it down |
| `-TrailerAudioGain` | 0 | Same thing for the trailer |
| `-AudioChunkSeconds` | 10 | How long each audio chunk is. 0 makes one ogg for the whole movie |
| `-AudioChunkOverlap` | 0.3 | Seconds each audio chunk runs past its end so the mod can crossfade to the next |
| `-VideoChunkSeconds` | 60 | How long each bink chunk is. 0 makes one bk2, so nobody can join late |
| `-Width` | 1280 | Has to be a multiple of 16 or the picture skews in game |
| `-Height` | 720 | Even numbers only |
| `-ColorFps` | 30 | Glow color samples a second |
| `-AudioQuality` | 4 | libvorbis quality, 0 to 10 |
| `-Rad` | found on its own | Full path to `radvideo64.exe` |
| `-Ffmpeg` | `ffmpeg` | Path to ffmpeg |
| `-Ffprobe` | `ffprobe` | Path to ffprobe |
| `-PartOfMovie` | | Used by the script when it makes the trailer, don't pass it yourself |

Sizes the window and `-Ask` offer: 144p 256x144, **240p 432x240**, 360p 640x360, 480p 848x480, 540p 960x540, 720p 1280x720, 1080p 1920x1080.

## Make-JimsCaptions.ps1 flags

Makes caption tracks for an add-on you already made. They're see-through videos the same size and chunks as the movie, drawn over it for players who pick them from **Captions** in the movie window. Turning them on waits for the movie's next chunk, since a video can't skip ahead. They take roughly half the movie's length to make for each language.

```
.\Make-JimsCaptions.ps1 -Subtitles "D:\movies\nosferatu.mkv" -Id "Nosferatu" -AllTracks
```

| Flag | Default | What it does |
|---|---|---|
| `-Subtitles` | required | The subtitle file, or a video with subtitle tracks |
| `-Id` | required | The add-on's code name, the part after `JimsMovies_` |
| `-Track` | | Which subtitle track when there's more than one, 1 is the first |
| `-Picks` | | Several tracks at once from one file or more, instead of `-Subtitles`: `track*file` joined by `\|` |
| `-AllTracks` | off | A caption track for every text track that says its language. Same language ones each get their own entry, EN then EN2, named after the track |
| `-Language` | the track's language or EN | Game language code, EN, ES, RU and so on |
| `-Label` | the track's title | A name for `-Track` in the game's menu, like Signs & Songs |
| `-Replace` | off | Clears out the add-on's other caption tracks first. The movie maker uses it when it makes the movie again |
| `-Offset` | 0 | Seconds to shift every caption, negative shows them sooner |
| `-Charset` | utf8, then CP1252 | Text encoding for old subtitle files |
| `-Font` | Arial, or the `.ass` file's own | Font for plain subtitles |
| `-ModsDir` | `%USERPROFILE%\Zomboid\mods` | Where the add-on is |
| `-Rad` | found on its own | Full path to `radvideo64.exe` |
| `-Ffmpeg` | `ffmpeg` | Path to ffmpeg |
| `-Ffprobe` | `ffprobe` | Path to ffprobe |

## Make-JimsAudio.ps1 flags

Adds audio tracks players can switch to, other languages or a commentary say, to an add-on you already made. They're cut into the same audio chunks as the movie's own sound, at its sample rate and channels, and players pick them from **Audio** in the movie window. The switch happens at the next audio chunk, within 10 seconds by default.

```
.\Make-JimsAudio.ps1 -Source "D:\movies\akira.mkv" -Id "Akira" -Tracks "2,3"
```

| Flag | Default | What it does |
|---|---|---|
| `-Source` | required | The video or audio file with the tracks, usually the movie itself |
| `-Id` | required | The add-on's code name, the part after `JimsMovies_` |
| `-Track` | | Which audio track, 1 is the first |
| `-Tracks` | | Several tracks at once, like `"2,3,5"`. Same language ones each get their own entry, EN then EN2, named after the track |
| `-AllTracks` | off | Every audio track that says its language instead of `-Track` or `-Tracks` |
| `-SkipTrack` | | A track to leave out, the one the movie already plays |
| `-Language` | the track's language | Game language code for `-Track`, EN, ES, JP and so on |
| `-Label` | the track's title | A name for `-Track` in the game's menu, like Commentary |
| `-Replace` | off | Clears out the add-on's other audio tracks first. The movie maker uses it when it makes the movie again |
| `-AudioGain` | 0 | Makes it louder in dB, negative turns it down |
| `-AudioQuality` | 4 | libvorbis quality, 0 to 10 |
| `-ModsDir` | `%USERPROFILE%\Zomboid\mods` | Where the add-on is |
| `-Ffmpeg` | `ffmpeg` | Path to ffmpeg |
| `-Ffprobe` | `ffprobe` | Path to ffprobe |

## Make-MovieColors.ps1 flags

The movie maker already runs this. You only need it by hand to redo the colors.

```
.\Make-MovieColors.ps1 -Video "D:\movies\5element.mp4" -MovieId "JimsMovies_5Element" -Out "...\JimsMovies5Element_Colors.lua"
```

| Flag | Default | What it does |
|---|---|---|
| `-Video` | required | The same source video the bk2 was made from |
| `-MovieId` | required | Like `JimsMovies_5Element` |
| `-Out` | required | The lua it writes, goes in the mod's `42/media/lua/shared` |
| `-Fps` | 30 | Color samples a second |
| `-Slices` | 4 | Color bands across the screen |
| `-Ffmpeg` | `ffmpeg` | Path to ffmpeg |
