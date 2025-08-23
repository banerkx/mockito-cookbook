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
  [Int32]${Indent} = 2,

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

.PARAMETER FilePath
  The file path to sanitize.

.EXAMPLE
  Sanitize-Path -FilePath "/home/user/config/settings.ini"
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
    [string]${FilePath}
  )

  process
  {
    ${FilePath} = Normalize-Path -Path "${FilePath}"

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
      return ${FilePath}
    }

    ${homePath} = Normalize-Path "${homePath}"
    ${sanitizedPath} = ${FilePath} -replace [regex]::Escape(${homePath}), '${HOME}'
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

.PARAMETER FilePath
  The path to the file.

.EXAMPLE
  Check-File-Exists-Readable -FilePath "report.txt"

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
    [string]${FilePath}
  )

  process
  {
    if ([string]::IsNullOrWhiteSpace(${FilePath}))
    {
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] The file path is empty or null."
      return ${false}
    }

    ${FilePath} = Normalize-Path -Path "${FilePath}"

    if (-not (Test-Path -Path ${FilePath} -PathType Leaf))
    {
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] The file [$(Sanitize-Path -FilePath ${FilePath})] does not exist."
      return ${false}
    }

    try
    {
################################################################################
# Trying to open the file for reading.                                         #
################################################################################
      ${null} = Get-Content -Path ${FilePath} -TotalCount 1 -ErrorAction Stop
      return ${true}
    }
    catch
    {
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] The file [$(Sanitize-Path -FilePath ${FilePath})] is not readable due to [$(${_}.GetType().FullName)]: $(${_}.Exception.Message)"
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
      Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] The linter [${script:SCRIPT}] found no issues in [${FileType}] file [$(Sanitize-Path -FilePath ${XmlFile})]."
    }
  }
  catch [System.Xml.XmlException]
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] The linter [${script:SCRIPT}] found issue(s) in [${FileType}] file [$(Sanitize-Path -FilePath ${XmlFile})] due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]."
    return 1
  }
  catch
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to lint [${FileType}] file [$(Sanitize-Path -FilePath ${XmlFile})] due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]."
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

.PARAMETER FilePath
  Path to the XML file.

.PARAMETER OriginalContent
  The original XML content to restore.

.EXAMPLE
  Restore-Original-XmlFile -FilePath "settings.xml.bak" -OriginalContent "..."

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
    [string]${FilePath},

    [Parameter(Mandatory = ${true})]
    [string]${OriginalContent}
  )

  if ([string]::IsNullOrWhiteSpace(${FilePath}) -or [string]::IsNullOrWhiteSpace(${OriginalContent}))
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] FilePath or OriginalContent is empty."
    return 1
  }

  try
  {
    Set-Content -Path ${FilePath} -Value ${OriginalContent} -NoNewline -Force -Encoding UTF8 -ErrorAction Stop
    Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] Restored original XML file [$(Sanitize-Path -FilePath ${FilePath})]."
    return 0
  }
  catch
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to restore original XML file [$(Sanitize-Path -FilePath ${FilePath})] due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]."
    return 1
  }
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

################################################################################
# If there are no blank nor whitespace-only lines, simply return 0.            #
################################################################################
  try
  {
    ${xmlContent} = Get-Content -Path ${XmlFile} -Encoding UTF8 -ErrorAction Stop
  }
  catch
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to open [${FileType}] file [$(Sanitize-Path -FilePath ${XmlFile})] due to [$(${_}.GetType().FullName)]: $(${_}.Exception.Message)"
    return 1
  }
  if (-not (${xmlContent} | Where-Object { ${_} -match '[ \t]*$' }))
  {
    return 0
  }

################################################################################
# If the file already has the multi-line comment blank line marker, will not   #
# beautify the file.                                                           #
################################################################################
  if (${xmlContent} | Where-Object { ${_} -ceq ${script:MULTI_LINE_COMMENT_BLANK_MARKER} })
  {
    Write-Information "${WARNING_LABEL} [$(${MyInvocation}.MyCommand.Name)] Can not beautify [${FileType}] file [$(Sanitize-Path -FilePath ${XmlFile})] due to [${script:MULTI_LINE_COMMENT_BLANK_MARKER}] being present in the file."
    return 1
  }

################################################################################
# If the file already has the blank line marker, will not beautify the file.   #
################################################################################
  if (${xmlContent} | Where-Object { ${_} -like "*${script:XML_BLANK_MARKER}*" })
  {
    Write-Information "${WARNING_LABEL} [$(${MyInvocation}.MyCommand.Name)] Can not beautify [${FileType}] file [$(Sanitize-Path -FilePath ${XmlFile})] due to [${script:XML_BLANK_MARKER}] being present in the file."
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
    if (${line} -match '(^[ \t]*)(<!--.*-->)([ \t]*)(<.*>)([ \t]*$)')
    {
################################################################################
# Placing a leading inline comment on the previous line.                       #
################################################################################
      "$(${matches}[2])`n$(${matches}[3])$(${matches}[4])"
    }
    elseif (${line} -match '(^[ \t]*)(<[^!].*[^-]>)([ \t])(<!--.*-->)([ \t]*$)')
    {
################################################################################
# Placing a trailing inline comment on the previous line.                      #
################################################################################
      "$(${matches}[4])`n$(${matches}[1])$(${matches}[2])"
    }
    elseif (${line} -match '^[ \t]*<!--.*-->')
    {
################################################################################
# Skipping single line comments.                                               #
################################################################################
      ${line}
    }
    elseif (${line} -match '^([ \t]*)(<!--)(.+[^ \t])([ \t]*)$')
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
    if (${_} -notmatch '^[ \t]*<!--.*-->')
    {
################################################################################
# Matching pattern where line ends with --> and has content before it with     #
# whitespace.                                                                  #
################################################################################
      if (${_} -match '^(.+\S)([ \t]+)(-->)$')
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
  } | Set-Content ${XmlFile} -Encoding UTF8 -ErrorAction Stop

  ${insideCommentRef} = [ref]${false}
  ${tagStackRef} = [ref](New-Object System.Collections.Stack)
  (Get-Content -Path ${XmlFile} -Encoding UTF8 -ErrorAction Stop) | ForEach-Object { # Pipeline Stage 1: Handle comments
################################################################################
# Replacing blank lines within multi-line comments with the multi-line comment #
# blank line marker.                                                           #
################################################################################
    try
    {
      ${line} = ${_}
      if (${_} -match '^\s*<!--')
      {
        ${insideCommentRef}.Value = ${true}
      }
      if (${insideCommentRef}.Value -and ${_} -match '^\s*$')
      {
        ${line} = ${script:MULTI_LINE_COMMENT_BLANK_MARKER}
      }
      if (${_} -match '-->\s*$')
      {
        ${insideCommentRef}.Value = ${false}
      }
      ${line}
    }
    catch
    {
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to replace blank lines within multi-line comments in [${FileType}] file [$(Sanitize-Path -FilePath ${XmlFile})] due to [$(${_}.GetType().FullName)]: $(${_}.Exception.Message)"
      return 1
    }
  } | ForEach-Object { # Pipeline Stage 2: Handle other blank lines
################################################################################
# Replacing all remaining blank lines with the blank line marker, unless they  #
# are inside an XML element.                                                   #
################################################################################
    try
    {
      ${line} = ${_}
      ${isLineBlank} = ${line} -match '^\s*$'
      ${isInsideElement} = ${tagStackRef}.Value.Count -gt 0

      if (-not ${isLineBlank})
      {
        ${tagRegex} = '</?[\w\:\-]+(?:[^>]*?)/?>'
        ${tagMatches} = [regex]::Matches(${line}, ${tagRegex})
        foreach (${match} in ${tagMatches})
        {
          ${tag} = ${match}.Value
          if (${tag} -match '/>\s*$')
          {
            continue
          }
          if (${tag} -match '^</')
          {
            if (${tagStackRef}.Value.Count -gt 0)
            {
              [void]${tagStackRef}.Value.Pop()
            }
          }
          else
          {
            ${tagName} = (${tag} -replace '^<|>$' -split '[\s>]+')[0]
            ${tagStackRef}.Value.Push(${tagName})
          }
        }
      }

      if (${isLineBlank} -and -not ${isInsideElement})
      {
        ${script:XML_BLANK_MARKER} # Replace blank line
      }
      else
      {
        ${line} # Preserve blank line or output non-blank line
      }
    }
    catch
    {
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to process blank lines in [${FileType}] file [$(Sanitize-Path -FilePath ${XmlFile})] due to [$(${_}.GetType().FullName)]: $(${_}.Exception.Message)"
      return 1
    }
  } | Set-Content -Path ${XmlFile} -Encoding UTF8 -ErrorAction Stop
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

  try
  {
################################################################################
# Replacing instances of " />" with "/>".                                      #
################################################################################
    ${lines} = (Get-Content -Path ${XmlFile} -Encoding UTF8 -ErrorAction Stop) -replace '\s+/>' , '/>' | ForEach-Object {
      ${line} = ${_}
################################################################################
# Restoring initially blank lines.                                             #
################################################################################
      if ((${line} -match "${script:MULTI_LINE_COMMENT_BLANK_MARKER}") -or (${line} -match "${script:XML_BLANK_MARKER}"))
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
        if (${line} -match '^[ \t]+<!--$')
        {
          ${line} = ${line} -replace '^[ \t]+', ''
        }
        elseif (${line} -match '^[ \t]+-->$')
        {
          ${line} = ${line} -replace '^[ \t]+', ''
        }
      }
      ${line}
    }
################################################################################
# Removing trailing blank lines.                                               #
################################################################################
    while (${lines}.Count -gt 0 -and ${lines}[-1].Trim() -eq '')
    {
      ${lines} = ${lines}[0..(${lines}.Count - 2)]
    }
  }
  catch
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to post-process [${FileType}] file [$(Sanitize-Path -FilePath ${XmlFile})] due to [$(${_}.GetType().FullName)]: $(${_}.Exception.Message)"
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
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to write [${FileType}] file [$(Sanitize-Path -FilePath ${XmlFile})] with original line endings due to [$(${_}.GetType().FullName)]: $(${_}.Exception.Message)"
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

.PARAMETER FilePath
  The path to the file whose line endings should be detected.

.OUTPUTS
  System.String

.EXAMPLE
  Detect-Original-LineEnding -FilePath "example.xml"
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
    [string]${FilePath}
  )
  ${bytes} = [System.IO.File]::ReadAllBytes(${FilePath})
  ${text} = [System.Text.Encoding]::Default.GetString(${bytes})
  if (${text} -match "`r`n")
  {
    return "`r`n"
  }
  elseif (${text} -match "`n")
  {
    return "`n"
  }
  else
  {
    return "`n"
  }
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

.PARAMETER Indent
  Number of spaces for indentation.

.PARAMETER FileType
  Descriptive type for output messages.

.PARAMETER Lint
  If set, only lints the XML file.

.OUTPUTS
  System.Int32

.EXAMPLE
  Beautify-XML -XmlFile "MyConfig.xml" -Indent 4 -FileType "Configuration"

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

    [Parameter(Mandatory = ${false})]
    [Int32]${Indent} = 2,

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
      ${originalXmlContent} = Get-Content -Path ${XmlFile} -Raw -Encoding UTF8 -ErrorAction Stop
    }
    catch
    {
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to backup the original XML file [$(Sanitize-Path -FilePath ${XmlFile})] due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]."
      exit 1
    }

################################################################################
# Saving the original line ending (LF or CRLF).                                #
################################################################################
    ${originalEOL} = Detect-Original-LineEnding -FilePath ${XmlFile}

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
    ${xmlContent} = Get-Content -Path ${XmlFile} -Raw -Encoding UTF8 -ErrorAction Stop
    ${xmlDoc}.LoadXml(${xmlContent})

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
# Using spaces for indents.                                                    #
################################################################################
    ${settings}.IndentChars = ' ' * ${Indent}
    ${settings}.NewLineOnAttributes = ${false}
    ${settings}.OmitXmlDeclaration = ${false}

################################################################################
# Writing the beautified XML.                                                  #
################################################################################
    ${writer} = [System.Xml.XmlWriter]::Create(${OutputFile}, ${settings})
    ${xmlDoc}.WriteContentTo(${writer})
    ${writer}.Close()

    ${stat} = Post-Beautify-XML -XmlFile ${XmlFile} -FileType ${FileType} -OriginalEOL ${originalEOL}
    if (0 -eq ${stat})
    {
################################################################################
# Ensuring the XML declaration is in upper case.                               #
################################################################################
      ${content} = Get-Content -Path ${XmlFile} -Raw -Encoding UTF8
      if (${content} -match '^\s*<\?xml')
      {
        ${content} = ${content} -replace 'encoding="utf-8"', 'encoding="UTF-8"'
        Set-Content -Path ${XmlFile} -Value ${content} -NoNewline -Encoding UTF8
      }
      Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] Beautified [${FileType}] file [$(Sanitize-Path -FilePath ${XmlFile})] using [PowerShell] script [${script:SCRIPT}].`n"
    }
    else
    {
################################################################################
# Restoring the original XML file since beautifying failed.                    #
################################################################################
      Restore-Original-XmlFile -FilePath ${XmlFile} -OriginalContent ${originalXmlContent}
    }
    exit ${stat}
  }
  catch [System.Xml.XmlException]
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] The command [${script:SCRIPT}] failed to lint/beautify [${FileType}] file [$(Sanitize-Path -FilePath ${XmlFile})] due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]."
    Restore-Original-XmlFile -FilePath ${XmlFile} -OriginalContent ${originalXmlContent}
    exit 1
  }
  catch
  {
    Restore-Original-XmlFile -FilePath ${XmlFile} -OriginalContent ${originalXmlContent}
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to lint/beautify [${FileType}] file [$(Sanitize-Path -FilePath ${XmlFile})] due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]."
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
    [string]${Schema}
  )

  process
  {
################################################################################
# Verifying the input schema exists and is readable.                           #
################################################################################
    ${result} = Check-File-Exists-Readable -FilePath ${Schema}
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
        return 'XSD'
      }
################################################################################
# Also checking for the root schema element if namespace isn't explicitly      #
# found (less reliable but good fallback).                                     #
################################################################################
      if (${fileContent} -match '<(xs|xsd):schema[^>]*>')
      {
        return 'XSD'
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
        return 'DTD'
      }

################################################################################
# If neither XSD nor DTD patterns were found, then return 'Unknown'.           #
################################################################################
      return 'Unknown'
    }
    catch
    {
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to determine if the specified schema file [$(Sanitize-Path -FilePath ${Schema})] is DTD or XSD due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]."
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
    ${xmlContent} = Get-Content -Path ${XmlFile} -Raw -Encoding UTF8 -ErrorAction Stop

################################################################################
# Checking if a DOCTYPE declaration already exists.                            #
# This regex looks for <!DOCTYPE ...> case-insensitively, allowing for various #
# content inside.                                                              #
################################################################################
    if (${xmlContent} -match '(?i)<!DOCTYPE\s+[^>]+>')
    {
      Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] The XML file [$(Sanitize-Path -FilePath ${XmlFile})] contains a DOCTYPE declaration."
      return [PSCustomObject]@{
        ModifiedXMLFile    = ${XmlFile}
        IsTemporaryXMLFile = ${false}
      }
    }

################################################################################
# Since no DOCTYPE declaration was found, proceeding to create a temporary     #
# file.                                                                        #
################################################################################
    Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] No DOCTYPE declaration was found in [$(Sanitize-Path -FilePath ${XmlFile})]; creating a temporary file."
    ${rootElement} = Execute-XPath-Query -XmlFile ${XmlFile} -XPath 'name(/*)'
    Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] Root element in [$(Sanitize-Path -FilePath ${XmlFile})] is [${rootElement}]."

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
    Set-Content -Path ${tempXmlFile} -Value ${modifiedXmlContent} -Encoding UTF8 -ErrorAction Stop
    Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] Created temporary XML file [$(Sanitize-Path -FilePath ${tempXmlFile})] with DOCTYPE."
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
# Define event handler to collect validation errors.                           #
#                                                                              #
# NOTE: Only the first error will be reported.                                 #
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
  ${reader} = [System.Xml.XmlReader]::Create(${XmlFile}, ${settings})

################################################################################
# Trying to Ensure the reader continues even after errors. Depending on the    #
# type of error, ${reader} may not always continue after an error.             #
################################################################################
  while (${true})
  {
    try
    {
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
    Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] [${FileType}] file [$(Sanitize-Path -FilePath ${originalXmlFile})] passed validation with ${type} file [$(Sanitize-Path -FilePath ${Schema})] using [${script:SCRIPT}].`n"
    ${stat} = 0
  }
  else
  {
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] [${FileType}] file [$(Sanitize-Path -FilePath ${originalXmlFile})] failed validation with ${type} file [$(Sanitize-Path -FilePath ${Schema})], using [${script:SCRIPT}], due to [$(${validationErrors}.Count)] error(s)."
    foreach (${eventArguments} in ${validationErrors})
    {
      Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] ${eventArguments}"
    }
    ${stat} = 1
  }
  if (${true} -eq ${doctypeTempXML})
  {
    Remove-Item -Path ${XmlFile} -ErrorAction SilentlyContinue
    Write-Information "${INFO_LABEL} [$(${MyInvocation}.MyCommand.Name)] Deleted temporary file [$(Sanitize-Path -FilePath ${XmlFile})]."
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
    Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] Failed to load XML file [$(Sanitize-Path -FilePath ${XmlFile})] due to [$(${_}.GetType().FullName)]: [$(${_}.Exception.Message)]."
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
Usage: ${script:SCRIPT} -XmlFile [XML file] -Indent [integer] -FileType [XML type] -Lint -Schema [XSD/DTD file] -XPath [xpath query] -Help
${newLine}
    -XmlFile  [XML file]     The XML file that should be processed. Required if the -Help option is not used.
    -Indent   [integer]      A positive integer for the number of spaces to use for indentation. The default
                             value is [2]. Optional.
    -FileType [XML type]     The XML file type, e.g., 'Maven POM'. Default value is [XML]. Optional.
    -Lint                    When specified, simply lint the file and do nothing else. Optional.
    -Schema   [XSD/DTD file] The schema/dtd file to use for XML validation. Optional.
    -XPath    [xpath query]  Execute the xpath query on the XML file. Optional.
    -Help                    Print this usage information and exit. Takes precedence over all other options. Optional.
${newLine}
    Example: Beautify a Maven POM file using 4 spaces for indentation:
      ${script:SCRIPT} -XmlFile pom.xml -FileType 'Maven POM' -Indent 4
${newLine}
    Example: Validate a Maven POM file using the specified schema:
      ${script:SCRIPT} -XmlFile pom.xml -FileType 'Maven POM' -Schema maven-4.0.0.xsd
${newLine}
    Example: Validate an Ant build file using the specified schema:
      ${script:SCRIPT} -XmlFile build.xml -FileType 'Ant build' -Schema ant.dtd
${newLine}
    Example: Only lint a Maven POM file:
      ${script:SCRIPT} -XmlFile pom.xml -FileType 'Maven POM' -Lint
${newLine}
    Example: Retrieve the project model version from a Maven POM file:
      ${script:SCRIPT} -XmlFile pom.xml -XPath '/*[local-name()="project"]/*[local-name()="modelVersion"]/text()'
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

################################################################################
# Validating the indent value.                                                 #
################################################################################
if (0 -ge ${Indent})
{
  Write-Error "${ERROR_LABEL} [$(${MyInvocation}.MyCommand.Name)] The specified indent value [${Indent}] is invalid; the indent value must be positive. Exiting."
  Usage -Exit-Code 1
  exit 1
}

################################################################################
# Verifying the input XML exists and is readable.                              #
################################################################################
${XmlFile} = [System.IO.Path]::GetFullPath(${XmlFile})
${result} = Check-File-Exists-Readable -FilePath ${XmlFile}
if (${false} -eq ${result})
{
  exit 1
}

################################################################################
# If a schema file is specified, then we simply validate the XML file.         #
################################################################################
if (-not [string]::IsNullOrEmpty(${Schema}))
{
  ${stat} = Validate-XML-File -XmlFile ${XmlFile} -Schema ${Schema} -FileType ${FileType}
  exit ${stat}
}
################################################################################
# If an xpath query was specified, then we simply perform the xpath query.     #
################################################################################
elseif (-not [string]::IsNullOrEmpty(${XPath}))
{
  Execute-XPath-Query -XmlFile ${XmlFile} -XPath ${XPath}
  exit 0
}
################################################################################
# If the Lint flag was specified, then we simply lint the XML file.            #
################################################################################
elseif (${true} -eq ${Lint})
{
  ${stat} = Beautify-XML -XmlFile ${XmlFile} -FileType ${FileType} -Lint
  exit ${stat}
}
################################################################################
# Otherwise, we simply beautify the XML file.                                  #
################################################################################
else
{
  ${stat} = Beautify-XML -XmlFile ${XmlFile} -Indent ${Indent} -FileType ${FileType}
  exit ${stat}
}
