@echo off
setlocal
set "WORDFIX_SELF=%~f0"
set "WORDFIX_INPUT=%~1"
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -Command "$raw=[IO.File]::ReadAllText($env:WORDFIX_SELF); $code=($raw -split ('# POWERSHELL_'+'START'),2)[1]; & ([scriptblock]::Create($code))"
set "result=%errorlevel%"
echo.
pause
exit /b %result%
# POWERSHELL_START
$ErrorActionPreference = 'Stop'

function Set-WAttr {
    param(
        [System.Xml.XmlElement]$Element,
        [string]$LocalName,
        [string]$NamespaceUri,
        [string]$Value
    )
    $attr = $Element.Attributes.GetNamedItem($LocalName, $NamespaceUri)
    if ($null -eq $attr) {
        $attr = $Element.OwnerDocument.CreateAttribute('w', $LocalName, $NamespaceUri)
        [void]$Element.Attributes.Append($attr)
    }
    $attr.Value = $Value
}

function Get-OrCreate-RPr {
    param(
        [System.Xml.XmlElement]$Run,
        [System.Xml.XmlNamespaceManager]$Ns,
        [string]$WNs
    )
    $rPr = $Run.SelectSingleNode('./w:rPr', $Ns)
    if ($null -eq $rPr) {
        $rPr = $Run.OwnerDocument.CreateElement('w', 'rPr', $WNs)
        if ($Run.HasChildNodes) { [void]$Run.InsertBefore($rPr, $Run.FirstChild) }
        else { [void]$Run.AppendChild($rPr) }
    }
    return $rPr
}

function Set-RunLanguage {
    param(
        [System.Xml.XmlElement]$RPr,
        [System.Xml.XmlNamespaceManager]$Ns,
        [string]$WNs,
        [string]$Val,
        [string]$EastAsia,
        [string]$Bidi
    )
    $lang = $RPr.SelectSingleNode('./w:lang', $Ns)
    if ($null -eq $lang) {
        $lang = $RPr.OwnerDocument.CreateElement('w', 'lang', $WNs)
        [void]$RPr.AppendChild($lang)
    }
    Set-WAttr -Element $lang -LocalName 'val'      -NamespaceUri $WNs -Value $Val
    Set-WAttr -Element $lang -LocalName 'eastAsia' -NamespaceUri $WNs -Value $EastAsia
    Set-WAttr -Element $lang -LocalName 'bidi'     -NamespaceUri $WNs -Value $Bidi
}

try {
    if ($env:WORDFIX_INPUT) {
        $files = @((Get-Item -LiteralPath $env:WORDFIX_INPUT).FullName)
    }
    else {
        Add-Type -AssemblyName System.Windows.Forms
        $picker = New-Object System.Windows.Forms.OpenFileDialog
        $picker.Title = 'Select Word document(s) - repair Arabic and English proofing'
        $picker.Filter = 'Word documents (*.docx)|*.docx'
        $picker.Multiselect = $true
        try {
            if ($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) {
                Write-Host 'Cancelled.'
                exit 0
            }
            $files = @($picker.FileNames)
        }
        finally { $picker.Dispose() }
    }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $wNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'

    # Arabic blocks, including presentation forms.
    $arabicRegex = '[\u0600-\u06FF\u0750-\u077F\u0870-\u089F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]'
    $latinRegex  = '[A-Za-z\u00C0-\u024F]'

    foreach ($inputFile in $files) {
        if ([IO.Path]::GetExtension($inputFile) -ine '.docx') {
            throw 'Please select a .docx file.'
        }

        $directory = [IO.Path]::GetDirectoryName($inputFile)
        $baseName = [IO.Path]::GetFileNameWithoutExtension($inputFile)
        $outputFile = Join-Path $directory ($baseName + '-LANG-FIXED-V2.docx')
        $n = 2
        while (Test-Path -LiteralPath $outputFile) {
            $outputFile = Join-Path $directory ($baseName + '-LANG-FIXED-V2-' + $n + '.docx')
            $n++
        }

        Write-Host ''
        Write-Host '=====================================================' -ForegroundColor Cyan
        Write-Host 'Word proofing-language repair V2' -ForegroundColor Cyan
        Write-Host '=====================================================' -ForegroundColor Cyan
        Write-Host "Input : $inputFile"
        Write-Host "Output: $outputFile"
        Write-Host ''
        Write-Host 'Arabic-only run : ar-SA in ALL language slots' -ForegroundColor Yellow
        Write-Host 'English-only run: en-US in ALL language slots' -ForegroundColor Yellow
        Write-Host 'Mixed run       : en-US Latin + ar-SA RTL' -ForegroundColor Yellow
        Write-Host 'Scope           : body, TABLES, comments, headers, footers, text boxes, notes and tracked text' -ForegroundColor Yellow
        Write-Host ''

        Copy-Item -LiteralPath $inputFile -Destination $outputFile
        (Get-Item -LiteralPath $outputFile).IsReadOnly = $false

        $zip = [IO.Compression.ZipFile]::Open($outputFile, [IO.Compression.ZipArchiveMode]::Update)
        try {
            $entries = @($zip.Entries | Where-Object { $_.FullName -match '^word/.+\.xml$' })
            $totalEntries = $entries.Count
            $entryIndex = 0
            $arabicCount = 0
            $englishCount = 0
            $mixedCount = 0
            $proofErrCount = 0
            $changedParts = 0

            foreach ($entry in $entries) {
                $entryIndex++
                $partName = $entry.FullName
                $pct = if ($totalEntries -gt 0) { [math]::Floor((($entryIndex - 1) / $totalEntries) * 100) } else { 0 }
                Write-Progress -Activity 'Repairing Word proofing languages' -Status "Part $entryIndex / $totalEntries : $partName" -PercentComplete $pct
                Write-Host "[$entryIndex/$totalEntries] $partName"

                $stream = $entry.Open()
                try {
                    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $true)
                    try { $xmlText = $reader.ReadToEnd() }
                    finally { $reader.Dispose() }
                }
                finally { $stream.Dispose() }

                if ($xmlText -notmatch 'wordprocessingml/2006/main') {
                    Write-Host '    skipped (no WordprocessingML)'
                    continue
                }

                $xml = New-Object Xml.XmlDocument
                $xml.PreserveWhitespace = $true
                $xml.LoadXml($xmlText)
                $ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
                $ns.AddNamespace('w', $wNs)
                $partChanged = $false

                # Classify EACH visible text run by the characters actually inside it.
                # This is the important V2 change: Arabic table runs no longer keep w:val=en-US.
                $runs = @($xml.SelectNodes('//w:r', $ns))
                foreach ($run in $runs) {
                    $textNodes = @($run.SelectNodes('.//w:t | .//w:delText', $ns))
                    if ($textNodes.Count -eq 0) { continue }

                    $text = (($textNodes | ForEach-Object { $_.InnerText }) -join '')
                    if ([string]::IsNullOrEmpty($text)) { continue }

                    $hasArabic = [regex]::IsMatch($text, $arabicRegex)
                    $hasLatin  = [regex]::IsMatch($text, $latinRegex)
                    if (-not $hasArabic -and -not $hasLatin) { continue }

                    $rPr = Get-OrCreate-RPr -Run $run -Ns $ns -WNs $wNs

                    if ($hasArabic -and -not $hasLatin) {
                        # Arabic only: force every possible Word script slot to Arabic.
                        Set-RunLanguage -RPr $rPr -Ns $ns -WNs $wNs -Val 'ar-SA' -EastAsia 'ar-SA' -Bidi 'ar-SA'
                        $arabicCount++
                    }
                    elseif ($hasLatin -and -not $hasArabic) {
                        # English/Latin only: force every slot to English US.
                        Set-RunLanguage -RPr $rPr -Ns $ns -WNs $wNs -Val 'en-US' -EastAsia 'en-US' -Bidi 'en-US'
                        $englishCount++
                    }
                    else {
                        # Arabic + English in the SAME Word run.
                        Set-RunLanguage -RPr $rPr -Ns $ns -WNs $wNs -Val 'en-US' -EastAsia 'en-US' -Bidi 'ar-SA'
                        $mixedCount++
                    }
                    $partChanged = $true
                }

                # Remove Word's cached red/blue proofing markers and force a fresh check.
                $proofErrors = @($xml.SelectNodes('//w:proofErr', $ns))
                foreach ($proofErr in $proofErrors) {
                    [void]$proofErr.ParentNode.RemoveChild($proofErr)
                    $proofErrCount++
                    $partChanged = $true
                }

                # Default mapping for styles/newly typed content.
                if ($partName -eq 'word/styles.xml') {
                    $styles = $xml.SelectSingleNode('/w:styles', $ns)
                    if ($null -ne $styles) {
                        $docDefaults = $styles.SelectSingleNode('./w:docDefaults', $ns)
                        if ($null -eq $docDefaults) {
                            $docDefaults = $xml.CreateElement('w', 'docDefaults', $wNs)
                            if ($styles.HasChildNodes) { [void]$styles.InsertBefore($docDefaults, $styles.FirstChild) }
                            else { [void]$styles.AppendChild($docDefaults) }
                        }
                        $rPrDefault = $docDefaults.SelectSingleNode('./w:rPrDefault', $ns)
                        if ($null -eq $rPrDefault) {
                            $rPrDefault = $xml.CreateElement('w', 'rPrDefault', $wNs)
                            [void]$docDefaults.AppendChild($rPrDefault)
                        }
                        $defaultRPr = $rPrDefault.SelectSingleNode('./w:rPr', $ns)
                        if ($null -eq $defaultRPr) {
                            $defaultRPr = $xml.CreateElement('w', 'rPr', $wNs)
                            [void]$rPrDefault.AppendChild($defaultRPr)
                        }
                        Set-RunLanguage -RPr $defaultRPr -Ns $ns -WNs $wNs -Val 'en-US' -EastAsia 'en-US' -Bidi 'ar-SA'

                        # Styles use bilingual defaults; existing visible runs above have explicit language tags.
                        $styleRPrs = @($xml.SelectNodes('//w:style/w:rPr', $ns))
                        foreach ($styleRPr in $styleRPrs) {
                            Set-RunLanguage -RPr $styleRPr -Ns $ns -WNs $wNs -Val 'en-US' -EastAsia 'en-US' -Bidi 'ar-SA'
                        }
                        $partChanged = $true
                    }
                }

                if ($partName -eq 'word/settings.xml') {
                    $settings = $xml.SelectSingleNode('/w:settings', $ns)
                    if ($null -ne $settings) {
                        $proofState = $settings.SelectSingleNode('./w:proofState', $ns)
                        if ($null -eq $proofState) {
                            $proofState = $xml.CreateElement('w', 'proofState', $wNs)
                            [void]$settings.AppendChild($proofState)
                        }
                        Set-WAttr -Element $proofState -LocalName 'spelling' -NamespaceUri $wNs -Value 'dirty'
                        Set-WAttr -Element $proofState -LocalName 'grammar'  -NamespaceUri $wNs -Value 'dirty'
                        $partChanged = $true
                    }
                }

                if ($partChanged) {
                    $memory = New-Object IO.MemoryStream
                    try {
                        $writerSettings = New-Object Xml.XmlWriterSettings
                        $writerSettings.Encoding = New-Object Text.UTF8Encoding($false)
                        $writerSettings.Indent = $false
                        $writerSettings.OmitXmlDeclaration = $false
                        $writer = [Xml.XmlWriter]::Create($memory, $writerSettings)
                        try { $xml.Save($writer) }
                        finally { $writer.Dispose() }
                        $bytes = $memory.ToArray()
                    }
                    finally { $memory.Dispose() }

                    $entry.Delete()
                    $newEntry = $zip.CreateEntry($partName, [IO.Compression.CompressionLevel]::Optimal)
                    $outStream = $newEntry.Open()
                    try { $outStream.Write($bytes, 0, $bytes.Length) }
                    finally { $outStream.Dispose() }
                    $changedParts++
                }
            }

            Write-Progress -Activity 'Repairing Word proofing languages' -Completed
            Write-Host ''
            Write-Host 'VERIFYING TABLE RUNS...' -ForegroundColor Cyan

            # Verification happens after the package is closed below.
        }
        finally { $zip.Dispose() }

        # Re-open read-only and verify that every Arabic/English table run has the expected direct language tag.
        $verifyZip = [IO.Compression.ZipFile]::OpenRead($outputFile)
        try {
            $docEntry = $verifyZip.GetEntry('word/document.xml')
            $s = $docEntry.Open()
            try {
                $r = New-Object IO.StreamReader($s, [Text.Encoding]::UTF8, $true)
                try { $docXmlText = $r.ReadToEnd() }
                finally { $r.Dispose() }
            }
            finally { $s.Dispose() }

            $docXml = New-Object Xml.XmlDocument
            $docXml.PreserveWhitespace = $true
            $docXml.LoadXml($docXmlText)
            $vns = New-Object Xml.XmlNamespaceManager($docXml.NameTable)
            $vns.AddNamespace('w', $wNs)
            $badTableRuns = 0
            $checkedTableRuns = 0
            $tableRuns = @($docXml.SelectNodes('//w:tbl//w:r', $vns))

            foreach ($run in $tableRuns) {
                $nodes = @($run.SelectNodes('.//w:t | .//w:delText', $vns))
                if ($nodes.Count -eq 0) { continue }
                $txt = (($nodes | ForEach-Object { $_.InnerText }) -join '')
                $a = [regex]::IsMatch($txt, $arabicRegex)
                $e = [regex]::IsMatch($txt, $latinRegex)
                if (-not $a -and -not $e) { continue }
                $checkedTableRuns++
                $lang = $run.SelectSingleNode('./w:rPr/w:lang', $vns)
                if ($null -eq $lang) { $badTableRuns++; continue }

                $val = $lang.GetAttribute('val', $wNs)
                $east = $lang.GetAttribute('eastAsia', $wNs)
                $bidi = $lang.GetAttribute('bidi', $wNs)

                if ($a -and -not $e) {
                    if ($val -ne 'ar-SA' -or $east -ne 'ar-SA' -or $bidi -ne 'ar-SA') { $badTableRuns++ }
                }
                elseif ($e -and -not $a) {
                    if ($val -ne 'en-US' -or $east -ne 'en-US' -or $bidi -ne 'en-US') { $badTableRuns++ }
                }
                else {
                    if ($val -ne 'en-US' -or $east -ne 'en-US' -or $bidi -ne 'ar-SA') { $badTableRuns++ }
                }
            }
        }
        finally { $verifyZip.Dispose() }

        Write-Host ''
        Write-Host '=====================================================' -ForegroundColor Green
        Write-Host 'DONE' -ForegroundColor Green
        Write-Host '=====================================================' -ForegroundColor Green
        Write-Host "Arabic-only runs fixed : $arabicCount"
        Write-Host "English-only runs fixed: $englishCount"
        Write-Host "Mixed runs fixed       : $mixedCount"
        Write-Host "Saved proof errors removed: $proofErrCount"
        Write-Host "XML parts changed      : $changedParts"
        Write-Host "Table text runs checked: $checkedTableRuns"
        if ($badTableRuns -eq 0) {
            Write-Host 'TABLE VERIFICATION      : PASS (0 incorrectly tagged runs)' -ForegroundColor Green
        }
        else {
            Write-Host "TABLE VERIFICATION      : FAIL ($badTableRuns incorrectly tagged runs)" -ForegroundColor Red
        }
        Write-Host ''
        Write-Host "Saved to: $outputFile" -ForegroundColor Cyan
    }
}
catch {
    Write-Host ''
    Write-Host 'ERROR:' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
