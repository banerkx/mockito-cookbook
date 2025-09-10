Add-Type -AssemblyName System.Xml

# Paths to XML and XSD (Unix-style)
${xmlPath} = './pom.xml'
${xsdPath} = './maven-4.0.0.xsd'

# Load schema properly
${schemaSet} = New-Object System.Xml.Schema.XmlSchemaSet
${schemaReader} = [System.Xml.XmlReader]::Create(${xsdPath})
${null} = ${schemaSet}.Add(${null}, ${schemaReader})
${schemaReader}.Close()

# Load XML
${xmlDoc} = New-Object System.Xml.XmlDocument
${xmlDoc}.Schemas = ${schemaSet}
${xmlDoc}.Load(${xmlPath})

# Collect validation errors
${errors} = @()

# Define validation event handler
${handler} = [System.Xml.Schema.ValidationEventHandler] {
  param(${source}, ${e})
  ${errors} += [PSCustomObject]@{
    Severity = ${e}.Severity
    Message  = ${e}.Message
    Node     = if (${source} -is [System.Xml.XmlNode])
    {
      ${source}.OuterXml.Substring(0, [Math]::Min(80, ${source}.OuterXml.Length))
    }
    else
    {
      '<unknown>'
    }
  }
}

# Validate each node individually
foreach (${node} in ${xmlDoc}.SelectNodes('//*'))
{
  ${xmlDoc}.Validate(${handler}, ${node})
}

# Show results
if (${errors}.Count -eq 0)
{
  Write-Output 'XML is valid against schema.' -ForegroundColor Green
}
else
{
  Write-Output 'Validation errors found:' -ForegroundColor Red
  ${errors} | Format-Table -AutoSize
}

