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
$form.ClientSize = New-Object System.Drawing.Size(560, 560)
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

function Add-Label($text, $x, $y, $width = 110) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point($x, ($y + 4))
    $label.Size = New-Object System.Drawing.Size($width, 20)
    $form.Controls.Add($label)
    return $label
}

function Add-TextBox($x, $y, $width) {
    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point($x, $y)
    $box.Size = New-Object System.Drawing.Size($width, 24)
    $form.Controls.Add($box)
    return $box
}

function Add-Button($text, $x, $y, $width = 80) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $text
    $button.Location = New-Object System.Drawing.Point($x, ($y - 1))
    $button.Size = New-Object System.Drawing.Size($width, 26)
    $form.Controls.Add($button)
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

# where it goes
Add-Label "Make it in" 16 402 | Out-Null
$outputBox = Add-TextBox 130 402 320
$outputBrowse = Add-Button "Browse..." 460 402

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Style = "Marquee"
$progress.MarqueeAnimationSpeed = 0
$progress.Location = New-Object System.Drawing.Point(16, 450)
$progress.Size = New-Object System.Drawing.Size(528, 18)
$form.Controls.Add($progress)
$status = Add-Label "Pick a movie to start" 16 472 528
$status.ForeColor = [System.Drawing.Color]::DimGray

$makeButton = Add-Button "Make Movie" 344 516 110
$closeButton = Add-Button "Close" 464 516 80
$form.AcceptButton = $makeButton
$form.CancelButton = $closeButton

function Update-Trailer {
    $trailerBox.Enabled = $trailerCheck.Checked
    $trailerBrowse.Enabled = $trailerCheck.Checked
    $trailerBoost.Enabled = $trailerCheck.Checked
}

# same rule as the bat: <name>-trailer next to the movie, or movie-trailer
function Set-Movie($path) {
    $movieBox.Text = $path
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

function Show-Problem($text) {
    [void][System.Windows.Forms.MessageBox]::Show($form, $text, "Jim's Movie Maker", "OK", "Warning")
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
    if (-not (Test-Path -LiteralPath $makerScript)) { Show-Problem "Make-JimsMovie.ps1 needs to be next to this script."; return }

    $ffmpeg = Find-Ffmpeg
    if (-not $ffmpeg) {
        $ffmpeg = Ask-ForExe "Can't find ffmpeg. Get it from https://ffmpeg.org/download.html, then show me where ffmpeg.exe is." "ffmpeg.exe" $ffmpegPathFile
        if (-not $ffmpeg) { return }
    }
    $ffprobe = Join-Path (Split-Path -Parent $ffmpeg) "ffprobe.exe"
    if (-not (Test-Path -LiteralPath $ffprobe)) {
        $onPath = Get-Command "ffprobe" -ErrorAction SilentlyContinue
        if (-not $onPath) { Show-Problem "Can't find ffprobe.exe, it comes with ffmpeg and should be in the same folder."; return }
        $ffprobe = $onPath.Source
    }
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

Update-Trailer
[void]$form.ShowDialog()
$form.Dispose()
