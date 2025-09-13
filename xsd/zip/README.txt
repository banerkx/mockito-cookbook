XML/XSD Validator Test Collection
=================================

This package contains 10 sets of XML and XSD files, ranging from simple to complex,
for testing XML Schema validation in PowerShell.

Directory Layout:
-----------------
set1/   -> simple root element and text content
set2/   -> XML with attributes
set3/   -> Repeated elements (xs:sequence, maxOccurs)
set4/   -> Nested complex types
set5/   -> Using enumerations and restrictions
set6/   -> Numeric and date constraints
set7/   -> Optional and repeated elements
set8/   -> xs:choice (mutually exclusive elements)
set9/   -> Key/Keyref (referential integrity)
set10/  -> xs:import (multiple schemas)

Usage:
------
1. Extract the zip file.
2. Place Run-XmlValidator.ps1 at the same level as the 'xml-xsd-tests' folder.
3. Run:
   powershell -ExecutionPolicy Bypass -File .\Run-XmlValidator.ps1
4. The script loops through each set and prints validation results.

Notes on xs:import:
-------------------
- The script supports both local and remote xs:import.
- If a schema imports another via a relative path, ensure the imported file is in the same folder.
- If it imports via HTTP/HTTPS, the script will fetch it remotely.

Enjoy testing!
