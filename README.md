# it-scripts

Small Windows and IT utility scripts I use in my home lab.

| Folder | Description |
|---|---|
| `rdp-shortcut-forge/` | Manage RDP connection profiles, create `.lnk` shortcuts, and store credentials in Windows Credential Manager. |
| `system-monitor/` | System-tray monitor that alerts on CPU throttling, high temperature, and high RAM usage. |
| `youtube-batch-downloader/` | Parallel yt-dlp/FFmpeg wrapper that downloads a TXT list of videos into organised folders. |
| `word-language-fix/` | Repairs Arabic and English proofing-language tags in `.docx` files. |

## Requirements

- Windows 10 / Windows Server 2019 or later
- PowerShell 5.1+ (included with Windows)
- Python 3.7+ (system-monitor only)
- yt-dlp, FFmpeg, and Deno (youtube-batch-downloader — see its README)

## Safety notice

Review every script before running it. These scripts are provided as-is,
without warranty. Use at your own risk.

## Licence

MIT — see [LICENSE](LICENSE).

## Links

- https://openmega.net
