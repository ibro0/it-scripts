[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$YtDlp,

    [Parameter(Mandatory = $true)]
    [string]$SourceFile,

    [Parameter(Mandatory = $true)]
    [string]$SaveDirectory,

    [Parameter(Mandatory = $true)]
    [string]$TempRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputTemplate,

    [Parameter(Mandatory = $true)]
    [string]$FormatSelector,

    [Parameter(Mandatory = $true)]
    [ValidateSet('mp4', 'mkv')]
    [string]$Container,

    [Parameter(Mandatory = $true)]
    [string]$FfmpegLocation,

    [Parameter(Mandatory = $true)]
    [string]$Deno,

    [Parameter(Mandatory = $true)]
    [ValidateSet(720, 1080)]
    [int]$RequestedQuality,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 32)]
    [int]$ConcurrentFragments,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 4)]
    [int]$ParallelDownloads,

    [ValidateRange(0, 60)]
    [int]$WorkerStartDelaySeconds = 5
)

$ErrorActionPreference = 'Stop'
$ffmpeg = Join-Path $FfmpegLocation 'ffmpeg.exe'
$ffprobe = Join-Path $FfmpegLocation 'ffprobe.exe'
$verifiedRoot = Join-Path $SaveDirectory '.youtube-verified'
$corruptRoot = Join-Path $SaveDirectory '_Corrupt'
$mediaExtensions = @('.mp4', '.mkv', '.webm', '.mov', '.m4v', '.avi')
$runLog = $null

function Write-RunLog {
    param([string]$Message)

    if (-not $runLog) {
        return
    }
    $line = '[{0}] {1}{2}' -f [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff'), $Message, [Environment]::NewLine
    [IO.File]::AppendAllText($runLog, $line, (New-Object Text.UTF8Encoding($false)))
}

function Get-ShortText {
    param(
        [AllowEmptyString()]
        [string]$Text,
        [int]$MaximumLength
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return '--'
    }

    $clean = ($Text -replace '[\r\n\t]+', ' ').Trim()
    if ($clean.Length -le $MaximumLength) {
        return $clean
    }

    if ($MaximumLength -le 3) {
        return $clean.Substring(0, $MaximumLength)
    }

    return $clean.Substring(0, $MaximumLength - 3) + '...'
}

function Get-SafeFolderName {
    param([string]$Name)

    $safe = ($Name -replace '[<>:"/\\|?*]+', ' - ') -replace '\s+', ' '
    $safe = $safe.Trim(' ', '.')
    if (-not $safe) {
        $safe = 'Uncategorized'
    }
    if ($safe.Length -gt 100) {
        $safe = $safe.Substring(0, 100).Trim(' ', '.')
    }

    $reserved = @('CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')
    if ($reserved -contains $safe.ToUpperInvariant()) {
        $safe = '_' + $safe
    }
    return $safe
}

function Get-YouTubeId {
    param([string]$Url)

    if ($Url -match '(?i)[?&]v=([A-Za-z0-9_-]{11})(?:[&#]|$)') {
        return $Matches[1]
    }
    if ($Url -match '(?i)(?:youtu\.be/|youtube(?:-nocookie)?\.com/(?:shorts/|live/|embed/))([A-Za-z0-9_-]{11})(?:[?&#/]|$)') {
        return $Matches[1]
    }
    return $null
}

function Get-RecordPath {
    param(
        [string]$SectionFolder,
        [string]$VideoId,
        [int]$Quality,
        [string]$OutputContainer
    )

    if (-not $VideoId) {
        return $null
    }
    $recordDirectory = Join-Path $verifiedRoot $SectionFolder
    return Join-Path $recordDirectory ($VideoId + '.q' + $Quality + '.' + $OutputContainer + '.json')
}

function Write-VerifiedRecord {
    param(
        [string]$RecordPath,
        [string]$VideoId,
        [string]$Section,
        [string]$MediaPath,
        [int]$Quality,
        [string]$OutputContainer,
        [string]$VerificationMethod
    )

    $media = Get-Item -LiteralPath $MediaPath -ErrorAction Stop
    $recordDirectory = Split-Path -Parent $RecordPath
    [IO.Directory]::CreateDirectory($recordDirectory) | Out-Null
    $record = [ordered]@{
        Version = 1
        VideoId = $VideoId
        Section = $Section
        RequestedQuality = $Quality
        Container = $OutputContainer
        FullPath = $media.FullName
        Length = $media.Length
        LastWriteTimeUtcTicks = $media.LastWriteTimeUtc.Ticks
        VerifiedUtc = [DateTime]::UtcNow.ToString('o')
        Verification = $VerificationMethod
    }
    $temporaryRecord = $RecordPath + '.tmp.' + [Guid]::NewGuid().ToString('N')
    $record | ConvertTo-Json | Set-Content -LiteralPath $temporaryRecord -Encoding UTF8
    Move-Item -LiteralPath $temporaryRecord -Destination $RecordPath -Force
}

function Get-CachedVerifiedFile {
    param([string]$RecordPath)

    if (-not $RecordPath -or -not (Test-Path -LiteralPath $RecordPath -PathType Leaf)) {
        return $null
    }

    try {
        $record = Get-Content -LiteralPath $RecordPath -Raw | ConvertFrom-Json
        if (-not $record.FullPath -or -not (Test-Path -LiteralPath ([string]$record.FullPath) -PathType Leaf)) {
            return $null
        }
        $media = Get-Item -LiteralPath ([string]$record.FullPath)
        if ($media.Length -ne [int64]$record.Length) {
            return $null
        }
        if ($media.LastWriteTimeUtc.Ticks -ne [int64]$record.LastWriteTimeUtcTicks) {
            return $null
        }

        & $ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $media.FullName 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            return $null
        }
        return $media
    } catch {
        return $null
    }
}

function Test-MediaIntegrity {
    param([string]$MediaPath)

    if (-not (Test-Path -LiteralPath $MediaPath -PathType Leaf)) {
        return $false
    }

    $probeOutput = @(& $ffprobe -v error -show_entries format=duration,size -of default=noprint_wrappers=1 $MediaPath 2>&1)
    if ($LASTEXITCODE -ne 0 -or $probeOutput.Count -eq 0) {
        return $false
    }

    $beginningOutput = @(& $ffmpeg -hide_banner -nostdin -v error -xerror -err_detect explode -i $MediaPath -t 8 -map '0:v?' -map '0:a?' -f null NUL 2>&1)
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    $endingOutput = @(& $ffmpeg -hide_banner -nostdin -v error -xerror -err_detect explode -sseof -8 -i $MediaPath -t 8 -map '0:v?' -map '0:a?' -f null NUL 2>&1)
    return ($LASTEXITCODE -eq 0)
}

function Move-ToSection {
    param(
        [System.IO.FileInfo]$Media,
        [string]$SectionDirectory
    )

    [IO.Directory]::CreateDirectory($SectionDirectory) | Out-Null
    $sectionPrefix = $SectionDirectory.TrimEnd('\') + '\'
    if ($Media.FullName.StartsWith($sectionPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $Media
    }

    $destination = Join-Path $SectionDirectory $Media.Name
    if (Test-Path -LiteralPath $destination) {
        $baseName = [IO.Path]::GetFileNameWithoutExtension($Media.Name)
        $destination = Join-Path $SectionDirectory ($baseName + ' - recovered ' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + $Media.Extension)
    }
    Move-Item -LiteralPath $Media.FullName -Destination $destination
    return Get-Item -LiteralPath $destination
}

function Move-ToCorruptFolder {
    param(
        [System.IO.FileInfo]$Media,
        [string]$SectionFolder
    )

    $destinationDirectory = Join-Path $corruptRoot $SectionFolder
    [IO.Directory]::CreateDirectory($destinationDirectory) | Out-Null
    $baseName = [IO.Path]::GetFileNameWithoutExtension($Media.Name)
    $destination = Join-Path $destinationDirectory ($baseName + '.corrupt-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + $Media.Extension)
    Move-Item -LiteralPath $Media.FullName -Destination $destination -Force
    return $destination
}

function Update-DownloadState {
    param(
        [Parameter(Mandatory = $true)]
        $State,
        [Parameter(Mandatory = $true)]
        [string]$Line
    )

    $text = $Line.Trim()
    if (-not $text) {
        return
    }

    if ($text.StartsWith('PROGRESS|', [StringComparison]::Ordinal)) {
        $parts = $text.Split('|')
        if ($parts.Count -ge 6) {
            $State.Title = ($parts[2..($parts.Count - 4)] -join '|').Trim()
            $State.Percent = $parts[$parts.Count - 3].Trim()
            $State.Speed = $parts[$parts.Count - 2].Trim()
            $State.Eta = $parts[$parts.Count - 1].Trim()
            $State.Status = 'Downloading'
        }
        return
    }

    if ($text.StartsWith('START|', [StringComparison]::Ordinal)) {
        $parts = $text.Split('|')
        if ($parts.Count -ge 3) {
            $State.Title = ($parts[2..($parts.Count - 1)] -join '|').Trim()
        }
        $State.Status = 'Preparing'
        return
    }

    if ($text.StartsWith('DONE|', [StringComparison]::Ordinal)) {
        $State.Percent = '100%'
        $State.Speed = '--'
        $State.Eta = '--'
        $State.Status = 'Downloaded; waiting for verification'
        return
    }

    if ($text.StartsWith('VERIFYING|', [StringComparison]::Ordinal)) {
        $State.Percent = '100%'
        $State.Speed = '--'
        $State.Eta = '--'
        $State.Status = 'Integrity check: full decode'
        return
    }

    if ($text.StartsWith('VERIFIED|', [StringComparison]::Ordinal)) {
        $State.Status = 'Verified'
        return
    }

    if ($text.StartsWith('__YBD_EXIT__|', [StringComparison]::Ordinal)) {
        $exitText = $text.Substring('__YBD_EXIT__|'.Length)
        $parsedExit = 1
        if ([int]::TryParse($exitText, [ref]$parsedExit)) {
            $State.ExitCode = $parsedExit
        }
        return
    }

    if ($text.StartsWith('ENGINE_ERROR|', [StringComparison]::Ordinal)) {
        $State.LastError = $text.Substring('ENGINE_ERROR|'.Length)
        return
    }

    if ($text -match '(?i)\bERROR:') {
        $State.LastError = $text
    }
}

function Show-Dashboard {
    param(
        [hashtable]$Active,
        [int]$Total,
        [int]$Succeeded,
        [int]$Failed,
        [int]$Skipped,
        [int]$Queued
    )

    try {
        Clear-Host
    } catch {
        # Some redirected consoles do not support clearing.
    }

    $finished = $Succeeded + $Failed + $Skipped
    Write-Host '============================================================'
    Write-Host ' YouTube Parallel Downloader'
    Write-Host '============================================================'
    Write-Host ''
    Write-Host (" Complete: {0}/{1}   Active: {2}   Queued: {3}   Verified/skipped: {4}   Failed: {5}" -f $finished, $Total, $Active.Count, $Queued, $Skipped, $Failed)
    Write-Host ''

    $consoleWidth = 120
    try {
        if ([Console]::WindowWidth -gt 40) {
            $consoleWidth = [Console]::WindowWidth
        }
    } catch {
        # Keep the fallback width.
    }
    $titleWidth = [Math]::Max(20, $consoleWidth - 55)

    foreach ($state in @($Active.Values | Sort-Object Index)) {
        $percent = Get-ShortText $state.Percent 8
        $speed = Get-ShortText $state.Speed 12
        $eta = Get-ShortText $state.Eta 8
        $displayTitle = '[' + $state.Section + '] ' + $state.Title
        $title = Get-ShortText $displayTitle $titleWidth
        Write-Host (" [{0,2}/{1}] {2,-8} | {3,-12} | ETA {4,-8} | {5}" -f $state.Index, $Total, $percent, $speed, $eta, $title)
        Write-Host ("         {0}" -f $state.Status)
    }

    if ($Active.Count -eq 0 -and $finished -lt $Total) {
        Write-Host ' Preparing workers...'
    }

    Write-Host ''
    Write-Host ' Each active row is a separate video download.'
    Write-Host ' New video jobs are staggered by 5 seconds to reduce request bursts.'
}

if (-not (Test-Path -LiteralPath $YtDlp -PathType Leaf)) {
    throw "yt-dlp was not found: $YtDlp"
}
if (-not (Test-Path -LiteralPath $ffmpeg -PathType Leaf)) {
    throw "ffmpeg was not found: $ffmpeg"
}
if (-not (Test-Path -LiteralPath $ffprobe -PathType Leaf)) {
    throw "ffprobe was not found: $ffprobe"
}
if (-not (Test-Path -LiteralPath $SourceFile -PathType Leaf)) {
    throw "Source file was not found: $SourceFile"
}

[IO.Directory]::CreateDirectory($SaveDirectory) | Out-Null
[IO.Directory]::CreateDirectory($verifiedRoot) | Out-Null
$logDirectory = Join-Path $SaveDirectory '_Downloader Logs'
[IO.Directory]::CreateDirectory($logDirectory) | Out-Null
$runLog = Join-Path $logDirectory ('download-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '-pid' + $PID + '.log')
[IO.File]::WriteAllText($runLog, '', (New-Object Text.UTF8Encoding($false)))
Write-RunLog 'YouTube downloader run started.'
Write-RunLog ("Source file: {0}" -f $SourceFile)
Write-RunLog ("Save directory: {0}" -f $SaveDirectory)
Write-RunLog ("Quality: {0}p; container: {1}; simultaneous videos: {2}; fragments per video: {3}" -f $RequestedQuality, $Container, $ParallelDownloads, $ConcurrentFragments)

$entries = New-Object System.Collections.Generic.List[object]
$currentSection = 'Uncategorized'
$itemIndex = 0
foreach ($line in [IO.File]::ReadLines($SourceFile)) {
    $text = $line.Trim()
    # Lines beginning with "##" are documentation comments.  A single "#"
    # starts a folder group, which keeps link lists friendly for people and AI.
    if ($text -match '^##(?:\s|$)') {
        continue
    }
    if ($text -match '^#\s+(.+?)\s*$') {
        $currentSection = $Matches[1].Trim()
        continue
    }
    # Keep compatibility with lists made by older versions of this tool.
    if ($text -match '^\[(.+)\]\s*$') {
        $currentSection = $Matches[1].Trim()
        continue
    }
    if ($text -notmatch '^https?://') {
        continue
    }

    $itemIndex++
    $sectionFolder = Get-SafeFolderName $currentSection
    $entries.Add([pscustomobject]@{
        Index = $itemIndex
        Url = $text
        Section = $currentSection
        SectionFolder = $sectionFolder
        SectionDirectory = Join-Path $SaveDirectory $sectionFolder
        VideoId = Get-YouTubeId $text
    })
}

$total = $entries.Count
if ($total -eq 0) {
    throw 'The source TXT file does not contain any HTTP download links.'
}

$sectionCount = @($entries | Select-Object -ExpandProperty SectionFolder -Unique).Count
Write-Host ("Found {0} video link(s) across {1} show folder(s)." -f $total, $sectionCount)
Write-Host 'Quick-checking the verified index and existing media...'
Write-Host ("Detailed log: {0}" -f $runLog)
Write-RunLog ("Parsed {0} video links across {1} show folders." -f $total, $sectionCount)

$mediaIndex = @{}
foreach ($media in @(Get-ChildItem -LiteralPath $SaveDirectory -Recurse -File -ErrorAction SilentlyContinue)) {
    if ($mediaExtensions -notcontains $media.Extension.ToLowerInvariant()) {
        continue
    }
    if ($media.FullName.StartsWith($verifiedRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        continue
    }
    if ($media.FullName.StartsWith($corruptRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        continue
    }
    if ($media.Name -match '\[([A-Za-z0-9_-]{11})\]') {
        $id = $Matches[1]
        if (-not $mediaIndex.ContainsKey($id)) {
            $mediaIndex[$id] = New-Object System.Collections.Generic.List[object]
        }
        $mediaIndex[$id].Add($media)
    }
}

$queue = New-Object System.Collections.Queue
$skipped = 0
foreach ($entry in $entries) {
    [IO.Directory]::CreateDirectory($entry.SectionDirectory) | Out-Null
    $recordPath = Get-RecordPath -SectionFolder $entry.SectionFolder -VideoId $entry.VideoId -Quality $RequestedQuality -OutputContainer $Container
    $entry | Add-Member -NotePropertyName RecordPath -NotePropertyValue $recordPath

    $cachedMedia = Get-CachedVerifiedFile -RecordPath $recordPath
    if ($cachedMedia) {
        Write-RunLog ("SKIP cached [{0}] [{1}] {2}" -f $entry.Index, $entry.Section, $cachedMedia.FullName)
        $skipped++
        continue
    }

    $candidate = $null
    if ($entry.VideoId -and $mediaIndex.ContainsKey($entry.VideoId)) {
        $sectionPrefix = $entry.SectionDirectory.TrimEnd('\') + '\'
        $qualityPattern = '\[' + $RequestedQuality + 'p\]'
        $candidate = @($mediaIndex[$entry.VideoId] | Where-Object { $_.Name -match $qualityPattern -and $_.FullName.StartsWith($sectionPrefix, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if (-not $candidate) {
            $candidate = @($mediaIndex[$entry.VideoId] | Where-Object { $_.Name -match $qualityPattern } | Select-Object -First 1)
        }
        if ($candidate.Count -gt 0) {
            $candidate = $candidate[0]
        } else {
            $candidate = $null
        }
    }

    if ($candidate) {
        Write-Host ("Quick-checking existing file [{0}/{1}]: {2}" -f $entry.Index, $total, (Get-ShortText $candidate.Name 80))
        Write-RunLog ("CHECK existing [{0}] [{1}] {2}" -f $entry.Index, $entry.Section, $candidate.FullName)
        if (Test-MediaIntegrity -MediaPath $candidate.FullName) {
            $organizedMedia = Move-ToSection -Media $candidate -SectionDirectory $entry.SectionDirectory
            Write-VerifiedRecord -RecordPath $recordPath -VideoId $entry.VideoId -Section $entry.Section -MediaPath $organizedMedia.FullName -Quality $RequestedQuality -OutputContainer $Container -VerificationMethod 'Fast ffprobe plus beginning/end decode'
            Write-RunLog ("SKIP newly indexed [{0}] [{1}] {2}" -f $entry.Index, $entry.Section, $organizedMedia.FullName)
            $skipped++
            continue
        }

        Write-Warning ("Corrupt media detected and quarantined: {0}" -f $candidate.FullName)
        $quarantinedPath = Move-ToCorruptFolder -Media $candidate -SectionFolder $entry.SectionFolder
        Write-RunLog ("CORRUPT quarantined [{0}] {1}" -f $entry.Index, $quarantinedPath)
        if ($recordPath) {
            Remove-Item -LiteralPath $recordPath -Force -ErrorAction SilentlyContinue
        }
    }

    $queue.Enqueue($entry)
}

$workerScript = {
    param($Payload)

    $exitCode = 1
    $completedFiles = New-Object System.Collections.Generic.List[object]
    try {
        $executable = [string]$Payload.Executable
        $workerArguments = [string[]]$Payload.Arguments
        & $executable @workerArguments 2>&1 | ForEach-Object {
            $line = [string]$_
            if ($line.StartsWith('DONE|', [StringComparison]::Ordinal)) {
                $parts = $line.Split('|')
                if ($parts.Count -ge 3) {
                    $encodedPath = ($parts[2..($parts.Count - 1)] -join '|')
                    try {
                        $decodedPath = ConvertFrom-Json -InputObject $encodedPath
                    } catch {
                        $decodedPath = $encodedPath
                    }
                    $completedFiles.Add([pscustomobject]@{
                        VideoId = $parts[1]
                        FullPath = [string]$decodedPath
                    })
                }
            }
            Write-Output $line
        }
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) {
            $exitCode = 0
        }

        if ($exitCode -eq 0) {
            if ($completedFiles.Count -eq 0) {
                throw 'yt-dlp did not report a completed media file to verify.'
            }

            foreach ($completed in $completedFiles) {
                Write-Output ('VERIFYING|' + $completed.VideoId + '|' + $completed.FullPath)
                $verificationMessages = @(
                    & $Payload.Ffmpeg -hide_banner -nostdin -v error -xerror -err_detect explode -i $completed.FullPath -map '0:v?' -map '0:a?' -f null NUL 2>&1
                )
                $verificationExitCode = $LASTEXITCODE
                if ($verificationExitCode -ne 0) {
                    $message = ($verificationMessages | ForEach-Object { [string]$_ }) -join ' '
                    if (-not $message) {
                        $message = 'ffmpeg detected invalid or unreadable media.'
                    }

                    [IO.Directory]::CreateDirectory($Payload.CorruptDirectory) | Out-Null
                    $media = Get-Item -LiteralPath $completed.FullPath -ErrorAction SilentlyContinue
                    if ($media) {
                        $baseName = [IO.Path]::GetFileNameWithoutExtension($media.Name)
                        $quarantinePath = Join-Path $Payload.CorruptDirectory ($baseName + '.corrupt-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + $media.Extension)
                        Move-Item -LiteralPath $media.FullName -Destination $quarantinePath -Force
                    }
                    throw $message
                }

                $media = Get-Item -LiteralPath $completed.FullPath -ErrorAction Stop
                $recordDirectory = Split-Path -Parent $Payload.RecordPath
                [IO.Directory]::CreateDirectory($recordDirectory) | Out-Null
                $record = [ordered]@{
                    Version = 1
                    VideoId = $completed.VideoId
                    Section = $Payload.Section
                    RequestedQuality = $Payload.RequestedQuality
                    Container = $Payload.Container
                    FullPath = $media.FullName
                    Length = $media.Length
                    LastWriteTimeUtcTicks = $media.LastWriteTimeUtc.Ticks
                    VerifiedUtc = [DateTime]::UtcNow.ToString('o')
                    Verification = 'Full ffmpeg decode'
                }
                $recordPath = Join-Path $recordDirectory ($completed.VideoId + '.q' + $Payload.RequestedQuality + '.' + $Payload.Container + '.json')
                $temporaryRecord = $recordPath + '.tmp.' + [Guid]::NewGuid().ToString('N')
                $record | ConvertTo-Json | Set-Content -LiteralPath $temporaryRecord -Encoding UTF8
                Move-Item -LiteralPath $temporaryRecord -Destination $recordPath -Force
                Write-Output ('VERIFIED|' + $completed.VideoId + '|' + $completed.FullPath)
            }
        }
    } catch {
        $message = $_.Exception.Message -replace '[\r\n]+', ' '
        Write-Output ('ENGINE_ERROR|' + $message)
        $exitCode = 1
    }

    Write-Output ('__YBD_EXIT__|' + $exitCode)
}

$active = @{}
$succeeded = 0
$failed = 0
$failures = New-Object System.Collections.Generic.List[object]
$lastDraw = [DateTime]::MinValue
$lastWorkerStart = [DateTime]::MinValue
$workerStartDelaySeconds = $WorkerStartDelaySeconds

try {
    while ($queue.Count -gt 0 -or $active.Count -gt 0) {
        $secondsSinceLastStart = ([DateTime]::UtcNow - $lastWorkerStart).TotalSeconds
        if ($queue.Count -gt 0 -and $active.Count -lt $ParallelDownloads -and $secondsSinceLastStart -ge $workerStartDelaySeconds) {
            $item = $queue.Dequeue()
            $jobTemp = Join-Path $TempRoot ('job_{0:D4}' -f $item.Index)
            [IO.Directory]::CreateDirectory($jobTemp) | Out-Null
            $recordDirectory = Join-Path $verifiedRoot $item.SectionFolder
            $corruptDirectory = Join-Path $corruptRoot $item.SectionFolder

            $arguments = [string[]]@(
                '--no-config',
                '--no-simulate',
                '--quiet',
                '--no-warnings',
                '--progress',
                '--newline',
                '--no-colors',
                '--progress-delta', '0.5',
                '--progress-template', 'download:PROGRESS|%(info.id)s|%(info.title).80B|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s',
                '--print', 'before_dl:START|%(id)s|%(title).80B',
                '--print', 'after_move:DONE|%(id)s|%(filepath)j',
                '--paths', ('home:' + $item.SectionDirectory),
                '--paths', ('temp:' + $jobTemp),
                '--output', $OutputTemplate,
                '--format', $FormatSelector,
                '--merge-output-format', $Container,
                '--remux-video', $Container,
                '--ffmpeg-location', $FfmpegLocation,
                '--js-runtimes', ('deno:' + $Deno),
                '--concurrent-fragments', [string]$ConcurrentFragments,
                '--continue',
                '--no-overwrites',
                $item.Url
            )

            $payload = [pscustomobject]@{
                Executable = $YtDlp
                Arguments = $arguments
                Ffmpeg = $ffmpeg
                Section = $item.Section
                RequestedQuality = $RequestedQuality
                Container = $Container
                RecordPath = Join-Path $recordDirectory 'placeholder.json'
                CorruptDirectory = $corruptDirectory
            }
            $job = Start-Job -ScriptBlock $workerScript -ArgumentList @($payload)
            Write-RunLog ("START job [{0}] [{1}] {2}" -f $item.Index, $item.Section, $item.Url)
            $active[$job.Id] = [pscustomobject]@{
                Job = $job
                Index = $item.Index
                Url = $item.Url
                Section = $item.Section
                Title = $item.Url
                Percent = '--'
                Speed = '--'
                Eta = '--'
                Status = 'Starting'
                LastError = ''
                ExitCode = $null
                TempDirectory = $jobTemp
            }
            $lastWorkerStart = [DateTime]::UtcNow
        }

        foreach ($jobId in @($active.Keys)) {
            $state = $active[$jobId]
            foreach ($outputLine in @(Receive-Job -Job $state.Job -ErrorAction SilentlyContinue)) {
                Write-RunLog ("JOB [{0}] {1}" -f $state.Index, ([string]$outputLine))
                Update-DownloadState -State $state -Line ([string]$outputLine)
            }

            if ($state.Job.State -in @('Completed', 'Failed', 'Stopped')) {
                foreach ($outputLine in @(Receive-Job -Job $state.Job -ErrorAction SilentlyContinue)) {
                    Write-RunLog ("JOB [{0}] {1}" -f $state.Index, ([string]$outputLine))
                    Update-DownloadState -State $state -Line ([string]$outputLine)
                }

                if ($null -eq $state.ExitCode) {
                    $state.ExitCode = if ($state.Job.State -eq 'Completed') { 0 } else { 1 }
                }

                if ($state.ExitCode -eq 0) {
                    $succeeded++
                    Write-RunLog ("SUCCESS job [{0}] [{1}] {2}" -f $state.Index, $state.Section, $state.Url)
                } else {
                    $failed++
                    Write-RunLog ("FAILED job [{0}] [{1}] {2} -- {3}" -f $state.Index, $state.Section, $state.Url, $state.LastError)
                    $failures.Add([pscustomobject]@{
                        Index = $state.Index
                        Url = $state.Url
                        Error = if ($state.LastError) { $state.LastError } else { 'Download or integrity verification failed.' }
                    })
                }

                Remove-Job -Job $state.Job -Force -ErrorAction SilentlyContinue
                $active.Remove($jobId)
                Remove-Item -LiteralPath $state.TempDirectory -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        if (([DateTime]::UtcNow - $lastDraw).TotalMilliseconds -ge 400) {
            Show-Dashboard -Active $active -Total $total -Succeeded $succeeded -Failed $failed -Skipped $skipped -Queued $queue.Count
            $lastDraw = [DateTime]::UtcNow
        }

        if ($queue.Count -gt 0 -or $active.Count -gt 0) {
            Start-Sleep -Milliseconds 150
        }
    }
} finally {
    foreach ($state in @($active.Values)) {
        Stop-Job -Job $state.Job -ErrorAction SilentlyContinue
        Remove-Job -Job $state.Job -Force -ErrorAction SilentlyContinue
    }
}

Show-Dashboard -Active @{} -Total $total -Succeeded $succeeded -Failed $failed -Skipped $skipped -Queued 0
Write-Host ''
if ($failed -eq 0) {
    Write-Host (" Finished successfully: {0} downloaded and verified; {1} already verified and skipped." -f $succeeded, $skipped)
} else {
    Write-Host (" Finished: {0} downloaded and verified; {1} skipped; {2} failed." -f $succeeded, $skipped, $failed)
    foreach ($failure in $failures) {
        Write-Host ("  [{0}] {1}" -f $failure.Index, (Get-ShortText $failure.Url 90))
        Write-Host ("      {0}" -f (Get-ShortText $failure.Error 100))
    }
}
Write-Host (" Detailed log: {0}" -f $runLog)
Write-RunLog ("Run finished. Downloaded and verified: {0}; skipped: {1}; failed: {2}." -f $succeeded, $skipped, $failed)

if ($failed -gt 0) {
    exit 1
}
exit 0
