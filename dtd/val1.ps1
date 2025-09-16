
<#
.SYNOPSIS
    Validates an XML file against a specified XSD schema file.

.DESCRIPTION
    This function performs robust schema validation on an XML file by
    first loading the XSD to explicitly determine its target namespace. It then
    uses this information to correctly apply the schema to the XML document,
    ensuring that all validation errors are properly reported.

.PARAMETER XmlPath
    The path to the XML file to be validated.

.PARAMETER XsdPath
    The path to the XSD schema file used for validation.

.EXAMPLE
    Validate-XmlFile -XmlPath "C:\Data\MyDocument.xml" -XsdPath "C:\Data\MySchema.xsd"

.NOTES
    Requires the .NET Framework, which is standard on modern Windows systems.
    The function reports a success or failure status and provides detailed error messages.
#>
function Validate-XmlFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$XmlPath,

        [Parameter(Mandatory=$true)]
        [string]$XsdPath
    )

    # Check if the XML and XSD files exist
    if (-not (Test-Path $XmlPath)) {
        Write-Error "XML file not found: $XmlPath"
        return $false
    }
    if (-not (Test-Path $XsdPath)) {
        Write-Error "XSD schema file not found: $XsdPath"
        return $false
    }

    # Use a try/catch block to handle potential exceptions
    try {
        # Create a collection to hold validation errors
        $validationErrors = @()

        # Create a new XmlSchemaSet to manage the schemas
        $schemaSet = New-Object System.Xml.Schema.XmlSchemaSet

        # Use an XmlReader to load the XSD schema and get its target namespace.
        # This is the most reliable way to link the schema to the XML.
        $xsdReader = [System.Xml.XmlReader]::Create($XsdPath)
        $xsdSchema = [System.Xml.Schema.XmlSchema]::Read($xsdReader, $null)

        # Add the XSD schema to the set. Use the schema's own target namespace
        # to ensure it's correctly applied to the XML document.
        [void]$schemaSet.Add($xsdSchema.TargetNamespace, $XsdPath)

        # Compile the schema set for faster validation
        $schemaSet.Compile()

        # Create a new XmlDocument object and load the XML file
        $xmlDoc = New-Object System.Xml.XmlDocument
        $xmlDoc.Load($XmlPath)

        # Assign the schema set to the XML document for validation
        $xmlDoc.Schemas = $schemaSet

        # Create an event handler to capture all validation errors and warnings
        $validationEventHandler = [System.Xml.Schema.ValidationEventHandler]{
            param($sender, $eventArgs)
            # Add a custom object to the error collection with the error level and message
            $validationErrors += [PSCustomObject]@{
                Level    = $eventArgs.Severity.ToString()
                Message  = $eventArgs.Message
                Line     = $eventArgs.Exception.LineNumber
                Position = $eventArgs.Exception.LinePosition
            }
        }

        # Validate the XML document against the schema set and capture all errors
        $xmlDoc.Validate($validationEventHandler)

        # Check if any errors or warnings were found
        if ($validationErrors.Count -gt 0) {
            Write-Warning "Validation completed with errors."
            Write-Output "--- Errors and Warnings ---"
            # Output each error/warning in the collection
            $validationErrors | Format-Table -AutoSize
            return $false
        } else {
            Write-Host "Validation successful. The XML file is valid against the schema." -ForegroundColor Green
            return $true
        }
    } catch {
        # Catch any unexpected exceptions during the process, including
        # fatal XML syntax errors that prevent full parsing.
        Write-Error "An unexpected error occurred during validation: $_"
        return $false
    }
}

Validate-XmlFile -XmlPath pom.xml -XsdPath ../maven-4.0.0.xsd

