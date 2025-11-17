@{
    # --- Basisinformationen ---
    RootModule        = 'AllDirectories.psm1'        # Hauptmoduldatei
    ModuleVersion     = '1.0.0'                # Versionsnummer
    GUID              = '552a4beb-bc92-4d54-b446-64f56fcbe706' # Eindeutige ID (New-Guid)
    Author            = 'Felix'
    Copyright         = '(c) 2025 Felix. Alle Rechte vorbehalten.'
    Description       = 'Dieses Modul bietet Funktionen für das schnelle Durchlaufen eines angegebenen Ordners'

    # --- Kompatibilität ---
    PowerShellVersion = '5.1'                  # Mindestversion
    CompatiblePSEditions = @('Desktop', 'Core')

    # --- Dateien & Ressourcen ---
    FunctionsToExport = @('Get-AllFileSystemEntriesIterative', 'Get-AllEntries') 

    # --- Private Daten ---
    PrivateData       = @{
        PSData = @{
            Tags       = @('PowerShell', 'Module', 'Example')
            LicenseUri = 'https://opensource.org/licenses/MIT'
            IconUri    = ''
            ReleaseNotes = 'Initiale Version.'
        }
    }
}
