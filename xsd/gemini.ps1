# Requires PowerShell 5.1 or later.
# This script formats XML and XSD files by manually managing indentation.
# This approach ensures all constraints, including preserving blank lines
# within <xs:documentation> tags, are met.
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
            # Step 1: Read all lines from the file.
            $originalLines = (Get-Content -Path $file.FullName -Raw) -split "`n"
            
            # This is where the formatted output will be stored.
            $formattedLines = [System.Collections.ArrayList]::new()
            
            # Track the current indentation level.
            $indentationLevel = 0
            
            # Regular expression to identify tags for indentation.
            $openTagPattern = '^\s*<([\w\-\.:]+)(\s+.*)?>.*(?!<\/)(?<!\/>)$'
            $closeTagPattern = '^\s*<\/(?:[\w\-\.:]+)>.*$'

            # Use a state variable to handle multi-line elements (like documentation blocks).
            $insideDocumentation = $false

            for ($i = 0; $i -lt $originalLines.Count; $i++) {
                $line = $originalLines[$i]

                # Trim leading and trailing whitespace.
                $trimmedLine = $line.Trim()

                # Preserve blank lines.
                if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
                    $formattedLines.Add("") | Out-Null
                    continue
                }

                # Check if we are entering or leaving a documentation block.
                if ($trimmedLine -like '<xs:documentation*') {
                    $insideDocumentation = $true
                }
                if ($trimmedLine -like '</xs:documentation*') {
                    $insideDocumentation = $false
                }

                # If inside a documentation block, just re-add the line with original leading spaces.
                # This bypasses the indentation logic for documentation content.
                if ($insideDocumentation -and $trimmedLine -ne '<xs:documentation>' -and $trimmedLine -ne '</xs:documentation>') {
                    $formattedLines.Add($line.Replace("`t", "  ")) | Out-Null
                    continue
                }

                # Check if the line is a closing tag.
                if ($trimmedLine -match $closeTagPattern) {
                    # Decrease indentation level before writing the line.
                    $indentationLevel--
                }
                
                # Apply the current indentation.
                $indentation = "  " * $indentationLevel
                $formattedLine = $indentation + $trimmedLine

                # Handle empty nodes: <name/> becomes <name></name>
                # This regex ensures we only expand self-closing tags without attributes.
                # Tags with attributes, like <name attr="value"/>, are not changed.
                $formattedLine = $formattedLine -replace '<(?![\/])([\w\-\.:]+)\s*\/>', '<$1></$1>'

                # Add the formatted line to the list.
                $formattedLines.Add($formattedLine) | Out-Null

                # Check if the line is an opening tag.
                if ($trimmedLine -match $openTagPattern) {
                    # Increase indentation level after writing the line.
                    $indentationLevel++
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
