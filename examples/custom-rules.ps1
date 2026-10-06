# Requires -Version 5.1
<#
.SYNOPSIS
    Example demonstrating how to customize file categorization rules.

.DESCRIPTION
    Shows how extension mappings are defined and how you can add or adjust categories
    (such as 3D Models, E-Books, Audio, etc.) in Sort-Downloads.ps1.
#>

# Example Custom Rules Hashtable
$CustomRules = @{
    # Documents
    '.pdf'      = 'Documents'
    '.docx'     = 'Documents'
    '.doc'      = 'Documents'
    '.txt'      = 'Documents'
    '.xlsx'     = 'Documents'
    '.pptx'     = 'Documents'
    '.md'       = 'Documents'

    # E-Books (dedicated folder example)
    '.epub'     = 'Documents\Books'
    '.mobi'     = 'Documents\Books'
    '.azw3'     = 'Documents\Books'

    # 3D Printing / CAD
    '.stl'      = '3D Models'
    '.obj'      = '3D Models'
    '.step'     = '3D Models'
    '.gcode'    = '3D Models'

    # Development
    '.ipynb'    = 'Development'
    '.py'       = 'Development'
    '.cpp'      = 'Development'
    '.ts'       = 'Development'
    '.js'       = 'Development'
    '.json'     = 'Development'

    # Images
    '.png'      = 'Images'
    '.jpg'      = 'Images'
    '.jpeg'     = 'Images'
    '.svg'      = 'Images'

    # Media
    '.mp4'      = 'Media'
    '.mkv'      = 'Media'
    '.mp3'      = 'Media'

    # Archives
    '.zip'      = 'Archives'
    '.7z'       = 'Archives'
    '.tar.gz'   = 'Archives'

    # Installers
    '.exe'      = 'Installers'
    '.msi'      = 'Installers'
}

Write-Host "Custom rules defined with $($CustomRules.Count) extension mappings."
