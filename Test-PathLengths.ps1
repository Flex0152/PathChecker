param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxLength = 255,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$UseParallel = $false,
    
    [Parameter(Mandatory=$false)]
    [int]$ThrottleLimit = [Environment]::ProcessorCount,
    
    [Parameter(Mandatory=$false)]
    [int]$BatchSize = 1000
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
        [bool]$UseParallel = $false,
        [int]$ThrottleLimit = 4,
        [int]$BatchSize = 1000
    )
    
    $longPaths = @()
    $processedCount = 0
    $startTime = Get-Date
    
    Write-Host "Starte Pfadlängen-Prüfung für: $RootPath" -ForegroundColor Green
    Write-Host "Maximale Pfadlänge: $MaxLength Zeichen" -ForegroundColor Green
    Write-Host "Parallele Verarbeitung: $UseParallel" -ForegroundColor Green
    if ($UseParallel) {
        Write-Host "Parallel-Threads: $ThrottleLimit" -ForegroundColor Green
        Write-Host "Batch-Größe: $BatchSize" -ForegroundColor Green
    }
    Write-Host ""
    
    try {
        # Erste Zählung für Progress-Anzeige
        Write-Host "Zähle Objekte..." -ForegroundColor Yellow
        $total = 0
        
        $totalItems = Get-ChildItem -Path $RootPath -Recurse -Force -ErrorAction SilentlyContinue
        $total = ($totalItems | Measure-Object).Count
        
        Write-Host "Gefunden: $total Objekte zum Prüfen" -ForegroundColor Yellow
        Write-Host ""

        if ($UseParallel) {
            # Parallele Verarbeitung
            Write-Host "Verwende parallele Verarbeitung..." -ForegroundColor Magenta
            $pool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
            $pool.Open()
            
            # ScriptBlock für die parallele Verarbeitung
            $scriptBlock = {
                param($items, $maxLen)
                $results = @()
                foreach ($item in $items) {
                    $pathLength = $item.FullName.Length
                    if ($pathLength -gt $maxLen) {
                        $results += [PSCustomObject]@{
                            Path = $item.FullName
                            Length = $pathLength
                            Excess = $pathLength - $maxLen
                        }
                    }
                }
                return $results
            }
            
            Write-Host "Verarbeite Items parallel..." -ForegroundColor Cyan

            $runspaces = @()
            # In Batches aufteilen
            for ($i = 0; $i -lt $total; $i += $BatchSize) {
                $batch = $totalItems[$i..([math]::Min($i + $BatchSize - 1, $totalItems.Count - 1))]
                
                $pwsh = [powershell]::Create()
                $pwsh.AddScript($scriptBlock).
                    AddArgument($batch).
                    AddArgument($MaxLength) | Out-Null
                $pwsh.RunspacePool = $pool
                $runspaces += [pscustomobject]@{
                    PowerShell = $pwsh
                    Handle = $pwsh.BeginInvoke()
                }

                # while ($runspaces.Handle.IsCompleted -contains $false){
                #     Start-Sleep -Milliseconds 500
                # }
                
                $processedCount += $batch.Count
                $percentComplete = if ($total -gt 0) { [math]::Round(($processedCount / $total) * 100, 1) } else { 0 }
                Write-Progress-Safe -Activity "Parallele Verarbeitung" -Status "Verarbeitet: $processedCount/$totalItems ($percentComplete%)" -PercentComplete $percentComplete
            }
        
            $longPaths = @()
            foreach($rs in $runspaces) {
                try{
                    $output = $rs.PowerShell.EndInvoke($rs.Handle)
                    $longPaths += $output
                }catch{
                    "Hier ist was schief gelaufen"
                }
                finally{
                    $rs.PowerShell.Dispose()
                }
            }
            $pool.Close()
            $pool.Dispose()

        } else { 
            Write-Host "Prüfe Items..." -ForegroundColor Cyan
            $totalItems | ForEach-Object {
                $processedCount++
                $currentPath = $_.FullName
                $pathLength = $currentPath.Length
                
                # Progress alle 100 Objekte aktualisieren
                if ($processedCount % 100 -eq 0 -or $processedCount -eq $total) {
                    $percentComplete = if ($total -gt 0) { [math]::Round(($processedCount / $total) * 100, 1) } else { 0 }
                    $elapsed = (Get-Date) - $startTime
                    $rate = if ($elapsed.TotalSeconds -gt 0) { [math]::Round($processedCount / $elapsed.TotalSeconds, 0) } else { 0 }
                    
                    Write-Progress-Safe -Activity "Prüfe Pfadlängen" `
                        -Status "$processedCount von $total Objekten geprüft ($percentComplete%)" `
                        -PercentComplete $percentComplete `
                        -CurrentOperation "Aktuell: $($_.Name) | Rate: $rate Obj/s"
                }
                
                if ($pathLength -gt $MaxLength) {
                    $longPaths += [PSCustomObject]@{
                        Path = $currentPath
                        Length = $pathLength
                        Excess = $pathLength - $MaxLength
                    }
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

if ($UseParallel) {
    Write-Host "Empfehlung: Parallele Verarbeitung ist ideal für:" -ForegroundColor Cyan
    Write-Host "  - Verzeichnisse mit >10.000 Objekten" -ForegroundColor White
    Write-Host "  - Systeme mit mehreren CPU-Kernen" -ForegroundColor White
    Write-Host "  - Langsame Speichermedien (Netzwerklaufwerke)" -ForegroundColor White
    Write-Host ""
}

# Prüfung starten
$startTime = Get-Date
$results = Test-PathLengths -RootPath $Path -MaxLength $MaxLength -UseParallel $UseParallel -ThrottleLimit $ThrottleLimit -BatchSize $BatchSize

# Ergebnisse anzeigen
$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ""
Write-Host "=== ERGEBNISSE ===" -ForegroundColor Magenta
Write-Host "Verarbeitungszeit: $($duration.TotalSeconds.ToString('F2')) Sekunden" -ForegroundColor Green

if ($results -eq $null) {
    Write-Host "Keine Pfade gefunden, die länger als $MaxLength Zeichen sind." -ForegroundColor Green
} else {
    Write-Host "Gefunden: $(($results | Measure-Object).Count) Pfade, die länger als $MaxLength Zeichen sind" -ForegroundColor Yellow
    Write-Host ""

    if ( $results.Length -gt 50 ) { $results | Out-GridView } else { $results }
    
    # Statistiken
    $maxLength = ($results | Measure-Object -Property Length -Maximum).Maximum
    
    Write-Host "Statistiken der zu langen Pfade:" -ForegroundColor Cyan
    Write-Host "  Längster Pfad: $maxLength Zeichen" -ForegroundColor White
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
