
################################################################################
#  Copyright © 2018-2025 K. Banerjee                                           #
#                                                                              #
#  This file is part of .git_template.                                         #
#                                                                              #
#  .git_template is free software: you can redistribute it and/or modify       #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  .git_template is distributed in the hope that it will be useful,            #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with .git_template.  If not, see <https://www.gnu.org/licenses/>.     #
################################################################################

<#
.SYNOPSIS
Validates an XML file against a specified XML schema.

.DESCRIPTION
This script takes an XML file and an XML schema file as input
and validates the XML file against the schema. It reports any
validation errors encountered.

.PARAMETER XmlFile
The path to the XML file to be validated. This parameter is
mandatory.

.PARAMETER Schema
The path to the XML schema file (.xsd) to validate against.
This parameter is mandatory.

.PARAMETER FileType
A descriptive string for the type of file being processed (e.g.,
"XML", "Configuration"). This is used in informational messages
and defaults to "XML".

.BUGS
Does not work for </xs:documentation>, found in XSD files, lines
with immediately preceding blank lines (indentation is lost).

.NOTES
Author: K. Banerjee
Version: 2.0
Date: 05-28-2025
#>

#requires -Version 5.1

param
(
  [Parameter(Mandatory = ${false})]
  [string]${XmlFile},

  [Parameter(Mandatory = ${false})]
  [string]${FileType} = 'XML',

  [Parameter(Mandatory = ${false})]
  [switch]${Lint},

  [Parameter(Mandatory = ${false})]
  [ValidatePattern('\.xsd$|\.dtd$')]
  [string]${Schema},

  [Parameter(Mandatory = ${false})]
  [string]${XPath},

  [Parameter(Mandatory = ${false})]
  [switch]${Help}
)

################################################################################
# Getting the script name.                                                     #
################################################################################
${script:SCRIPT} = [System.IO.Path]::GetFileName(${MyInvocation}.MyCommand.Path)

################################################################################
# XML blank line marker for blank lines within multi-line comments.            #
################################################################################
${script:MULTI_LINE_COMMENT_BLANK_MARKER} = 'multi-line-comment-blank-line-marker'

################################################################################
# XML blank line marker for blank lines outside of multi-line comments.        #
################################################################################
${script:XML_BLANK_MARKER} = '<!--xxxx-xxxx-xxxx-->'

################################################################################
# Log message labels.                                                          #
################################################################################
if ([Console]::IsOutputRedirected)
{
  ${script:ERROR_LABEL}   = "[${script:SCRIPT}] ERROR:"
  ${script:WARNING_LABEL} = "[${script:SCRIPT}] WARNING:"
  ${script:INFO_LABEL}    = "[${script:SCRIPT}] INFO:"
}
else
{
  ${script:RED}    = 'Red'
  ${script:YELLOW} = 'Yellow'
  ${script:GREEN}  = 'Green'

  ${script:ERROR_LABEL}   = "[${script:SCRIPT}] ${script:RED}ERROR:"
  ${script:WARNING_LABEL} = "[${script:SCRIPT}] ${script:YELLOW}WARNING:"
  ${script:INFO_LABEL}    = "[${script:SCRIPT}] ${script:GREEN}INFO:"
}

################################################################################
# Want Write-Information to be displayed.                                      #
################################################################################
${InformationPreference} = 'Continue'

################################################################################
# Want consistency for encoding (do not want BOM encoding).                    #
################################################################################
if (${PSVersionTable}.PSVersion.Major -ge 6)
{
  ${script:ContentEncoding} = 'UTF8NoBOM'
}
else
{
  ${script:ContentEncoding} = 'ASCII'
}

################################################################################
# Normalize-Path                                                               #
################################################################################
<#
.SYNOPSIS
  Normalizes a file system path to a consistent, Unix-like format.

.DESCRIPTION
  Resolves a path to its absolute form, replaces backslashes with forward slashes,
  and, on Windows, converts drive letters to Unix-style root paths.

.PARAMETER Path
  The file system path to normalize.

.INPUTS
  System.String

.OUTPUTS
  System.String

.EXAMPLE
  Normalize-Path -Path "C:\Users\Public\Documents"
  Output: /c/Users/Public/Documents (on Windows)

.NOTES
  Author: K. Banerjee
  Date: May 21, 2025
#>
function Normalize-Path
{
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
  [CmdletBinding()]
  [OutputType([string])]
  param
  (
    [Parameter(Mandatory = ${true}, ValueFromPipeline = ${false})]
    [string]${Path}
  )

  process
  {
    try
    {
      if ([string]::IsNullOrWhiteSpace(${Path}))
      {
        return ${null}
      }

################################################################################
# Trimming trailing whitespace from the full path.                             #
################################################################################
      ${trimmedPath} = $([System.IO.Path]::GetFullPath(${Path})).Trim()

################################################################################
# Expanding environment variables.                                             #
################################################################################
      ${expandedPath} = [Environment]::ExpandEnvironmentVariables(${trimmedPath})

################################################################################
# Replacing backslashes with forward slashes.                                  #
################################################################################
      ${unixPath} = ${expandedPath} -replace '\\', '/'

      if (${IsWindows} -or ${env:OS} -match 'Windows')
      {
        if (${unixPath} -match '^//([^/]+)/([^/]+)(.*)')
        {
################################################################################
# Handling UNC paths on Windows.                                               #
#   //server/share/path -> /server/share/path                                  #
################################################################################
          ${unixPath} = '/' + ${matches}[1] + '/' + ${matches}[2] + ${matches}[3]
        }
      }
      return ${unixPath}
    }
    catch
    {
      Write-Error "${ERROR_LABEL} Failed to normalize path [${Path}] due to [$(${_}.GetType().FullName)]: $(${_}.Exception.Message)"
      return ${null}
    }
  }
}

################################################################################
# Sanitize-Path                                                                #
################################################################################
<#
.SYNOPSIS
  Replaces the user's home directory path in a file path with '${HOME}'.

.DESCRIPTION
  Makes file paths portable/anonymized by replacing the home directory portion
  with '${HOME}'.

.PARAMETER Path
  The file path to sanitize.

.EXAMPLE
  Sanitize-Path -Path "/home/user/config/settings.ini"
# Output: ${HOME}/config/settings.ini

.NOTES
  Author: K. Banerjee
  Date: May 18, 2025
#>
function Sanitize-Path
{
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
  [CmdletBinding()]
  [OutputType([string])]
  param
  (
    [Parameter(Mandatory = ${true}, ValueFromPipeline = ${false})]
    [string]${Path}
  )

  process
  {
    ${Path} = Normalize-Path -Path "${Path}"

################################################################################
# Using HOME on Unix, USERPROFILE on Windows.                                  #
################################################################################
    ${homePath} = if (${IsWindows} -or ${env:OS} -match 'Windows')
    {
      ${env:USERPROFILE}
    }
    else
    {
      ${env:HOME}
    }

    if ([string]::IsNullOrEmpty(${homePath}))
    {
      return ${Path}
    }

    ${homePath} = Normalize-Path -Path "${homePath}"
    ${sanitizedPath} = ${Path} -replace [regex]::Escape(${homePath}), '${HOME}'
    return ${sanitizedPath}
  }
}

################################################################################
# Check-File-Exists-Readable                                                   #
################################################################################
<#
.SYNOPSIS
  Checks if a file exists and is readable.

.DESCRIPTION
  Returns true if the file exists and can be read, false otherwise.

.PARAMETER Path
  The path to the file.

.EXAMPLE
  Check-File-Exists-Readable -Path "report.txt"

.NOTES
  Author: K. Banerjee
  Date: May 18, 2025
#>
function Check-File-Exists-Readable
{
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
  [CmdletBinding()]
  [OutputType([boolean])]
  param
  (
    [Parameter(Mandatory = ${true}, ValueFromPipeline = ${false})]
    [string]${Path}
  )

  process
  {
    if ([string]::IsNullOrWhiteSpace(${Path}))
    {
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] The file path is empty or null."
      return ${false}
    }

    ${Path} = Normalize-Path -Path "${Path}"

    if (-not (Test-Path -Path ${Path} -PathType Leaf))
    {
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] The file [$(Sanitize-Path -Path ${Path})] does not exist."
      return ${false}
    }

    try
    {
################################################################################
# Trying to open the file for reading.                                         #
################################################################################
      ${null} = Get-Content -Path ${Path} -TotalCount 1 -ErrorAction Stop
      return ${true}
    }
    catch
    {
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] The file [$(Sanitize-Path -Path ${Path})] is not readable due to [$(${_}.GetType().FullName)]: $(${_}.Exception.Message)"
      return ${false}
    }
  }
}

################################################################################
# Lint-XML-File                                                                #
################################################################################
<#
.SYNOPSIS
  Validates the well-formedness of an XML file.

.DESCRIPTION
  Loads and parses the XML file, reporting parsing errors.

.PARAMETER XmlFile
  Path to the XML file.

.PARAMETER FileType
  Descriptive type for output messages.

.PARAMETER Wordy
  If set, prints a success message when valid.

.OUTPUTS
  System.Int32

.EXAMPLE
  Lint-XML-File -XmlFile "config.xml" -FileType "Configuration" -Wordy

.NOTES
  Author: K. Banerjee
  Date: May 18, 2025
#>
function Lint-XML-File
{
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
  [CmdletBinding()]
  [OutputType([int])]
  param
  (
    [Parameter(Mandatory = ${true})]
    [string]${XmlFile},

    [Parameter(Mandatory = ${true})]
    [string]${FileType},

    [Parameter(Mandatory = ${false})]
    [switch]${Wordy}
  )

  try
  {
################################################################################
# Loading the XML content as a single string.                                  #
################################################################################
    ${xmlContent} = Get-Content -Path ${XmlFile} -Raw -ErrorAction Stop
################################################################################
# Creating and loading an XML document to lint the XML file.                   #
################################################################################
    ${xmlDoc} = New-Object System.Xml.XmlDocument
    ${xmlDoc}.LoadXml(${xmlContent})
    if (${true} -eq ${Wordy})
    {
      Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] The linter [${script:SCRIPT}] found no issues in [${FileType}] file [$(Sanitize-Path -Path ${XmlFile})]."
    }
  }
  catch [System.Xml.XmlException]
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] The linter [${script:SCRIPT}] found issue(s) in [${FileType}] file [$(Sanitize-Path -Path ${XmlFile})] due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]."
    return 1
  }
  catch
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to lint [${FileType}] file [$(Sanitize-Path -Path ${XmlFile})] due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]."
    return 2
  }
  return 0
}

################################################################################
# Restore-Original-XmlFile                                                     #
################################################################################
<#
.SYNOPSIS
  Restores the original content of an XML file.

.DESCRIPTION
  Overwrites the specified XML file with provided original content.

.PARAMETER Path
  Path to the XML file.

.PARAMETER OriginalContent
  The original XML content to restore.

.EXAMPLE
  Restore-Original-XmlFile -Path "settings.xml" -OriginalContent "..."

.NOTES
  Author: K. Banerjee
  Date: May 18, 2025
#>
function Restore-Original-XmlFile
{
  [OutputType([int])]
  param
  (
    [Parameter(Mandatory = ${true})]
    [string]${Path},

    [Parameter(Mandatory = ${true})]
    [string]${OriginalContent}
  )

  if ([string]::IsNullOrWhiteSpace(${Path}) -or [string]::IsNullOrWhiteSpace(${OriginalContent}))
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Path or OriginalContent is empty."
    return 1
  }

  try
  {
    Set-Content -Path ${Path} -Value ${OriginalContent} -NoNewline -Force -Encoding ${script:ContentEncoding} -ErrorAction Stop
    Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] Restored original XML file [$(Sanitize-Path -Path ${Path})]."
    return 0
  }
  catch
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to restore original XML file [$(Sanitize-Path -Path ${Path})] due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]."
    return 1
  }
}

<#
.SYNOPSIS
  Joins multi-line <xs:schema> declarations in an XSD file into a single line.

.DESCRIPTION
  This function processes an XML Schema Definition (XSD) file to find <xs:schema>
  declarations that are split across multiple lines. It identifies the start of
  such a declaration, concatenates all subsequent lines until the closing '>'
  is found, and replaces the multiple lines with a single, joined line.

  This is primarily a helper function used as a pre-processing step before
  sorting schema attributes, ensuring the entire <xs:schema> tag is on one line
  for easier parsing. The file is modified in place.

.PARAMETER XmlFile
  The path to the XSD file to process. This parameter is mandatory.

.OUTPUTS
  System.Int32
  Returns 0 on success, or 1 if an error occurs.

.EXAMPLE
  Join-Xs-Schema-Tokens -XmlFile "MySchema.xsd"
# If MySchema.xsd contains a split <xs:schema> tag, it will be joined.

.NOTES
  This function modifies the input file directly. It is designed to be called
  by other functions in this script, such as `Sort-Schema-Attributes`.
#>
function Join-Xs-Schema-Tokens
{
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
  [OutputType([int])]
  param
  (
    [Parameter(Mandatory = ${true})]
    [string]${XmlFile}
  )

  try
  {
################################################################################
# Joining possibly split xs:schema lines.                                      #
################################################################################
    ${content} = Get-Content -Path ${XmlFile} -Encoding ${script:ContentEncoding} -ErrorAction Stop
    ${pattern} = '^<xs:schema .*[^>]$'
    ${splitSchemaLines} = ${content} | Select-String -Pattern ${pattern} | Select-Object -First 1

    if (${splitSchemaLines})
    {
      ${in_xs_schema} = ${false}
      ${schema_line}  = ''

      ${lines} = (${content}) | ForEach-Object {
        ${line} = ${_}
        if ((-not ${in_xs_schema}) -and (${line} -match '^<xs:schema .*[^>]$'))
        {
################################################################################
# Start of a split <xs:schema> lines.                                          #
################################################################################
          ${in_xs_schema} = ${true}
          ${schema_line}  = ${line}
          return
        }
        elseif (${in_xs_schema})
        {
################################################################################
# Trimming leading spaces.                                                     #
################################################################################
          ${str} = ${line} -replace '^[\s]+', ''
################################################################################
# Appending with single space.                                                 #
################################################################################
          ${schema_line} += " ${str}"

          if (${str} -match '>$')
          {
################################################################################
# Closing line found, emit and reset.                                          #
################################################################################
            ${in_xs_schema} = ${false}
            ${line} = ${schema_line}
            ${line}
          }
          return
        }
        else
        {
################################################################################
# Normal line, emit as-is.                                                     #
################################################################################
          ${line}
          return
        }
      }
      ${lines} | Set-Content -Path ${XmlFile} -Encoding ${script:ContentEncoding} -ErrorAction Stop
      Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] Joined split xs:schema tokens in [$(Sanitize-Path -Path ${XmlFile})] using [PowerShell] script [${script:SCRIPT}].`n"
    }
  }
  catch
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to join split xs:schema tokens in [$(Sanitize-Path -Path ${XmlFile})] due to [$(${_}.GetType().FullName)]: $(${_}.Exception.Message)"
    return 1
  }
  return 0
}

<#
.SYNOPSIS
  Sorts attributes within the <xs:schema> tag of an XSD file.

.DESCRIPTION
  This function reads an XML Schema Definition (XSD) file, finds the <xs:schema>
  declaration line, and sorts its attributes alphabetically. It prioritizes
  namespace attributes (xmlns) by sorting them as a separate group before other
  attributes. This helps maintain a consistent and predictable format for schema
  declarations. The file is modified in place.

.PARAMETER XmlFile
  The path to the XSD file to process. This parameter is mandatory.

.OUTPUTS
  System.Int32
  Returns 0 on success. The function modifies the file directly.

.EXAMPLE
  Sort-Schema-Attributes -XmlFile "MySchema.xsd"

.NOTES
  This function is intended to be used as a helper within the XML beautification process.
#>
function Sort-Schema-Attributes
{
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
  [OutputType([int])]
  param
  (
    [Parameter(Mandatory = ${true})]
    [string]${XmlFile}
  )

  ${stat} = Join-Xs-Schema-Tokens -XmlFile ${XmlFile}
  if (0 -ne ${stat})
  {
    return ${stat}
  }

  try
  {
    ${content} = Get-Content -Path ${XmlFile} -Encoding ${script:ContentEncoding} -ErrorAction Stop
    ${pattern} = '^<xs:schema .*>$'
    ${schemaLineMatch} = ${content} | Select-String -Pattern ${pattern} | Select-Object -First 1

    if (${schemaLineMatch})
    {
      ${lineIndex} = ${schemaLineMatch}.LineNumber - 1
      ${line} = ${content}[${lineIndex}]

################################################################################
# Removing trailing '>'.                                                       #
################################################################################
      ${line} = ${line} -replace '>$', ''
################################################################################
# Replacing multiple spaces with single space, then splitting into tokens.     #
################################################################################
      ${tokens} = ${line} -replace '\s{2,}', ' ' -split ' '
################################################################################
# The first token is always <xs:schema.                                        #
################################################################################
      ${firstToken} = ${tokens}[0]
      ${attributes} = ${tokens}[1..(${tokens}.Length - 1)]

################################################################################
# Splitting attributes into xmlns and others.                                  #
################################################################################
      ${xmlns} = @()
      ${others} = @()
      foreach (${attr} in ${attributes})
      {
        if (${attr} -like 'xmlns*')
        {
          ${xmlns} += ${attr}
        }
        else
        {
          ${others} += ${attr}
        }
      }

################################################################################
# Sorting both groups.                                                         #
################################################################################
      ${xmlns} = ${xmlns} | Sort-Object
      ${others} = ${others} | Sort-Object

################################################################################
# Reconstructing the line.                                                     #
################################################################################
      ${newLine} = "${firstToken} $(${xmlns} -join ' ') $(${others} -join ' ')>"
      ${content}[${lineIndex}] = ${newLine}

      Set-Content -Path ${XmlFile} -Value ${content} -Encoding ${script:ContentEncoding} -ErrorAction Stop
    }
    Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] Sorted schema attributes in [$(Sanitize-Path -Path ${XmlFile})] using [PowerShell] script [${script:SCRIPT}].`n"
  }
  catch
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to sort schema attributes in [$(Sanitize-Path -Path ${XmlFile})] due to [$(${_}.GetType().FullName)]: $(${_}.Exception.Message)"
    return 1
  }
  return 0
}

################################################################################
# Pre-Beautify-XML                                                             #
################################################################################
<#
.SYNOPSIS
  Prepares an XML file for beautifying by normalizing whitespace and comments.

.DESCRIPTION
  Trims trailing whitespace, separates multi-line comments, and marks blank lines
  with special markers.

.PARAMETER XmlFile
  Path to the XML file.

.PARAMETER FileType
  Descriptive type for output messages.

.OUTPUTS
  System.Int32

.NOTES
  Author: K. Banerjee
  Date: May 18, 2025
#>
function Pre-Beautify-XML
{
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
  [CmdletBinding()]
  [OutputType([int])]
  param
  (
    [Parameter(Mandatory = ${true})]
    [string]${XmlFile},

    [Parameter(Mandatory = ${true})]
    [string]${FileType}
  )

  try
  {
    ${xmlContent} = Get-Content -Path ${XmlFile} -Encoding ${script:ContentEncoding} -ErrorAction Stop
  }
  catch
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to open [${FileType}] file [$(Sanitize-Path -Path ${XmlFile})] due to [$(${_}.GetType().FullName)]: $(${_}.Exception.Message)"
    return 1
  }

################################################################################
# If the file already has the multi-line comment blank line marker, will not   #
# beautify the file.                                                           #
################################################################################
  if (${xmlContent} | Where-Object { ${_} -ceq ${script:MULTI_LINE_COMMENT_BLANK_MARKER} })
  {
    Write-Information "${WARNING_LABEL} [$(${MyInvocation}.MyCommand.Name)] Can not beautify [${FileType}] file [$(Sanitize-Path -Path ${XmlFile})] due to [${script:MULTI_LINE_COMMENT_BLANK_MARKER}] being present in the file."
    return 1
  }

################################################################################
# If the file already has the blank line marker, will not beautify the file.   #
################################################################################
  if (${xmlContent} | Where-Object { ${_} -like "*${script:XML_BLANK_MARKER}*" })
  {
    Write-Information "${WARNING_LABEL} [$(${MyInvocation}.MyCommand.Name)] Can not beautify [${FileType}] file [$(Sanitize-Path -Path ${XmlFile})] due to [${script:XML_BLANK_MARKER}] being present in the file."
    return 1
  }

  (${xmlContent}) | ForEach-Object {
################################################################################
# Replacing each tab with 2 spaces.                                            #
################################################################################
    ${line} = ${_} -replace "`t", '  '
################################################################################
# Trimming trailing whitespace.                                                #
################################################################################
    ${line} = ${line} -replace '\s+$', ''
    if (${line} -match '(^\s*)(<!--.*-->)(\s*)(<.*>)(\s*$)')
    {
################################################################################
# Placing a leading inline comment on the previous line.                       #
################################################################################
      "$(${matches}[2])`n$(${matches}[3])$(${matches}[4])"
    }
    elseif (${line} -match '(^\s*)(<[^!].*[^-]>)(\s)(<!--.*-->)(\s*$)')
    {
################################################################################
# Placing a trailing inline comment on the previous line.                      #
################################################################################
      "$(${matches}[4])`n$(${matches}[1])$(${matches}[2])"
    }
    elseif (${line} -match '^\s*<!--.*-->')
    {
################################################################################
# Skipping single line comments.                                               #
################################################################################
      ${line}
    }
    elseif (${line} -match '^(\s*)(<!--)(.+[^ \t])(\s*)$')
    {
################################################################################
# Reformatting inline comments.                                                #
################################################################################
      "$(${matches}[2])`n$(${matches}[1])    $(${matches}[3])"
    }
    else
    {
      ${line}
    }
################################################################################
# Placing the "-->" from multi-line comments on separate lines.                #
################################################################################
  } | ForEach-Object {
################################################################################
# Skipping single line comments.                                               #
################################################################################
    if (${_} -notmatch '^\s*<!--.*-->')
    {
################################################################################
# Matching pattern where line ends with --> and has content before it with     #
# whitespace.                                                                  #
################################################################################
      if (${_} -match '^(.+\S)(\s+)(-->)$')
      {
        "$(${matches}[1])"
        "$(${matches}[3])"
      }
      else
      {
        ${_}
      }
    }
    else
    {
      ${_}
    }
  } | Set-Content -Path ${XmlFile} -Encoding ${script:ContentEncoding} -ErrorAction Stop

  ${ext} = (Get-Item "${XmlFile}").Extension.TrimStart('.')
  if ('xsd' -eq "${ext}")
  {
    ${stat} = Sort-Schema-Attributes -XmlFile ${XmlFile}
    if (0 -ne ${stat})
    {
      return ${stat}
    }
  }

################################################################################
# Replacing blank lines within multi-line comments with the multi-line comment #
# blank line marker.                                                           #
################################################################################
  (Get-Content -Path ${XmlFile} -Encoding ${script:ContentEncoding} -ErrorAction Stop) | ForEach-Object {
    try
    {
      ${line} = ${_}
      if (${_} -match '^ *<!--')
      {
        ${insideComment} = ${true}
      }
      if (${insideComment} -and ${_} -match '^\s*$')
      {
        ${line} = ${script:MULTI_LINE_COMMENT_BLANK_MARKER}
      }
      if (${_} -match '--> *$')
      {
        ${insideComment} = ${false}
      }
      ${line}
    }
    catch
    {
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to replace blank lines within multi-line comments in [${FileType}] file [$(Sanitize-Path -Path ${XmlFile})] due to [$(${_}.GetType().FullName)]: $(${_}.Exception.Message)"
      return 1
    }
  } | Set-Content -Path ${XmlFile} -Encoding ${script:ContentEncoding} -ErrorAction Stop

  ${inXsDoc} = ${false}
  (Get-Content -Path ${XmlFile} -Encoding ${script:ContentEncoding} -ErrorAction Stop) | ForEach-Object {
################################################################################
# Replacing all remaining blank lines with the blank line marker.              #
#                                                                              #
# NOTE: Blank lines within <xs:documentation>, </xs:documentation> tags are    #
#       not deleted so they do not need to be replaced with                    #
#       ${script:XML_BLANK_MARKER}.                                            #
################################################################################
    try
    {
      ${line} = ${_}
      if ((${line} -match '^\s*<xs:documentation [a-z]+=".*">$') -or (${line} -match '^\s*<xs:documentation [a-z]+=".*">.*[^>]$'))
      {
        ${inXsDoc} = ${true}
      }
      elseif (${line} -match '^\s*</xs:documentation>$')
      {
        ${inXsDoc} = ${false}
      }
      elseif ((${inXsDoc} -eq ${false}) -and (${line} -match '^$'))
      {
        ${line} = ${script:XML_BLANK_MARKER}
      }
      ${line}
    }
    catch
    {
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to replace blank lines in [${FileType}] file [$(Sanitize-Path -Path ${XmlFile})] due to [$(${_}.GetType().FullName)]: $(${_}.Exception.Message)"
      return 1
    }
  } | Set-Content -Path ${XmlFile} -Encoding ${script:ContentEncoding} -ErrorAction Stop
  return 0
}

<#
.SYNOPSIS
  Normalizes the indentation of <xs:documentation> blocks in an XML file.

.DESCRIPTION
  This function processes an XML file to correct the indentation within <xs:documentation>
  blocks. It ensures that the content inside these blocks is indented consistently
  relative to the opening <xs:documentation> tag. It handles single-line content,
  multi-line content, and preserves blank lines within the documentation.

.PARAMETER XmlFile
  The path to the XML file to process. This parameter is mandatory.

.EXAMPLE
  Normalize-Xs-Doc-Indentation -XmlFile "MySchema.xsd"
# Corrects indentation for all <xs:documentation> blocks in MySchema.xsd.

.NOTES
  Author: K. Banerjee
  Date: May 28, 2025
  This function is designed to be a helper for XML beautification, specifically
  for XSD files where <xs:documentation> tags are common. It modifies the file in place.
#>
function Normalize-Xs-Doc-Indentation
{
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
  [OutputType([int])]
  param
  (
    [Parameter(Mandatory = ${true})]
    [string]${XmlFile}
  )

  try
  {
    ${inXsDoc} = ${false}
    ${xsDocIndent} = ''
################################################################################
# Using 2 spaces for indents.                                                  #
################################################################################
    ${indent} = ' ' * 2

    ${lines} = (Get-Content -Path ${XmlFile} -Encoding ${script:ContentEncoding} -ErrorAction Stop) | ForEach-Object {
      ${line} = ${_}

################################################################################
# Print the line if it is a <xs:documentation ...>...</xs:documentation> line  #
# or a <xs:documentation .../> line, and then continue.                        #
################################################################################
      if (${line} -match '^\s*<xs:documentation.*<\/xs:documentation>$' -or ${line} -match '^\s*<xs:documentation .*\/>$')
      {
        ${line}
        return
      }

################################################################################
# Now inside a [<xs:documentation ...>, </xs:documentation>] block.            #
################################################################################
      if (${inXsDoc})
      {
        if (${line} -match '(^\s*)([^<]*)(<\/xs:documentation>)')
        {
          ${content} = ${Matches}[2].Trim()
          if (${content}.Length -gt 0)
          {
            "${xsDocIndent}${indent}${content}"
          }
################################################################################
# Printing the correctly indented closing tag.                                 #
################################################################################
          "${xsDocIndent}$(${Matches}[3])"
################################################################################
# Resetting state.                                                             #
################################################################################
          ${inXsDoc} = ${false}
          ${xsDocIndent} = ''
          return
        }
        else
        {
################################################################################
# Now we have a line of content inside the block.                              #
################################################################################
          ${content} = ${line}.TrimStart()
          if (${content}.Length -gt 0)
          {
            "${xsDocIndent}${indent}${content}"
          }
          else
          {
################################################################################
# Preserving empty lines within the block.                                     #
################################################################################
            ${line}
          }
          return
        }
      }
################################################################################
# We are **not** inside a documentation block.                                 #
################################################################################
      else
      {
################################################################################
# Checking for the opening tag. The regex captures the tag and any potential   #
# content on the same line.                                                    #
################################################################################
        if (${line} -match '(^\s*)(<xs:documentation[^>]*>)(.*)')
        {
          ${xsDocIndent} = ${Matches}[1]
          ${inXsDoc} = ${true}
################################################################################
# Printing the opening tag.                                                    #
################################################################################
          "$(${Matches}[1])$(${Matches}[2])"
          ${content} = ${Matches}[3].Trim()
          if (${content}.Length -gt 0)
          {
            "${xsDocIndent}${indent}${content}"
          }
          return
        }
        else
        {
################################################################################
# We have a regular line, printing it as is.                                   #
################################################################################
          ${line}
          return
        }
      }
    }
    ${lines} | Set-Content -Path ${XmlFile} -Encoding ${script:ContentEncoding} -ErrorAction Stop
    Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] Normalized xs:documentation indentation in [$(Sanitize-Path -Path ${XmlFile})] using [PowerShell] script [${script:SCRIPT}].`n"
  }
  catch
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to normalize xs:documentation indentation in [$(Sanitize-Path -Path ${XmlFile})] due to [$(${_}.GetType().FullName)]: $(${_}.Exception.Message)"
    return 1
  }
  return 0
}

################################################################################
# Post-Beautify-XML                                                            #
################################################################################
<#
.SYNOPSIS
  Performs post beautifying operations on an XML file.

.DESCRIPTION
  Restores blank lines, ensures a single trailing blank line, and unindents comments.

.PARAMETER XmlFile
  Path to the XML file.

.PARAMETER FileType
  Descriptive type for output messages.

.OUTPUTS
  System.Int32

.NOTES
  Author: K. Banerjee
  Date: May 18, 2025
#>
function Post-Beautify-XML
{
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
  [CmdletBinding()]
  [OutputType([int])]
  param
  (
    [Parameter(Mandatory = ${true})]
    [string]${XmlFile},

    [Parameter(Mandatory = ${true})]
    [string]${FileType},

    [Parameter(Mandatory = ${true})]
    [string]${OriginalEOL}
  )

  ${ext} = (Get-Item "${XmlFile}").Extension.TrimStart('.')
  if ('xsd' -eq "${ext}")
  {
    ${stat} = Normalize-Xs-Doc-Indentation -XmlFile ${XmlFile}
    if (0 -ne ${stat})
    {
      return ${stat}
    }
  }

  try
  {
################################################################################
# Replacing instances of "\s+/>" with "/>".                                    #
################################################################################
    ${lines} = (Get-Content -Path ${XmlFile} -Encoding ${script:ContentEncoding} -ErrorAction Stop) -replace '\s+/>' , '/>' | ForEach-Object {
      ${line} = ${_}
################################################################################
# Restoring initially blank lines in multi-line comments.                      #
################################################################################
      if (${line} -match "${script:MULTI_LINE_COMMENT_BLANK_MARKER}")
      {
        ${line} = ''
      }
      elseif (${line} -match "^\s*${script:XML_BLANK_MARKER}$")
      {
        ${line} = ''
      }
      else
      {
################################################################################
# Removing indentation from single-line comments.                              #
################################################################################
        ${line} = ${line} -replace '^\s*(<!--.*?-->)', '${1}'
################################################################################
# Unindenting '<!--$' and '-->$' lines.                                        #
################################################################################
        if (${line} -match '^\s+<!--$')
        {
          ${line} = ${line} -replace '^\s+', ''
        }
        elseif (${line} -match '^\s+-->$')
        {
          ${line} = ${line} -replace '^\s+', ''
        }
################################################################################
# Removing trailing whitespace.                                                #
################################################################################
        ${line} = ${line} -replace '\s*$', ''
      }
      ${line}
    }
################################################################################
# Removing trailing blank lines.                                               #
################################################################################
    while (${lines}.Count -gt 0 -and ${lines}[-1].ToString().Trim() -eq '')
    {
      ${lines} = ${lines}[0..(${lines}.Count - 2)]
    }
  }
  catch
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to post-process [${FileType}] file [$(Sanitize-Path -Path ${XmlFile})] due to [$(${_}.GetType().FullName)]: $(${_}.Exception.Message)"
    return 1
  }

  try
  {
################################################################################
# Joining the lines and then writing them with their original line ending.     #
################################################################################
    ${joined} = ${lines} -join ${OriginalEOL}
    [System.IO.File]::WriteAllText(${XmlFile}, ${joined} + ${OriginalEOL}, [System.Text.Encoding]::UTF8)

################################################################################
# Adding a single trailing blank line (if not already present).                #
################################################################################
    if (${lines}[-1] -ne '')
    {
      [System.IO.File]::AppendAllText(${XmlFile}, ${OriginalEOL}, [System.Text.Encoding]::UTF8)
    }
  }
  catch
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to write [${FileType}] file [$(Sanitize-Path -Path ${XmlFile})] with original line endings due to [$(${_}.GetType().FullName)]: $(${_}.Exception.Message)"
    return 1
  }
  return 0
}

################################################################################
# Detect-Original-LineEnding                                                   #
################################################################################
<#
.SYNOPSIS
  Detects the original line ending style used in a text file.

.DESCRIPTION
  Reads the specified file and determines whether its line endings are CRLF (`r`n) or LF (`n`).
  Returns the detected line ending as a string. Defaults to LF if no line endings are found.

.PARAMETER Path
  The path to the file whose line endings should be detected.

.OUTPUTS
  System.String

.EXAMPLE
  Detect-Original-LineEnding -Path "example.xml"
# Returns "`r`n" if CRLF is detected, "`n" if LF is detected.

.NOTES
  Author: K. Banerjee
  Date: July 30, 2025
#>
function Detect-Original-LineEnding
{
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
  [CmdletBinding()]
  [OutputType([string])]
  param
  (
    [Parameter(Mandatory = ${true})]
    [string]${Path}
  )
  ${bytes} = [System.IO.File]::ReadAllBytes(${Path})
  ${text} = [System.Text.Encoding]::Default.GetString(${bytes})
  if (${text} -match "`r`n")
  {
    return "`r`n"
  }
  return "`n"
}

################################################################################
# Beautify-XML                                                                 #
################################################################################
<#
.SYNOPSIS
  Beautifies an XML file with proper indentation.

.DESCRIPTION
  Reads, formats, and writes XML with consistent indentation. Optionally lints only.

.PARAMETER XmlFile
  Path to the XML file.

.PARAMETER FileType
  Descriptive type for output messages.

.PARAMETER Lint
  If set, only lints the XML file.

.OUTPUTS
  System.Int32

.EXAMPLE
  Beautify-XML -XmlFile "MyConfig.xml" -FileType "Configuration"

.NOTES
  Author: K. Banerjee
  Date: July 8, 2025
#>
function Beautify-XML
{
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
  [CmdletBinding()]
  [OutputType([int])]
  param
  (
    [Parameter(Mandatory = ${true})]
    [string]${XmlFile},

    [Parameter(Mandatory = ${true})]
    [string]${FileType},

    [Parameter(Mandatory = ${false})]
    [switch]${Lint}
  )

  try
  {
################################################################################
# Backing up the original XML content in case we need to restore it.           #
################################################################################
    try
    {
      ${originalXmlContent} = Get-Content -Path ${XmlFile} -Raw -Encoding ${script:ContentEncoding} -ErrorAction Stop
    }
    catch
    {
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to backup the original XML file [$(Sanitize-Path -Path ${XmlFile})] due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]."
      exit 1
    }

################################################################################
# Saving the original line ending (LF or CRLF).                                #
################################################################################
    ${originalEOL} = Detect-Original-LineEnding -Path ${XmlFile}

################################################################################
# Linting the XML file.                                                        #
################################################################################
    if (${true} -eq ${Lint})
    {
      ${stat} = Lint-XML-File -XmlFile ${XmlFile} -FileType ${FileType} -Wordy
      exit ${stat}
    }

    ${stat} = Pre-Beautify-XML -XmlFile ${XmlFile} -FileType ${FileType}
    if (0 -ne ${stat})
    {
      exit ${stat}
    }

################################################################################
# Setting output file to input file.                                           #
################################################################################
    ${OutputFile} = ${XmlFile}

################################################################################
# Reading the XML file.                                                        #
################################################################################
    ${xmlDoc} = New-Object System.Xml.XmlDocument
    ${xmlDoc}.PreserveWhitespace = ${false}
    ${xmlDoc}.Load(${XmlFile})

################################################################################
# Normalizing empty XML nodes.                                                 #
# - Expands attribute-less empty nodes:                                        #
#     <properties/> -> <properties></properties>                               #
# - Collapses attributed empty nodes:                                          #
#     <node a="b"></node> -> <node a="b"/>                                     #
################################################################################
    ${allElements} = ${xmlDoc}.SelectNodes('//*')
    foreach (${element} in ${allElements})
    {
      if (-not ${element}.HasChildNodes)
      {
        if (${element}.Attributes.Count -eq 0)
        {
################################################################################
# Expanding attribute-less empty nodes.                                        #
################################################################################
          ${element}.IsEmpty = ${false}
        }
        else
        {
################################################################################
# Collapsing attributed empty nodes.                                           #
################################################################################
          ${element}.IsEmpty = ${true}
        }
      }
    }

################################################################################
# Creating an XmlWriter with indentation settings.                             #
################################################################################
    ${settings} = New-Object System.Xml.XmlWriterSettings
    ${settings}.Indent = ${true}
################################################################################
# Using 2 spaces for indents.                                                  #
################################################################################
    ${settings}.IndentChars = ' ' * 2
    ${settings}.NewLineOnAttributes = ${false}
    ${settings}.OmitXmlDeclaration = ${false}

################################################################################
# Writing the beautified XML.                                                  #
################################################################################
    ${writer} = [System.Xml.XmlWriter]::Create(${OutputFile}, ${settings})
    ${xmlDoc}.Save(${writer})
    ${writer}.Close()

    ${stat} = Post-Beautify-XML -XmlFile ${XmlFile} -FileType ${FileType} -OriginalEOL ${originalEOL}
    if (0 -eq ${stat})
    {
################################################################################
# Ensuring the XML declaration is in upper case.                               #
################################################################################
      ${content} = Get-Content -Path ${XmlFile} -Raw -Encoding ${script:ContentEncoding}
      if (${content} -match '^\s*<\?xml')
      {
        ${content} = ${content} -replace 'encoding="utf-8"', 'encoding="UTF-8"'
        Set-Content -Path ${XmlFile} -Value ${content} -NoNewline -Encoding ${script:ContentEncoding}
      }
      Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] Beautified [${FileType}] file [$(Sanitize-Path -Path ${XmlFile})] using [PowerShell] script [${script:SCRIPT}].`n"
    }
    else
    {
################################################################################
# Restoring the original XML file since beautifying failed.                    #
################################################################################
      Restore-Original-XmlFile -Path ${XmlFile} -OriginalContent ${originalXmlContent}
    }
    exit ${stat}
  }
  catch [System.Xml.XmlException]
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] The command [${script:SCRIPT}] failed to lint/beautify [${FileType}] file [$(Sanitize-Path -Path ${XmlFile})] due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]."
    Restore-Original-XmlFile -Path ${XmlFile} -OriginalContent ${originalXmlContent}
    exit 1
  }
  catch
  {
    Restore-Original-XmlFile -Path ${XmlFile} -OriginalContent ${originalXmlContent}
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to lint/beautify [${FileType}] file [$(Sanitize-Path -Path ${XmlFile})] due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]."
    exit 2
  }
  return 0
}

################################################################################
# Get-Schema-File-Type                                                         #
################################################################################
<#
.SYNOPSIS
  Determines if a file is an XSD or DTD schema.

.DESCRIPTION
  Scans file content for patterns indicating XSD or DTD type.

.PARAMETER Schema
  Path to the schema file.

.OUTPUTS
  System.String

.EXAMPLE
  Get-Schema-File-Type -Schema "MySchema.xsd"

.NOTES
  Author: K. Banerjee
  Date: May 18, 2025
#>
function Get-Schema-File-Type
{
  [CmdletBinding()]
  [OutputType([string])]
  param
  (
    [Parameter(Mandatory = ${true}, ValueFromPipeline = ${true}, ValueFromPipelineByPropertyName = ${true})]
    [ValidatePattern('\.xsd$|\.dtd$')]
    [string]${Schema}
  )

  process
  {
################################################################################
# Verifying the input schema exists and is readable.                           #
################################################################################
    ${result} = Check-File-Exists-Readable -Path ${Schema}
    if (${false} -eq ${result})
    {
      exit 1
    }

    try
    {
################################################################################
# Reading the file content as a single string.                                 #
################################################################################
      ${fileContent} = Get-Content -Path ${Schema} -Raw -ErrorAction Stop

################################################################################
# If the file is empty, print an error message and exit.                       #
################################################################################
      if ([string]::IsNullOrWhiteSpace(${fileContent}))
      {
        Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] The schema file [${Schema}] is empty. Exiting."
        exit 1
      }

################################################################################
# XSD files typically contain the XML Schema namespace URI and/or the          #
# <xs:schema> root element. We use regex to be case-insensitive and allow for  #
# variations in prefixes, e.g., xs or xsd. Look for the namespace declaration. #
################################################################################
      if (${fileContent} -match 'xmlns:(xs|xsd)\s*=\s*["'']http://www.w3.org/2001/XMLSchema["'']')
      {
        Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] Schema type for file [$(Sanitize-Path -Path ${Schema})] is [XSD].`n"
        return 'XSD'
      }
################################################################################
# Also checking for the root schema element if namespace isn't explicitly      #
# found (less reliable but good fallback).                                     #
################################################################################
      if (${fileContent} -match '<(xs|xsd):schema[^>]*>')
      {
        Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] Schema type for file [$(Sanitize-Path -Path ${Schema})] is [XSD].`n"
        return 'XSD'
      }

################################################################################
# Checking the file extension.                                                 #
################################################################################
      ${ext} = (Get-Item "${Schema}").Extension.TrimStart('.')
      if ('xsd' -eq "${ext}")
      {
        return 'XSD'
      }

################################################################################
# At this point, if the file extension is not 'dtd', we have an error.         #
################################################################################
      if ('dtd' -ne "${ext}")
      {
        Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] File extension [${ext}] from [$(Sanitize-Path -Path ${Schema})] is invalid; can not determine schema type.`n"
        return 'Unknown'
      }

################################################################################
# DTD files often start with DOCTYPE, ELEMENT, ATTLIST, ENTITY, NOTATION       #
# declarations. So looking for common DTD declarations.                        #
################################################################################
      if (${fileContent} -match '<!DOCTYPE' -or
        ${fileContent} -match '<!ELEMENT' -or
        ${fileContent} -match '<!ATTLIST' -or
        ${fileContent} -match '<!ENTITY' -or
        ${fileContent} -match '<!NOTATION')
      {
        Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] Schema type for file [$(Sanitize-Path -Path ${Schema})] is [DTD].`n"
        return 'DTD'
      }

################################################################################
# If neither XSD nor DTD patterns were found, then return 'Unknown'.           #
################################################################################
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Could not determine schema type for file [$(Sanitize-Path -Path ${Schema})].`n"
      return 'Unknown'
    }
    catch
    {
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to determine if the specified schema file [$(Sanitize-Path -Path ${Schema})] is DTD or XSD due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]."
      return 'Unknown'
    }
  }
}

################################################################################
# Ensure-DOCTYPE-Declaration                                                   #
################################################################################
<#
.SYNOPSIS
  Ensures an XML file has a DOCTYPE declaration referencing an external DTD.

.DESCRIPTION
  Adds a DOCTYPE referencing the DTD if missing, returns a temporary file if modified.

.PARAMETER XmlFile
  Path to the XML file.

.PARAMETER DtdFile
  Path to the DTD file.

.OUTPUTS
  PSCustomObject (ModifiedXMLFile, IsTemporaryXMLFile)

.EXAMPLE
  Ensure-DOCTYPE-Declaration -XmlFile "config.xml" -DtdFile "schema.dtd"

.NOTES
  Author: K. Banerjee
  Date: May 18, 2025
#>
function Ensure-DOCTYPE-Declaration
{
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
  [CmdletBinding(SupportsShouldProcess = ${true})]
  [OutputType([string])]
  param
  (
    [Parameter(Mandatory = ${true}, HelpMessage = 'Path to the XML file to check.')]
    [string]${XmlFile},

    [Parameter(Mandatory = ${true}, HelpMessage = 'Path to the external DTD file to reference.')]
    [string]${DtdFile}
  )

  try
  {
################################################################################
# Reading the entire XML file content as a single string.                      #
################################################################################
    ${xmlContent} = Get-Content -Path ${XmlFile} -Raw -Encoding ${script:ContentEncoding} -ErrorAction Stop

################################################################################
# Checking if a DOCTYPE declaration already exists.                            #
# This regex looks for <!DOCTYPE ...> case-insensitively, allowing for various #
# content inside.                                                              #
################################################################################
    if (${xmlContent} -match '(?i)<!DOCTYPE\s+[^>]+>')
    {
      Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] The XML file [$(Sanitize-Path -Path ${XmlFile})] contains a DOCTYPE declaration."
      return [PSCustomObject]@{
        ModifiedXMLFile    = ${XmlFile}
        IsTemporaryXMLFile = ${false}
      }
    }

################################################################################
# Since no DOCTYPE declaration was found, proceeding to create a temporary     #
# file.                                                                        #
################################################################################
    Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] No DOCTYPE declaration was found in [$(Sanitize-Path -Path ${XmlFile})]; creating a temporary file."
    ${rootElement} = Execute-XPath-Query -XmlFile ${XmlFile} -XPath 'name(/*)'
    Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] Root element in [$(Sanitize-Path -Path ${XmlFile})] is [${rootElement}]."

################################################################################
# Generating a unique temporary file path.                                     #
################################################################################
    ${tempDir} = [System.IO.Path]::GetTempPath()
    ${tempFileName} = [System.IO.Path]::GetRandomFileName() + '.xml'
    ${tempXmlFile} = Join-Path -Path ${tempDir} -ChildPath ${tempFileName}

################################################################################
# Constructing the DOCTYPE declaration. The SYSTEM identifier in DOCTYPE       #
# expects a URI. Converting the local path to a file URI. Using Convert-Path   #
# to get the full, resolved path, then formatting as a URI.                    #
################################################################################
    ${absoluteDtdPath} = (Convert-Path ${DtdFile})
################################################################################
# Replacing backslashes with forward slashes for URI consistency and escaping  #
# special characters.                                                          #
################################################################################
    ${dtdUri} = [uri]::EscapeUriString(${absoluteDtdPath}.Replace('\', '/'))
################################################################################
# Ensuring it starts with 'file:///' for local file URIs if it's not already   #
# an absolute URI.                                                             #
################################################################################
    if (${dtdUri} -notmatch '^[a-z]+://')
    {
      ${dtdUri} = 'file://' + ${dtdUri}
    }

################################################################################
# Creating the DOCTYPE declaration.                                            #
################################################################################
    ${doctypeDeclaration} = "<!DOCTYPE $(${rootElement}) SYSTEM `"$(${dtdUri})`">"

################################################################################
# Inserting the DOCTYPE declaration into the XML content.                      #
################################################################################
    ${modifiedXmlContent} = ${xmlContent}
################################################################################
# Checking for XML declaration (e.g., <?xml version="1.0" encoding="UTF-8"?>). #
################################################################################
    if (${xmlContent} -match '^\s*<\?xml[^?]+\?>')
    {
################################################################################
# If XML declaration exists, inserting DOCTYPE immediately after it on a new   #
# line.                                                                        #
# (?s) makes '.' match newlines, allowing the regex to span multiple lines if  #
# needed.                                                                      #
################################################################################
      ${modifiedXmlContent} = ${xmlContent} -replace '(?s)(^\s*<\?xml[^?]+\?>)', "`$1`n${doctypeDeclaration}"
    }
    else
    {
################################################################################
# If no XML declaration, inserting DOCTYPE at the very beginning of the        #
# document.                                                                    #
################################################################################
      ${modifiedXmlContent} = "${doctypeDeclaration}`n" + ${xmlContent}
    }

################################################################################
# Writing the modified content to the temporary file.                          #
################################################################################
    Set-Content -Path ${tempXmlFile} -Value ${modifiedXmlContent} -Encoding ${script:ContentEncoding} -ErrorAction Stop
    Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] Created temporary XML file [$(Sanitize-Path -Path ${tempXmlFile})] with DOCTYPE."
    return [PSCustomObject]@{
      ModifiedXMLFile    = ${tempXmlFile}
      IsTemporaryXMLFile = ${true}
    }
  }
  catch
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to create temporary file with DOCTYPE declaration due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]"
    return [PSCustomObject]@{
      ModifiedXMLFile    = ${null}
      IsTemporaryXMLFile = ${false}
    }
  }
}

################################################################################
# Validate-XML-File                                                            #
################################################################################
<#
.SYNOPSIS
  Validates an XML file against an XSD or DTD schema.

.DESCRIPTION
  Lints and validates the XML file against the specified schema, reporting errors.

.PARAMETER XmlFile
  Path to the XML file.

.PARAMETER Schema
  Path to the schema file (.xsd or .dtd).

.PARAMETER FileType
  Descriptive type for output messages.

.OUTPUTS
  None (writes to console, exits with status code)

.EXAMPLE
  Validate-XML-File -XmlFile "MyConfig.xml" -Schema "MySchema.xsd" -FileType "Configuration"

.NOTES
  Author: K. Banerjee
  Date: May 18, 2025
#>
function Validate-XML-File
{
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
  [OutputType([int])]
  param
  (
    [Parameter(Mandatory = ${true})]
    [string]${XmlFile},

    [Parameter(Mandatory = ${true})]
    [ValidatePattern('\.xsd$|\.dtd$')]
    [string]${Schema},

    [Parameter(Mandatory = ${true})]
    [string]${FileType}
  )

################################################################################
# Getting the validation file type (XSD' or 'DTD').                            #
################################################################################
  ${Schema} = [System.IO.Path]::GetFullPath(${Schema})
  ${type} = Get-Schema-File-Type -Schema ${Schema}
  if ('Unknown' -eq ${type})
  {
    exit 1
  }

################################################################################
# Linting the XML file.                                                        #
################################################################################
  ${stat} = Lint-XML-File -XmlFile ${XmlFile} -FileType "${FileType}"
  if (0 -ne ${stat})
  {
    exit ${stat}
  }

################################################################################
# Linting the schema file.                                                     #
################################################################################
  if ('XSD' -eq ${type} )
  {
    ${stat} = Lint-XML-File -XmlFile ${Schema} -FileType 'XML schema'
    if (0 -ne ${stat})
    {
      exit ${stat}
    }
  }

################################################################################
# Initialize error collection and settings.                                    #
################################################################################
  ${validationErrors} = New-Object System.Collections.ArrayList
  ${settings} = New-Object System.Xml.XmlReaderSettings

################################################################################
# If a DTD file is being used for validation and the XML file does not have a  #
# DOCTYPE declaration referencing the DTD, then a temporary file will be       #
# created with an added DOCTYPE declaration for the DTD file. If this is the   #
# case, then the line numbers of errors will be incremented by 1 relative to   #
# the original XML file. To correct for this, the error line numbers must be   #
# decremented by 1. Otherwise, the line number offset will be 0.               #
################################################################################
  ${lineNumberOffset} = 0
  ${originalXmlFile} = ${XmlFile}

################################################################################
# Configure settings based on whether XSD or DTD is used.                      #
#                                                                              #
# NOTE: Does not support xs:import.                                            #
################################################################################
  if ('XSD' -eq ${type} )
  {
################################################################################
# If the schema file has targetNamespace attribute, we return it. Otherwise,   #
# ${null} is returned.                                                         #
################################################################################
    ${targetNamespace} = & {
      param
      (
        [Parameter(Mandatory = ${true})]
        [string]${Schema}
      )

      try
      {
        [xml]${SchemaContent} = Get-Content -Path ${Schema} -ErrorAction Stop
        ${rootElementName} = if (${SchemaContent}.schema)
        {
          'schema'
        }
        elseif (${SchemaContent}.'xs:schema')
        {
          'xs:schema'
        }
        else
        {
          return ${null}
        }
        return ${SchemaContent}.${rootElementName}.targetNamespace
      }
      catch
      {
        return ${null}
      }
    } -Schema ${Schema}

################################################################################
# Creating XmlReaderSettings for loading the schema, enabling DTD processing.  #
################################################################################
    ${schemaReaderSettings} = New-Object System.Xml.XmlReaderSettings
    ${schemaReaderSettings}.DtdProcessing = [System.Xml.DtdProcessing]::Parse
################################################################################
# Not validating the schema itself, just parsing it.                           #
################################################################################
    ${schemaReaderSettings}.ValidationType = [System.Xml.ValidationType]::None

################################################################################
# Creating an XmlReader for the schema file using the new settings.            #
################################################################################
    ${schemaReader} = [System.Xml.XmlReader]::Create(${Schema}, ${schemaReaderSettings})

    ${XmlSchemaSet} = New-Object System.Xml.Schema.XmlSchemaSet
################################################################################
# Adding the schema to the XmlSchemaSet using the reader.                      #
################################################################################
    ${XmlSchemaSet}.Add(${targetNamespace}, ${schemaReader}) | Out-Null

################################################################################
# Closing the schema reader.                                                   #
################################################################################
    ${schemaReader}.Close()

    ${settings}.ValidationType = [System.Xml.ValidationType]::Schema
    ${settings}.Schemas.Add(${XmlSchemaSet})
    ${settings}.ValidationFlags = `
      [System.Xml.Schema.XmlSchemaValidationFlags]::ProcessIdentityConstraints -bor `
      [System.Xml.Schema.XmlSchemaValidationFlags]::ReportValidationWarnings -bor `
      [System.Xml.Schema.XmlSchemaValidationFlags]::ProcessInlineSchema

################################################################################
# Ensuring DTD processing is also enabled for the document validation, in case #
# the XML document also has DTDs. In this case, it's the XSD that has the      #
# DOCTYPE.                                                                     #
################################################################################
    ${settings}.DtdProcessing = [System.Xml.DtdProcessing]::Parse
  }
  else
  {
################################################################################
# Ensuring that the XML file has a DOCTYPE statement for DTD validation.       #
################################################################################
    ${doctypeFileInfo} = Ensure-DOCTYPE-Declaration -XmlFile ${XmlFile} -DtdFile ${Schema}
    if (${null} -eq ${doctypeFileInfo}.ModifiedXMLFile)
    {
      exit 1
    }
    ${XmlFile} = ${doctypeFileInfo}.ModifiedXMLFile
    ${doctypeTempXML} = ${doctypeFileInfo}.IsTemporaryXMLFile
################################################################################
# If a temporary file is being used for the validation, then need to correct   #
# the error line numbers.                                                      #
################################################################################
    if (${true} -eq ${doctypeTempXML})
    {
      ${lineNumberOffset} = 1
    }

    ${settings}.ValidationType = [System.Xml.ValidationType]::DTD
    ${settings}.DtdProcessing = [System.Xml.DtdProcessing]::Parse

################################################################################
# Creating an XmlResolver to resolve the DTD file path (if it's not inline in  #
# the XML).                                                                    #
################################################################################
    ${resolver} = New-Object System.Xml.XmlUrlResolver
    ${resolver}.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    ${settings}.XmlResolver = ${resolver}
  }

################################################################################
# Define event handler to collect validation error(s).                         #
#                                                                              #
# NOTE: Depending on the type of error, only the first error may be reported.  #
################################################################################
  ${validationEventHandler} = {
    param
    (
      [object]${from},
      [System.Xml.Schema.ValidationEventArgs]${eventArguments}
    )

################################################################################
# The following dummy assignment is used to suppress the warning:              #
#                                                                              #
# PSReviewUnusedParameter The parameter 'from' has been declared but not used. #
#                                                                              #
# from PSScriptAnalyzer.Invoke-ScriptAnalyzer at the required level of         #
# granularity, i.e., do not want to suppress PSReviewUnusedParameter globally. #
#                                                                              #
# NOTE: The ${from} parameter is actually used.                                #
################################################################################
    ${null} = ${from}

    if (${eventArguments}.Exception)
    {
      ${lineNumber} = $(${eventArguments}.Exception.LineNumber - ${lineNumberOffset})
      ${linePosition} = ${eventArguments}.Exception.LinePosition
    }
    else
    {
      ${lineNumber} = 0
      ${linePosition} = 0
    }

    if (${eventArguments}.Severity -eq [System.Xml.Schema.XmlSeverityType]::Error)
    {
      ${formattedMessage} = "$(${eventArguments}.Message) at Line [$(${lineNumber})], Position [$(${linePosition})], Severity [System.Xml.Schema.XmlSeverityType]::Error]"
    }
    else
    {
      ${formattedMessage} = "$(${eventArguments}.Message) at Line [$(${lineNumber})], Position [$(${linePosition})], Severity [System.Xml.Schema.XmlSeverityType]::Warning]"
    }
    [void]${validationErrors}.Add(${formattedMessage})
  }

################################################################################
# Adding the validation event handler.                                         #
################################################################################
  ${settings}.add_ValidationEventHandler(${validationEventHandler})

################################################################################
# Validating the XML document using XmlReader.                                 #
################################################################################
  try
  {
    ${reader} = [System.Xml.XmlReader]::Create(${XmlFile}, ${settings})
  }
  catch
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to create XmlReader for [${FileType}] file [$(Sanitize-Path -Path ${originalXmlFile})] due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)] (does not support xs:import)."
    return 1
  }

################################################################################
# Trying to Ensure the reader continues even after errors. Depending on the    #
# type of error, ${reader} may not always continue after an error.             #
################################################################################
  while (${true})
  {
    try
    {
      if (${null} -eq ${reader})
      {
        break
      }
      if (-not ${reader}.Read())
      {
        break
      }
    }
    catch
    {
################################################################################
# Let the validation event handler deal with the error, continue reading.      #
################################################################################
      continue
    }
  }
  ${reader}.Close()

################################################################################
# Check validation errors.                                                     #
################################################################################
  if (${validationErrors}.Count -eq 0)
  {
    Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] [${FileType}] file [$(Sanitize-Path -Path ${originalXmlFile})] passed validation with ${type} file [$(Sanitize-Path -Path ${Schema})] using [${script:SCRIPT}].`n"
    ${stat} = 0
  }
  else
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] [${FileType}] file [$(Sanitize-Path -Path ${originalXmlFile})] failed validation with ${type} file [$(Sanitize-Path -Path ${Schema})], using [${script:SCRIPT}], due to [$(${validationErrors}.Count)] error(s)."
    foreach (${eventArguments} in ${validationErrors})
    {
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] ${eventArguments}"
    }
    ${stat} = 1
  }
  if (${true} -eq ${doctypeTempXML})
  {
    Remove-Item -Path ${XmlFile} -ErrorAction SilentlyContinue
    Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] Deleted temporary file [$(Sanitize-Path -Path ${XmlFile})]."
  }
  exit ${stat}
}

################################################################################
# Execute-XPath-Query                                                          #
################################################################################
<#
.SYNOPSIS
  Executes an XPath query against an XML file.

.DESCRIPTION
  Validates and loads the XML file, then executes the XPath query and outputs results.

.PARAMETER XmlFile
  Path to the XML file.

.PARAMETER XPath
  XPath expression to execute.

.OUTPUTS
  System.Int32 (outputs query results)

.EXAMPLE
  Execute-XPath-Query -XmlFile "config.xml" -XPath "/configuration/settings/version"

.NOTES
  Author: K. Banerjee
  Date: May 18, 2025
#>
function Execute-XPath-Query
{
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
  [CmdletBinding()]
  [OutputType([int])]
  param
  (
    [Parameter(Mandatory = ${true})]
    [string]${XmlFile},

    [Parameter(Mandatory = ${true})]
    [string]${XPath}
  )

################################################################################
# Linting the XML file.                                                        #
################################################################################
  ${stat} = Lint-XML-File -XmlFile ${XmlFile} -FileType 'XML'
  if (0 -ne ${stat})
  {
    exit ${stat}
  }

################################################################################
# Loading the XML document.                                                    #
################################################################################
  ${xml} = New-Object System.Xml.XmlDocument
  try
  {
    ${xml}.Load(${XmlFile})
  }
  catch
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to load XML file [$(Sanitize-Path -Path ${XmlFile})] due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]."
    exit 1
  }

################################################################################
# Creating an XPathNavigator.                                                  #
################################################################################
  ${nav} = ${xml}.CreateNavigator()

################################################################################
# Evaluating the XPath expression.                                             #
################################################################################
  ${result} = ${nav}.Evaluate(${XPath})

################################################################################
# Handling node-set and scalar results.                                        #
################################################################################
  if (${result} -is [System.Xml.XPath.XPathNodeIterator])
  {
    foreach (${node} in ${result})
    {
################################################################################
# Print the value (text) of each node.                                         #
################################################################################
      Write-Output ${node}.Value
    }
  }
  else
  {
################################################################################
# Print scalar result (number, string, etc.).                                  #
################################################################################
    Write-Output ${result}
  }
}

################################################################################
# Usage                                                                        #
################################################################################
<#
.SYNOPSIS
  Displays usage information for the script.

.DESCRIPTION
  Prints usage instructions, parameter descriptions, and examples.

.PARAMETER ExitCode
  Exit code after displaying usage.

.EXAMPLE
  Usage -ExitCode 0

.NOTES
  Author: K. Banerjee
  Date: May 18, 2025
#>
function Usage
{
  param
  (
    [Parameter(Mandatory = ${true})]
    [int]${ExitCode}
  )

  if (${env:OS} -match 'Windows')
  {
    ${newLine} = "`n"
  }
  else
  {
    ${newLine} = "`u{00A0}"
  }

  Write-Information @"
Usage: ${script:SCRIPT} -XmlFile [XML file] -FileType [XML type] -Lint -Schema [XSD/DTD file] -XPath [xpath query] -Help
${newLine}
    -XmlFile  [XML file]     The XML file that should be processed. Required if the -Help option is not used.
    -FileType [XML type]     The XML file type, e.g., 'Maven POM'. Default value is [XML]. Optional.
    -Lint                    When specified, simply lint the file and do nothing else. Optional.
    -Schema   [XSD/DTD file] The schema/dtd file to use for XML validation. Optional.
    -XPath    [xpath query]  Execute the xpath query on the XML file. Optional.
    -Help                    Print this usage information and exit. Takes precedence over all other options. Optional.
${newLine}
    Example: Beautify a Maven POM file:
      ${script:SCRIPT} -XmlFile /path/to/pom.xml -FileType 'Maven POM'
${newLine}
    Example: Validate a Maven POM file using the specified schema:
      ${script:SCRIPT} -XmlFile /path/to/pom.xml -FileType 'Maven POM' -Schema /path/to/maven-4.0.0.xsd
${newLine}
    Example: Validate an Ant build file using the specified schema:
      ${script:SCRIPT} -XmlFile /path/to/build.xml -FileType 'Ant build' -Schema /path/to/ant.dtd
${newLine}
    Example: Only lint a Maven POM file:
      ${script:SCRIPT} -XmlFile /path/to/pom.xml -FileType 'Maven POM' -Lint
${newLine}
    Example: Retrieve the project model version from a Maven POM file:
      ${script:SCRIPT} -XmlFile /path/to/pom.xml -XPath '/*[local-name()="project"]/*[local-name()="modelVersion"]/text()'
"@

  exit ${ExitCode}
}

################################################################################
# "main"                                                                       #
################################################################################

################################################################################
# Checking to see if the -Help option was used.                                #
################################################################################
if (${true} -eq ${Help})
{
  Usage -ExitCode 0
}

${stat} = Validate-XML-File -XmlFile /home/banerkx/git/mockito-cookbook/xsd/9set/example_9.xml -Schema /home/banerkx/git/mockito-cookbook/xsd/9set/example_9.xsd -FileType 'example_9'
exit ${stat}
