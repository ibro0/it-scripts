# YouTube Batch Downloader

Run `YouTube_Batch_Downloader.bat`, then drag a TXT link list into the window
(or paste its path). The app downloads up to four URLs at the same time and
creates a folder for every `# Folder Name` heading.

## Prerequisites

This tool expects the following executables in a folder named
`.youtube-downloader-tools/` next to the BAT file:

- `yt-dlp.exe` — https://github.com/yt-dlp/yt-dlp
- `ffmpeg.exe` — https://ffmpeg.org
- `ffprobe.exe` (shipped with FFmpeg)
- `deno.exe` — https://github.com/denoland/deno/releases

On first run the BAT offers to download these for you. If you prefer to
install them yourself, place the four executables directly inside
`.youtube-downloader-tools/`.

## Link-list format

```text
## Lines starting with ## are comments and are ignored.

# Cars
https://www.youtube.com/watch?v=...
https://www.youtube.com/watch?v=...

# Home
https://www.youtube.com/watch?v=...
https://www.youtube.com/playlist?list=...
```

Each URL must be on its own line. Video and playlist URLs are supported. URLs
above the first folder heading are saved under `Uncategorized`. The BAT can
create a fully documented example file for you.

Downloads are checked with FFmpeg, completed items are remembered, and
detailed logs are written beneath the chosen destination.

## Legal notice

Users are responsible for complying with YouTube's Terms of Service
(https://www.youtube.com/t/terms) and applicable copyright law in their
jurisdiction. Download content only when you have the right to do so.
