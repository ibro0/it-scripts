@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "APP_NAME=YouTube Batch Downloader"
set "APP_DIR=%~dp0"
set "CONFIG_FILE=%APP_DIR%YouTube_Batch_Downloader.conf"
set "TOOLS_DIR=%APP_DIR%.youtube-downloader-tools"
set "YTDLP=%TOOLS_DIR%\yt-dlp.exe"
set "DENO=%TOOLS_DIR%\deno.exe"
set "FFMPEG=%TOOLS_DIR%\ffmpeg.exe"
set "FFPROBE=%TOOLS_DIR%\ffprobe.exe"
set "ENGINE=%APP_DIR%YouTube_Download_Engine.ps1"
set "SETUP_LOCK=%TOOLS_DIR%\setup.lock"
set "UPDATE_LOCK=%TOOLS_DIR%\update.lock"
set "INSTANCE_ID=%RANDOM%_%RANDOM%_%RANDOM%"

title %APP_NAME% - %INSTANCE_ID%

call :LoadConfig
if errorlevel 1 (
    echo.
    echo ERROR: The configuration could not be loaded.
    pause
    exit /b 1
)

:MainMenu
cls
echo ============================================================
echo  %APP_NAME%
echo ============================================================
echo.
echo  [1] Start a download job
echo  [2] Edit settings
echo  [3] Exit
echo.
choice /C 123 /N /M "Choose an option [1-3]: "
if errorlevel 3 exit /b 0
if errorlevel 2 goto SettingsMenu
goto StartJob

:SettingsMenu
call :LoadConfig
cls
echo ============================================================
echo  Interactive settings
echo ============================================================
echo.
echo  Current settings
echo  Default save folder: "%DEFAULT_SAVE_DIR%"
echo  Default quality:     %DEFAULT_QUALITY%p
echo  Fragments per video: %CONCURRENT_FRAGMENTS%
echo  Simultaneous videos: %PARALLEL_DOWNLOADS%
echo  Output container:    %OUTPUT_CONTAINER%
echo  Auto-update yt-dlp:  %AUTO_UPDATE_YTDLP%
echo  Filename template:
set OUTPUT_TEMPLATE
echo.
echo  [1] Change default save folder
echo  [2] Change default quality
echo  [3] Change fragments per video
echo  [4] Change simultaneous videos
echo  [5] Change output container
echo  [6] Change filename layout
echo  [7] Toggle yt-dlp auto-update
echo  [8] Reset all settings
echo  [9] Back to main menu
echo.
choice /C 123456789 /N /M "Choose a setting [1-9]: "
if errorlevel 9 goto MainMenu
if errorlevel 8 goto ResetSettings
if errorlevel 7 goto ToggleAutoUpdate
if errorlevel 6 goto NameMenu
if errorlevel 5 goto SetContainer
if errorlevel 4 goto SetParallelDownloads
if errorlevel 3 goto SetFragments
if errorlevel 2 goto SetDefaultQuality
goto SetDefaultSaveDir

:SetDefaultSaveDir
echo.
set "NEW_SAVE_DIR="
set /p "NEW_SAVE_DIR=New default save folder (blank cancels): "
if not defined NEW_SAVE_DIR goto SettingsMenu
set "NEW_SAVE_DIR=%NEW_SAVE_DIR:"=%"
for %%I in ("%NEW_SAVE_DIR%") do set "DEFAULT_SAVE_DIR=%%~fI"
goto SaveSetting

:SetDefaultQuality
echo.
echo  [1] 1080p
echo  [2] 720p
choice /C 12 /N /M "Choose the default quality [1-2]: "
if errorlevel 2 goto SetDefaultQuality720
set "DEFAULT_QUALITY=1080"
goto SaveSetting

:SetDefaultQuality720
set "DEFAULT_QUALITY=720"
goto SaveSetting

:SetFragments
echo.
set "NEW_FRAGMENTS="
set /p "NEW_FRAGMENTS=Parallel fragments per video [1-32] (blank cancels): "
if not defined NEW_FRAGMENTS goto SettingsMenu
set "NORMALIZED_FRAGMENTS="
for /f "tokens=* delims= " %%N in ("%NEW_FRAGMENTS%") do set "NORMALIZED_FRAGMENTS=%%N"
if not defined NORMALIZED_FRAGMENTS goto InvalidFragments
set "NEW_FRAGMENTS=%NORMALIZED_FRAGMENTS%"
set "NON_NUMERIC="
for /f "delims=0123456789" %%N in ("%NEW_FRAGMENTS%") do set "NON_NUMERIC=%%N"
if defined NON_NUMERIC goto InvalidFragments
if not "%NEW_FRAGMENTS:~2,1%"=="" goto InvalidFragments
if "%NEW_FRAGMENTS%"=="0" goto InvalidFragments
if %NEW_FRAGMENTS% GTR 32 goto InvalidFragments
set "CONCURRENT_FRAGMENTS=%NEW_FRAGMENTS%"
goto SaveSetting

:InvalidFragments
echo Please enter a number from 1 through 32.
pause
goto SetFragments

:SetParallelDownloads
echo.
set "NEW_PARALLEL="
set /p "NEW_PARALLEL=Videos to download simultaneously [1-4] (blank cancels): "
if not defined NEW_PARALLEL goto SettingsMenu
set "NORMALIZED_PARALLEL="
for /f "tokens=* delims= " %%N in ("%NEW_PARALLEL%") do set "NORMALIZED_PARALLEL=%%N"
if not defined NORMALIZED_PARALLEL goto InvalidParallel
set "NEW_PARALLEL=%NORMALIZED_PARALLEL%"
set "NON_NUMERIC="
for /f "delims=0123456789" %%N in ("%NEW_PARALLEL%") do set "NON_NUMERIC=%%N"
if defined NON_NUMERIC goto InvalidParallel
if not "%NEW_PARALLEL:~1,1%"=="" goto InvalidParallel
if "%NEW_PARALLEL%"=="0" goto InvalidParallel
if %NEW_PARALLEL% GTR 4 goto InvalidParallel
set "PARALLEL_DOWNLOADS=%NEW_PARALLEL%"
goto SaveSetting

:InvalidParallel
echo Please enter a number from 1 through 4.
pause
goto SetParallelDownloads

:SetContainer
echo.
echo  [1] MP4
echo  [2] MKV
choice /C 12 /N /M "Choose the output container [1-2]: "
if errorlevel 2 goto SetContainerMkv
set "OUTPUT_CONTAINER=mp4"
goto SaveSetting

:SetContainerMkv
set "OUTPUT_CONTAINER=mkv"
goto SaveSetting

:NameMenu
echo.
echo  [1] Title [video ID] [quality]
echo  [2] Uploader folder\Title [video ID] [quality]
echo  [3] Playlist folder\index - Title [video ID] [quality]
choice /C 123 /N /M "Choose the filename layout [1-3]: "
if errorlevel 3 goto SetLayoutPlaylist
if errorlevel 2 goto SetLayoutUploader
set "OUTPUT_TEMPLATE=%%(title).150B [%%(id)s] [%%(height)sp].%%(ext)s"
goto SaveSetting

:SetLayoutUploader
set "OUTPUT_TEMPLATE=%%(uploader|Unknown Uploader).80B\%%(title).140B [%%(id)s] [%%(height)sp].%%(ext)s"
goto SaveSetting

:SetLayoutPlaylist
set "OUTPUT_TEMPLATE=%%(playlist_title|Single Videos).80B\%%(playlist_index)03d - %%(title).120B [%%(id)s] [%%(height)sp].%%(ext)s"
goto SaveSetting

:ToggleAutoUpdate
if "%AUTO_UPDATE_YTDLP%"=="1" goto DisableAutoUpdate
set "AUTO_UPDATE_YTDLP=1"
goto SaveSetting

:DisableAutoUpdate
set "AUTO_UPDATE_YTDLP=0"
goto SaveSetting

:ResetSettings
echo.
choice /C YN /N /M "Reset every setting to its default? [Y/N]: "
if errorlevel 2 goto SettingsMenu
set "DEFAULT_SAVE_DIR=C:\Projects"
set "DEFAULT_QUALITY=1080"
set "CONCURRENT_FRAGMENTS=4"
set "PARALLEL_DOWNLOADS=4"
set "OUTPUT_CONTAINER=mp4"
set "OUTPUT_TEMPLATE=%%(title).150B [%%(id)s] [%%(height)sp].%%(ext)s"
set "AUTO_UPDATE_YTDLP=1"
goto SaveSetting

:SaveSetting
call :SaveConfig
if errorlevel 1 (
    echo.
    echo ERROR: The setting could not be saved.
    pause
)
goto SettingsMenu

:StartJob
cls
echo ============================================================
echo  New download job
echo ============================================================
echo.

:AskSource
echo  Source-list format: use # Folder Name, followed by one URL per line.
echo.
choice /C YN /N /M "Create an example TXT file with instructions? [Y/N]: "
if errorlevel 2 goto PromptForSource
call :CreateExampleList
if errorlevel 1 (
    echo ERROR: The example file could not be created.
) else (
    echo Example created: "%EXAMPLE_FILE%"
    echo Edit it, save it, then return here.
    start "" notepad.exe "%EXAMPLE_FILE%"
)
echo.

:PromptForSource
set "SOURCE_FILE="
set /p "SOURCE_FILE=Paste or drag the source TXT file here: "
set "SOURCE_FILE=%SOURCE_FILE:"=%"
if not defined SOURCE_FILE (
    echo Please enter a file path.
    echo.
    goto PromptForSource
)
for %%I in ("%SOURCE_FILE%") do set "SOURCE_FILE=%%~fI"
if not exist "%SOURCE_FILE%" (
    echo File not found: "%SOURCE_FILE%"
    echo.
    goto PromptForSource
)
if exist "%SOURCE_FILE%\*" (
    echo Please select a TXT file, not a folder.
    echo.
    goto PromptForSource
)

:AskSaveDir
echo.
set "SAVE_DIR="
set /p "SAVE_DIR=Save folder [%DEFAULT_SAVE_DIR%]: "
if not defined SAVE_DIR set "SAVE_DIR=%DEFAULT_SAVE_DIR%"
set "SAVE_DIR=%SAVE_DIR:"=%"
for %%I in ("%SAVE_DIR%") do set "SAVE_DIR=%%~fI"
if not exist "%SAVE_DIR%\" md "%SAVE_DIR%" 2>nul
if not exist "%SAVE_DIR%\" (
    echo Could not create or access: "%SAVE_DIR%"
    goto AskSaveDir
)

:AskQuality
echo.
set "QUALITY="
set /p "QUALITY=Maximum quality, 1080 or 720 [%DEFAULT_QUALITY%]: "
if not defined QUALITY set "QUALITY=%DEFAULT_QUALITY%"
if "%QUALITY%"=="1080" goto InputsReady
if "%QUALITY%"=="720" goto InputsReady
echo Please enter only 1080 or 720.
goto AskQuality

:InputsReady
echo.
echo Source:      "%SOURCE_FILE%"
echo Destination: "%SAVE_DIR%"
echo Quality:     %QUALITY%p maximum
echo.

call :EnsureTools
if errorlevel 1 (
    echo.
    echo ERROR: Required tools could not be prepared.
    echo Check the internet connection and try again.
    pause
    goto MainMenu
)
if not exist "%ENGINE%" (
    echo.
    echo ERROR: Missing download engine:
    echo "%ENGINE%"
    pause
    goto MainMenu
)

set "INSTANCE_TEMP=%TEMP%\YouTubeBatchDownloader_%INSTANCE_ID%_%RANDOM%"
md "%INSTANCE_TEMP%" 2>nul
if not exist "%INSTANCE_TEMP%\" (
    echo ERROR: Could not create the temporary folder.
    pause
    goto MainMenu
)

if /I "%OUTPUT_CONTAINER%"=="mp4" (
    set "FORMAT_SELECTOR=bv*[height<=%QUALITY%][ext=mp4]+ba[ext=m4a]/b[height<=%QUALITY%][ext=mp4]/bv*[height<=%QUALITY%]+ba/b[height<=%QUALITY%]"
) else (
    set "FORMAT_SELECTOR=bv*[height<=%QUALITY%]+ba/b[height<=%QUALITY%]"
)

echo.
echo Starting parallel download dashboard...
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" ^
    -YtDlp "%YTDLP%" ^
    -SourceFile "%SOURCE_FILE%" ^
    -SaveDirectory "%SAVE_DIR%" ^
    -TempRoot "%INSTANCE_TEMP%" ^
    -OutputTemplate "%OUTPUT_TEMPLATE%" ^
    -FormatSelector "%FORMAT_SELECTOR%" ^
    -Container "%OUTPUT_CONTAINER%" ^
    -FfmpegLocation "%TOOLS_DIR%" ^
    -Deno "%DENO%" ^
    -RequestedQuality "%QUALITY%" ^
    -ConcurrentFragments "%CONCURRENT_FRAGMENTS%" ^
    -ParallelDownloads "%PARALLEL_DOWNLOADS%"

set "DOWNLOAD_RESULT=%ERRORLEVEL%"
2>nul rd "%INSTANCE_TEMP%"

echo.
if "%DOWNLOAD_RESULT%"=="0" (
    echo Download job finished.
) else (
    echo Download job finished with one or more errors.
)
echo Files are in: "%SAVE_DIR%"
echo.
pause
goto MainMenu

:LoadConfig
set "DEFAULT_SAVE_DIR=C:\Projects"
set "DEFAULT_QUALITY=1080"
set "CONCURRENT_FRAGMENTS=4"
set "PARALLEL_DOWNLOADS=4"
set "OUTPUT_CONTAINER=mp4"
set "OUTPUT_TEMPLATE=%%(title).150B [%%(id)s] [%%(height)sp].%%(ext)s"
set "AUTO_UPDATE_YTDLP=1"

if not exist "%CONFIG_FILE%" call :CreateDefaultConfig
if not exist "%CONFIG_FILE%" exit /b 1

for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
    if /I "%%A"=="DEFAULT_SAVE_DIR" set "DEFAULT_SAVE_DIR=%%B"
    if /I "%%A"=="DEFAULT_QUALITY" set "DEFAULT_QUALITY=%%B"
    if /I "%%A"=="CONCURRENT_FRAGMENTS" set "CONCURRENT_FRAGMENTS=%%B"
    if /I "%%A"=="PARALLEL_DOWNLOADS" set "PARALLEL_DOWNLOADS=%%B"
    if /I "%%A"=="OUTPUT_CONTAINER" set "OUTPUT_CONTAINER=%%B"
    if /I "%%A"=="OUTPUT_TEMPLATE" set "OUTPUT_TEMPLATE=%%B"
    if /I "%%A"=="AUTO_UPDATE_YTDLP" set "AUTO_UPDATE_YTDLP=%%B"
)

if not defined DEFAULT_SAVE_DIR set "DEFAULT_SAVE_DIR=C:\Projects"
if not "%DEFAULT_QUALITY%"=="1080" if not "%DEFAULT_QUALITY%"=="720" set "DEFAULT_QUALITY=1080"
if /I not "%OUTPUT_CONTAINER%"=="mp4" if /I not "%OUTPUT_CONTAINER%"=="mkv" set "OUTPUT_CONTAINER=mp4"
if not defined OUTPUT_TEMPLATE set "OUTPUT_TEMPLATE=%%(title).150B [%%(id)s] [%%(height)sp].%%(ext)s"
if not "%AUTO_UPDATE_YTDLP%"=="0" if not "%AUTO_UPDATE_YTDLP%"=="1" set "AUTO_UPDATE_YTDLP=1"

set "NORMALIZED_FRAGMENTS="
for /f "tokens=* delims= " %%N in ("%CONCURRENT_FRAGMENTS%") do set "NORMALIZED_FRAGMENTS=%%N"
if defined NORMALIZED_FRAGMENTS set "CONCURRENT_FRAGMENTS=%NORMALIZED_FRAGMENTS%"
if not defined NORMALIZED_FRAGMENTS set "CONCURRENT_FRAGMENTS=4"
set "NON_NUMERIC="
for /f "delims=0123456789" %%N in ("%CONCURRENT_FRAGMENTS%") do set "NON_NUMERIC=%%N"
if defined NON_NUMERIC set "CONCURRENT_FRAGMENTS=4"
if not "%CONCURRENT_FRAGMENTS:~2,1%"=="" set "CONCURRENT_FRAGMENTS=4"
if "%CONCURRENT_FRAGMENTS%"=="0" set "CONCURRENT_FRAGMENTS=4"
if %CONCURRENT_FRAGMENTS% GTR 32 set "CONCURRENT_FRAGMENTS=32"

set "NORMALIZED_PARALLEL="
for /f "tokens=* delims= " %%N in ("%PARALLEL_DOWNLOADS%") do set "NORMALIZED_PARALLEL=%%N"
if defined NORMALIZED_PARALLEL set "PARALLEL_DOWNLOADS=%NORMALIZED_PARALLEL%"
if not defined NORMALIZED_PARALLEL set "PARALLEL_DOWNLOADS=4"
set "NON_NUMERIC="
for /f "delims=0123456789" %%N in ("%PARALLEL_DOWNLOADS%") do set "NON_NUMERIC=%%N"
if defined NON_NUMERIC set "PARALLEL_DOWNLOADS=4"
if not "%PARALLEL_DOWNLOADS:~1,1%"=="" set "PARALLEL_DOWNLOADS=4"
if "%PARALLEL_DOWNLOADS%"=="0" set "PARALLEL_DOWNLOADS=4"
if %PARALLEL_DOWNLOADS% GTR 4 set "PARALLEL_DOWNLOADS=4"
exit /b 0

:CreateDefaultConfig
call :SaveConfig
exit /b %ERRORLEVEL%

:CreateExampleList
set "EXAMPLE_FILE=%APP_DIR%Example Video List.txt"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
    "$lines=[string[]]@(" ^
    "'## YOUTUBE BATCH DOWNLOADER - LINK LIST INSTRUCTIONS'," ^
    "'##'," ^
    "'## Put a folder heading on a line by itself: # Folder Name'," ^
    "'## Put each video or playlist URL on its own line below that heading.'," ^
    "'## The downloader creates one folder per heading and saves its videos there.'," ^
    "'## Use more # headings to organize additional groups. Blank lines are allowed.'," ^
    "'## Lines beginning with ## are instructions/comments and are ignored.'," ^
    "'## URLs before the first folder heading go into an Uncategorized folder.'," ^
    "'## You can give this file to a friend or AI agent and ask them to organize links'," ^
    "'## into this exact format without changing the URLs.'," ^
    "''," ^
    "'# Cars'," ^
    "'https://www.youtube.com/watch?v=VIDEO_ID_1'," ^
    "'https://www.youtube.com/playlist?list=PLAYLIST_ID_1'," ^
    "''," ^
    "'# Home'," ^
    "'https://www.youtube.com/watch?v=VIDEO_ID_2'," ^
    "'https://youtu.be/VIDEO_ID_3'" ^
    ");" ^
    "$utf8=New-Object System.Text.UTF8Encoding($false);" ^
    "[IO.File]::WriteAllLines($env:EXAMPLE_FILE,$lines,$utf8)"
exit /b %ERRORLEVEL%

:SaveConfig
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
    "$lines=[string[]]@(" ^
    "'# YouTube Batch Downloader settings - managed by the BAT interactive menu'," ^
    "'# Do not add spaces around the equals sign.'," ^
    "''," ^
    "('DEFAULT_SAVE_DIR=' + $env:DEFAULT_SAVE_DIR)," ^
    "('DEFAULT_QUALITY=' + $env:DEFAULT_QUALITY)," ^
    "('CONCURRENT_FRAGMENTS=' + $env:CONCURRENT_FRAGMENTS)," ^
    "('PARALLEL_DOWNLOADS=' + $env:PARALLEL_DOWNLOADS)," ^
    "('OUTPUT_CONTAINER=' + $env:OUTPUT_CONTAINER)," ^
    "('OUTPUT_TEMPLATE=' + $env:OUTPUT_TEMPLATE)," ^
    "('AUTO_UPDATE_YTDLP=' + $env:AUTO_UPDATE_YTDLP)" ^
    ");" ^
    "$utf8=New-Object System.Text.UTF8Encoding($false);" ^
    "[IO.File]::WriteAllLines($env:CONFIG_FILE,$lines,$utf8)"
exit /b %ERRORLEVEL%

:EnsureTools
set "TOOLS_JUST_INSTALLED=0"
if not exist "%TOOLS_DIR%\" md "%TOOLS_DIR%" 2>nul
if not exist "%TOOLS_DIR%\" exit /b 1

call :ToolsPresent
if not errorlevel 1 goto ToolsReady

2>nul md "%SETUP_LOCK%"
if errorlevel 1 goto WaitForTools

call :InstallTools
set "INSTALL_RESULT=%ERRORLEVEL%"
2>nul rd "%SETUP_LOCK%"
if not "%INSTALL_RESULT%"=="0" exit /b 1
set "TOOLS_JUST_INSTALLED=1"
goto ToolsReady

:WaitForTools
echo Another instance is preparing the shared tools. Waiting...
set "WAIT_COUNT=0"

:WaitForToolsLoop
call :ToolsPresent
if not errorlevel 1 goto ToolsReady
if not exist "%SETUP_LOCK%\" goto EnsureTools
set /a WAIT_COUNT+=1
if %WAIT_COUNT% GEQ 300 (
    echo Timed out while waiting for the other instance.
    exit /b 1
)
timeout /t 2 /nobreak >nul
goto WaitForToolsLoop

:ToolsReady
if "%AUTO_UPDATE_YTDLP%"=="1" if "%TOOLS_JUST_INSTALLED%"=="0" call :UpdateYtdlp
exit /b 0

:ToolsPresent
if not exist "%YTDLP%" exit /b 1
if not exist "%DENO%" exit /b 1
if not exist "%FFMPEG%" exit /b 1
if not exist "%FFPROBE%" exit /b 1
exit /b 0

:InstallTools
set "INSTALL_ID=%INSTANCE_ID%_%RANDOM%"
set "YTDLP_NEW=%TOOLS_DIR%\yt-dlp.%INSTALL_ID%.exe"
set "DENO_NEW=%TOOLS_DIR%\deno.%INSTALL_ID%.exe"
set "FFMPEG_NEW=%TOOLS_DIR%\ffmpeg.%INSTALL_ID%.exe"
set "FFPROBE_NEW=%TOOLS_DIR%\ffprobe.%INSTALL_ID%.exe"
set "DENO_ZIP=%TOOLS_DIR%\deno.%INSTALL_ID%.zip"
set "FFMPEG_ZIP=%TOOLS_DIR%\ffmpeg.%INSTALL_ID%.zip"

echo First-run setup: downloading yt-dlp...
call :DownloadFile "https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp.exe" "%YTDLP_NEW%"
if errorlevel 1 goto InstallFailed
"%YTDLP_NEW%" --version >nul 2>&1
if errorlevel 1 goto InstallFailed

echo First-run setup: downloading Deno...
call :DownloadFile "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip" "%DENO_ZIP%"
if errorlevel 1 goto InstallFailed
call :ExtractZipEntry "%DENO_ZIP%" "deno.exe" "%DENO_NEW%"
if errorlevel 1 goto InstallFailed
"%DENO_NEW%" --version >nul 2>&1
if errorlevel 1 goto InstallFailed

echo First-run setup: downloading FFmpeg. This is the largest download...
call :DownloadFile "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip" "%FFMPEG_ZIP%"
if errorlevel 1 goto InstallFailed
call :ExtractZipEntry "%FFMPEG_ZIP%" "ffmpeg.exe" "%FFMPEG_NEW%"
if errorlevel 1 goto InstallFailed
call :ExtractZipEntry "%FFMPEG_ZIP%" "ffprobe.exe" "%FFPROBE_NEW%"
if errorlevel 1 goto InstallFailed
"%FFMPEG_NEW%" -version >nul 2>&1
if errorlevel 1 goto InstallFailed

move /y "%YTDLP_NEW%" "%YTDLP%" >nul
if errorlevel 1 goto InstallFailed
move /y "%DENO_NEW%" "%DENO%" >nul
if errorlevel 1 goto InstallFailed
move /y "%FFMPEG_NEW%" "%FFMPEG%" >nul
if errorlevel 1 goto InstallFailed
move /y "%FFPROBE_NEW%" "%FFPROBE%" >nul
if errorlevel 1 goto InstallFailed
del /q "%DENO_ZIP%" "%FFMPEG_ZIP%" 2>nul
echo Tool setup complete.
exit /b 0

:InstallFailed
del /q "%YTDLP_NEW%" "%DENO_NEW%" "%FFMPEG_NEW%" "%FFPROBE_NEW%" "%DENO_ZIP%" "%FFMPEG_ZIP%" 2>nul
exit /b 1

:UpdateYtdlp
2>nul md "%UPDATE_LOCK%"
if errorlevel 1 exit /b 0
echo Checking for a yt-dlp update...
"%YTDLP%" -U
2>nul rd "%UPDATE_LOCK%"
exit /b 0

:DownloadFile
set "DOWNLOAD_URL=%~1"
set "DOWNLOAD_DEST=%~2"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop';" ^
    "$ProgressPreference='SilentlyContinue';" ^
    "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
    "Invoke-WebRequest -UseBasicParsing -Uri $env:DOWNLOAD_URL -OutFile $env:DOWNLOAD_DEST"
set "DOWNLOAD_RESULT=%ERRORLEVEL%"
set "DOWNLOAD_URL="
set "DOWNLOAD_DEST="
exit /b %DOWNLOAD_RESULT%

:ExtractZipEntry
set "ARCHIVE_FILE=%~1"
set "ARCHIVE_ENTRY=%~2"
set "EXTRACT_DEST=%~3"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop';" ^
    "Add-Type -AssemblyName System.IO.Compression.FileSystem;" ^
    "$zip=[IO.Compression.ZipFile]::OpenRead($env:ARCHIVE_FILE);" ^
    "try {" ^
    "  $entry=$zip.Entries | Where-Object { $_.Name -ieq $env:ARCHIVE_ENTRY } | Select-Object -First 1;" ^
    "  if (-not $entry) { throw ('Missing archive entry: ' + $env:ARCHIVE_ENTRY) }" ^
    "  $input=$entry.Open();" ^
    "  try {" ^
    "    $output=[IO.File]::Open($env:EXTRACT_DEST,[IO.FileMode]::Create,[IO.FileAccess]::Write);" ^
    "    try { $input.CopyTo($output) } finally { $output.Dispose() }" ^
    "  } finally { $input.Dispose() }" ^
    "} finally { $zip.Dispose() }"
set "EXTRACT_RESULT=%ERRORLEVEL%"
set "ARCHIVE_FILE="
set "ARCHIVE_ENTRY="
set "EXTRACT_DEST="
exit /b %EXTRACT_RESULT%
