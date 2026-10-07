# Changelog

## 2026-07-17 - v1.2 multi-mode shortcut coexistence

- Fixed multi-mode shortcut deletion. Root cause: `New-RdpShortcut` removed all
  sibling variant paths after saving one shortcut. Fix: shortcut creation now
  writes exactly one `.lnk` and never deletes sibling modes.
- Added per-profile `Shortcuts` array. Root cause: the old schema stored one
  scalar `DisplayMode` and one scalar `ShortcutName`, so one profile could not
  represent multiple shortcuts. Fix: each shortcut entry stores `Mode`,
  `FileBaseName`, `CreatedAt`, and `UpdatedAt` while preserving legacy fields.
- Added legacy migration. Root cause: old records had no shortcut-entry list and
  PS 5.1 can unwrap single-element JSON arrays. Fix: normalization wraps nested
  shortcut data with `@()`, synthesizes one legacy entry when needed, drops
  invalid modes, and dedupes duplicate modes by newest `UpdatedAt`.
- Fixed same-IP profile blocking. Root cause: add-profile matched duplicate
  name or duplicate IP as the same overwrite condition. Fix: duplicate names
  keep the update flow; duplicate IPs print a note and are allowed.
- Fixed update-path shortcut stem drift. Root cause: updating a matching profile
  defaulted the shortcut name prompt to the new friendly name, not the stored
  stem. Fix: update prompts default to the matched profile's existing
  `ShortcutName`.
- Fixed filename collision checks. Root cause: uniqueness compared raw
  `ShortcutName` values while runtime paths were keyed by stripped/generated
  filenames. Fix: the prompt checks resolved filenames across all profiles and
  all modes, names the owning profile, and suggests a free stem.
- Fixed rename data loss. Root cause: rename deleted every old variant before
  asking whether to regenerate. Fix: rename is an in-place exact-path move for
  each stored shortcut entry and no-ops when the stem is unchanged.
- Fixed profile delete overreach. Root cause: delete used base-name variant
  deletion. Fix: delete lists and removes only exact paths from the selected
  profile's own shortcut entries.
- Reworked shortcut management. Root cause: the old create-shortcut menu stored
  one mode and had no single-shortcut delete path. Fix: the menu now adds
  missing modes, regenerates one/all shortcuts for a profile, removes one exact
  shortcut plus its DB entry, and sets the default mode.
- Reworked regenerate-all. Root cause: a global mode override was destructive
  under a multi-mode model. Fix: regenerate-all iterates every profile shortcut
  entry with its own stored mode and filename and reports shortcut/profile
  counts.
- Fixed database recovery. Root cause: any exception during database load caused
  a full backup-and-empty reset, and empty raw content could throw under
  StrictMode. Fix: root parse errors still reset with backup, empty DB loads as
  empty, and unreadable records are skipped individually after backing up the
  original DB.
- Removed dead credential test code. Root cause: `Test-RdpCredential` was no
  longer called and used locale-sensitive output heuristics. Fix: deleted it.
- Fixed automatic-variable shadowing. Root cause: `Get-RdpCredentialTargets`
  assigned to `$matches`, shadowing PowerShell's `$Matches`. Fix: renamed local
  variables to `$targetMatches` and `$targetMatch`.
- Limited legacy suffix stripping. Root cause: generated/deletion logic treated
  suffixes like `-All_Screens` and `-Windowed` as live runtime variants. Fix:
  suffix stripping is now legacy migration only; runtime path derivation uses
  stored `FileBaseName`.
- Fixed mode presence display. Root cause: `Show-Profiles` checked only one
  current-mode path. Fix: the table now shows `W/F/M` with present, missing, and
  unconfigured status.
- Fixed mutation contract inconsistency. Root cause: shortcut-management and
  regenerate-all mutated arrays without returning them. Fix: both now return the
  profile array and the main loop assigns it.
- Added connect-mode picker. Root cause: connect-now always used the stored
  default mode. Fix: it now prompts for mode with Enter selecting the profile
  default.
- Added an import-only guard for automated verification. Root cause: the script
  could not be dot-sourced for tests without entering the menu loop. Fix: setting
  `RDP_SHORTCUT_FORGE_IMPORT_ONLY=1` loads functions without launching the app;
  the BAT launcher is unchanged.
