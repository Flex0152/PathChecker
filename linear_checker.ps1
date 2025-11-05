param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxLength = 260,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeFiles = $true,
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeFolders = $true
)

function Write-Progress-Safe {
    param($Activity, $Status, $PercentComplete, $CurrentOperation)
    try {
        Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete -CurrentOperation $CurrentOperation
    }
    catch {
        # Fallback wenn Write-Progress nicht verfügbar ist
        Write-Host "$Activity - $Status - $CurrentOperation"
    }
}

function Test-PathLengths {
    param(
        [string]$RootPath,
        [int]$MaxLength,
        [bool]$CheckFiles,
        [bool]$CheckFolders
    )
    
    $longPaths = @()
    $processedCount = 0
    
    Write-Host "Starte Pfadlängen-Prüfung für: $RootPath" -ForegroundColor Green
    Write-Host "Maximale Pfadlänge: $MaxLength Zeichen" -ForegroundColor Green
    Write-Host "Prüfe Dateien: $CheckFiles" -ForegroundColor Green
    Write-Host "Prüfe Ordner: $CheckFolders" -ForegroundColor Green
    Write-Host ""
    
    try {
        # Erste Zählung für Progress-Anzeige (schneller Überblick)
        Write-Host "Zähle Objekte..." -ForegroundColor Yellow
        $totalItems = 0
        
        if ($CheckFolders) {
            $totalItems += (Get-ChildItem -Path $RootPath -Directory -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
        }
        
        if ($CheckFiles) {
            $totalItems += (Get-ChildItem -Path $RootPath -File -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
        }
        
        Write-Host "Gefunden: $totalItems Objekte zum Prüfen" -ForegroundColor Yellow
        Write-Host ""
        
        # Ordner prüfen
        if ($CheckFolders) {
            Write-Host "Prüfe Ordner..." -ForegroundColor Cyan
            Get-ChildItem -Path $RootPath -Directory -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $processedCount++
                $currentPath = $_.FullName
                $pathLength = $currentPath.Length
                
                # Progress alle 100 Objekte aktualisieren
                if ($processedCount % 100 -eq 0 -or $processedCount -eq $totalItems) {
                    $percentComplete = if ($totalItems -gt 0) { [math]::Round(($processedCount / $totalItems) * 100, 1) } else { 0 }
                    $elapsed = (Get-Date) - $startTime
                    $rate = if ($elapsed.TotalSeconds -gt 0) { [math]::Round($processedCount / $elapsed.TotalSeconds, 0) } else { 0 }
                    
                    Write-Progress-Safe -Activity "Prüfe Pfadlängen" `
                        -Status "$processedCount von $totalItems Objekten geprüft ($percentComplete%)" `
                        -PercentComplete $percentComplete `
                        -CurrentOperation "Aktuell: $($_.Name) | Rate: $rate Obj/s"
                }
                
                if ($pathLength -gt $MaxLength) {
                    $longPaths += [PSCustomObject]@{
                        Type = "Ordner"
                        Path = $currentPath
                        Length = $pathLength
                        Excess = $pathLength - $MaxLength
                        Name = $_.Name
                        Parent = $_.Parent.FullName
                    }
                    
                    Write-Host "GEFUNDEN: Ordner zu lang ($pathLength Zeichen): $currentPath" -ForegroundColor Red
                }
            }
        }
        
        # Dateien prüfen
        if ($CheckFiles) {
            Write-Host "Prüfe Dateien..." -ForegroundColor Cyan
            Get-ChildItem -Path $RootPath -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $processedCount++
                $currentPath = $_.FullName
                $pathLength = $currentPath.Length
                
                # Progress alle 100 Objekte aktualisieren
                if ($processedCount % 100 -eq 0 -or $processedCount -eq $totalItems) {
                    $percentComplete = if ($totalItems -gt 0) { [math]::Round(($processedCount / $totalItems) * 100, 1) } else { 0 }
                    $elapsed = (Get-Date) - $startTime
                    $rate = if ($elapsed.TotalSeconds -gt 0) { [math]::Round($processedCount / $elapsed.TotalSeconds, 0) } else { 0 }
                    
                    Write-Progress-Safe -Activity "Prüfe Pfadlängen" `
                        -Status "$processedCount von $totalItems Objekten geprüft ($percentComplete%)" `
                        -PercentComplete $percentComplete `
                        -CurrentOperation "Aktuell: $($_.Name) | Rate: $rate Obj/s"
                }
                
                if ($pathLength -gt $MaxLength) {
                    $longPaths += [PSCustomObject]@{
                        Type = "Datei"
                        Path = $currentPath
                        Length = $pathLength
                        Excess = $pathLength - $MaxLength
                        Name = $_.Name
                        Parent = $_.Directory.FullName
                        Size = $_.Length
                    }
                    
                    Write-Host "GEFUNDEN: Datei zu lang ($pathLength Zeichen): $currentPath" -ForegroundColor Red
                }
            }
        }
    }
    catch {
        Write-Host "Fehler beim Durchsuchen: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Write-Progress -Activity "Prüfe Pfadlängen" -Completed
    }
    
    return $longPaths
}

# Hauptprogramm
$startTime = Get-Date
Clear-Host
Write-Host "=== Windows Pfadlängen-Prüfer ===" -ForegroundColor Magenta
Write-Host ""

# Parameter validieren
if (-not (Test-Path $Path)) {
    Write-Host "FEHLER: Der angegebene Pfad existiert nicht: $Path" -ForegroundColor Red
    exit 1
}

if ($MaxLength -lt 1) {
    Write-Host "FEHLER: MaxLength muss größer als 0 sein" -ForegroundColor Red
    exit 1
}

# Prüfung starten
$results = Test-PathLengths -RootPath $Path -MaxLength $MaxLength -CheckFiles $IncludeFiles -CheckFolders $IncludeFolders

# Ergebnisse anzeigen
$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ""
Write-Host "=== ERGEBNISSE ===" -ForegroundColor Magenta
Write-Host "Verarbeitungszeit: $($duration.TotalSeconds.ToString('F2')) Sekunden" -ForegroundColor Green

if ($results -eq $null) {
    Write-Host "Keine Pfade gefunden, die länger als $MaxLength Zeichen sind." -ForegroundColor Green
} else {
    Write-Host "Gefunden: $($results.Count) Pfade, die länger als $MaxLength Zeichen sind" -ForegroundColor Yellow
    Write-Host ""
    
    # Sortierte Anzeige der längsten Pfade
    $sortedResults = $results | Sort-Object Length -Descending
    
    Write-Host "Top 10 längste Pfade:" -ForegroundColor Cyan
    $sortedResults | Select-Object -First 10 | ForEach-Object {
        Write-Host "$($_.Type): $($_.Length) Zeichen (+$($_.Excess))" -ForegroundColor White
        Write-Host "  $($_.Path)" -ForegroundColor Gray
        Write-Host ""
    }
    
    # Statistiken
    $avgLength = [math]::Round(($sortedResults | Measure-Object -Property Length -Average).Average, 1)
    $maxLength = ($sortedResults | Measure-Object -Property Length -Maximum).Maximum
    
    Write-Host "Statistiken der zu langen Pfade:" -ForegroundColor Cyan
    Write-Host "  Durchschnittliche Länge: $avgLength Zeichen" -ForegroundColor White
    Write-Host "  Längster Pfad: $maxLength Zeichen" -ForegroundColor White
    Write-Host "  Dateien: $(($results | Where-Object Type -eq 'Datei' | Measure-Object).Count)" -ForegroundColor White
    Write-Host "  Ordner: $(($results | Where-Object Type -eq 'Ordner' | Measure-Object).Count)" -ForegroundColor White
}

# Optional: Ergebnisse in Datei speichern
if ($OutputFile -ne "") {
    try {
        $results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
        Write-Host ""
        Write-Host "Ergebnisse gespeichert in: $OutputFile" -ForegroundColor Green
    }
    catch {
        Write-Host "Fehler beim Speichern der Datei: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Prüfung abgeschlossen." -ForegroundColor Green
