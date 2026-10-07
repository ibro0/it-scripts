# RDP Shortcut Forge

RDP Shortcut Forge is a Windows console utility for saving Remote Desktop
connection profiles, creating desktop shortcuts, and regenerating those
shortcuts later. It is designed to run without administrator rights.

Passwords are never written to `db.json`, `config.json`, shortcuts, or log
files.

## How to run it

1. Open the RDP Shortcut Forge folder.
2. Double-click `RDPShortcutForge.bat`.
3. Choose an option from the numbered menu.

The BAT file applies PowerShell's execution-policy bypass only to the
PowerShell process it starts. It does not change the machine or user execution
policy.

The menu is grouped into Profiles, Shortcuts, Credentials, and System sections.
Its status line shows profile count, shortcut count, credential count, default
identity, and shortcut folder.

The main menu numbering is:

1. Add new RDP profile
2. List or rename saved profiles
3. Delete saved profile
4. Manage shortcuts for saved profile
5. Regenerate all shortcuts
6. Connect now (no shortcut)
7. Add or update credential only
8. Open project folder
9. Exit

## Profiles, shortcuts, and credentials

Connection details are stored in `db.json`. A profile contains its friendly
name, IPv4 address, domain, username, preferred display mode, shortcut name
stem, shortcut entries, and timestamps. It never contains a password.

Each profile can now own multiple shortcuts at the same time. Shortcut identity
is profile plus mode:

- `FullScreen` uses the bare stem, for example `PC01.lnk`.
- `Windowed` appends `-Windowed`, for example `PC01-Windowed.lnk`.
- `AllMonitors` appends `-All_Monitors`, for example
  `PC01-All_Monitors.lnk`.

The legacy `DisplayMode` field remains the profile's preferred/default mode.
The legacy `ShortcutName` field remains the filename stem. New builds also
write a `Shortcuts` array with each configured mode and exact `FileBaseName`.
Legacy databases are migrated on load without renaming existing `.lnk` files.

Profile tables include **Cred?** and **Modes** columns. **Modes** shows `W`,
`F`, and `M` for Windowed, FullScreen, and AllMonitors:

- `✓` means the shortcut is configured and the file exists.
- `·` means it is configured but the file is missing.
- `-` means that mode is not configured for the profile.

When you choose to save a credential, the password prompt is hidden and the tool
passes the credential directly to Windows Credential Manager using this target:

```text
TERMSRV/<IP address>
```

Windows stores the result in Credential Manager for the current user. You can
inspect it in **Control Panel > Credential Manager > Windows Credentials**.
The tool writes credentials through the Windows `CredWrite` API from a
temporary unmanaged memory buffer, clears that buffer immediately afterward,
and never places the password on a child process command line.

## Creating and managing shortcuts

Choose **Add new RDP profile** to create a profile. The display mode prompt
accepts a single mode or multiple modes such as `1,3` or `1 2 3`; all selected
shortcuts are configured and can be created in one pass. If another profile
already uses the same IP address, the tool prints a note and still allows the
new profile. Duplicate friendly names still offer the update flow.

Choose **Manage shortcuts for saved profile** to:

- add a missing display mode
- regenerate one shortcut
- regenerate all shortcuts for that profile
- remove one shortcut and its matching DB entry
- set the profile's default mode

Choose **Regenerate all shortcuts** to recreate every configured shortcut for
every profile. It does not ask for a global display-mode override; each shortcut
keeps its own stored mode and filename.

Choose **Connect now (no shortcut)** to launch Remote Desktop with a selected
profile and a chosen display mode. Press Enter at the mode picker to use the
profile default.

Renaming a profile can also rename the shortcut stem. Existing shortcut files
are moved in place from their old exact filenames to their new exact filenames.
No sibling mode shortcuts are deleted during creation, regeneration, or rename.

Deleting a profile removes it from `db.json`, then lists that profile's exact
configured shortcut files before asking whether to delete them. It never deletes
shortcut variants by wildcard or shared base name.

## Display modes

- **Windowed**: opens an explicitly sized RDP window using
  `/v:<IP> /w:<width> /h:<height>`. The default size is 1280x720.
- **Full screen single monitor**: uses `/f /v:<IP>`.
- **All monitors (multi-monitor)**: uses `/multimon /v:<IP>`. Each local
  monitor becomes an independent remote display. The tool does not use `/span`.

The internal mode values in `db.json` are `Windowed`, `FullScreen`, and
`AllMonitors`.

## Configuration and recovery

`config.json` controls the default domain, username, shortcut folder, display
mode, path to `mstsc.exe`, and windowed dimensions. `WindowedWidth` defaults to
`1280` and accepts `640` through `7680`; `WindowedHeight` defaults to `720` and
accepts `480` through `4320`. Invalid values fall back to those defaults.
Missing configuration keys and missing configuration or database files are
created automatically.

If `config.json` is malformed, it is renamed with a timestamp and replaced with
defaults. If `db.json` is unparseable at the root, it is backed up and replaced
with an empty database. If individual database records are unreadable, the
original DB is backed up, bad records are skipped with a warning, and readable
profiles are kept.

## Troubleshooting

- **PowerShell reports that the script cannot run:** start the tool through
  `RDPShortcutForge.bat`, which uses a process-only execution-policy bypass.
- **Remote Desktop cannot be found:** verify `MstscPath` in `config.json`. The
  default is `C:\Windows\System32\mstsc.exe`.
- **The shortcut is not on the expected Desktop:** Windows may redirect Desktop
  to OneDrive. The default `ShortcutFolder` asks Windows for the current user's
  actual Desktop path.
- **A credential does not work:** choose **Add or update credential only**,
  select the profile, and enter the password again. Confirm that the stored
  domain and username are correct.
- **A shortcut name is rejected:** remove Windows-invalid filename characters
  (`\ / : * ? " < > |`), trailing spaces, or trailing periods. The tool checks
  resolved filenames across all profiles and all modes, not just the raw stem.
- **Multi-monitor disconnects with error `0x3` / extended error `0x11`:** if a
  host disconnects `/multimon` sessions while single-screen sessions work,
  check the host registry key
  `HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services`. Remove
  `AVCHardwareEncodePreferred`, `AVC444ModePreferred`, and
  `bEnumerateHWBeforeSW`, then sign out and reconnect.

## Test checklist

1. Run the BAT file.
2. Add a new profile with display modes `1,2,3`.
3. Create the shortcuts and confirm all three `.lnk` files exist together.
4. Open each shortcut and confirm Remote Desktop launches with the expected
   display mode.
5. Regenerate all shortcuts and confirm file count does not change.
6. Rename the profile and shortcut stem, then confirm shortcuts were moved in
   place.
7. Use **Manage shortcuts for saved profile** to remove one mode.
8. Open `db.json` and confirm no password exists inside it.
9. Delete a profile and confirm the exact listed shortcuts are removed only
   after confirmation.
