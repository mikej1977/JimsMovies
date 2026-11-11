# JimsMovies
Jim's Movies for Project Zomboid 42.22+

# Jim's Movie Maker

**The Movie Maker tools were barfed out by Gemmy and are provided as a courtesy. If you aren't comfortable reading or running random power shell scripts you found on the internet, then don't run it.**

Turns an mp4 (or anything ffmpeg can read) into a complete movie add-on for Jim's Movie Theater.

## What you need

**These tools were made for Windows since RAD Video Tools is a Windows only program**

- [Download the zip file and unzip it somewhere](https://github.com/mikej1977/JimsMovies/releases/latest/download/JimsMovieMaker.zip)
- **ffmpeg** On your PATH, or point the tool at it. If you need to install ffmpeg, you can open a command prompt and type `winget install -e --id Gyan.FFmpeg` 
- **RAD Video Tools** for Windows, free from https://www.radgametools.com/bnkdown.htm. It's the only thing that encodes Bink 2. The tool looks on PATH, then `Program Files (x86)\RADVideo` and `Program Files\RADVideo`, and asks you where it is if it can't find it.
- Windows only.

## Three ways to run it

### 1. Drag and drop (easiest)

Put `<name>.mp4` in a folder, and `<name>-trailer.mp4` next to it if you have one (`<name>-trailer` and `movie-trailer` both get picked up). Drag the movie onto `Make-JimsMovie.bat`. It asks for the name, genre, size, audio and audio boosts, and makes the add-on in that folder.

- **Forgot the trailer?** Drag the trailer onto the bat by itself. It offers to add it to the `JimsMovies_<Id>` add-on in that folder, matches that add-on's size and audio, and asks before replacing a trailer that's already there.
- Anything after the video goes straight to the script:

  ```
  Make-JimsMovie.bat "D:\movies\nosferatu.mp4" -Genre horror -ModsDir "D:\mods"
  ```

### 2. The window

Double-click `Make-JimsMovie-Window.bat`. Pick the movie and a trailer if you want one, then the name, genre, size, stereo or mono, audio quality, audio boosts and output folder, and hit **Make Movie**. The build runs in its own console so you can watch ffmpeg and RAD. Close that console when it's done. The window remembers your last folder and where ffmpeg and RAD are, in `%APPDATA%\JimsMovieMaker`.

### 3. Command line

```
powershell -NoProfile -ExecutionPolicy Bypass -File Make-JimsMovie.ps1 -Video "D:\movies\nosferatu.mp4" -Name "Nosferatu"
```

## What it does

1. ffmpeg makes a silent 30 fps video at your size, with black bars if the shape doesn't fit
2. RAD compresses it to Bink chunks, 60 seconds each by default, so people who show up late can join at the next one
3. ffmpeg rips the audio out to 10 second ogg chunks
4. Make-MovieColors makes the screen glow colors
5. it all gets laid out as a mod called `JimsMovies_<Id>` with `42/mod.info`, the registration lua, `_Colors.lua`, sound scripts, oggs, bk2s and the name translations

Enable the add-on along with Jim's Movie Theater. Keep it in your local `Zomboid\mods`, not on the workshop. You are responsible for making sure you abide by the laws in your country in regards to copyright, public domain, etc. 

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
| `-Mono` | stereo | Mono audio |
| `-SampleRate` | 0 (keep the source's) | Audio sample rate, 22050 or 44100 say |
| `-SmallAudio` | off | Mono at 22050, about a quarter of the memory. The game decodes the whole ogg into memory when it plays, so a 2 hour stereo movie is ~2.6 GB of RAM and a long freeze at Start Movie |
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
