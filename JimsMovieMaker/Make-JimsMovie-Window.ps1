<#
    powershell -NoProfile -ExecutionPolicy Bypass -File Make-JimsMovie-Window.ps1
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$VIDEO_FILTER = "Videos (*.mp4;*.mkv;*.mov;*.avi;*.webm;*.m4v)|*.mp4;*.mkv;*.mov;*.avi;*.webm;*.m4v|All files (*.*)|*.*"
$SIZES = @(
    @{ Text = "144p"; Width = 256; Height = 144 },
    @{ Text = "240p"; Width = 432; Height = 240 },
    @{ Text = "360p"; Width = 640; Height = 360 },
    @{ Text = "480p"; Width = 848; Height = 480 },
    @{ Text = "540p"; Width = 960; Height = 540 },
    @{ Text = "720p"; Width = 1280; Height = 720 },
    @{ Text = "1080p"; Width = 1920; Height = 1080 }
)
$GENRES = @("None", "Action", "Comedy", "Drama", "Horror", "Sci-fi")
$RATES = @(11025, 22050, 44100, 48000)
$DEFAULT_SIZE = "240p"
$DEFAULT_RATE = 44100

# the last folder a video was picked from, so the next movie opens there
$settingsDir = Join-Path $env:APPDATA "JimsMovieMaker"
$lastFolderFile = Join-Path $settingsDir "last-folder.txt"
$lastFolder = $null
if (Test-Path -LiteralPath $lastFolderFile) {
    $saved = (Get-Content -LiteralPath $lastFolderFile -Raw).Trim()
    if ($saved -and (Test-Path -LiteralPath $saved)) { $lastFolder = $saved }
}

function Save-LastFolder($path) {
    $script:lastFolder = Split-Path -Parent $path
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    Set-Content -LiteralPath $lastFolderFile -Value $script:lastFolder -Encoding UTF8
}

$makerScript = Join-Path $PSScriptRoot "Make-JimsMovie.ps1"
$captionsScript = Join-Path $PSScriptRoot "Make-JimsCaptions.ps1"
$radPathFile = Join-Path $settingsDir "rad-path.txt"
$ffmpegPathFile = Join-Path $settingsDir "ffmpeg-path.txt"

function Read-SavedPath($file) {
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $saved = (Get-Content -LiteralPath $file -Raw).Trim()
    if ($saved -and (Test-Path -LiteralPath $saved)) { return $saved }
    return $null
}

function Save-Path($file, $path) {
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    Set-Content -LiteralPath $file -Value $path -Encoding UTF8
}

function Find-Rad {
    $saved = Read-SavedPath $radPathFile
    if ($saved) { return $saved }
    $onPath = Get-Command "radvideo64.exe" -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    foreach ($programFiles in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (-not $programFiles) { continue }
        $path = Join-Path $programFiles "RADVideo\radvideo64.exe"
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

function Find-Ffmpeg {
    $saved = Read-SavedPath $ffmpegPathFile
    if ($saved) { return $saved }
    $onPath = Get-Command "ffmpeg" -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    return $null
}

# returns the picked path, or nothing if they cancel
function Ask-ForExe($why, $exeName, $file) {
    [void][System.Windows.Forms.MessageBox]::Show($form, $why, "Jim's Movie Maker", "OK", "Information")
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Where's $exeName?"
    $dialog.Filter = "$exeName|$exeName"
    if ($dialog.ShowDialog($form) -ne "OK") { return $null }
    Save-Path $file $dialog.FileName
    return $dialog.FileName
}

# for the command line: quotes around it, and a path ending in \ would eat the closing quote
function Format-Argument($value) {
    $value = [string]$value
    if ($value.EndsWith("\")) { $value += "." }
    return '"' + ($value -replace '"', '\"') + '"'
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Jim's Movie Maker"
$form.ClientSize = New-Object System.Drawing.Size(560, 594)
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

function Add-Label($text, $x, $y, $width = 110, $parent = $form) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point($x, ($y + 4))
    $label.Size = New-Object System.Drawing.Size($width, 20)
    $parent.Controls.Add($label)
    return $label
}

function Add-TextBox($x, $y, $width, $parent = $form) {
    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point($x, $y)
    $box.Size = New-Object System.Drawing.Size($width, 24)
    $parent.Controls.Add($box)
    return $box
}

function Add-Button($text, $x, $y, $width = 80, $parent = $form) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $text
    $button.Location = New-Object System.Drawing.Point($x, ($y - 1))
    $button.Size = New-Object System.Drawing.Size($width, 26)
    $parent.Controls.Add($button)
    return $button
}

function Find-Video($folder, $baseName) {
    foreach ($extension in @(".mp4", ".mkv", ".mov", ".avi", ".webm", ".m4v")) {
        $path = Join-Path $folder "$baseName$extension"
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

# files
Add-Label "Movie" 16 16 | Out-Null
$movieBox = Add-TextBox 130 16 320
$movieBrowse = Add-Button "Browse..." 460 16

$trailerCheck = New-Object System.Windows.Forms.CheckBox
$trailerCheck.Text = "Trailer"
$trailerCheck.Location = New-Object System.Drawing.Point(16, 50)
$trailerCheck.Size = New-Object System.Drawing.Size(110, 24)
$form.Controls.Add($trailerCheck)
$trailerBox = Add-TextBox 130 50 320
$trailerBrowse = Add-Button "Browse..." 460 50
$trailerNote = Add-Label "" 130 74 400
$trailerNote.ForeColor = [System.Drawing.Color]::DimGray

Add-Label "Movie name" 16 104 | Out-Null
$nameBox = Add-TextBox 130 104 320

Add-Label "Genre" 16 138 | Out-Null
$genreBox = New-Object System.Windows.Forms.ComboBox
$genreBox.DropDownStyle = "DropDownList"
$genreBox.Location = New-Object System.Drawing.Point(130, 138)
$genreBox.Size = New-Object System.Drawing.Size(150, 24)
$genreBox.Items.AddRange($GENRES)
$genreBox.SelectedIndex = 0
$form.Controls.Add($genreBox)

# picture size, one radio button per size
$sizeGroup = New-Object System.Windows.Forms.GroupBox
$sizeGroup.Text = "Movie size"
$sizeGroup.Location = New-Object System.Drawing.Point(16, 176)
$sizeGroup.Size = New-Object System.Drawing.Size(250, 210)
$form.Controls.Add($sizeGroup)
$sizeButtons = @()
for ($i = 0; $i -lt $SIZES.Count; $i++) {
    $size = $SIZES[$i]
    $radio = New-Object System.Windows.Forms.RadioButton
    $radio.Text = "$($size.Text)  ($($size.Width)x$($size.Height))"
    if ($size.Text -eq $DEFAULT_SIZE) { $radio.Text += "  default" }
    $radio.Location = New-Object System.Drawing.Point(14, (24 + $i * 25))
    $radio.Size = New-Object System.Drawing.Size(220, 22)
    $radio.Checked = $size.Text -eq $DEFAULT_SIZE
    $sizeGroup.Controls.Add($radio)
    $sizeButtons += $radio
}

# sound
$soundGroup = New-Object System.Windows.Forms.GroupBox
$soundGroup.Text = "Sound"
$soundGroup.Location = New-Object System.Drawing.Point(284, 176)
$soundGroup.Size = New-Object System.Drawing.Size(260, 210)
$form.Controls.Add($soundGroup)

$stereoRadio = New-Object System.Windows.Forms.RadioButton
$stereoRadio.Text = "Stereo"
$stereoRadio.Location = New-Object System.Drawing.Point(14, 24)
$stereoRadio.Checked = $true
$soundGroup.Controls.Add($stereoRadio)
$monoRadio = New-Object System.Windows.Forms.RadioButton
$monoRadio.Text = "Mono"
$monoRadio.Location = New-Object System.Drawing.Point(130, 24)
$soundGroup.Controls.Add($monoRadio)

$rateLabel = New-Object System.Windows.Forms.Label
$rateLabel.Text = "Quality"
$rateLabel.Location = New-Object System.Drawing.Point(14, 62)
$rateLabel.Size = New-Object System.Drawing.Size(90, 20)
$soundGroup.Controls.Add($rateLabel)
$rateBox = New-Object System.Windows.Forms.ComboBox
$rateBox.DropDownStyle = "DropDownList"
$rateBox.Location = New-Object System.Drawing.Point(110, 58)
$rateBox.Size = New-Object System.Drawing.Size(130, 24)
foreach ($rate in $RATES) {
    $rateText = "$rate Hz"
    if ($rate -eq $DEFAULT_RATE) { $rateText += "  default" }
    [void]$rateBox.Items.Add($rateText)
}
$rateBox.SelectedIndex = [array]::IndexOf($RATES, $DEFAULT_RATE)
$soundGroup.Controls.Add($rateBox)

function New-Boost($text, $y) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point(14, ($y + 4))
    $label.Size = New-Object System.Drawing.Size(90, 20)
    $soundGroup.Controls.Add($label)
    $number = New-Object System.Windows.Forms.NumericUpDown
    $number.Minimum = -20
    $number.Maximum = 30
    $number.Location = New-Object System.Drawing.Point(110, $y)
    $number.Size = New-Object System.Drawing.Size(70, 24)
    $soundGroup.Controls.Add($number)
    $unit = New-Object System.Windows.Forms.Label
    $unit.Text = "dB"
    $unit.Location = New-Object System.Drawing.Point(186, ($y + 4))
    $unit.Size = New-Object System.Drawing.Size(30, 20)
    $soundGroup.Controls.Add($unit)
    return $number
}
$movieBoost = New-Boost "Movie boost" 98
$trailerBoost = New-Boost "Trailer boost" 132

$audioTrackLabel = New-Object System.Windows.Forms.Label
$audioTrackLabel.Text = "Audio track"
$audioTrackLabel.Location = New-Object System.Drawing.Point(14, 170)
$audioTrackLabel.Size = New-Object System.Drawing.Size(90, 20)
$soundGroup.Controls.Add($audioTrackLabel)
$audioTrackBox = New-Object System.Windows.Forms.ComboBox
$audioTrackBox.DropDownStyle = "DropDownList"
$audioTrackBox.Location = New-Object System.Drawing.Point(110, 166)
$audioTrackBox.Size = New-Object System.Drawing.Size(140, 24)
$audioTrackBox.DropDownWidth = 360
$audioTrackBox.Enabled = $false
$soundGroup.Controls.Add($audioTrackBox)

# captions, made from the movie's own subtitles or a subtitle file once the movie's done
$captionsCheck = New-Object System.Windows.Forms.CheckBox
$captionsCheck.Text = "Captions"
$captionsCheck.Location = New-Object System.Drawing.Point(16, 402)
$captionsCheck.Size = New-Object System.Drawing.Size(110, 24)
$form.Controls.Add($captionsCheck)
$captionsBox = New-Object System.Windows.Forms.ComboBox
$captionsBox.DropDownStyle = "DropDownList"
$captionsBox.Location = New-Object System.Drawing.Point(130, 402)
$captionsBox.Size = New-Object System.Drawing.Size(270, 24)
$captionsBox.DropDownWidth = 420
$form.Controls.Add($captionsBox)
Add-Label "Language" 408 402 60 | Out-Null
$captionLanguageBox = Add-TextBox 470 402 74
$captionLanguageBox.CharacterCasing = "Upper"
$captionLanguageBox.Text = "EN"

# where it goes
Add-Label "Make it in" 16 436 | Out-Null
$outputBox = Add-TextBox 130 436 320
$outputBrowse = Add-Button "Browse..." 460 436

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Style = "Marquee"
$progress.MarqueeAnimationSpeed = 0
$progress.Location = New-Object System.Drawing.Point(16, 484)
$progress.Size = New-Object System.Drawing.Size(528, 18)
$form.Controls.Add($progress)
$status = Add-Label "Pick a movie to start" 16 506 528
$status.ForeColor = [System.Drawing.Color]::DimGray

$captionsButton = Add-Button "Add Captions to an Add-on..." 16 550 200
$makeButton = Add-Button "Make Movie" 344 550 110
$closeButton = Add-Button "Close" 464 550 80
$form.AcceptButton = $makeButton
$form.CancelButton = $closeButton

function Update-Trailer {
    $trailerBox.Enabled = $trailerCheck.Checked
    $trailerBrowse.Enabled = $trailerCheck.Checked
    $trailerBoost.Enabled = $trailerCheck.Checked
}

# ffprobe without asking for it, for filling in lists when a movie gets picked
function Find-Ffprobe {
    $ffmpeg = Find-Ffmpeg
    if ($ffmpeg) {
        $beside = Join-Path (Split-Path -Parent $ffmpeg) "ffprobe.exe"
        if (Test-Path -LiteralPath $beside) { return $beside }
    }
    $onPath = Get-Command "ffprobe" -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    return $null
}

# Path, Track, Label, Usable and Language for each subtitle track in a file, labels from Make-JimsCaptions.ps1
function Get-SubtitleChoices($path, $labelStart) {
    $ffmpeg = Find-Ffmpeg
    $ffprobe = Find-Ffprobe
    if (-not $ffmpeg -or -not $ffprobe -or -not (Test-Path -LiteralPath $captionsScript)) { return }
    $count = @(& $ffprobe -v error -select_streams s -show_entries stream=index -of csv=p=0 $path | Where-Object { $_ }).Count
    if ($count -eq 0) { return }
    $ErrorActionPreference = "Continue"
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $captionsScript -Subtitles $path -ListTracks -Ffmpeg $ffmpeg -Ffprobe $ffprobe 2>&1
    if ($LASTEXITCODE -ne 0) { return }
    # powershell 5 hands back the json array as one thing, the ForEach unrolls it
    $tracks = @((@($output | ForEach-Object { "$_" }) -join "") | ConvertFrom-Json | ForEach-Object { $_ })
    for ($i = 0; $i -lt $tracks.Count; $i++) {
        $label = if ($tracks.Count -eq 1 -and $labelStart -ne "From the movie") { $labelStart } else { "${labelStart}: $($tracks[$i].Label)" }
        [pscustomobject]@{ Path = $path; Track = $i + 1; Label = $label; Usable = $tracks[$i].Usable; Language = $tracks[$i].Language }
    }
}

$PICK_SUBTITLE_FILE = "Pick a subtitle file..."
$captionChoices = @()
$lastCaptionIndex = -1

function Update-CaptionsRow {
    $captionsBox.Enabled = $captionsCheck.Checked
    $captionLanguageBox.Enabled = $captionsCheck.Checked
}

function Set-CaptionChoices($choices) {
    $script:captionChoices = @($choices)
    $captionsBox.Items.Clear()
    foreach ($choice in $script:captionChoices) { [void]$captionsBox.Items.Add($choice.Label) }
    [void]$captionsBox.Items.Add($PICK_SUBTITLE_FILE)
}

# the movie's own subtitle tracks, plus subtitle files named like the movie next to it
function Update-CaptionChoices($path) {
    $folder = Split-Path -Parent $path
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($path)
    $choices = @(Get-SubtitleChoices $path "From the movie")
    foreach ($file in Get-ChildItem -LiteralPath $folder -File -Filter "$baseName*" -ErrorAction SilentlyContinue) {
        if (@(".srt", ".ass", ".ssa", ".vtt") -contains $file.Extension.ToLower()) { $choices += @(Get-SubtitleChoices $file.FullName $file.Name) }
    }
    Set-CaptionChoices $choices
    $script:lastCaptionIndex = -1
    if ($choices.Count -gt 0) {
        $captionsBox.SelectedIndex = 0
        $captionsCheck.Checked = $true
    }
    else {
        $captionsCheck.Checked = $false
    }
    Update-CaptionsRow
}

$captionsBox.Add_SelectedIndexChanged({
    $index = $captionsBox.SelectedIndex
    if ($index -lt 0) { return }
    if ($index -lt $captionChoices.Count) {
        $script:lastCaptionIndex = $index
        $captionLanguageBox.Text = $captionChoices[$index].Language
        return
    }
    $picker = New-Object System.Windows.Forms.OpenFileDialog
    $picker.Title = "Pick the subtitles"
    $picker.Filter = "Subtitles and videos (*.srt;*.ass;*.ssa;*.vtt;*.mkv;*.mp4;*.mov;*.webm;*.m4v)|*.srt;*.ass;*.ssa;*.vtt;*.mkv;*.mp4;*.mov;*.webm;*.m4v|All files (*.*)|*.*"
    if ($lastFolder) { $picker.InitialDirectory = $lastFolder }
    $added = @()
    if ($picker.ShowDialog($form) -eq "OK") {
        $added = @(Get-SubtitleChoices $picker.FileName ([System.IO.Path]::GetFileName($picker.FileName)))
        if ($added.Count -eq 0) { Show-Problem "No text subtitles in $([System.IO.Path]::GetFileName($picker.FileName))." }
    }
    if ($added.Count -gt 0) {
        $firstNew = $captionChoices.Count
        Set-CaptionChoices ($captionChoices + $added)
        $captionsBox.SelectedIndex = $firstNew
    }
    else {
        $captionsBox.SelectedIndex = $lastCaptionIndex
    }
})

$captionsCheck.Add_CheckedChanged({ Update-CaptionsRow })

# fills the audio track list, only worth picking when there's more than one
function Update-AudioTracks($path) {
    $audioTrackBox.Items.Clear()
    $audioTrackBox.Enabled = $false
    $ffprobe = Find-Ffprobe
    if (-not $ffprobe) { return }
    $probe = (& $ffprobe -v error -select_streams a -show_entries "stream=channels:stream_tags=language,title" -of json $path) -join "`n" | ConvertFrom-Json
    foreach ($stream in @($probe.streams)) {
        if (-not $stream) { continue }
        $parts = @()
        if ($stream.tags -and $stream.tags.title) { $parts += $stream.tags.title }
        if ($stream.tags -and $stream.tags.language) { $parts += $stream.tags.language }
        $parts += "$($stream.channels) channels"
        [void]$audioTrackBox.Items.Add($parts -join ", ")
    }
    if ($audioTrackBox.Items.Count -gt 0) { $audioTrackBox.SelectedIndex = 0 }
    $audioTrackBox.Enabled = $audioTrackBox.Items.Count -gt 1
}

# same rule as the bat: <name>-trailer next to the movie, or movie-trailer
function Set-Movie($path) {
    $movieBox.Text = $path
    $status.Text = "Looking at the movie..."
    $form.Refresh()
    Update-AudioTracks $path
    Update-CaptionChoices $path
    $folder = Split-Path -Parent $path
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($path)
    if (-not $nameBox.Text) { $nameBox.Text = $baseName }
    if (-not $outputBox.Text) { $outputBox.Text = $folder }
    $trailer = Find-Video $folder "$baseName-trailer"
    if (-not $trailer) { $trailer = Find-Video $folder "movie-trailer" }
    if ($trailer) {
        $trailerBox.Text = $trailer
        $trailerCheck.Checked = $true
        $trailerNote.Text = "Found $([System.IO.Path]::GetFileName($trailer)), it'll be the trailer"
        $trailerNote.ForeColor = [System.Drawing.Color]::DarkGreen
    }
    else {
        $trailerCheck.Checked = $false
        $trailerNote.Text = "No trailer found, it would be named $baseName-trailer"
        $trailerNote.ForeColor = [System.Drawing.Color]::DarkGoldenrod
    }
    $status.Text = "Ready"
    Update-Trailer
}

$movieBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Pick the movie"
    $dialog.Filter = $VIDEO_FILTER
    if ($lastFolder) { $dialog.InitialDirectory = $lastFolder }
    if ($dialog.ShowDialog($form) -eq "OK") {
        Save-LastFolder $dialog.FileName
        Set-Movie $dialog.FileName
    }
})

$trailerBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Pick the trailer"
    $dialog.Filter = $VIDEO_FILTER
    if ($lastFolder) { $dialog.InitialDirectory = $lastFolder }
    if ($dialog.ShowDialog($form) -eq "OK") {
        $trailerBox.Text = $dialog.FileName
        $trailerNote.Text = ""
    }
})

$outputBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Where should the add-on folder go?"
    if ($outputBox.Text) { $dialog.SelectedPath = $outputBox.Text }
    if ($dialog.ShowDialog($form) -eq "OK") { $outputBox.Text = $dialog.SelectedPath }
})

$trailerCheck.Add_CheckedChanged({ Update-Trailer })

# the movie maker runs in its own console so you can watch ffmpeg and RAD, this just waits for it to close
$makeProcess = $null
$watchTimer = New-Object System.Windows.Forms.Timer
$watchTimer.Interval = 500
$watchTimer.Add_Tick({
    if ($makeProcess -and -not $makeProcess.HasExited) { return }
    $watchTimer.Stop()
    $progress.MarqueeAnimationSpeed = 0
    $makeButton.Enabled = $true
    $status.Text = "Ready for the next one"
})

function Show-Problem($text, $owner = $form) {
    [void][System.Windows.Forms.MessageBox]::Show($owner, $text, "Jim's Movie Maker", "OK", "Warning")
}

# returns ffmpeg and ffprobe, or nothing if they can't be found
function Get-FfmpegTools($owner) {
    $ffmpeg = Find-Ffmpeg
    if (-not $ffmpeg) {
        $ffmpeg = Ask-ForExe "Can't find ffmpeg. Get it from https://ffmpeg.org/download.html, then show me where ffmpeg.exe is." "ffmpeg.exe" $ffmpegPathFile
        if (-not $ffmpeg) { return $null }
    }
    $ffprobe = Join-Path (Split-Path -Parent $ffmpeg) "ffprobe.exe"
    if (-not (Test-Path -LiteralPath $ffprobe)) {
        $onPath = Get-Command "ffprobe" -ErrorAction SilentlyContinue
        if (-not $onPath) { Show-Problem "Can't find ffprobe.exe, it comes with ffmpeg and should be in the same folder." $owner; return $null }
        $ffprobe = $onPath.Source
    }
    return @($ffmpeg, $ffprobe)
}

$makeButton.Add_Click({
    $movie = $movieBox.Text.Trim()
    if (-not $movie -or -not (Test-Path -LiteralPath $movie)) { Show-Problem "Pick a movie first."; return }
    $name = $nameBox.Text.Trim()
    $id = $name -replace '[^A-Za-z0-9]', ''
    if ($id -notmatch '^[A-Za-z]') { Show-Problem "The movie name needs to start with a letter."; return }
    $trailer = $trailerBox.Text.Trim()
    if ($trailerCheck.Checked -and -not (Test-Path -LiteralPath $trailer)) { Show-Problem "Can't find the trailer, pick it again or untick Trailer."; return }
    $output = $outputBox.Text.Trim()
    if (-not $output -or -not (Test-Path -LiteralPath $output)) { Show-Problem "Pick where the add-on should go."; return }
    if ($captionsCheck.Checked) {
        $index = $captionsBox.SelectedIndex
        if ($index -lt 0 -or $index -ge $captionChoices.Count) { Show-Problem "Pick the subtitles for the captions, or untick Captions."; return }
        if (-not $captionChoices[$index].Usable) { Show-Problem "Those are picture subtitles, not text. Turn them into an srt with Subtitle Edit's OCR first, or untick Captions."; return }
        if ($captionLanguageBox.Text.Trim() -notmatch '^[A-Z]{2,4}$') { Show-Problem "The captions language should be a game language code like EN or PTBR."; return }
    }
    if (-not (Test-Path -LiteralPath $makerScript)) { Show-Problem "Make-JimsMovie.ps1 needs to be next to this script."; return }

    $tools = Get-FfmpegTools $form
    if (-not $tools) { return }
    $ffmpeg, $ffprobe = $tools
    $rad = Find-Rad
    if (-not $rad) {
        $rad = Ask-ForExe "Can't find RAD Video Tools. It's a free download from https://www.radgametools.com/bnkdown.htm, then show me where radvideo64.exe is." "radvideo64.exe" $radPathFile
        if (-not $rad) { return }
    }

    $addOn = Join-Path $output "JimsMovies_$id"
    if (Test-Path -LiteralPath $addOn) {
        $answer = [System.Windows.Forms.MessageBox]::Show($form, "$addOn is already there. Replace its files?", "Jim's Movie Maker", "YesNo", "Question")
        if ($answer -ne "Yes") { return }
    }

    $size = $SIZES[[array]::IndexOf($sizeButtons, ($sizeButtons | Where-Object { $_.Checked }))]
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $arguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-NoExit", "-File", (Format-Argument $makerScript),
        "-Video", (Format-Argument $movie),
        "-Name", (Format-Argument $name),
        "-ModsDir", (Format-Argument $output),
        "-Width", $size.Width, "-Height", $size.Height,
        "-SampleRate", $RATES[$rateBox.SelectedIndex],
        "-AudioGain", ([double]$movieBoost.Value).ToString($culture),
        "-Rad", (Format-Argument $rad),
        "-Ffmpeg", (Format-Argument $ffmpeg),
        "-Ffprobe", (Format-Argument $ffprobe)
    )
    if ($monoRadio.Checked) { $arguments += "-Mono" }
    if ($audioTrackBox.Enabled) { $arguments += @("-AudioTrack", ($audioTrackBox.SelectedIndex + 1)) }
    if ($captionsCheck.Checked) {
        $caption = $captionChoices[$captionsBox.SelectedIndex]
        $arguments += @("-Captions", (Format-Argument $caption.Path), "-CaptionTrack", $caption.Track, "-CaptionLanguage", $captionLanguageBox.Text.Trim())
    }
    if ($genreBox.SelectedIndex -gt 0) { $arguments += @("-Genre", ($genreBox.SelectedItem -replace '[^A-Za-z]', '').ToLower()) }
    if ($trailerCheck.Checked) {
        $arguments += @("-TrailerFile", (Format-Argument $trailer), "-TrailerAudioGain", ([double]$trailerBoost.Value).ToString($culture))
    }

    $script:makeProcess = Start-Process -FilePath "powershell.exe" -ArgumentList ($arguments -join " ") -PassThru
    $makeButton.Enabled = $false
    $progress.MarqueeAnimationSpeed = 30
    $status.Text = "Making $name in the other window, close it when it's done"
    $watchTimer.Start()
})

$SUBTITLE_FILTER = "Subtitles and videos (*.srt;*.ass;*.ssa;*.vtt;*.mkv;*.mp4;*.mov;*.webm;*.m4v)|*.srt;*.ass;*.ssa;*.vtt;*.mkv;*.mp4;*.mov;*.webm;*.m4v|All files (*.*)|*.*"

function Find-MovieAddOns($folder) {
    if (-not $folder -or -not (Test-Path -LiteralPath $folder)) { return @() }
    foreach ($dir in Get-ChildItem -LiteralPath $folder -Directory -Filter "JimsMovies_*") {
        $addOnId = $dir.Name.Substring("JimsMovies_".Length)
        $registration = Join-Path $dir.FullName "42\media\lua\shared\$($dir.Name)\JimsMovies$addOnId.lua"
        if (Test-Path -LiteralPath $registration) { $dir.FullName }
    }
}

# "Full Metal Jacket (JimsMovies_FullMetalJacket)", the movie name comes out of the add-on's translation file
function Get-AddOnLabel($dir) {
    $folderName = Split-Path -Leaf $dir
    $addOnId = $folderName.Substring("JimsMovies_".Length)
    $translation = Join-Path $dir "common\media\lua\shared\Translate\EN\IG_UI.json"
    if (Test-Path -LiteralPath $translation) {
        try {
            $movieName = (Get-Content -LiteralPath $translation -Raw -Encoding UTF8 | ConvertFrom-Json)."IGUI_JimsMovies${addOnId}_Name"
            if ($movieName) { return "$movieName ($folderName)" }
        }
        catch { }
    }
    return $folderName
}

function Show-CaptionsWindow {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Jim's Movie Maker: Add Captions to an Add-on"
    $dialog.ClientSize = New-Object System.Drawing.Size(560, 330)
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.StartPosition = "CenterParent"
    $dialog.Font = $form.Font

    Add-Label "Subtitles" 16 16 110 $dialog | Out-Null
    $subtitlesBox = Add-TextBox 130 16 320 $dialog
    $subtitlesBox.ReadOnly = $true
    $subtitlesBrowse = Add-Button "Browse..." 460 16 80 $dialog

    Add-Label "Track" 16 50 110 $dialog | Out-Null
    $trackBox = New-Object System.Windows.Forms.ComboBox
    $trackBox.DropDownStyle = "DropDownList"
    $trackBox.Location = New-Object System.Drawing.Point(130, 50)
    $trackBox.Size = New-Object System.Drawing.Size(410, 24)
    $dialog.Controls.Add($trackBox)

    Add-Label "Movie add-on" 16 84 110 $dialog | Out-Null
    $addOnBox = New-Object System.Windows.Forms.ComboBox
    $addOnBox.DropDownStyle = "DropDownList"
    $addOnBox.Location = New-Object System.Drawing.Point(130, 84)
    $addOnBox.Size = New-Object System.Drawing.Size(320, 24)
    $dialog.Controls.Add($addOnBox)
    $addOnBrowse = Add-Button "Browse..." 460 84 80 $dialog

    Add-Label "Language" 16 118 110 $dialog | Out-Null
    $languageBox = Add-TextBox 130 118 60 $dialog
    $languageBox.Text = "EN"
    $languageBox.CharacterCasing = "Upper"
    $languageHint = Add-Label "game language code, EN, ES, FR, DE, PTBR..." 200 118 340 $dialog
    $languageHint.ForeColor = [System.Drawing.Color]::DimGray

    Add-Label "Shift by" 16 152 110 $dialog | Out-Null
    $offsetBox = New-Object System.Windows.Forms.NumericUpDown
    $offsetBox.DecimalPlaces = 1
    $offsetBox.Increment = 0.1
    $offsetBox.Minimum = -3600
    $offsetBox.Maximum = 3600
    $offsetBox.Location = New-Object System.Drawing.Point(130, 152)
    $offsetBox.Size = New-Object System.Drawing.Size(80, 24)
    $dialog.Controls.Add($offsetBox)
    $offsetHint = Add-Label "seconds, negative shows them sooner" 220 152 320 $dialog
    $offsetHint.ForeColor = [System.Drawing.Color]::DimGray

    Add-Label "Put them in" 16 186 110 $dialog | Out-Null
    $inAddOnRadio = New-Object System.Windows.Forms.RadioButton
    $inAddOnRadio.Text = "The movie add-on"
    $inAddOnRadio.Location = New-Object System.Drawing.Point(130, 186)
    $inAddOnRadio.Size = New-Object System.Drawing.Size(160, 24)
    $inAddOnRadio.Checked = $true
    $dialog.Controls.Add($inAddOnRadio)
    $otherModRadio = New-Object System.Windows.Forms.RadioButton
    $otherModRadio.Text = "Another mod folder, like a language pack"
    $otherModRadio.Location = New-Object System.Drawing.Point(290, 186)
    $otherModRadio.Size = New-Object System.Drawing.Size(260, 24)
    $dialog.Controls.Add($otherModRadio)
    $otherModBox = Add-TextBox 130 218 320 $dialog
    $otherModBrowse = Add-Button "Browse..." 460 218 80 $dialog

    $captionsStatus = Add-Label "Pick the subtitles, or a movie with subtitles in it" 16 256 528 $dialog
    $captionsStatus.ForeColor = [System.Drawing.Color]::DimGray

    $makeCaptionsButton = Add-Button "Make Captions" 344 290 110 $dialog
    $closeCaptionsButton = Add-Button "Close" 464 290 80 $dialog
    $closeCaptionsButton.DialogResult = "Cancel"
    $dialog.AcceptButton = $makeCaptionsButton
    $dialog.CancelButton = $closeCaptionsButton

    # handlers can't assign back to this function's variables, but they can fill in a table
    $state = @{ Tracks = @(); AddOnPaths = New-Object System.Collections.ArrayList }

    $updateOtherMod = {
        $otherModBox.Enabled = $otherModRadio.Checked
        $otherModBrowse.Enabled = $otherModRadio.Checked
    }
    & $updateOtherMod
    $otherModRadio.Add_CheckedChanged($updateOtherMod)

    # never picks one on its own, captions in the wrong movie are worse than a click
    $addAddOn = {
        param($path, $select)
        $index = $state.AddOnPaths.IndexOf($path)
        if ($index -lt 0) {
            $index = $state.AddOnPaths.Add($path)
            [void]$addOnBox.Items.Add((Get-AddOnLabel $path))
        }
        if ($select) { $addOnBox.SelectedIndex = $index }
    }

    foreach ($path in @(Find-MovieAddOns (Join-Path $env:USERPROFILE "Zomboid\mods"))) { & $addAddOn $path $false }

    $trackBox.Add_SelectedIndexChanged({
        if ($trackBox.SelectedIndex -ge 0) { $languageBox.Text = $state.Tracks[$trackBox.SelectedIndex].Language }
    })

    $subtitlesBrowse.Add_Click({
        $picker = New-Object System.Windows.Forms.OpenFileDialog
        $picker.Title = "Pick the subtitles, or a movie with subtitles in it"
        $picker.Filter = $SUBTITLE_FILTER
        if ($lastFolder) { $picker.InitialDirectory = $lastFolder }
        if ($picker.ShowDialog($dialog) -ne "OK") { return }
        $tools = Get-FfmpegTools $dialog
        if (-not $tools) { return }

        $subtitlesBox.Text = $picker.FileName
        $state.Tracks = @()
        $trackBox.Items.Clear()
        $captionsStatus.Text = "Looking for subtitles..."
        $dialog.Refresh()

        $ErrorActionPreference = "Continue"
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $captionsScript -Subtitles $picker.FileName -ListTracks -Ffmpeg $tools[0] -Ffprobe $tools[1] 2>&1
        if ($LASTEXITCODE -ne 0) {
            $captionsStatus.Text = "Couldn't read the subtitles"
            Show-Problem ((@($output | ForEach-Object { "$_" }) -join "`n").Trim()) $dialog
            return
        }
        # powershell 5 hands back the json array as one thing, the ForEach unrolls it
        $found = @((@($output | ForEach-Object { "$_" }) -join "") | ConvertFrom-Json | ForEach-Object { $_ })
        $state.Tracks = $found
        foreach ($track in $found) { [void]$trackBox.Items.Add($track.Label) }
        $trackBox.SelectedIndex = 0
        $captionsStatus.Text = if ($found.Count -eq 1) { "Found 1 subtitle track" } else { "Found $($found.Count) subtitle tracks, pick one" }

        foreach ($path in @(Find-MovieAddOns (Split-Path -Parent $picker.FileName))) { & $addAddOn $path $false }
    })

    $addOnBrowse.Add_Click({
        $picker = New-Object System.Windows.Forms.FolderBrowserDialog
        $picker.Description = "Pick the movie add-on folder, the JimsMovies_ one"
        if ($addOnBox.SelectedIndex -ge 0) { $picker.SelectedPath = $state.AddOnPaths[$addOnBox.SelectedIndex] }
        if ($picker.ShowDialog($dialog) -ne "OK") { return }
        if (-not (Split-Path -Leaf $picker.SelectedPath).StartsWith("JimsMovies_")) { Show-Problem "That's not a movie add-on, it should be a folder named JimsMovies_ something." $dialog; return }
        & $addAddOn $picker.SelectedPath $true
    })

    $otherModBrowse.Add_Click({
        $picker = New-Object System.Windows.Forms.FolderBrowserDialog
        $picker.Description = "Pick the mod folder the captions go in"
        if ($otherModBox.Text) { $picker.SelectedPath = $otherModBox.Text }
        if ($picker.ShowDialog($dialog) -eq "OK") { $otherModBox.Text = $picker.SelectedPath }
    })

    $makeCaptionsButton.Add_Click({
        if (-not $subtitlesBox.Text -or $trackBox.SelectedIndex -lt 0) { Show-Problem "Pick the subtitles first." $dialog; return }
        if (-not $state.Tracks[$trackBox.SelectedIndex].Usable) { Show-Problem "That track is picture subtitles, not text. Turn it into an srt with Subtitle Edit's OCR first, it's free." $dialog; return }
        if ($addOnBox.SelectedIndex -lt 0) { Show-Problem "Pick the movie add-on these captions are for." $dialog; return }
        $addOn = $state.AddOnPaths[$addOnBox.SelectedIndex]
        $language = $languageBox.Text.Trim()
        if ($language -notmatch '^[A-Z]{2,4}$') { Show-Problem "The language should be a game language code like EN or PTBR." $dialog; return }
        $outDir = $addOn
        if ($otherModRadio.Checked) {
            $outDir = $otherModBox.Text.Trim()
            if (-not $outDir) { Show-Problem "Pick the mod folder the captions go in." $dialog; return }
        }
        $tools = Get-FfmpegTools $dialog
        if (-not $tools) { return }

        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        $arguments = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-NoExit", "-File", (Format-Argument $captionsScript),
            "-Subtitles", (Format-Argument $subtitlesBox.Text),
            "-Track", ($trackBox.SelectedIndex + 1),
            "-Id", (Split-Path -Leaf $addOn).Substring("JimsMovies_".Length),
            "-ModsDir", (Format-Argument (Split-Path -Parent $addOn)),
            "-OutDir", (Format-Argument $outDir),
            "-Language", $language,
            "-Offset", ([double]$offsetBox.Value).ToString($culture),
            "-Ffmpeg", (Format-Argument $tools[0]),
            "-Ffprobe", (Format-Argument $tools[1]),
            "-Ask"
        )
        Start-Process -FilePath "powershell.exe" -ArgumentList ($arguments -join " ") | Out-Null
        $captionsStatus.Text = "Making them in the other window"
    })

    [void]$dialog.ShowDialog($form)
    $dialog.Dispose()
}

$captionsButton.Add_Click({
    if (-not (Test-Path -LiteralPath $captionsScript)) { Show-Problem "Make-JimsCaptions.ps1 needs to be next to this script."; return }
    Show-CaptionsWindow
})

Update-Trailer
Set-CaptionChoices @()
Update-CaptionsRow
[void]$form.ShowDialog()
$form.Dispose()
