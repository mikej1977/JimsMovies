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
$form.ClientSize = New-Object System.Drawing.Size(560, 810)
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

# what to do with subtitles first. burning in takes one from the From list, caption tracks get checked in a list
$subtitlesGroup = New-Object System.Windows.Forms.GroupBox
$subtitlesGroup.Text = "Subtitles"
$subtitlesGroup.Location = New-Object System.Drawing.Point(16, 396)
$subtitlesGroup.Size = New-Object System.Drawing.Size(528, 136)
$form.Controls.Add($subtitlesGroup)

function New-GroupRadio($group, $text, $x, $y, $width) {
    $radio = New-Object System.Windows.Forms.RadioButton
    $radio.Text = $text
    $radio.Location = New-Object System.Drawing.Point($x, $y)
    $radio.Size = New-Object System.Drawing.Size($width, 22)
    $group.Controls.Add($radio)
    return $radio
}

$noSubtitlesRadio = New-GroupRadio $subtitlesGroup "None" 14 22 100
$noSubtitlesRadio.Checked = $true
$burnRadio = New-GroupRadio $subtitlesGroup "Burn into the video" 120 22 160
$captionTracksRadio = New-GroupRadio $subtitlesGroup "Caption tracks" 300 22 200

$subtitlesFromBox = New-Object System.Windows.Forms.ComboBox
$subtitlesFromBox.DropDownStyle = "DropDownList"
$subtitlesFromBox.Location = New-Object System.Drawing.Point(14, 50)
$subtitlesFromBox.Size = New-Object System.Drawing.Size(404, 24)
$subtitlesFromBox.DropDownWidth = 480
$subtitlesGroup.Controls.Add($subtitlesFromBox)

$captionsList = New-Object System.Windows.Forms.CheckedListBox
$captionsList.Location = New-Object System.Drawing.Point(14, 50)
$captionsList.Size = New-Object System.Drawing.Size(404, 76)
$captionsList.CheckOnClick = $true
$captionsList.IntegralHeight = $false
$subtitlesGroup.Controls.Add($captionsList)

$subtitlesBrowse = Add-Button "Browse..." 430 50 84 $subtitlesGroup

# other audio tracks players can switch to, every track but the one the movie plays
$otherAudioGroup = New-Object System.Windows.Forms.GroupBox
$otherAudioGroup.Text = "Other audio players can switch to"
$otherAudioGroup.Location = New-Object System.Drawing.Point(16, 540)
$otherAudioGroup.Size = New-Object System.Drawing.Size(528, 112)
$form.Controls.Add($otherAudioGroup)
$otherAudioList = New-Object System.Windows.Forms.CheckedListBox
$otherAudioList.Location = New-Object System.Drawing.Point(14, 22)
$otherAudioList.Size = New-Object System.Drawing.Size(500, 80)
$otherAudioList.CheckOnClick = $true
$otherAudioList.IntegralHeight = $false
$otherAudioGroup.Controls.Add($otherAudioList)

# where it goes
Add-Label "Make it in" 16 662 | Out-Null
$outputBox = Add-TextBox 130 662 320
$outputBrowse = Add-Button "Browse..." 460 662

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Style = "Marquee"
$progress.MarqueeAnimationSpeed = 0
$progress.Location = New-Object System.Drawing.Point(16, 702)
$progress.Size = New-Object System.Drawing.Size(528, 18)
$form.Controls.Add($progress)
$status = Add-Label "Pick a movie to start" 16 724 528
$status.ForeColor = [System.Drawing.Color]::DimGray

$makeButton = Add-Button "Make Movie" 344 766 110
$closeButton = Add-Button "Close" 464 766 80
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

$IMAGE_SUBTITLE_CODECS = @("hdmv_pgs_subtitle", "dvd_subtitle", "dvb_subtitle", "xsub", "dvb_teletext")

# Path, Track, Label and Usable for each subtitle track in a file
function Get-SubtitleChoices($path, $labelStart) {
    $ffprobe = Find-Ffprobe
    if (-not $ffprobe) { return }
    $probe = (& $ffprobe -v error -select_streams s -show_entries "stream=codec_name:stream_tags=language,title:stream_disposition=forced" -of json $path) -join "`n" | ConvertFrom-Json
    $tracks = @($probe.streams | Where-Object { $_ })
    for ($i = 0; $i -lt $tracks.Count; $i++) {
        $stream = $tracks[$i]
        $usable = $IMAGE_SUBTITLE_CODECS -notcontains $stream.codec_name
        $parts = @()
        $parts += if ($stream.tags -and $stream.tags.language) { $stream.tags.language } else { "unknown language" }
        if ($stream.tags -and $stream.tags.title) { $parts += $stream.tags.title }
        if ($stream.disposition -and $stream.disposition.forced -eq 1) { $parts += "forced, only the foreign bits" }
        $parts += if ($usable) { $stream.codec_name } else { "picture subtitles, can't use" }
        $label = if ($tracks.Count -eq 1 -and $labelStart -ne "From the movie") { $labelStart } else { "${labelStart}: $($parts -join ', ')" }
        [pscustomobject]@{ Path = $path; Track = $i + 1; Label = $label; Usable = $usable }
    }
}

# every subtitle track found so far, the movie's own and any files next to it or picked
$subtitleChoices = @()

function Get-ChoiceKey($choice) { return "$($choice.Track)*$($choice.Path)" }

# fills both lists from the choices, keeping what was checked or picked by its file and track
function Update-SubtitleLists($checkKeys, $selectKey) {
    if ($null -eq $checkKeys) {
        $checkKeys = @()
        for ($i = 0; $i -lt $captionsList.Items.Count; $i++) {
            if ($captionsList.GetItemChecked($i) -and $i -lt $subtitleChoices.Count) { $checkKeys += Get-ChoiceKey $subtitleChoices[$i] }
        }
    }
    if (-not $selectKey -and $subtitlesFromBox.SelectedIndex -ge 0 -and $subtitlesFromBox.SelectedIndex -lt $subtitleChoices.Count) {
        $selectKey = Get-ChoiceKey $subtitleChoices[$subtitlesFromBox.SelectedIndex]
    }
    $captionsList.Items.Clear()
    $subtitlesFromBox.Items.Clear()
    $select = 0
    for ($i = 0; $i -lt $subtitleChoices.Count; $i++) {
        $choice = $subtitleChoices[$i]
        $key = Get-ChoiceKey $choice
        [void]$captionsList.Items.Add($choice.Label, ($choice.Usable -and $checkKeys -contains $key))
        [void]$subtitlesFromBox.Items.Add($choice.Label)
        if ($key -eq $selectKey) { $select = $i }
    }
    if ($subtitleChoices.Count -gt 0) { $subtitlesFromBox.SelectedIndex = $select }
    Update-SubtitlesMode
}

# burning in shows From, caption tracks show the checklist, None greys out whichever is showing
function Update-SubtitlesMode {
    $subtitlesFromBox.Visible = -not $captionTracksRadio.Checked
    $captionsList.Visible = $captionTracksRadio.Checked
    $subtitlesFromBox.Enabled = $burnRadio.Checked
    $captionsList.Enabled = $captionTracksRadio.Checked
    $subtitlesBrowse.Enabled = -not $noSubtitlesRadio.Checked
}

# the movie's own subtitle tracks, plus subtitle files named like the movie next to it
function Update-SubtitleChoices($path) {
    $folder = Split-Path -Parent $path
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($path)
    $choices = @(Get-SubtitleChoices $path "From the movie")
    foreach ($file in Get-ChildItem -LiteralPath $folder -File -Filter "$baseName*" -ErrorAction SilentlyContinue) {
        if (@(".srt", ".ass", ".ssa", ".vtt") -contains $file.Extension.ToLower()) { $choices += @(Get-SubtitleChoices $file.FullName $file.Name) }
    }
    $script:subtitleChoices = $choices
    # starts with the first usable track checked, the rest are a click away
    $first = @($choices | Where-Object { $_.Usable } | Select-Object -First 1)
    if ($first.Count -gt 0) { $captionTracksRadio.Checked = $true } else { $noSubtitlesRadio.Checked = $true }
    Update-SubtitleLists @($first | ForEach-Object { Get-ChoiceKey $_ }) $null
}

# a file that's already listed, the movie itself say, just gets picked instead of its tracks going in twice
function Add-SubtitleFile($path) {
    $already = @($subtitleChoices | Where-Object { $_.Path -eq $path })
    $added = @()
    if ($already.Count -eq 0) {
        $added = @(Get-SubtitleChoices $path ([System.IO.Path]::GetFileName($path)))
        if ($added.Count -eq 0) { Show-Problem "No subtitles in $([System.IO.Path]::GetFileName($path))."; return }
        $script:subtitleChoices = @($subtitleChoices) + $added
    }
    if ($noSubtitlesRadio.Checked) { $captionTracksRadio.Checked = $true }
    $fileChoices = if ($added.Count -gt 0) { $added } else { $already }
    $checkKeys = @()
    for ($i = 0; $i -lt $captionsList.Items.Count; $i++) {
        if ($captionsList.GetItemChecked($i)) { $checkKeys += Get-ChoiceKey $subtitleChoices[$i] }
    }
    # a newly browsed file gets its tracks checked, that's why it got picked
    $checkKeys += @($fileChoices | Where-Object { $_.Usable } | ForEach-Object { Get-ChoiceKey $_ })
    Update-SubtitleLists $checkKeys (Get-ChoiceKey $fileChoices[0])
}

$subtitlesBrowse.Add_Click({
    $picker = New-Object System.Windows.Forms.OpenFileDialog
    $picker.Title = "Pick the subtitles, or a video with subtitles in it"
    $picker.Filter = "Subtitles and videos (*.srt;*.ass;*.ssa;*.vtt;*.mkv;*.mp4;*.mov;*.webm;*.m4v)|*.srt;*.ass;*.ssa;*.vtt;*.mkv;*.mp4;*.mov;*.webm;*.m4v|All files (*.*)|*.*"
    if ($lastFolder) { $picker.InitialDirectory = $lastFolder }
    if ($picker.ShowDialog($form) -eq "OK") { Add-SubtitleFile $picker.FileName }
})

# picture subtitles can't be made into anything, so they won't take a check
$captionsList.Add_ItemCheck({
    param($list, $check)
    if ($check.NewValue -eq "Checked" -and $check.Index -lt $subtitleChoices.Count -and -not $subtitleChoices[$check.Index].Usable) {
        $check.NewValue = "Unchecked"
    }
})

foreach ($radio in @($noSubtitlesRadio, $burnRadio, $captionTracksRadio)) {
    $radio.Add_CheckedChanged({ if ($this.Checked) { Update-SubtitlesMode } })
}

# track numbers behind the other audio list, every track but the one the movie plays
$otherAudioTracks = @()

# keeps the same tracks checked when the movie's own track changes
function Update-OtherAudioTracks {
    $checked = @()
    for ($i = 0; $i -lt $otherAudioList.Items.Count; $i++) {
        if ($otherAudioList.GetItemChecked($i) -and $i -lt $otherAudioTracks.Count) { $checked += $otherAudioTracks[$i] }
    }
    $script:otherAudioTracks = @()
    $otherAudioList.Items.Clear()
    for ($i = 0; $i -lt $audioTrackBox.Items.Count; $i++) {
        if ($i -eq $audioTrackBox.SelectedIndex) { continue }
        $script:otherAudioTracks += $i + 1
        [void]$otherAudioList.Items.Add($audioTrackBox.Items[$i], ($checked -contains ($i + 1)))
    }
    $otherAudioGroup.Enabled = $otherAudioList.Items.Count -gt 0
}

$audioTrackBox.Add_SelectedIndexChanged({ Update-OtherAudioTracks })

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

    $otherAudioList.Items.Clear()
    $script:otherAudioTracks = @()
    Update-OtherAudioTracks
}

# same rule as the bat: <name>-trailer next to the movie, or movie-trailer
function Set-Movie($path) {
    $movieBox.Text = $path
    $status.Text = "Looking at the movie..."
    $form.Refresh()
    Update-AudioTracks $path
    Update-SubtitleChoices $path
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
    if ($burnRadio.Checked) {
        $index = $subtitlesFromBox.SelectedIndex
        if ($index -lt 0 -or $index -ge $subtitleChoices.Count) { Show-Problem "Pick the subtitles to burn in, or set Subtitles to None."; return }
        if (-not $subtitleChoices[$index].Usable) { Show-Problem "Those are picture subtitles, not text. Turn them into an srt with Subtitle Edit's OCR first, or set Subtitles to None."; return }
    }
    $captionPicks = @()
    if ($captionTracksRadio.Checked) {
        for ($i = 0; $i -lt $captionsList.Items.Count; $i++) {
            if ($captionsList.GetItemChecked($i)) { $captionPicks += Get-ChoiceKey $subtitleChoices[$i] }
        }
        if ($captionPicks.Count -eq 0) { Show-Problem "Check at least one caption track, or set Subtitles to None."; return }
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
    $audioPicks = @()
    for ($i = 0; $i -lt $otherAudioList.Items.Count; $i++) {
        if ($otherAudioList.GetItemChecked($i)) { $audioPicks += $otherAudioTracks[$i] }
    }
    if ($audioPicks.Count -gt 0) { $arguments += @("-AudioTracks", ($audioPicks -join ",")) }
    if ($burnRadio.Checked) {
        $subtitle = $subtitleChoices[$subtitlesFromBox.SelectedIndex]
        $arguments += @("-BurnSubtitles", (Format-Argument $subtitle.Path), "-BurnTrack", $subtitle.Track)
    }
    elseif ($captionPicks.Count -gt 0) { $arguments += @("-CaptionPicks", (Format-Argument ($captionPicks -join "|"))) }
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

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 20000
$toolTip.InitialDelay = 400

# number boxes have a text box inside them that eats the hover, so the tip goes on those too
function Set-Tip($control, $text) {
    $toolTip.SetToolTip($control, $text)
    foreach ($child in $control.Controls) { $toolTip.SetToolTip($child, $text) }
}

Set-Tip $movieBox "The movie file. mp4, mkv, mov, avi, webm or m4v"
Set-Tip $trailerCheck "Makes a trailer too, it plays before the movie.`nName it <movie>-trailer next to the movie and it gets found on its own"
Set-Tip $nameBox "What the movie's called in the Start Movie list.`nThe add-on's code name is this with the spaces and symbols taken out"
Set-Tip $genreBox "Which moodles the movie helps with.`nNone gives the default mix"
foreach ($radio in $sizeButtons) {
    Set-Tip $radio "How big the picture is. Bigger looks sharper on the big screens`nbut takes a lot longer to make and makes a bigger add-on.`n240p is plenty for TVs"
}
Set-Tip $stereoRadio "Two channels"
Set-Tip $monoRadio "One channel, half the memory"
Set-Tip $rateBox "Sound quality. The game decodes the whole movie's sound into memory,`nso lower uses a lot less of it"
Set-Tip $movieBoost "Makes the movie louder, in dB. For quiet sources, 6 to 18 say.`nNegative turns it down"
Set-Tip $trailerBoost "Same thing for the trailer"
Set-Tip $audioTrackBox "Which audio track to use when the movie has more than one, like another language or commentary"
Set-Tip $otherAudioList "Audio tracks players can switch to from Audio in the movie window,`nlike another language or a commentary. Check as many as you want, none is fine.`nThe one the movie already plays isn't in the list. It switches over within a few seconds"
Set-Tip $burnRadio "Drawn right into the movie. Everybody sees them and they can't be turned off, so only one"
Set-Tip $captionTracksRadio "Players pick one from Captions in the movie window, or leave them off.`nEach takes roughly half the movie's length to make"
Set-Tip $subtitlesFromBox "The subtitles to burn in, the movie's own tracks or a subtitle file named like it.`nAny language works. Picture subtitles (Blu-ray, DVD) don't work, Subtitle Edit's OCR can turn them into an srt"
Set-Tip $captionsList "Check every caption track you want, each one is its own choice in game.`nAny language works. Picture subtitles (Blu-ray, DVD) won't check, Subtitle Edit's OCR can turn them into an srt"
Set-Tip $subtitlesBrowse "Add a subtitle file from somewhere else, or another video with subtitles in it"
Set-Tip $outputBox "Where the JimsMovies_ add-on folder gets made"
Set-Tip $makeButton "Makes the add-on in its own window. Bink takes a while, close that window when it's done"

Update-Trailer
Update-SubtitleLists @() $null
Update-OtherAudioTracks
[void]$form.ShowDialog()
$form.Dispose()
