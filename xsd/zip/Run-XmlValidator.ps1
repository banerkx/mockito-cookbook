param(
    [string]$BasePath = ".\xml-xsd-tests"
)

function Test-Xml {
    param(
        [string]$XmlPath,
        [string[]]$XsdPaths
    )

    $xmlReaderSettings = New-Object System.Xml.XmlReaderSettings
    $schemaSet = New-Object System.Xml.Schema.XmlSchemaSet

    # allow both local + remote imports
    $schemaSet.XmlResolver = New-Object System.Xml.XmlUrlResolver

    foreach ($xsd in $XsdPaths) {
        try {
            $schemaSet.Add($null, $xsd) | Out-Null
        } catch {
            Write-Host "  ❌ Failed to load schema: $xsd" -ForegroundColor Red
            return $false
        }
    }

    $xmlReaderSettings.Schemas = $schemaSet
    $xmlReaderSettings.ValidationType = [System.Xml.ValidationType]::Schema
    $xmlReaderSettings.XmlResolver = New-Object System.Xml.XmlUrlResolver

    $hasErrors = $false
    $xmlReaderSettings.add_ValidationEventHandler({
        param($sender, $args)
        Write-Host ("  ❌ Validation error: {0}" -f $args.Message) -ForegroundColor Red
        $hasErrors = $true
    })

    try {
        $reader = [System.Xml.XmlReader]::Create($XmlPath, $xmlReaderSettings)
        while ($reader.Read()) { } # parse entire document
        $reader.Close()
    } catch {
        Write-Host "  ❌ Exception: $_" -ForegroundColor Red
        return $false
    }

    if ($hasErrors) {
        return $false
    } else {
        return $true
    }
}

Write-Host "🔎 Running XML Schema Validation Tests..." -ForegroundColor Cyan
$allSets = Get-ChildItem -Path $BasePath -Directory | Sort-Object Name

foreach ($set in $allSets) {
    Write-Host "`n▶ Testing $($set.Name)" -ForegroundColor Yellow

    $xmlFile = Get-ChildItem -Path $set.FullName -Filter *.xml | Select-Object -First 1
    $xsdFiles = Get-ChildItem -Path $set.FullName -Filter *.xsd

    if (-not $xmlFile -or -not $xsdFiles) {
        Write-Host "  ⚠ Missing XML or XSD files in $($set.Name)" -ForegroundColor DarkYellow
        continue
    }

    $result = Test-Xml -XmlPath $xmlFile.FullName -XsdPaths $xsdFiles.FullName
    if ($result) {
        Write-Host "  ✅ $($xmlFile.Name) is valid" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $($xmlFile.Name) is invalid" -ForegroundColor Red
    }
}

Write-Host "`n🏁 Validation run complete." -ForegroundColor Cyan
