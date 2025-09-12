
<#
.SYNOPSIS
    Validates an XML file against a specified XSD schema file.

.DESCRIPTION
    This function uses .NET classes to perform schema validation on an XML file.
    It first loads the XSD schema to determine its target namespace, then loads
    the XML document, and finally validates the document against a schema set
    configured with the correct namespace. This is the most reliable method
    for handling namespaced XML and reporting all errors.

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

        # Load the XSD schema as an XmlDocument to get the target namespace.
        # This is a crucial step to correctly link the schema to the XML.
        $xsdDoc = New-Object System.Xml.XmlDocument
        $xsdDoc.Load($XsdPath)
        
        # Determine the target namespace of the XSD schema.
        $targetNamespace = $xsdDoc.documentElement.GetAttribute("targetNamespace")
        
        # Add the XSD schema to the set with its specific target namespace.
        # If the targetNamespace attribute is not present, the first parameter should be null.
        if ([string]::IsNullOrEmpty($targetNamespace)) {
            [void]$schemaSet.Add($null, $XsdPath)
        } else {
            [void]$schemaSet.Add($targetNamespace, $XsdPath)
        }

        # Compile the schema set for faster validation
        $schemaSet.Compile()

        # Create a new XmlDocument object and load the XML file
        $xmlDoc = New-Object System.Xml.XmlDocument
        $xmlDoc.Load($XmlPath)

        # Assign the schema set to the XML document for validation
        $xmlDoc.Schemas.Add($schemaSet)

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

Validate-XmlFile -XmlPath pom.xml -XsdPath maven-4.0.0.xsd
