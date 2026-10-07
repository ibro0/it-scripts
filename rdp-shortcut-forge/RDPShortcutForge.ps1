[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}
catch {
    # Some non-interactive hosts do not expose a writable console encoding.
}

$script:ProjectFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigPath = Join-Path $script:ProjectFolder 'config.json'
$script:DbPath = Join-Path $script:ProjectFolder 'db.json'
$script:CanonicalProfileFields = @(
    'Name',
    'IpAddress',
    'Domain',
    'Username',
    'DisplayMode',
    'ShortcutName',
    'Shortcuts',
    'CreatedAt',
    'UpdatedAt'
)
$script:ValidDisplayModes = @('Windowed', 'FullScreen', 'AllMonitors')
$script:LegacyShortcutSuffixes = @('-All_Screens', '-All_Monitors', '-Windowed')

function Write-Color {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    Write-Host $Text -ForegroundColor $Color
}

function Get-ObjectPropertyValue {
    param(
        $InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        $DefaultValue = $null
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }

    $propertyInfo = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $propertyInfo) {
        return $DefaultValue
    }

    return $propertyInfo.Value
}

function Get-DisplayModeValue {
    param(
        [string]$Mode,
        [string]$Fallback = 'FullScreen'
    )

    foreach ($validMode in $script:ValidDisplayModes) {
        if ($validMode -ieq $Mode) {
            return $validMode
        }
    }

    foreach ($validMode in $script:ValidDisplayModes) {
        if ($validMode -ieq $Fallback) {
            return $validMode
        }
    }

    return 'FullScreen'
}

function Test-DisplayMode {
    param([string]$Mode)

    foreach ($validMode in $script:ValidDisplayModes) {
        if ($validMode -ieq $Mode) {
            return $true
        }
    }

    return $false
}

function Get-ShortcutFileBaseName {
    param(
        [Parameter(Mandatory = $true)][string]$Stem,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    $displayMode = Get-DisplayModeValue -Mode $Mode -Fallback 'FullScreen'
    switch ($displayMode) {
        'Windowed' { return ("{0}-Windowed" -f $Stem) }
        'AllMonitors' { return ("{0}-All_Monitors" -f $Stem) }
        default { return $Stem }
    }
}

function Get-LegacyBaseShortcutName {
    param([Parameter(Mandatory = $true)][string]$ShortcutName)

    $baseName = $ShortcutName
    foreach ($suffix in $script:LegacyShortcutSuffixes) {
        if ($baseName.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase)) {
            $baseName = $baseName.Substring(0, $baseName.Length - $suffix.Length)
            break
        }
    }

    return $baseName
}

function Get-LegacyShortcutFileBaseName {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutName,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    $baseName = Get-LegacyBaseShortcutName -ShortcutName $ShortcutName
    return Get-ShortcutFileBaseName -Stem $baseName -Mode $Mode
}

function Get-DateSortValue {
    param([string]$Value)

    $parsedDate = [datetime]::MinValue
    if ([datetime]::TryParse($Value, [ref]$parsedDate)) {
        return $parsedDate
    }

    return [datetime]::MinValue
}

function New-RdpShortcutEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string]$FileBaseName,
        [Parameter(Mandatory = $true)][string]$CreatedAt,
        [Parameter(Mandatory = $true)][string]$UpdatedAt
    )

    return [pscustomobject][ordered]@{
        Mode         = (Get-DisplayModeValue -Mode $Mode -Fallback 'FullScreen')
        FileBaseName = $FileBaseName
        CreatedAt    = $CreatedAt
        UpdatedAt    = $UpdatedAt
    }
}

function ConvertTo-RdpShortcutEntry {
    param(
        $InputObject,
        [Parameter(Mandatory = $true)][string]$DefaultStem,
        [Parameter(Mandatory = $true)][string]$Now
    )

    $rawMode = [string](Get-ObjectPropertyValue -InputObject $InputObject -Name 'Mode' -DefaultValue '')
    if (-not (Test-DisplayMode -Mode $rawMode)) {
        return $null
    }

    $displayMode = Get-DisplayModeValue -Mode $rawMode -Fallback 'FullScreen'
    $fileBaseName = [string](Get-ObjectPropertyValue -InputObject $InputObject -Name 'FileBaseName' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($fileBaseName)) {
        $fileBaseName = Get-ShortcutFileBaseName -Stem $DefaultStem -Mode $displayMode
    }

    if (-not (Test-ShortcutName -Name $fileBaseName)) {
        return $null
    }

    $createdAt = [string](Get-ObjectPropertyValue -InputObject $InputObject -Name 'CreatedAt' -DefaultValue $Now)
    if ([string]::IsNullOrWhiteSpace($createdAt)) {
        $createdAt = $Now
    }

    $updatedAt = [string](Get-ObjectPropertyValue -InputObject $InputObject -Name 'UpdatedAt' -DefaultValue $Now)
    if ([string]::IsNullOrWhiteSpace($updatedAt)) {
        $updatedAt = $Now
    }

    return New-RdpShortcutEntry -Mode $displayMode -FileBaseName $fileBaseName -CreatedAt $createdAt -UpdatedAt $updatedAt
}

function Get-RdpShortcutEntries {
    param($RdpProfile)

    $entries = Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'Shortcuts' -DefaultValue @()
    return @($entries)
}

function Get-RdpShortcutEntryByMode {
    param(
        [Parameter(Mandatory = $true)]$RdpProfile,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    $displayMode = Get-DisplayModeValue -Mode $Mode -Fallback 'FullScreen'
    foreach ($shortcutEntry in @(Get-RdpShortcutEntries -RdpProfile $RdpProfile)) {
        $entryMode = Get-DisplayModeValue -Mode ([string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'Mode' -DefaultValue '')) -Fallback 'FullScreen'
        if ($entryMode -eq $displayMode) {
            return $shortcutEntry
        }
    }

    return $null
}

function Get-ShortcutCount {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles)

    $count = 0
    foreach ($entry in @($Profiles)) {
        $count += @(Get-RdpShortcutEntries -RdpProfile $entry).Count
    }

    return $count
}

function Get-BoundedIntegerValue {
    param(
        $Value,
        [Parameter(Mandatory = $true)][int]$DefaultValue,
        [Parameter(Mandatory = $true)][int]$Minimum,
        [Parameter(Mandatory = $true)][int]$Maximum
    )

    $parsedValue = 0
    if ([int]::TryParse([string]$Value, [ref]$parsedValue) -and
        $parsedValue -ge $Minimum -and
        $parsedValue -le $Maximum) {
        return $parsedValue
    }

    return $DefaultValue
}

function Get-DefaultConfig {
    return [pscustomobject][ordered]@{
        DefaultDomain      = ''
        DefaultUsername    = ''
        ShortcutFolder     = 'Desktop'
        DefaultDisplayMode = 'FullScreen'
        MstscPath          = 'C:\Windows\System32\mstsc.exe'
        WindowedWidth      = 1280
        WindowedHeight     = 720
    }
}

function ConvertTo-RdpProfile {
    param(
        $InputObject,
        [Parameter(Mandatory = $true)]$Config
    )

    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $defaultDomain = [string](Get-ObjectPropertyValue -InputObject $Config -Name 'DefaultDomain' -DefaultValue '')
    $defaultUsername = [string](Get-ObjectPropertyValue -InputObject $Config -Name 'DefaultUsername' -DefaultValue '')
    $configuredMode = [string](Get-ObjectPropertyValue -InputObject $Config -Name 'DefaultDisplayMode' -DefaultValue 'FullScreen')
    $defaultMode = Get-DisplayModeValue -Mode $configuredMode -Fallback 'FullScreen'

    $hasShortcutsProperty = $false
    if ($null -ne $InputObject) {
        $hasShortcutsProperty = $null -ne $InputObject.PSObject.Properties['Shortcuts']
    }

    $rawShortcutName = [string](Get-ObjectPropertyValue -InputObject $InputObject -Name 'ShortcutName' -DefaultValue '')
    $name = [string](Get-ObjectPropertyValue -InputObject $InputObject -Name 'Name' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = $rawShortcutName
    }
    if ([string]::IsNullOrWhiteSpace($rawShortcutName)) {
        $rawShortcutName = $name
    }

    $shortcutName = $rawShortcutName
    if (-not $hasShortcutsProperty) {
        $shortcutName = Get-LegacyBaseShortcutName -ShortcutName $rawShortcutName
    }
    if ([string]::IsNullOrWhiteSpace($shortcutName)) {
        $shortcutName = $name
    }

    $ipAddress = [string](Get-ObjectPropertyValue -InputObject $InputObject -Name 'IpAddress' -DefaultValue '')
    $domain = [string](Get-ObjectPropertyValue -InputObject $InputObject -Name 'Domain' -DefaultValue $defaultDomain)
    if ([string]::IsNullOrWhiteSpace($domain)) {
        $domain = $defaultDomain
    }

    $username = [string](Get-ObjectPropertyValue -InputObject $InputObject -Name 'Username' -DefaultValue $defaultUsername)
    if ([string]::IsNullOrWhiteSpace($username)) {
        $username = $defaultUsername
    }

    $rawMode = [string](Get-ObjectPropertyValue -InputObject $InputObject -Name 'DisplayMode' -DefaultValue $defaultMode)
    $displayMode = Get-DisplayModeValue -Mode $rawMode -Fallback $defaultMode

    $createdAt = [string](Get-ObjectPropertyValue -InputObject $InputObject -Name 'CreatedAt' -DefaultValue $now)
    if ([string]::IsNullOrWhiteSpace($createdAt)) {
        $createdAt = $now
    }

    $updatedAt = [string](Get-ObjectPropertyValue -InputObject $InputObject -Name 'UpdatedAt' -DefaultValue $now)
    if ([string]::IsNullOrWhiteSpace($updatedAt)) {
        $updatedAt = $now
    }

    $shortcutEntries = @()
    $rawShortcuts = Get-ObjectPropertyValue -InputObject $InputObject -Name 'Shortcuts' -DefaultValue $null
    $rawShortcutItems = @()
    if ($null -ne $rawShortcuts) {
        if ($rawShortcuts -is [System.Array]) {
            $rawShortcutItems = @($rawShortcuts)
        } else {
            $rawMode = Get-ObjectPropertyValue -InputObject $rawShortcuts -Name 'Mode' -DefaultValue $null
            $rawFileBaseName = Get-ObjectPropertyValue -InputObject $rawShortcuts -Name 'FileBaseName' -DefaultValue $null
            if ($null -ne $rawMode -or $null -ne $rawFileBaseName) {
                $rawShortcutItems = @($rawShortcuts)
            }
        }
    }

    foreach ($rawShortcutItem in @($rawShortcutItems)) {
        $shortcutEntry = ConvertTo-RdpShortcutEntry -InputObject $rawShortcutItem -DefaultStem $shortcutName -Now $now
        if ($null -ne $shortcutEntry) {
            $shortcutEntries += $shortcutEntry
        }
    }

    if ($shortcutEntries.Count -eq 0) {
        $legacyFileBaseName = Get-LegacyShortcutFileBaseName -ShortcutName $rawShortcutName -Mode $displayMode
        if ([string]::IsNullOrWhiteSpace($legacyFileBaseName)) {
            $legacyFileBaseName = Get-ShortcutFileBaseName -Stem $shortcutName -Mode $displayMode
        }
        $shortcutEntries += New-RdpShortcutEntry -Mode $displayMode -FileBaseName $legacyFileBaseName -CreatedAt $createdAt -UpdatedAt $updatedAt
    }

    $shortcutByMode = @{}
    foreach ($shortcutEntry in @($shortcutEntries)) {
        $entryMode = Get-DisplayModeValue -Mode ([string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'Mode' -DefaultValue '')) -Fallback 'FullScreen'
        if (-not (Test-DisplayMode -Mode $entryMode)) {
            continue
        }

        $existingShortcut = $null
        if ($shortcutByMode.ContainsKey($entryMode)) {
            $existingShortcut = $shortcutByMode[$entryMode]
        }

        if ($null -eq $existingShortcut) {
            $shortcutByMode[$entryMode] = $shortcutEntry
        } else {
            $existingUpdatedAt = [string](Get-ObjectPropertyValue -InputObject $existingShortcut -Name 'UpdatedAt' -DefaultValue '')
            $candidateUpdatedAt = [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'UpdatedAt' -DefaultValue '')
            if ((Get-DateSortValue -Value $candidateUpdatedAt) -ge (Get-DateSortValue -Value $existingUpdatedAt)) {
                $shortcutByMode[$entryMode] = $shortcutEntry
            }
        }
    }

    $normalizedShortcuts = @()
    foreach ($validMode in $script:ValidDisplayModes) {
        if ($shortcutByMode.ContainsKey($validMode)) {
            $normalizedShortcuts += $shortcutByMode[$validMode]
        }
    }

    $normalizedValues = [ordered]@{
        Name         = $name
        IpAddress    = $ipAddress
        Domain       = $domain
        Username     = $username
        DisplayMode  = $displayMode
        ShortcutName = $shortcutName
        Shortcuts    = @($normalizedShortcuts)
        CreatedAt    = $createdAt
        UpdatedAt    = $updatedAt
    }

    if ($null -ne $InputObject) {
        foreach ($propertyInfo in $InputObject.PSObject.Properties) {
            $isCanonical = $script:CanonicalProfileFields -icontains $propertyInfo.Name
            $isSecret = $propertyInfo.Name -match '(?i)password'
            if (-not $isCanonical -and -not $isSecret) {
                $normalizedValues[$propertyInfo.Name] = $propertyInfo.Value
            }
        }
    }

    return [pscustomobject]$normalizedValues
}

function Update-RdpProfileValues {
    param(
        [Parameter(Mandatory = $true)]$RdpProfile,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][hashtable]$Values
    )

    $updatedProfile = ConvertTo-RdpProfile -InputObject $RdpProfile -Config $Config
    foreach ($propertyName in $Values.Keys) {
        $updatedProfile | Add-Member -NotePropertyName $propertyName -NotePropertyValue $Values[$propertyName] -Force
    }

    return ConvertTo-RdpProfile -InputObject $updatedProfile -Config $Config
}

function Get-SeedProfiles {
    param([Parameter(Mandatory = $true)]$Config)

    $seedEntries = @(
        [pscustomobject][ordered]@{
            Name = 'SERVER01'
            IpAddress = '192.0.2.10'
            Domain = 'CONTOSO'
            Username = 'admin'
            DisplayMode = 'AllMonitors'
            ShortcutName = 'SERVER01'
        }
        [pscustomobject][ordered]@{
            Name = 'SERVER02'
            IpAddress = '192.0.2.11'
            Domain = 'CONTOSO'
            Username = 'admin'
            DisplayMode = 'Windowed'
            ShortcutName = 'SERVER02'
        }
        [pscustomobject][ordered]@{
            Name = 'SERVER03'
            IpAddress = '192.0.2.12'
            Domain = 'CONTOSO'
            Username = 'admin'
            DisplayMode = 'Windowed'
            ShortcutName = 'SERVER03'
        }
    )

    $normalizedSeeds = @()
    foreach ($entry in $seedEntries) {
        $normalizedSeeds += ConvertTo-RdpProfile -InputObject $entry -Config $Config
    }

    return @($normalizedSeeds)
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Value,
        [int]$Depth = 12
    )

    $temporaryPath = "$Path.tmp"
    $json = ConvertTo-Json -InputObject $Value -Depth $Depth
    Set-Content -LiteralPath $temporaryPath -Value $json -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Backup-BrokenJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BaseName
    )

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $script:ProjectFolder ("{0}.broken-{1}.json" -f $BaseName, $timestamp)
    Move-Item -LiteralPath $Path -Destination $backupPath -Force
    Write-Color ("Invalid JSON was backed up to: {0}" -f $backupPath) Yellow
}

function Copy-BrokenJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BaseName
    )

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $script:ProjectFolder ("{0}.broken-{1}.json" -f $BaseName, $timestamp)
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    Write-Color ("A backup of the original JSON was written to: {0}" -f $backupPath) Yellow
    return $backupPath
}

function Initialize-Config {
    $defaults = Get-DefaultConfig
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        Write-JsonFile -Path $script:ConfigPath -Value $defaults
        return $defaults
    }

    try {
        $rawConfig = Get-Content -LiteralPath $script:ConfigPath -Raw
        $loadedConfig = $rawConfig | ConvertFrom-Json
        if ($null -eq $loadedConfig -or $loadedConfig -is [System.Array]) {
            throw 'The configuration root must be a JSON object.'
        }

        $changed = $false
        foreach ($defaultProperty in $defaults.PSObject.Properties) {
            if ($null -eq $loadedConfig.PSObject.Properties[$defaultProperty.Name]) {
                $loadedConfig | Add-Member -NotePropertyName $defaultProperty.Name -NotePropertyValue $defaultProperty.Value
                $changed = $true
            }
        }

        $configuredMode = [string](Get-ObjectPropertyValue -InputObject $loadedConfig -Name 'DefaultDisplayMode' -DefaultValue 'FullScreen')
        $validMode = Get-DisplayModeValue -Mode $configuredMode -Fallback 'FullScreen'
        if ($configuredMode -cne $validMode) {
            $loadedConfig | Add-Member -NotePropertyName 'DefaultDisplayMode' -NotePropertyValue $validMode -Force
            $changed = $true
        }

        $configuredWidth = Get-ObjectPropertyValue -InputObject $loadedConfig -Name 'WindowedWidth' -DefaultValue 1280
        $validWidth = Get-BoundedIntegerValue -Value $configuredWidth -DefaultValue 1280 -Minimum 640 -Maximum 7680
        if (-not ($configuredWidth -is [int]) -or [int]$configuredWidth -ne $validWidth) {
            $loadedConfig | Add-Member -NotePropertyName 'WindowedWidth' -NotePropertyValue $validWidth -Force
            $changed = $true
        }

        $configuredHeight = Get-ObjectPropertyValue -InputObject $loadedConfig -Name 'WindowedHeight' -DefaultValue 720
        $validHeight = Get-BoundedIntegerValue -Value $configuredHeight -DefaultValue 720 -Minimum 480 -Maximum 4320
        if (-not ($configuredHeight -is [int]) -or [int]$configuredHeight -ne $validHeight) {
            $loadedConfig | Add-Member -NotePropertyName 'WindowedHeight' -NotePropertyValue $validHeight -Force
            $changed = $true
        }

        if ($changed) {
            Write-JsonFile -Path $script:ConfigPath -Value $loadedConfig
        }
        return $loadedConfig
    }
    catch {
        Backup-BrokenJson -Path $script:ConfigPath -BaseName 'config'
        Write-JsonFile -Path $script:ConfigPath -Value $defaults
        Write-Color 'A new default config.json was created.' Green
        return $defaults
    }
}

function Initialize-Database {
    param([Parameter(Mandatory = $true)]$Config)

    $normalized = @()

    if (-not (Test-Path -LiteralPath $script:DbPath)) {
        $normalized = @(Get-SeedProfiles -Config $Config)
        Write-JsonFile -Path $script:DbPath -Value @($normalized)
        return @($normalized)
    }

    try {
        $rawDatabase = Get-Content -LiteralPath $script:DbPath -Raw
        if ([string]::IsNullOrWhiteSpace($rawDatabase)) {
            Write-JsonFile -Path $script:DbPath -Value @($normalized)
            Write-Color 'db.json was empty; an empty database was kept.' Yellow
            return @($normalized)
        }

        if (-not $rawDatabase.TrimStart().StartsWith('[')) {
            throw 'The database root must be a JSON array.'
        }

        $loadedEntries = $rawDatabase | ConvertFrom-Json
        $skippedCount = 0
        foreach ($entry in @($loadedEntries)) {
            try {
                $normalizedEntry = ConvertTo-RdpProfile -InputObject $entry -Config $Config
                $entryName = [string](Get-ObjectPropertyValue -InputObject $normalizedEntry -Name 'Name' -DefaultValue '')
                $entryIpAddress = [string](Get-ObjectPropertyValue -InputObject $normalizedEntry -Name 'IpAddress' -DefaultValue '')
                $entryShortcutName = [string](Get-ObjectPropertyValue -InputObject $normalizedEntry -Name 'ShortcutName' -DefaultValue '')
                $entryShortcuts = @(Get-RdpShortcutEntries -RdpProfile $normalizedEntry)

                if ([string]::IsNullOrWhiteSpace($entryName)) {
                    throw 'Profile name is empty.'
                }
                if (-not (Test-IPv4Address -Address $entryIpAddress)) {
                    throw "Profile '$entryName' has an invalid IPv4 address."
                }
                if (-not (Test-ShortcutName -Name $entryShortcutName)) {
                    throw "Profile '$entryName' has an invalid shortcut stem."
                }
                if ($entryShortcuts.Count -eq 0) {
                    throw "Profile '$entryName' has no readable shortcuts."
                }
                foreach ($shortcutEntry in @($entryShortcuts)) {
                    $fileBaseName = [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'FileBaseName' -DefaultValue '')
                    if (-not (Test-ShortcutName -Name $fileBaseName)) {
                        throw "Profile '$entryName' has an invalid shortcut filename."
                    }
                }

                $normalized += $normalizedEntry
            }
            catch {
                $skippedCount++
                Write-Color ("Skipped unreadable profile record {0}: {1}" -f $skippedCount, $_.Exception.Message) Yellow
            }
        }

        if ($skippedCount -gt 0) {
            [void](Copy-BrokenJson -Path $script:DbPath -BaseName 'db')
            Write-Color ("Skipped {0} unreadable profile(s); readable profiles were kept." -f $skippedCount) Yellow
        }

        Write-JsonFile -Path $script:DbPath -Value @($normalized)
        return @($normalized)
    }
    catch {
        Backup-BrokenJson -Path $script:DbPath -BaseName 'db'
        $normalized = @()
        Write-JsonFile -Path $script:DbPath -Value @($normalized)
        Write-Color 'A new empty db.json was created.' Green
        return @($normalized)
    }
}

function Save-Database {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles,
        [Parameter(Mandatory = $true)]$Config
    )

    $normalized = @()
    foreach ($entry in @($Profiles)) {
        $normalized += ConvertTo-RdpProfile -InputObject $entry -Config $Config
    }

    Write-JsonFile -Path $script:DbPath -Value @($normalized)
}

function Show-Header {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles,
        [Parameter(Mandatory = $true)]$Config
    )

    $defaultDomain = [string](Get-ObjectPropertyValue -InputObject $Config -Name 'DefaultDomain' -DefaultValue '')
    $defaultUsername = [string](Get-ObjectPropertyValue -InputObject $Config -Name 'DefaultUsername' -DefaultValue '')
    $shortcutSetting = [string](Get-ObjectPropertyValue -InputObject $Config -Name 'ShortcutFolder' -DefaultValue 'Desktop')
    if ([string]::IsNullOrWhiteSpace($shortcutSetting)) {
        $shortcutSetting = 'Desktop'
    }

    $defaultIdentity = if ([string]::IsNullOrWhiteSpace($defaultDomain)) {
        $defaultUsername
    } else {
        "{0}\{1}" -f $defaultDomain, $defaultUsername
    }

    $credentialTargets = Get-RdpCredentialTargets
    $credentialCount = 0
    $seenCredentialTargets = @{}
    foreach ($entry in @($Profiles)) {
        $ipAddress = [string](Get-ObjectPropertyValue -InputObject $entry -Name 'IpAddress' -DefaultValue '')
        $target = "TERMSRV/$ipAddress"
        if (-not [string]::IsNullOrWhiteSpace($ipAddress) -and
            -not $seenCredentialTargets.ContainsKey($target) -and
            $credentialTargets.Contains($target)) {
            $seenCredentialTargets[$target] = $true
            $credentialCount++
        }
    }

    $shortcutCount = Get-ShortcutCount -Profiles $Profiles

    Clear-Host
    Write-Color '==================================================' Cyan
    Write-Color '              RDP Shortcut Forge' White
    Write-Color '==================================================' Cyan
    Write-Color ("Profiles: {0} | Shortcuts: {1} | Creds: {2} | Default: {3} | Folder: {4}" -f $Profiles.Count, $shortcutCount, $credentialCount, $defaultIdentity, $shortcutSetting) DarkGray
    Write-Color '--------------------------------------------------' DarkGray
    Write-Host
}

function Show-Section {
    param([Parameter(Mandatory = $true)][string]$Title)

    Write-Color ("--- {0} ---" -f $Title) Cyan
    Write-Host
}

function Wait-MenuReturn {
    Write-Host
    Write-Color 'Press Enter to return to the main menu...' DarkGray
    [void](Read-Host)
}

function Read-YesNo {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [bool]$DefaultYes = $true
    )

    $suffix = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $answer = (Read-Host "$Prompt $suffix").Trim()
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $DefaultYes
        }

        switch ($answer.ToLowerInvariant()) {
            'y' { return $true }
            'yes' { return $true }
            'n' { return $false }
            'no' { return $false }
            default { Write-Color 'Please enter Y or N.' Red }
        }
    }
}

function Read-RequiredValue {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [string]$Default = ''
    )

    while ($true) {
        $label = if ([string]::IsNullOrWhiteSpace($Default)) {
            $Prompt
        } else {
            "$Prompt [$Default]"
        }
        $value = (Read-Host $label).Trim()
        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = $Default
        }
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
        Write-Color 'This value cannot be empty.' Red
    }
}

function Read-UsernameFromSaved {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles,
        [Parameter(Mandatory = $true)][string]$Domain,
        [string]$DefaultUsername = ''
    )

    $savedUsernames = @()
    foreach ($entry in @($Profiles)) {
        $entryDomain = [string](Get-ObjectPropertyValue -InputObject $entry -Name 'Domain' -DefaultValue '')
        $entryUsername = [string](Get-ObjectPropertyValue -InputObject $entry -Name 'Username' -DefaultValue '')
        if ($entryDomain -ieq $Domain -and
            -not [string]::IsNullOrWhiteSpace($entryUsername) -and
            $savedUsernames -inotcontains $entryUsername) {
            $savedUsernames += $entryUsername
        }
    }

    if ($savedUsernames.Count -eq 0) {
        Write-Color ("No saved usernames were found for domain '{0}'." -f $Domain) DarkGray
        return Read-RequiredValue -Prompt 'Username' -Default $DefaultUsername
    }

    Write-Host
    Write-Color ("Saved usernames for domain '{0}':" -f $Domain) Cyan
    for ($index = 0; $index -lt $savedUsernames.Count; $index++) {
        Write-Host ("{0}. {1}\{2}" -f ($index + 1), $Domain, $savedUsernames[$index])
    }

    $addChoice = $savedUsernames.Count + 1
    Write-Host ("{0}. Add a new username" -f $addChoice)

    $defaultChoice = 1
    for ($index = 0; $index -lt $savedUsernames.Count; $index++) {
        if ($savedUsernames[$index] -ieq $DefaultUsername) {
            $defaultChoice = $index + 1
            break
        }
    }

    while ($true) {
        $answer = (Read-Host "Choose a username [$defaultChoice]").Trim()
        if ([string]::IsNullOrWhiteSpace($answer)) {
            $answer = [string]$defaultChoice
        }

        $choice = 0
        if ([int]::TryParse($answer, [ref]$choice)) {
            if ($choice -ge 1 -and $choice -le $savedUsernames.Count) {
                return $savedUsernames[$choice - 1]
            }
            if ($choice -eq $addChoice) {
                return Read-RequiredValue -Prompt 'New username'
            }
        }
        Write-Color ("Choose a number from 1 to {0}." -f $addChoice) Red
    }
}

function Test-IPv4Address {
    param([string]$Address)

    $parsedAddress = $null
    return (
        [System.Net.IPAddress]::TryParse($Address, [ref]$parsedAddress) -and
        $parsedAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
        $Address -match '^\d{1,3}(\.\d{1,3}){3}$'
    )
}

function Read-IPv4 {
    param([Parameter(Mandatory = $true)][string]$Prompt)

    while ($true) {
        $address = (Read-Host $Prompt).Trim()
        if (Test-IPv4Address -Address $address) {
            return $address
        }
        Write-Color 'Enter a valid IPv4 address, for example 192.0.2.12.' Red
    }
}

function Test-ShortcutName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }
    if ($Name.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        return $false
    }
    if ($Name.EndsWith('.') -or $Name.EndsWith(' ')) {
        return $false
    }

    $baseName = $Name.Split('.')[0].ToUpperInvariant()
    if ($baseName -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
        return $false
    }
    return $true
}

function Read-ShortcutName {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$Default
    )

    while ($true) {
        $name = (Read-Host "$Prompt [$Default]").Trim()
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = $Default
        }
        if (Test-ShortcutName -Name $name) {
            return $name
        }
        Write-Color 'Use a valid Windows filename without \ / : * ? " < > | or a trailing dot/space.' Red
    }
}

function Get-ShortcutFileBaseNamesForStem {
    param(
        [Parameter(Mandatory = $true)][string]$Stem,
        [string[]]$Modes = $script:ValidDisplayModes
    )

    $fileBaseNames = @()
    foreach ($mode in @($Modes)) {
        $displayMode = Get-DisplayModeValue -Mode $mode -Fallback 'FullScreen'
        $fileBaseName = Get-ShortcutFileBaseName -Stem $Stem -Mode $displayMode
        if ($fileBaseNames -inotcontains $fileBaseName) {
            $fileBaseNames += $fileBaseName
        }
    }

    return @($fileBaseNames)
}

function Get-ShortcutFilenameOwners {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles,
        $ExcludeIndex = $null
    )

    $owners = @{}
    for ($index = 0; $index -lt $Profiles.Count; $index++) {
        if ($null -ne $ExcludeIndex -and $index -eq [int]$ExcludeIndex) {
            continue
        }

        $ownerName = [string](Get-ObjectPropertyValue -InputObject $Profiles[$index] -Name 'Name' -DefaultValue '')
        foreach ($shortcutEntry in @(Get-RdpShortcutEntries -RdpProfile $Profiles[$index])) {
            $fileBaseName = [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'FileBaseName' -DefaultValue '')
            if (-not [string]::IsNullOrWhiteSpace($fileBaseName) -and -not $owners.ContainsKey($fileBaseName)) {
                $owners[$fileBaseName] = $ownerName
            }
        }
    }

    return $owners
}

function Test-ShortcutStemAvailable {
    param(
        [Parameter(Mandatory = $true)][string]$Stem,
        [Parameter(Mandatory = $true)]$Owners
    )

    foreach ($fileBaseName in @(Get-ShortcutFileBaseNamesForStem -Stem $Stem)) {
        if ($Owners.ContainsKey($fileBaseName)) {
            return $false
        }
    }

    return $true
}

function Get-FreeShortcutStem {
    param(
        [Parameter(Mandatory = $true)][string]$Stem,
        [Parameter(Mandatory = $true)]$Owners
    )

    $candidate = $Stem
    $suffixNumber = 2
    while (-not (Test-ShortcutStemAvailable -Stem $candidate -Owners $Owners)) {
        $candidate = "{0}-{1}" -f $Stem, $suffixNumber
        $suffixNumber++
    }

    return $candidate
}

function Read-UniqueShortcutName {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$Default,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles,
        $ExcludeIndex = $null
    )

    while ($true) {
        $shortcutName = Read-ShortcutName -Prompt $Prompt -Default $Default
        $owners = Get-ShortcutFilenameOwners -Profiles $Profiles -ExcludeIndex $ExcludeIndex
        $conflictingFileBaseName = ''
        $ownerName = ''
        foreach ($fileBaseName in @(Get-ShortcutFileBaseNamesForStem -Stem $shortcutName)) {
            if ($owners.ContainsKey($fileBaseName)) {
                $conflictingFileBaseName = $fileBaseName
                $ownerName = [string]$owners[$fileBaseName]
                break
            }
        }

        if ([string]::IsNullOrWhiteSpace($conflictingFileBaseName)) {
            return $shortcutName
        }

        $suggestedName = Get-FreeShortcutStem -Stem $shortcutName -Owners $owners
        Write-Color ("Shortcut stem '{0}' would use '{1}.lnk', already owned by profile '{2}'. Try '{3}'." -f $shortcutName, $conflictingFileBaseName, $ownerName, $suggestedName) Red
    }
}

function Read-DisplayMode {
    param(
        [string]$DefaultMode = 'FullScreen',
        [string]$Prompt = '',
        [switch]$Multiple
    )

    Write-Host '1. Windowed'
    Write-Host '2. Full screen single monitor'
    Write-Host '3. All monitors (multi-monitor)'

    $validatedDefault = Get-DisplayModeValue -Mode $DefaultMode -Fallback 'FullScreen'
    $defaultChoice = switch ($validatedDefault) {
        'Windowed' { '1' }
        'AllMonitors' { '3' }
        default { '2' }
    }

    while ($true) {
        $displayPrompt = if ([string]::IsNullOrWhiteSpace($Prompt)) {
            if ($Multiple) {
                "Display mode(s) [$defaultChoice]"
            } else {
                "Display mode [$defaultChoice]"
            }
        } else {
            $Prompt
        }
        $choice = (Read-Host $displayPrompt).Trim()
        if ([string]::IsNullOrWhiteSpace($choice)) {
            $choice = $defaultChoice
        }

        if (-not $Multiple) {
            switch ($choice) {
                '1' { return 'Windowed' }
                '2' { return 'FullScreen' }
                '3' { return 'AllMonitors' }
                default { Write-Color 'Choose 1, 2, or 3.' Red }
            }
        } else {
            $selectedModes = @()
            $validChoice = $true
            $tokens = @($choice -split '[,\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            foreach ($token in @($tokens)) {
                $mode = ''
                switch ($token) {
                    '1' { $mode = 'Windowed' }
                    '2' { $mode = 'FullScreen' }
                    '3' { $mode = 'AllMonitors' }
                    default {
                        $validChoice = $false
                    }
                }

                if ($validChoice -and $selectedModes -inotcontains $mode) {
                    $selectedModes += $mode
                }
            }

            if ($validChoice -and $selectedModes.Count -gt 0) {
                return @($selectedModes)
            }

            Write-Color 'Choose one or more values from 1, 2, and 3. Separate multiple choices with commas or spaces.' Red
        }
    }
}

function Get-ShortcutFolder {
    param([Parameter(Mandatory = $true)]$Config)

    $configuredFolder = [string](Get-ObjectPropertyValue -InputObject $Config -Name 'ShortcutFolder' -DefaultValue 'Desktop')
    if ([string]::IsNullOrWhiteSpace($configuredFolder) -or $configuredFolder -eq 'Desktop') {
        return [Environment]::GetFolderPath('Desktop')
    }

    $expandedFolder = [Environment]::ExpandEnvironmentVariables($configuredFolder)
    if (-not [System.IO.Path]::IsPathRooted($expandedFolder)) {
        $expandedFolder = Join-Path $env:USERPROFILE $expandedFolder
    }
    return $expandedFolder
}

function Get-ShortcutPathInfo {
    param(
        [Parameter(Mandatory = $true)]$RdpProfile,
        [Parameter(Mandatory = $true)]$Config,
        $ShortcutEntry = $null,
        [string]$Mode = '',
        [string]$FileBaseName = ''
    )

    if ($null -ne $ShortcutEntry) {
        $Mode = [string](Get-ObjectPropertyValue -InputObject $ShortcutEntry -Name 'Mode' -DefaultValue $Mode)
        $FileBaseName = [string](Get-ObjectPropertyValue -InputObject $ShortcutEntry -Name 'FileBaseName' -DefaultValue $FileBaseName)
    }

    $displayMode = Get-DisplayModeValue -Mode $Mode -Fallback ([string](Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'DisplayMode' -DefaultValue 'FullScreen'))
    if ([string]::IsNullOrWhiteSpace($FileBaseName)) {
        $shortcutStem = [string](Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'ShortcutName' -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($shortcutStem)) {
            $shortcutStem = [string](Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'Name' -DefaultValue '')
        }
        $FileBaseName = Get-ShortcutFileBaseName -Stem $shortcutStem -Mode $displayMode
    }

    if (-not (Test-ShortcutName -Name $FileBaseName)) {
        throw "Shortcut filename '$FileBaseName' is not a valid Windows filename."
    }

    $shortcutFolder = Get-ShortcutFolder -Config $Config
    $shortcutPath = Join-Path $shortcutFolder ("{0}.lnk" -f $FileBaseName)

    return [pscustomobject][ordered]@{
        EffectiveName = $FileBaseName
        Mode          = $displayMode
        Path          = $shortcutPath
    }
}

function Get-MstscPath {
    param([Parameter(Mandatory = $true)]$Config)

    $mstscPath = [Environment]::ExpandEnvironmentVariables(
        [string](Get-ObjectPropertyValue -InputObject $Config -Name 'MstscPath' -DefaultValue 'C:\Windows\System32\mstsc.exe')
    )
    if (-not (Test-Path -LiteralPath $mstscPath)) {
        throw "Remote Desktop was not found at '$mstscPath'. Check MstscPath in config.json."
    }

    return $mstscPath
}

function Get-RdpArguments {
    param(
        [Parameter(Mandatory = $true)]$RdpProfile,
        [Parameter(Mandatory = $true)]$Config,
        $ShortcutEntry = $null,
        [string]$Mode = ''
    )

    if ($null -ne $ShortcutEntry) {
        $Mode = [string](Get-ObjectPropertyValue -InputObject $ShortcutEntry -Name 'Mode' -DefaultValue $Mode)
    }
    $displayMode = Get-DisplayModeValue -Mode $Mode -Fallback ([string](Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'DisplayMode' -DefaultValue 'FullScreen'))
    $ipAddress = [string](Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'IpAddress' -DefaultValue '')
    $friendlyName = [string](Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'Name' -DefaultValue '')
    if (-not (Test-IPv4Address -Address $ipAddress)) {
        throw "Profile '$friendlyName' does not contain a valid IPv4 address."
    }

    $configuredWidth = Get-ObjectPropertyValue -InputObject $Config -Name 'WindowedWidth' -DefaultValue 1280
    $windowedWidth = Get-BoundedIntegerValue -Value $configuredWidth -DefaultValue 1280 -Minimum 640 -Maximum 7680
    $configuredHeight = Get-ObjectPropertyValue -InputObject $Config -Name 'WindowedHeight' -DefaultValue 720
    $windowedHeight = Get-BoundedIntegerValue -Value $configuredHeight -DefaultValue 720 -Minimum 480 -Maximum 4320

    $arguments = switch ($displayMode) {
        'Windowed' { "/v:$ipAddress /w:$windowedWidth /h:$windowedHeight" }
        'AllMonitors' { "/multimon /v:$ipAddress" }
        default { "/f /v:$ipAddress" }
    }
    return $arguments
}

function New-RdpShortcut {
    param(
        [Parameter(Mandatory = $true)]$RdpProfile,
        [Parameter(Mandatory = $true)]$Config,
        $ShortcutEntry = $null
    )

    $mstscPath = Get-MstscPath -Config $Config
    $pathInfo = Get-ShortcutPathInfo -RdpProfile $RdpProfile -Config $Config -ShortcutEntry $ShortcutEntry
    $shortcutPath = [string]$pathInfo.Path
    $arguments = Get-RdpArguments -RdpProfile $RdpProfile -Config $Config -ShortcutEntry $ShortcutEntry
    $friendlyName = [string](Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'Name' -DefaultValue '')

    $shortcutFolder = Get-ShortcutFolder -Config $Config
    if (-not (Test-Path -LiteralPath $shortcutFolder)) {
        New-Item -ItemType Directory -Path $shortcutFolder -Force | Out-Null
    }

    $shell = $null
    $shortcut = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $mstscPath
        $shortcut.Arguments = $arguments
        $shortcut.WorkingDirectory = Split-Path -Parent $mstscPath
        $shortcut.IconLocation = "$mstscPath,0"
        $shortcut.Description = "Remote Desktop connection to $friendlyName"
        $shortcut.Save()
    }
    finally {
        if ($null -ne $shortcut) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut)
        }
        if ($null -ne $shell) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }
    }

    return $shortcutPath
}

function Remove-RdpShortcutFiles {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Paths)

    $deletedCount = 0
    $failedCount = 0
    foreach ($shortcutPath in @($Paths)) {
        if (Test-Path -LiteralPath $shortcutPath) {
            try {
                Remove-Item -LiteralPath $shortcutPath -Force
                $deletedCount++
            }
            catch {
                $failedCount++
                Write-Color ("Shortcut could not be deleted: {0} ({1})" -f $shortcutPath, $_.Exception.Message) Red
            }
        }
    }

    return [pscustomobject]@{
        Deleted = $deletedCount
        Failed  = $failedCount
    }
}

function Initialize-CredentialNativeType {
    if ($null -ne ('RdpShortcutForge.NativeCredential' -as [type])) {
        return
    }

    $typeDefinition = @'
using System;
using System.Runtime.InteropServices;

namespace RdpShortcutForge
{
    public static class NativeCredential
    {
        private const UInt32 CredTypeGeneric = 1;
        private const UInt32 CredPersistLocalMachine = 2;

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeFileTime
        {
            public UInt32 LowDateTime;
            public UInt32 HighDateTime;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct Credential
        {
            public UInt32 Flags;
            public UInt32 Type;
            [MarshalAs(UnmanagedType.LPWStr)]
            public string TargetName;
            [MarshalAs(UnmanagedType.LPWStr)]
            public string Comment;
            public NativeFileTime LastWritten;
            public UInt32 CredentialBlobSize;
            public IntPtr CredentialBlob;
            public UInt32 Persist;
            public UInt32 AttributeCount;
            public IntPtr Attributes;
            [MarshalAs(UnmanagedType.LPWStr)]
            public string TargetAlias;
            [MarshalAs(UnmanagedType.LPWStr)]
            public string UserName;
        }

        [DllImport("advapi32.dll", EntryPoint = "CredWriteW",
            CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CredWrite(ref Credential credential, UInt32 flags);

        public static Int32 WriteGeneric(
            string targetName,
            string userName,
            IntPtr credentialBlob,
            UInt32 credentialBlobSize)
        {
            Credential credential = new Credential();
            credential.Type = CredTypeGeneric;
            credential.TargetName = targetName;
            credential.UserName = userName;
            credential.CredentialBlob = credentialBlob;
            credential.CredentialBlobSize = credentialBlobSize;
            credential.Persist = CredPersistLocalMachine;

            if (CredWrite(ref credential, 0))
            {
                return 0;
            }

            return Marshal.GetLastWin32Error();
        }
    }
}
'@

    Add-Type -TypeDefinition $typeDefinition -Language CSharp | Out-Null
}

function Set-RdpCredential {
    param([Parameter(Mandatory = $true)]$RdpProfile)

    $securePassword = $null
    $passwordPointer = [IntPtr]::Zero
    try {
        Write-Color 'Password input is hidden.' DarkGray
        $securePassword = Read-Host 'Password' -AsSecureString
        if ($securePassword.Length -eq 0) {
            throw 'The password cannot be empty.'
        }

        $ipAddress = [string](Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'IpAddress' -DefaultValue '')
        $domain = [string](Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'Domain' -DefaultValue '')
        $username = [string](Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'Username' -DefaultValue '')
        if (-not (Test-IPv4Address -Address $ipAddress)) {
            throw 'The profile does not contain a valid IPv4 address.'
        }

        $target = "TERMSRV/$ipAddress"
        $user = if ([string]::IsNullOrWhiteSpace($domain)) {
            $username
        } else {
            "{0}\{1}" -f $domain, $username
        }

        Initialize-CredentialNativeType
        $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($securePassword)
        $passwordByteLength = [uint32]($securePassword.Length * 2)
        $errorCode = [RdpShortcutForge.NativeCredential]::WriteGeneric(
            $target,
            $user,
            $passwordPointer,
            $passwordByteLength
        )
        if ($errorCode -ne 0) {
            $nativeError = New-Object -TypeName ComponentModel.Win32Exception -ArgumentList $errorCode
            throw "Windows Credential Manager returned error $errorCode`: $($nativeError.Message)"
        }
    }
    finally {
        if ($passwordPointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($passwordPointer)
        }
        if ($null -ne $securePassword) {
            $securePassword.Dispose()
        }
        $securePassword = $null
    }
}

function Get-RdpCredentialTargets {
    $targets = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    try {
        $cmdkeyOutput = @(& cmdkey.exe '/list' 2>&1)
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            return ,$targets
        }

        foreach ($outputLine in @($cmdkeyOutput)) {
            $targetMatches = [regex]::Matches(
                [string]$outputLine,
                'TERMSRV/[^\s"]+',
                [Text.RegularExpressions.RegexOptions]::IgnoreCase
            )
            foreach ($targetMatch in $targetMatches) {
                [void]$targets.Add($targetMatch.Value.TrimEnd(',', ';'))
            }
        }
    }
    catch {
        return ,$targets
    }

    return ,$targets
}

function Get-ShortcutModeStatusText {
    param(
        [Parameter(Mandatory = $true)]$RdpProfile,
        [Parameter(Mandatory = $true)]$Config
    )

    $checkMark = [char]0x2713
    $missingMark = [char]0x00B7
    $parts = @()
    $modeLetters = @{
        Windowed    = 'W'
        FullScreen  = 'F'
        AllMonitors = 'M'
    }

    foreach ($displayMode in $script:ValidDisplayModes) {
        $shortcutEntry = Get-RdpShortcutEntryByMode -RdpProfile $RdpProfile -Mode $displayMode
        if ($null -eq $shortcutEntry) {
            $parts += ("{0}-" -f $modeLetters[$displayMode])
        } else {
            $mark = $missingMark
            try {
                $pathInfo = Get-ShortcutPathInfo -RdpProfile $RdpProfile -Config $Config -ShortcutEntry $shortcutEntry
                if (Test-Path -LiteralPath $pathInfo.Path) {
                    $mark = $checkMark
                }
            }
            catch {
                $mark = $missingMark
            }
            $parts += ("{0}{1}" -f $modeLetters[$displayMode], $mark)
        }
    }

    return ($parts -join ' ')
}

function Get-RdpShortcutPaths {
    param(
        [Parameter(Mandatory = $true)]$RdpProfile,
        [Parameter(Mandatory = $true)]$Config
    )

    $paths = @()
    foreach ($shortcutEntry in @(Get-RdpShortcutEntries -RdpProfile $RdpProfile)) {
        try {
            $pathInfo = Get-ShortcutPathInfo -RdpProfile $RdpProfile -Config $Config -ShortcutEntry $shortcutEntry
            $paths += [string]$pathInfo.Path
        }
        catch {
        }
    }

    return @($paths)
}

function Move-RdpShortcutFilesForStemChange {
    param(
        [Parameter(Mandatory = $true)]$RdpProfile,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$NewStem,
        [Parameter(Mandatory = $true)][string]$Timestamp
    )

    $movePlan = @()
    $updatedEntries = @()
    foreach ($shortcutEntry in @(Get-RdpShortcutEntries -RdpProfile $RdpProfile)) {
        $entryMode = Get-DisplayModeValue -Mode ([string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'Mode' -DefaultValue 'FullScreen')) -Fallback 'FullScreen'
        $oldFileBaseName = [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'FileBaseName' -DefaultValue '')
        $newFileBaseName = Get-ShortcutFileBaseName -Stem $NewStem -Mode $entryMode
        $entryCreatedAt = [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'CreatedAt' -DefaultValue $Timestamp)
        $entryUpdatedAt = [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'UpdatedAt' -DefaultValue $Timestamp)
        $newUpdatedAt = $entryUpdatedAt

        if (-not [string]::Equals($oldFileBaseName, $newFileBaseName, [StringComparison]::OrdinalIgnoreCase)) {
            $oldPathInfo = Get-ShortcutPathInfo -RdpProfile $RdpProfile -Config $Config -Mode $entryMode -FileBaseName $oldFileBaseName
            $newPathInfo = Get-ShortcutPathInfo -RdpProfile $RdpProfile -Config $Config -Mode $entryMode -FileBaseName $newFileBaseName
            $oldPath = [string]$oldPathInfo.Path
            $newPath = [string]$newPathInfo.Path
            if ((Test-Path -LiteralPath $oldPath) -and
                (Test-Path -LiteralPath $newPath) -and
                -not [string]::Equals($oldPath, $newPath, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Cannot rename shortcut '$oldFileBaseName.lnk' because '$newFileBaseName.lnk' already exists."
            }

            $movePlan += [pscustomobject]@{
                OldPath = $oldPath
                NewPath = $newPath
                OldFileBaseName = $oldFileBaseName
                NewFileBaseName = $newFileBaseName
            }
            $newUpdatedAt = $Timestamp
        }

        $updatedEntries += New-RdpShortcutEntry -Mode $entryMode -FileBaseName $newFileBaseName -CreatedAt $entryCreatedAt -UpdatedAt $newUpdatedAt
    }

    $completedMoves = @()
    try {
        foreach ($moveItem in @($movePlan)) {
            if ((Test-Path -LiteralPath $moveItem.OldPath) -and
                -not [string]::Equals([string]$moveItem.OldPath, [string]$moveItem.NewPath, [StringComparison]::OrdinalIgnoreCase)) {
                Move-Item -LiteralPath $moveItem.OldPath -Destination $moveItem.NewPath -Force
                $completedMoves += $moveItem
                Write-Color ("Renamed shortcut: {0}.lnk -> {1}.lnk" -f $moveItem.OldFileBaseName, $moveItem.NewFileBaseName) Green
            }
        }
    }
    catch {
        for ($moveIndex = $completedMoves.Count - 1; $moveIndex -ge 0; $moveIndex--) {
            $completedMove = $completedMoves[$moveIndex]
            if ((Test-Path -LiteralPath $completedMove.NewPath) -and
                -not (Test-Path -LiteralPath $completedMove.OldPath)) {
                try {
                    Move-Item -LiteralPath $completedMove.NewPath -Destination $completedMove.OldPath -Force
                }
                catch {
                }
            }
        }
        throw
    }

    return @($updatedEntries)
}

function Set-RdpShortcutModes {
    param(
        [Parameter(Mandatory = $true)]$RdpProfile,
        [Parameter(Mandatory = $true)][string[]]$Modes,
        [Parameter(Mandatory = $true)][string]$Stem,
        [Parameter(Mandatory = $true)][string]$Timestamp,
        [switch]$RewriteAllForStem
    )

    $entries = @()
    foreach ($shortcutEntry in @(Get-RdpShortcutEntries -RdpProfile $RdpProfile)) {
        $entryMode = Get-DisplayModeValue -Mode ([string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'Mode' -DefaultValue 'FullScreen')) -Fallback 'FullScreen'
        $entryFileBaseName = [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'FileBaseName' -DefaultValue (Get-ShortcutFileBaseName -Stem $Stem -Mode $entryMode))
        if ($RewriteAllForStem) {
            $entryFileBaseName = Get-ShortcutFileBaseName -Stem $Stem -Mode $entryMode
        }
        $entryCreatedAt = [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'CreatedAt' -DefaultValue $Timestamp)
        $entryUpdatedAt = [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'UpdatedAt' -DefaultValue $Timestamp)
        if ($RewriteAllForStem) {
            $entryUpdatedAt = $Timestamp
        }
        $entries += New-RdpShortcutEntry -Mode $entryMode -FileBaseName $entryFileBaseName -CreatedAt $entryCreatedAt -UpdatedAt $entryUpdatedAt
    }

    foreach ($mode in @($Modes)) {
        $displayMode = Get-DisplayModeValue -Mode $mode -Fallback 'FullScreen'
        $existingIndex = $null
        for ($index = 0; $index -lt $entries.Count; $index++) {
            $entryMode = Get-DisplayModeValue -Mode ([string](Get-ObjectPropertyValue -InputObject $entries[$index] -Name 'Mode' -DefaultValue 'FullScreen')) -Fallback 'FullScreen'
            if ($entryMode -eq $displayMode) {
                $existingIndex = $index
                break
            }
        }

        $fileBaseName = Get-ShortcutFileBaseName -Stem $Stem -Mode $displayMode
        if ($null -eq $existingIndex) {
            $entries += New-RdpShortcutEntry -Mode $displayMode -FileBaseName $fileBaseName -CreatedAt $Timestamp -UpdatedAt $Timestamp
        } else {
            $createdAt = [string](Get-ObjectPropertyValue -InputObject $entries[$existingIndex] -Name 'CreatedAt' -DefaultValue $Timestamp)
            $entries[$existingIndex] = New-RdpShortcutEntry -Mode $displayMode -FileBaseName $fileBaseName -CreatedAt $createdAt -UpdatedAt $Timestamp
        }
    }

    return @($entries)
}

function Show-Profiles {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles,
        [Parameter(Mandatory = $true)]$Config
    )

    if ($Profiles.Count -eq 0) {
        Write-Color 'No saved profiles were found.' Yellow
        return
    }

    $credentialTargets = Get-RdpCredentialTargets
    $rows = for ($index = 0; $index -lt $Profiles.Count; $index++) {
        $entry = $Profiles[$index]
        $domain = [string](Get-ObjectPropertyValue -InputObject $entry -Name 'Domain' -DefaultValue '')
        $username = [string](Get-ObjectPropertyValue -InputObject $entry -Name 'Username' -DefaultValue '')
        $ipAddress = [string](Get-ObjectPropertyValue -InputObject $entry -Name 'IpAddress' -DefaultValue '')
        $identity = if ([string]::IsNullOrWhiteSpace($domain)) {
            $username
        } else {
            "{0}\{1}" -f $domain, $username
        }
        $credentialMark = if ($credentialTargets.Contains("TERMSRV/$ipAddress")) {
            [char]0x2713
        } else {
            [char]0x2014
        }
        $shortcutModes = Get-ShortcutModeStatusText -RdpProfile $entry -Config $Config

        [pscustomobject]@{
            Number = $index + 1
            Name = [string](Get-ObjectPropertyValue -InputObject $entry -Name 'Name' -DefaultValue '')
            'IP Address' = $ipAddress
            Username = $identity
            'Display Mode' = [string](Get-ObjectPropertyValue -InputObject $entry -Name 'DisplayMode' -DefaultValue 'FullScreen')
            'Shortcut Name' = [string](Get-ObjectPropertyValue -InputObject $entry -Name 'ShortcutName' -DefaultValue '')
            'Cred?' = $credentialMark
            'Modes' = $shortcutModes
        }
    }

    $rows | Format-Table -AutoSize | Out-Host
}

function Select-ProfileIndex {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles,
        [Parameter(Mandatory = $true)]$Config,
        [string]$Prompt = 'Choose a profile number'
    )

    if ($Profiles.Count -eq 0) {
        Write-Color 'No saved profiles were found.' Yellow
        return $null
    }

    Show-Profiles -Profiles $Profiles -Config $Config
    while ($true) {
        $answer = (Read-Host $Prompt).Trim()
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and
            $number -ge 1 -and
            $number -le $Profiles.Count) {
            return ($number - 1)
        }
        Write-Color ("Enter a number from 1 to {0}." -f $Profiles.Count) Red
    }
}

function Show-RdpProfileSummary {
    param([Parameter(Mandatory = $true)]$RdpProfile)

    $domain = [string](Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'Domain' -DefaultValue '')
    $username = [string](Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'Username' -DefaultValue '')
    $identity = if ([string]::IsNullOrWhiteSpace($domain)) {
        $username
    } else {
        "{0}\{1}" -f $domain, $username
    }

    Write-Host
    Write-Color 'Profile summary' Cyan
    Write-Color '----------------------------------------' DarkGray
    Write-Host ("Name          : {0}" -f (Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'Name' -DefaultValue ''))
    Write-Host ("IP address    : {0}" -f (Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'IpAddress' -DefaultValue ''))
    Write-Host ("User          : {0}" -f $identity)
    Write-Host ("Display mode  : {0}" -f (Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'DisplayMode' -DefaultValue 'FullScreen'))
    Write-Host ("Shortcut name : {0}" -f (Get-ObjectPropertyValue -InputObject $RdpProfile -Name 'ShortcutName' -DefaultValue ''))
    $shortcutEntries = @(Get-RdpShortcutEntries -RdpProfile $RdpProfile)
    if ($shortcutEntries.Count -gt 0) {
        foreach ($shortcutEntry in @($shortcutEntries)) {
            Write-Host ("Shortcut      : {0} -> {1}.lnk" -f (Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'Mode' -DefaultValue ''), (Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'FileBaseName' -DefaultValue ''))
        }
    }
    Write-Color '----------------------------------------' DarkGray
}

function Add-RdpProfile {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles,
        [Parameter(Mandatory = $true)]$Config
    )

    Show-Header -Profiles $Profiles -Config $Config
    Show-Section 'Add new RDP profile'

    $name = Read-RequiredValue -Prompt 'Friendly name'
    $ipAddress = Read-IPv4 -Prompt 'IP address'
    $defaultDomain = [string](Get-ObjectPropertyValue -InputObject $Config -Name 'DefaultDomain' -DefaultValue '')
    $defaultUsername = [string](Get-ObjectPropertyValue -InputObject $Config -Name 'DefaultUsername' -DefaultValue '')
    $defaultMode = [string](Get-ObjectPropertyValue -InputObject $Config -Name 'DefaultDisplayMode' -DefaultValue 'FullScreen')
    $domain = Read-RequiredValue -Prompt 'Domain' -Default $defaultDomain
    $username = Read-UsernameFromSaved -Profiles $Profiles -Domain $domain -DefaultUsername $defaultUsername
    $selectedModes = @(Read-DisplayMode -DefaultMode $defaultMode -Multiple)
    $displayMode = $selectedModes[0]

    $nameMatchingIndexes = @()
    $ipMatchingIndexes = @()
    for ($index = 0; $index -lt $Profiles.Count; $index++) {
        $entryName = [string](Get-ObjectPropertyValue -InputObject $Profiles[$index] -Name 'Name' -DefaultValue '')
        $entryIpAddress = [string](Get-ObjectPropertyValue -InputObject $Profiles[$index] -Name 'IpAddress' -DefaultValue '')
        if ($entryName -ieq $name) {
            $nameMatchingIndexes += $index
        } elseif ($entryIpAddress -eq $ipAddress) {
            $ipMatchingIndexes += $index
        }
    }

    $updateIndex = $null
    if ($nameMatchingIndexes.Count -gt 0) {
        Write-Host
        Write-Color 'A profile with the same name already exists.' Yellow
        $matchingEntries = @()
        foreach ($matchingIndex in $nameMatchingIndexes) {
            $matchingEntries += $Profiles[$matchingIndex]
        }
        Show-Profiles -Profiles $matchingEntries -Config $Config

        if (-not (Read-YesNo -Prompt 'Update an existing matching profile instead?' -DefaultYes $true)) {
            Write-Color 'No profile was saved. Duplicate profile names are not created.' Yellow
            return $Profiles
        }

        if ($nameMatchingIndexes.Count -eq 1) {
            $updateIndex = $nameMatchingIndexes[0]
        } else {
            $selectedMatch = Select-ProfileIndex -Profiles $matchingEntries -Config $Config -Prompt 'Choose the matching profile to update'
            $updateIndex = $nameMatchingIndexes[$selectedMatch]
        }
    }

    foreach ($ipMatchingIndex in @($ipMatchingIndexes)) {
        $ipOwnerName = [string](Get-ObjectPropertyValue -InputObject $Profiles[$ipMatchingIndex] -Name 'Name' -DefaultValue '')
        Write-Color ("Note: profile '{0}' already uses {1}." -f $ipOwnerName, $ipAddress) Yellow
    }

    $shortcutDefault = $name
    if ($null -ne $updateIndex) {
        $shortcutDefault = [string](Get-ObjectPropertyValue -InputObject $Profiles[$updateIndex] -Name 'ShortcutName' -DefaultValue $name)
    }
    $shortcutName = Read-UniqueShortcutName -Prompt 'Shortcut name' -Default $shortcutDefault -Profiles $Profiles -ExcludeIndex $updateIndex

    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $createdAt = $now
    $existingProfile = $null
    $rewriteAllShortcutsForStem = $false
    if ($null -ne $updateIndex) {
        $existingProfile = $Profiles[$updateIndex]
        $createdAt = [string](Get-ObjectPropertyValue -InputObject $existingProfile -Name 'CreatedAt' -DefaultValue $now)
        if ([string]::IsNullOrWhiteSpace($createdAt)) {
            $createdAt = $now
        }
        $existingShortcutStem = [string](Get-ObjectPropertyValue -InputObject $existingProfile -Name 'ShortcutName' -DefaultValue '')
        $rewriteAllShortcutsForStem = -not [string]::Equals($existingShortcutStem, $shortcutName, [StringComparison]::OrdinalIgnoreCase)
    }

    $rdpProfile = ConvertTo-RdpProfile -InputObject ([pscustomobject][ordered]@{
        Name = $name
        IpAddress = $ipAddress
        Domain = $domain
        Username = $username
        DisplayMode = $displayMode
        ShortcutName = $shortcutName
        CreatedAt = $createdAt
        UpdatedAt = $now
        Shortcuts = @()
    }) -Config $Config
    if ($null -ne $existingProfile) {
        $existingShortcuts = @(Get-RdpShortcutEntries -RdpProfile $existingProfile)
        $rdpProfile = Update-RdpProfileValues -RdpProfile $rdpProfile -Config $Config -Values @{
            Shortcuts = @($existingShortcuts)
        }
    }
    $updatedShortcuts = Set-RdpShortcutModes -RdpProfile $rdpProfile -Modes $selectedModes -Stem $shortcutName -Timestamp $now -RewriteAllForStem:$rewriteAllShortcutsForStem
    $rdpProfile = Update-RdpProfileValues -RdpProfile $rdpProfile -Config $Config -Values @{
        Shortcuts = @($updatedShortcuts)
    }

    Show-RdpProfileSummary -RdpProfile $rdpProfile
    if (-not (Read-YesNo -Prompt 'Save this profile?' -DefaultYes $true)) {
        Write-Color 'The profile was not saved.' Yellow
        return $Profiles
    }

    if ($null -ne $updateIndex) {
        if ($rewriteAllShortcutsForStem) {
            $movedShortcuts = Move-RdpShortcutFilesForStemChange -RdpProfile $existingProfile -Config $Config -NewStem $shortcutName -Timestamp $now
            $rdpProfile = Update-RdpProfileValues -RdpProfile $rdpProfile -Config $Config -Values @{
                Shortcuts = @(Set-RdpShortcutModes -RdpProfile (Update-RdpProfileValues -RdpProfile $existingProfile -Config $Config -Values @{ Shortcuts = @($movedShortcuts) }) -Modes $selectedModes -Stem $shortcutName -Timestamp $now -RewriteAllForStem)
            }
        }
        $Profiles[$updateIndex] = $rdpProfile
        Write-Color 'The saved profile was updated.' Green
    } else {
        $Profiles = @($Profiles) + $rdpProfile
        Write-Color 'The new profile was saved.' Green
    }
    Save-Database -Profiles $Profiles -Config $Config

    if (Read-YesNo -Prompt 'Create or update the shortcut now?' -DefaultYes $true) {
        $createdShortcutCount = 0
        try {
            foreach ($selectedMode in @($selectedModes)) {
                $shortcutEntry = Get-RdpShortcutEntryByMode -RdpProfile $rdpProfile -Mode $selectedMode
                $shortcutPath = New-RdpShortcut -RdpProfile $rdpProfile -Config $Config -ShortcutEntry $shortcutEntry
                $createdShortcutCount++
                Write-Color ("Shortcut created or updated: {0}" -f $shortcutPath) Green
            }
        }
        catch {
            Write-Color ("Shortcut could not be created: {0}" -f $_.Exception.Message) Red
        }

        if ($createdShortcutCount -gt 0 -and (Read-YesNo -Prompt ("Connect now using {0}?" -f $displayMode) -DefaultYes $false)) {
            try {
                $mstscPath = Get-MstscPath -Config $Config
                $defaultShortcutEntry = Get-RdpShortcutEntryByMode -RdpProfile $rdpProfile -Mode $displayMode
                $arguments = Get-RdpArguments -RdpProfile $rdpProfile -Config $Config -ShortcutEntry $defaultShortcutEntry
                Start-Process -FilePath $mstscPath -ArgumentList $arguments
                Write-Color 'Remote Desktop was started.' Green
            }
            catch {
                Write-Color ("Remote Desktop could not be started: {0}" -f $_.Exception.Message) Red
            }
        }
    } else {
        Write-Color 'Shortcut creation was skipped.' Yellow
    }

    if (Read-YesNo -Prompt 'Save/update the Windows credential now?' -DefaultYes $true) {
        try {
            Set-RdpCredential -RdpProfile $rdpProfile
            Write-Color 'The credential was saved in Windows Credential Manager.' Green
        }
        catch {
            Write-Color ("Credential could not be saved: {0}" -f $_.Exception.Message) Red
        }
    } else {
        Write-Color 'Credential storage was skipped.' Yellow
    }

    return $Profiles
}

function Rename-Profile {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles,
        [Parameter(Mandatory = $true)]$Config
    )

    Show-Header -Profiles $Profiles -Config $Config
    Show-Section 'List or rename saved profiles'
    if ($Profiles.Count -eq 0) {
        Write-Color 'No saved profiles were found.' Yellow
        return $Profiles
    }

    Show-Profiles -Profiles $Profiles -Config $Config
    Write-Host
    while ($true) {
        $answer = (Read-Host 'Enter a profile number to rename, or press Enter to return').Trim()
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Profiles
        }

        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and
            $number -ge 1 -and
            $number -le $Profiles.Count) {
            break
        }
        Write-Color ("Enter a number from 1 to {0}, or press Enter to return." -f $Profiles.Count) Red
    }

    $selectedIndex = $number - 1
    $selectedEntry = $Profiles[$selectedIndex]
    $currentName = [string](Get-ObjectPropertyValue -InputObject $selectedEntry -Name 'Name' -DefaultValue '')
    $currentShortcutName = [string](Get-ObjectPropertyValue -InputObject $selectedEntry -Name 'ShortcutName' -DefaultValue $currentName)

    while ($true) {
        $newName = Read-RequiredValue -Prompt 'Friendly name' -Default $currentName
        $nameOwner = $null
        for ($otherIndex = 0; $otherIndex -lt $Profiles.Count; $otherIndex++) {
            $otherName = [string](Get-ObjectPropertyValue -InputObject $Profiles[$otherIndex] -Name 'Name' -DefaultValue '')
            if ($otherIndex -ne $selectedIndex -and $otherName -ieq $newName) {
                $nameOwner = $otherName
                break
            }
        }
        if ($null -eq $nameOwner) {
            break
        }
        Write-Color ("Another profile already uses the name '{0}'. Choose another name." -f $nameOwner) Red
    }

    $newShortcutName = Read-UniqueShortcutName -Prompt 'Shortcut name' -Default $currentShortcutName -Profiles $Profiles -ExcludeIndex $selectedIndex
    $nameChanged = -not [string]::Equals($currentName, $newName, [StringComparison]::Ordinal)
    $shortcutStemChanged = -not [string]::Equals($currentShortcutName, $newShortcutName, [StringComparison]::OrdinalIgnoreCase)

    if (-not $nameChanged -and -not $shortcutStemChanged) {
        Write-Color 'No profile changes were made.' Yellow
        return $Profiles
    }

    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $updatedShortcuts = @(Get-RdpShortcutEntries -RdpProfile $selectedEntry)
    if ($shortcutStemChanged) {
        $updatedShortcuts = Move-RdpShortcutFilesForStemChange -RdpProfile $selectedEntry -Config $Config -NewStem $newShortcutName -Timestamp $now
    }

    $updatedEntry = Update-RdpProfileValues -RdpProfile $selectedEntry -Config $Config -Values @{
        Name         = $newName
        ShortcutName = $newShortcutName
        Shortcuts    = @($updatedShortcuts)
        UpdatedAt    = $now
    }
    $Profiles[$selectedIndex] = $updatedEntry

    Save-Database -Profiles $Profiles -Config $Config
    Write-Color 'The profile names were updated.' Green

    return $Profiles
}

function Remove-RdpProfile {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles,
        [Parameter(Mandatory = $true)]$Config
    )

    Show-Header -Profiles $Profiles -Config $Config
    Show-Section 'Delete saved profile'
    $selectedIndex = Select-ProfileIndex -Profiles $Profiles -Config $Config
    if ($null -eq $selectedIndex) {
        return $Profiles
    }

    $selectedEntry = $Profiles[$selectedIndex]
    $entryName = [string](Get-ObjectPropertyValue -InputObject $selectedEntry -Name 'Name' -DefaultValue '')
    $ipAddress = [string](Get-ObjectPropertyValue -InputObject $selectedEntry -Name 'IpAddress' -DefaultValue '')
    if (-not (Read-YesNo -Prompt "Delete profile '$entryName' from db.json?" -DefaultYes $false)) {
        Write-Color 'Nothing was deleted.' Yellow
        return $Profiles
    }

    $remainingEntries = @()
    for ($itemIndex = 0; $itemIndex -lt $Profiles.Count; $itemIndex++) {
        if ($itemIndex -ne $selectedIndex) {
            $remainingEntries += $Profiles[$itemIndex]
        }
    }

    Save-Database -Profiles $remainingEntries -Config $Config
    Write-Color 'The profile was removed from db.json.' Green

    $shortcutPaths = @(Get-RdpShortcutPaths -RdpProfile $selectedEntry -Config $Config)
    if ($shortcutPaths.Count -gt 0) {
        Write-Host
        Write-Color 'Shortcut files for this profile:' Cyan
        foreach ($shortcutPath in @($shortcutPaths)) {
            Write-Host ("- {0}" -f $shortcutPath)
        }
    }

    if ($shortcutPaths.Count -gt 0 -and (Read-YesNo -Prompt "Also delete the shortcut file(s) listed above?" -DefaultYes $true)) {
        $removalResult = Remove-RdpShortcutFiles -Paths $shortcutPaths
        if ($removalResult.Deleted -gt 0) {
            Write-Color ("Deleted {0} shortcut file(s)." -f $removalResult.Deleted) Green
        } elseif ($removalResult.Failed -eq 0) {
            Write-Color 'No matching shortcut files were found.' DarkGray
        }
    } elseif ($shortcutPaths.Count -gt 0) {
        Write-Color 'The shortcut files were left unchanged.' Yellow
    } else {
        Write-Color 'No shortcut files are configured for this profile.' DarkGray
    }

    if (Read-YesNo -Prompt "Also delete the TERMSRV/$ipAddress Windows credential?" -DefaultYes $false) {
        $cmdkeyOutput = @(& cmdkey.exe "/delete:TERMSRV/$ipAddress" 2>&1)
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            Write-Color 'The Windows credential was deleted.' Green
        } else {
            Write-Color ("Credential deletion failed with exit code {0}." -f $exitCode) Red
        }
    } else {
        Write-Color 'The Windows credential was left unchanged.' Yellow
    }

    return @($remainingEntries)
}

function Get-DisplayModeLabel {
    param([Parameter(Mandatory = $true)][string]$Mode)

    $displayMode = Get-DisplayModeValue -Mode $Mode -Fallback 'FullScreen'
    switch ($displayMode) {
        'Windowed' { return 'Windowed' }
        'AllMonitors' { return 'All monitors' }
        default { return 'Full screen' }
    }
}

function Select-DisplayModeFromList {
    param(
        [Parameter(Mandatory = $true)][string[]]$Modes,
        [Parameter(Mandatory = $true)][string]$Prompt
    )

    if ($Modes.Count -eq 0) {
        return $null
    }

    for ($index = 0; $index -lt $Modes.Count; $index++) {
        Write-Host ("{0}. {1}" -f ($index + 1), (Get-DisplayModeLabel -Mode $Modes[$index]))
    }

    while ($true) {
        $answer = (Read-Host $Prompt).Trim()
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and
            $number -ge 1 -and
            $number -le $Modes.Count) {
            return $Modes[$number - 1]
        }
        Write-Color ("Enter a number from 1 to {0}." -f $Modes.Count) Red
    }
}

function Show-RdpShortcutEntries {
    param(
        [Parameter(Mandatory = $true)]$RdpProfile,
        [Parameter(Mandatory = $true)]$Config
    )

    $entries = @(Get-RdpShortcutEntries -RdpProfile $RdpProfile)
    if ($entries.Count -eq 0) {
        Write-Color 'No shortcuts are configured for this profile.' Yellow
        return
    }

    Write-Color 'Configured shortcuts:' Cyan
    foreach ($shortcutEntry in @($entries)) {
        $entryMode = [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'Mode' -DefaultValue '')
        $fileBaseName = [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'FileBaseName' -DefaultValue '')
        $pathInfo = Get-ShortcutPathInfo -RdpProfile $RdpProfile -Config $Config -ShortcutEntry $shortcutEntry
        $presence = if (Test-Path -LiteralPath $pathInfo.Path) { 'present' } else { 'missing' }
        Write-Host ("- {0}: {1}.lnk ({2})" -f (Get-DisplayModeLabel -Mode $entryMode), $fileBaseName, $presence)
    }
}

function Update-RdpShortcutEntryTimestamps {
    param(
        [Parameter(Mandatory = $true)]$RdpProfile,
        [Parameter(Mandatory = $true)][string[]]$Modes,
        [Parameter(Mandatory = $true)][string]$Timestamp
    )

    $updatedEntries = @()
    foreach ($shortcutEntry in @(Get-RdpShortcutEntries -RdpProfile $RdpProfile)) {
        $entryMode = Get-DisplayModeValue -Mode ([string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'Mode' -DefaultValue 'FullScreen')) -Fallback 'FullScreen'
        $fileBaseName = [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'FileBaseName' -DefaultValue '')
        $createdAt = [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'CreatedAt' -DefaultValue $Timestamp)
        $updatedAt = [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'UpdatedAt' -DefaultValue $Timestamp)
        if ($Modes -icontains $entryMode) {
            $updatedAt = $Timestamp
        }
        $updatedEntries += New-RdpShortcutEntry -Mode $entryMode -FileBaseName $fileBaseName -CreatedAt $createdAt -UpdatedAt $updatedAt
    }

    return @($updatedEntries)
}

function New-SelectedShortcut {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles,
        [Parameter(Mandatory = $true)]$Config
    )

    Show-Header -Profiles $Profiles -Config $Config
    Show-Section 'Manage shortcuts for saved profile'
    $selectedIndex = Select-ProfileIndex -Profiles $Profiles -Config $Config
    if ($null -eq $selectedIndex) {
        return $Profiles
    }

    while ($true) {
        $selectedEntry = $Profiles[$selectedIndex]
        Show-Header -Profiles $Profiles -Config $Config
        Show-Section 'Manage shortcuts for a profile'
        Show-RdpProfileSummary -RdpProfile $selectedEntry
        Show-RdpShortcutEntries -RdpProfile $selectedEntry -Config $Config
        Write-Host
        Write-Host '1. Add a missing mode'
        Write-Host '2. Regenerate one shortcut'
        Write-Host '3. Regenerate all shortcuts for this profile'
        Write-Host '4. Remove one shortcut'
        Write-Host '5. Set default mode'
        Write-Host '6. Return'
        Write-Host

        $choice = (Read-Host 'Choose an option [1-6]').Trim()
        switch ($choice) {
            '1' {
                $missingModes = @()
                foreach ($displayMode in $script:ValidDisplayModes) {
                    if ($null -eq (Get-RdpShortcutEntryByMode -RdpProfile $selectedEntry -Mode $displayMode)) {
                        $missingModes += $displayMode
                    }
                }

                if ($missingModes.Count -eq 0) {
                    Write-Color 'All display modes are already configured.' Yellow
                    Wait-MenuReturn
                    continue
                }

                $selectedMode = Select-DisplayModeFromList -Modes $missingModes -Prompt 'Choose a mode to add'
                if ($null -eq $selectedMode) {
                    continue
                }

                $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $shortcutStem = [string](Get-ObjectPropertyValue -InputObject $selectedEntry -Name 'ShortcutName' -DefaultValue '')
                $updatedShortcuts = Set-RdpShortcutModes -RdpProfile $selectedEntry -Modes @($selectedMode) -Stem $shortcutStem -Timestamp $now
                $selectedEntry = Update-RdpProfileValues -RdpProfile $selectedEntry -Config $Config -Values @{
                    Shortcuts = @($updatedShortcuts)
                    UpdatedAt = $now
                }
                $Profiles[$selectedIndex] = $selectedEntry
                Save-Database -Profiles $Profiles -Config $Config

                try {
                    $shortcutEntry = Get-RdpShortcutEntryByMode -RdpProfile $selectedEntry -Mode $selectedMode
                    $shortcutPath = New-RdpShortcut -RdpProfile $selectedEntry -Config $Config -ShortcutEntry $shortcutEntry
                    Write-Color ("Shortcut created or updated: {0}" -f $shortcutPath) Green
                }
                catch {
                    Write-Color ("Shortcut could not be created: {0}" -f $_.Exception.Message) Red
                }
                Wait-MenuReturn
            }
            '2' {
                $existingModes = @()
                foreach ($shortcutEntry in @(Get-RdpShortcutEntries -RdpProfile $selectedEntry)) {
                    $existingModes += [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'Mode' -DefaultValue '')
                }
                $selectedMode = Select-DisplayModeFromList -Modes $existingModes -Prompt 'Choose a shortcut to regenerate'
                if ($null -eq $selectedMode) {
                    Wait-MenuReturn
                    continue
                }

                try {
                    $shortcutEntry = Get-RdpShortcutEntryByMode -RdpProfile $selectedEntry -Mode $selectedMode
                    $shortcutPath = New-RdpShortcut -RdpProfile $selectedEntry -Config $Config -ShortcutEntry $shortcutEntry
                    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    $updatedShortcuts = Update-RdpShortcutEntryTimestamps -RdpProfile $selectedEntry -Modes @($selectedMode) -Timestamp $now
                    $Profiles[$selectedIndex] = Update-RdpProfileValues -RdpProfile $selectedEntry -Config $Config -Values @{
                        Shortcuts = @($updatedShortcuts)
                        UpdatedAt = $now
                    }
                    Save-Database -Profiles $Profiles -Config $Config
                    Write-Color ("Shortcut created or updated: {0}" -f $shortcutPath) Green
                }
                catch {
                    Write-Color ("Shortcut could not be created: {0}" -f $_.Exception.Message) Red
                }
                Wait-MenuReturn
            }
            '3' {
                $okCount = 0
                $failedCount = 0
                foreach ($shortcutEntry in @(Get-RdpShortcutEntries -RdpProfile $selectedEntry)) {
                    try {
                        [void](New-RdpShortcut -RdpProfile $selectedEntry -Config $Config -ShortcutEntry $shortcutEntry)
                        $okCount++
                    }
                    catch {
                        $failedCount++
                        $entryMode = [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'Mode' -DefaultValue '')
                        Write-Color ("[FAILED] {0}: {1}" -f (Get-DisplayModeLabel -Mode $entryMode), $_.Exception.Message) Red
                    }
                }

                if ($okCount -gt 0) {
                    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    $allModes = @()
                    foreach ($shortcutEntry in @(Get-RdpShortcutEntries -RdpProfile $selectedEntry)) {
                        $allModes += [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'Mode' -DefaultValue '')
                    }
                    $updatedShortcuts = Update-RdpShortcutEntryTimestamps -RdpProfile $selectedEntry -Modes $allModes -Timestamp $now
                    $Profiles[$selectedIndex] = Update-RdpProfileValues -RdpProfile $selectedEntry -Config $Config -Values @{
                        Shortcuts = @($updatedShortcuts)
                        UpdatedAt = $now
                    }
                    Save-Database -Profiles $Profiles -Config $Config
                }
                Write-Color ("Regenerated: {0} ok, {1} failed." -f $okCount, $failedCount) Cyan
                Wait-MenuReturn
            }
            '4' {
                $entries = @(Get-RdpShortcutEntries -RdpProfile $selectedEntry)
                if ($entries.Count -le 1) {
                    Write-Color 'A profile must keep at least one configured shortcut. Delete the profile instead.' Yellow
                    Wait-MenuReturn
                    continue
                }

                $existingModes = @()
                foreach ($shortcutEntry in @($entries)) {
                    $existingModes += [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'Mode' -DefaultValue '')
                }
                $selectedMode = Select-DisplayModeFromList -Modes $existingModes -Prompt 'Choose a shortcut to remove'
                if ($null -eq $selectedMode) {
                    Wait-MenuReturn
                    continue
                }

                $shortcutEntryToRemove = Get-RdpShortcutEntryByMode -RdpProfile $selectedEntry -Mode $selectedMode
                $pathInfo = Get-ShortcutPathInfo -RdpProfile $selectedEntry -Config $Config -ShortcutEntry $shortcutEntryToRemove
                if (-not (Read-YesNo -Prompt ("Remove this shortcut and db entry? {0}" -f $pathInfo.Path) -DefaultYes $false)) {
                    Write-Color 'Nothing was removed.' Yellow
                    Wait-MenuReturn
                    continue
                }

                [void](Remove-RdpShortcutFiles -Paths @($pathInfo.Path))
                $remainingShortcuts = @()
                foreach ($shortcutEntry in @($entries)) {
                    $entryMode = Get-DisplayModeValue -Mode ([string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'Mode' -DefaultValue 'FullScreen')) -Fallback 'FullScreen'
                    if ($entryMode -ne (Get-DisplayModeValue -Mode $selectedMode -Fallback 'FullScreen')) {
                        $remainingShortcuts += $shortcutEntry
                    }
                }

                $currentDefaultMode = Get-DisplayModeValue -Mode ([string](Get-ObjectPropertyValue -InputObject $selectedEntry -Name 'DisplayMode' -DefaultValue 'FullScreen')) -Fallback 'FullScreen'
                $newDefaultMode = $currentDefaultMode
                if ($currentDefaultMode -eq (Get-DisplayModeValue -Mode $selectedMode -Fallback 'FullScreen')) {
                    $newDefaultMode = [string](Get-ObjectPropertyValue -InputObject $remainingShortcuts[0] -Name 'Mode' -DefaultValue 'FullScreen')
                }

                $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $Profiles[$selectedIndex] = Update-RdpProfileValues -RdpProfile $selectedEntry -Config $Config -Values @{
                    DisplayMode = $newDefaultMode
                    Shortcuts   = @($remainingShortcuts)
                    UpdatedAt   = $now
                }
                Save-Database -Profiles $Profiles -Config $Config
                Write-Color 'The shortcut was removed from disk and db.json.' Green
                Wait-MenuReturn
            }
            '5' {
                $existingModes = @()
                foreach ($shortcutEntry in @(Get-RdpShortcutEntries -RdpProfile $selectedEntry)) {
                    $existingModes += [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'Mode' -DefaultValue '')
                }
                $currentMode = Get-DisplayModeValue -Mode ([string](Get-ObjectPropertyValue -InputObject $selectedEntry -Name 'DisplayMode' -DefaultValue 'FullScreen')) -Fallback 'FullScreen'
                Write-Color ("Current default mode: {0}" -f (Get-DisplayModeLabel -Mode $currentMode)) Cyan
                $selectedMode = Select-DisplayModeFromList -Modes $existingModes -Prompt 'Choose the default mode'
                if ($null -eq $selectedMode) {
                    Wait-MenuReturn
                    continue
                }

                $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $Profiles[$selectedIndex] = Update-RdpProfileValues -RdpProfile $selectedEntry -Config $Config -Values @{
                    DisplayMode = $selectedMode
                    UpdatedAt   = $now
                }
                Save-Database -Profiles $Profiles -Config $Config
                Write-Color ("Default mode saved as: {0}" -f (Get-DisplayModeLabel -Mode $selectedMode)) Green
                Wait-MenuReturn
            }
            '6' {
                return $Profiles
            }
            default {
                Write-Color 'Choose a number from 1 to 6.' Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Update-AllShortcuts {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles,
        [Parameter(Mandatory = $true)]$Config
    )

    Show-Header -Profiles $Profiles -Config $Config
    Show-Section 'Regenerate all shortcuts'
    if ($Profiles.Count -eq 0) {
        Write-Color 'No saved profiles were found.' Yellow
        return $Profiles
    }

    Write-Host

    $okCount = 0
    $failedCount = 0
    $profilesWithShortcuts = 0
    for ($index = 0; $index -lt $Profiles.Count; $index++) {
        $entry = $Profiles[$index]
        $entryName = [string](Get-ObjectPropertyValue -InputObject $entry -Name 'Name' -DefaultValue '')
        $entryShortcuts = @(Get-RdpShortcutEntries -RdpProfile $entry)
        if ($entryShortcuts.Count -gt 0) {
            $profilesWithShortcuts++
        }

        $successfulModes = @()
        foreach ($shortcutEntry in @($entryShortcuts)) {
            $entryMode = [string](Get-ObjectPropertyValue -InputObject $shortcutEntry -Name 'Mode' -DefaultValue '')
            try {
                [void](New-RdpShortcut -RdpProfile $entry -Config $Config -ShortcutEntry $shortcutEntry)
                $okCount++
                $successfulModes += $entryMode
                Write-Color ("[OK] {0} ({1})" -f $entryName, (Get-DisplayModeLabel -Mode $entryMode)) Green
            }
            catch {
                $failedCount++
                Write-Color ("[FAILED] {0} ({1}): {2}" -f $entryName, (Get-DisplayModeLabel -Mode $entryMode), $_.Exception.Message) Red
            }
        }

        if ($successfulModes.Count -gt 0) {
            $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            $updatedShortcuts = Update-RdpShortcutEntryTimestamps -RdpProfile $entry -Modes $successfulModes -Timestamp $now
            $Profiles[$index] = Update-RdpProfileValues -RdpProfile $entry -Config $Config -Values @{
                Shortcuts = @($updatedShortcuts)
                UpdatedAt = $now
            }
        }
    }

    if ($okCount -gt 0) {
        Save-Database -Profiles $Profiles -Config $Config
    }
    Write-Host
    Write-Color ("{0} shortcuts across {1} profiles regenerated; {2} failed." -f $okCount, $profilesWithShortcuts, $failedCount) Cyan
    return $Profiles
}

function Connect-RdpProfile {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles,
        [Parameter(Mandatory = $true)]$Config
    )

    Show-Header -Profiles $Profiles -Config $Config
    Show-Section 'Connect now (no shortcut)'
    $selectedIndex = Select-ProfileIndex -Profiles $Profiles -Config $Config
    if ($null -eq $selectedIndex) {
        return
    }

    $selectedEntry = $Profiles[$selectedIndex]
    $currentMode = Get-DisplayModeValue -Mode ([string](Get-ObjectPropertyValue -InputObject $selectedEntry -Name 'DisplayMode' -DefaultValue 'FullScreen')) -Fallback 'FullScreen'
    Write-Color ("Default mode: {0}" -f (Get-DisplayModeLabel -Mode $currentMode)) Cyan
    $selectedMode = Read-DisplayMode -DefaultMode $currentMode -Prompt ("Display mode (Enter = {0})" -f (Get-DisplayModeLabel -Mode $currentMode))
    $mstscPath = Get-MstscPath -Config $Config
    $arguments = Get-RdpArguments -RdpProfile $selectedEntry -Config $Config -Mode $selectedMode
    Start-Process -FilePath $mstscPath -ArgumentList $arguments
    Write-Color 'Remote Desktop was started.' Green
}

function Update-SelectedCredential {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$Profiles,
        [Parameter(Mandatory = $true)]$Config
    )

    Show-Header -Profiles $Profiles -Config $Config
    Show-Section 'Add or update credential'
    $selectedIndex = Select-ProfileIndex -Profiles $Profiles -Config $Config
    if ($null -eq $selectedIndex) {
        return
    }

    Set-RdpCredential -RdpProfile $Profiles[$selectedIndex]
    Write-Color 'The credential was saved in Windows Credential Manager.' Green
}

function Open-ProjectFolder {
    Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$script:ProjectFolder`""
    Write-Color 'Project folder opened in File Explorer.' Green
}

function Show-MainMenu {
    Write-Color 'Profiles' DarkGray
    Write-Host '  1. Add new RDP profile'
    Write-Host '  2. List or rename saved profiles'
    Write-Host '  3. Delete saved profile'
    Write-Host
    Write-Color 'Shortcuts' DarkGray
    Write-Host '  4. Manage shortcuts for saved profile'
    Write-Host '  5. Regenerate all shortcuts'
    Write-Host '  6. Connect now (no shortcut)'
    Write-Host
    Write-Color 'Credentials' DarkGray
    Write-Host '  7. Add or update credential only'
    Write-Host
    Write-Color 'System' DarkGray
    Write-Host '  8. Open project folder'
    Write-Host '  9. Exit'
    Write-Host
}

if ($env:RDP_SHORTCUT_FORGE_IMPORT_ONLY -ne '1') {
    try {
        if (-not (Test-Path -LiteralPath $script:ProjectFolder)) {
            New-Item -ItemType Directory -Path $script:ProjectFolder -Force | Out-Null
        }

        $config = Initialize-Config
        $profiles = @(Initialize-Database -Config $config)

        while ($true) {
            Show-Header -Profiles $profiles -Config $config
            Show-MainMenu
            $choice = (Read-Host 'Choose an option [1-9]').Trim()
            $pauseAfterAction = $true

            try {
                switch ($choice) {
                    '1' {
                        $profiles = @(Add-RdpProfile -Profiles $profiles -Config $config)
                    }
                    '2' {
                        $profiles = @(Rename-Profile -Profiles $profiles -Config $config)
                    }
                    '3' {
                        $profiles = @(Remove-RdpProfile -Profiles $profiles -Config $config)
                    }
                    '4' {
                        $profiles = @(New-SelectedShortcut -Profiles $profiles -Config $config)
                    }
                    '5' {
                        $profiles = @(Update-AllShortcuts -Profiles $profiles -Config $config)
                    }
                    '6' {
                        Connect-RdpProfile -Profiles $profiles -Config $config
                    }
                    '7' {
                        Update-SelectedCredential -Profiles $profiles -Config $config
                    }
                    '8' {
                        Show-Header -Profiles $profiles -Config $config
                        Open-ProjectFolder
                    }
                    '9' {
                        Write-Color 'Goodbye.' Cyan
                        exit 0
                    }
                    default {
                        Write-Color 'Choose a number from 1 to 9.' Red
                        $pauseAfterAction = $false
                        Start-Sleep -Seconds 1
                    }
                }
            }
            catch {
                Write-Color ("The action could not be completed: {0}" -f $_.Exception.Message) Red
            }

            if ($pauseAfterAction) {
                Wait-MenuReturn
            }
        }
    }
    catch {
        Write-Host
        Write-Color ("RDP Shortcut Forge could not continue: {0}" -f $_.Exception.Message) Red
        exit 1
    }
}
