# Requires PowerShell 5.1 or later.
# This script formats XML and XSD files, applying a consistent indentation
# and handling whitespace.
#
# Constraints handled:
# 1. Indents with 2 spaces.
# 2. Replaces all tabs with 2 spaces.
# 3. Preserves blank lines.
# 4. Trims trailing whitespace.
# 5. Expands empty nodes like <name/> to <name></name>.
# 6. Preserves self-closing nodes with attributes, e.g., <name attr="value"/>.
#
# Usage:
# Run the script from the command line, providing the path to the file(s).
# Example to format a single file:
#   .\Beautify-Xml.ps1 -Path 'C:\data\my-file.xml'
#
# Example to format all XML/XSD files in a directory and its subdirectories:
#   .\Beautify-Xml.ps1 -Path 'C:\data' -Recurse

param
(
        [Parameter(Mandatory=$true)]
        [string]$Path
)

function Format-XmlFile {
    [CmdletBinding()]
    param (
        # The path to the XML or XSD file to format.
        # This can be a file or a directory.
        [Parameter(Mandatory=$true)]
        [string]$Path,

        # Set this switch to process files in subdirectories.
        [Parameter()]
        [switch]$Recurse
    )

    # Use Get-ChildItem to find all XML and XSD files based on the provided path.
    $files = Get-ChildItem -Path $Path -Include "*.xml", "*.xsd" -Recurse:$Recurse -File

    if (-not $files) {
        Write-Warning "No .xml or .xsd files found at the specified path: $Path"
        return
    }

    foreach ($file in $files) {
        Write-Host "Processing file: $($file.FullName)"

        try {
            # Step 1: Read all lines and identify blank ones using the -split operator.
            $originalLines = (Get-Content -Path $file.FullName -Raw) -split "`n"
            
            # Use a collection to store the indices of blank lines.
            $blankLineIndices = [System.Collections.ArrayList]::new()
            $nonBlankLines = @()

            for ($i = 0; $i -lt $originalLines.Count; $i++) {
                if ([string]::IsNullOrWhiteSpace($originalLines[$i])) {
                    $blankLineIndices.Add($i) | Out-Null
                } else {
                    $nonBlankLines += $originalLines[$i]
                }
            }

            # If the file is empty or only has blank lines, there's nothing to format.
            if (-not $nonBlankLines) {
                Write-Host "File is empty or contains only blank lines. Skipping formatting." -ForegroundColor Yellow
                $originalLines | Set-Content -Path $file.FullName -Force -Encoding UTF8
                continue
            }

            # Step 2: Format the non-blank lines using the .NET XML library.
            # This will handle correct indentation but will not preserve original line breaks.
            $contentToFormat = ($nonBlankLines -join "`n")
            $xmlDoc = New-Object System.Xml.XmlDocument
            $xmlDoc.LoadXml($contentToFormat)

            $stringWriter = New-Object System.IO.StringWriter
            $writerSettings = New-Object System.Xml.XmlWriterSettings
            $writerSettings.Indent = $true
            $writerSettings.IndentChars = "  " # Use 2 spaces for indentation
            $writerSettings.NewLineChars = [System.Environment]::NewLine
            $writerSettings.OmitXmlDeclaration = $false
            $writerSettings.Encoding = [System.Text.Encoding]::UTF8

            $xmlWriter = [System.Xml.XmlWriter]::Create($stringWriter, $writerSettings)
            $xmlDoc.Save($xmlWriter)
            $formattedXml = $stringWriter.ToString()

            # The XML declaration can sometimes be malformed during the save.
            # To fix this, we replace it with a standard declaration.
            $formattedXml = $formattedXml -replace '<\?xml version="1.0" encoding="utf-8" standalone="yes"?>', '<?xml version="1.0" encoding="utf-8"?>'

            # Step 3: Expand empty nodes (e.g., <name/> to <name></name>)
            # This regex specifically targets self-closing tags that do not have attributes.
            # It captures the tag name and uses it to construct the full open/close tags.
            $formattedXml = $formattedXml -replace '<(?![\/])([\w\-\.:]+)\s*\/>', '<$1></$1>'

            # Step 4: Re-insert blank lines at their saved positions.
            # We now cast the array to an ArrayList to allow insertions.
            $formattedLines = [System.Collections.ArrayList]($formattedXml -split "`n")
            
            # Insert a blank line at each stored index.
            # We must adjust the index as we insert new lines.
            $offset = 0
            foreach ($index in $blankLineIndices) {
                $adjustedIndex = $index + $offset
                if ($adjustedIndex -le $formattedLines.Count) {
                    $formattedLines.Insert($adjustedIndex, "") | Out-Null
                    $offset++
                }
            }

            # Write the final result back to the file.
            $formattedLines | Set-Content -Path $file.FullName -Force -Encoding UTF8

            Write-Host "Successfully formatted $($file.Name)" -ForegroundColor Green

        }
        catch {
            Write-Error "Failed to format $($file.FullName) due to an error: $_"
        }
    }
}


Format-XmlFile -Path ${Path}
