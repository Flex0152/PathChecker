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
    [int]$BatchSize = 5000
)

<#
.SYNOPSIS
Ein Pfadlängen Checker, zum prüfen der Pfade auf maximal Länge.

.DESCRIPTION
Dieses Skript prüft die Länge von Pfaden unterhalb eines angegebenen Root-Pfads. 
Alle vollqualifizierten Pfade werden ermittelt und auf ihre Länge überprüft. 
Überschreitet ein Pfad die definierte maximale Länge, wird er in die Auswertung aufgenommen.

Das Skript unterstützt:
- **Parallelverarbeitung**: Mit dem Parameter `ThrottleLimit` kann die Anzahl der Threads festgelegt werden.
- **Batch-Verarbeitung**: Um das System nicht zu überlasten, werden Pfade in Batches geprüft.
- **CSV-Export**: Ergebnisse können über den Parameter `OutputFile` als CSV-Datei gespeichert werden.

Ausgabe:
- Standardmäßig erfolgt die Ausgabe in der Shell.
- Bis zu 50 gefundene Pfade werden direkt angezeigt.
- Bei mehr als 50 Pfaden öffnet sich ein separates Fenster zur Darstellung.

.VERSION 
1.0

.DATE 
18.11.2025

.PARAMETER <Path>
Beschreibt den zu untersuchenden Pfad. 

.PARAMETER <MaxLength>
Beschreibt die maximale Zeichenlänge der vollqualifizierten Pfade.  

.PARAMETER <OutputFile>
Hier kann ein CSV Pfad angegeben werden um das Ergebnis zu exportieren. 

.PARAMETER <UseParallel>
Bei angabe des Parameters wird der Pfad parallel Bearbeitet.

.PARAMETER <ThrottleLimit>
Beschreibt die maximale Anzahl der Threads. Nur mit dem Parameter UseParallel sinnvoll.

.PARAMETER <BatchSize>
Beschreibt die maximale Anzahl der gleichzeitig untersuchenden Pfade. 

.EXAMPLE
Prüft den Pfad c:\temp sequenziell und gibt das Ergebnis auf der Shell aus.
Test-PathLengths.ps1 -Path C:\temp\ -MaxLength 140

Prüft den Pfad c:\temp parallel und gibt das Ergebnis auf der Shell aus.
Test-PathLengths.ps1 -Path c:\temp -MaxLength 140 -UseParallel

Prüft den Pfad c:\temp sequenziell und speichert das Ergebnis als CSV im angegebenen Pfad. 
Test-PathLengths.ps1 -Path C:\temp\ -MaxLength 140 -OutputFile c:\temp\result.csv
#>

if (Test-Path .\AllDirectories){
    Import-Module .\AllDirectories
} else {
    Write-Host "The module was not found. Please download the application again."
    return 
}

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
    
    Write-Host "Starts Path Length Check for: $RootPath" -ForegroundColor Green
    Write-Host "Maximum Path Length: $MaxLength Character" -ForegroundColor Green
    Write-Host "Parallel Processing: $UseParallel" -ForegroundColor Green
    if ($UseParallel) {
        Write-Host "Parallel-Threads: $ThrottleLimit" -ForegroundColor Green
        Write-Host "Batch-Size: $BatchSize" -ForegroundColor Green
    }
    Write-Host ""
    
    try {
        # Erste Zählung für Progress-Anzeige
        $total = 0
        
        $totalItems = Get-AllEntries -path $RootPath -IgnoreInaccessible -RecurseSubdirectories
        $total = ($totalItems | Measure-Object).Count
        
        Write-Host "Found: $total objects to check" -ForegroundColor Yellow
        Write-Host ""

        if ($UseParallel) {
            # Parallele Verarbeitung
            $pool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
            $pool.Open()
            
            # ScriptBlock für die parallele Verarbeitung
            $scriptBlock = {
                param($items, $maxLen)
                $results = foreach ($item in $items) {
                    $pathLength = $item.Length
                    if ($pathLength -gt $maxLen) {
                        [PSCustomObject]@{
                            Path = $item
                            Length = $pathLength
                            Excess = $pathLength - $maxLen
                        }
                    }
                }
                return $results
            }
            
            Write-Host "Process items in parallel..." -ForegroundColor Cyan

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
                Write-Progress-Safe -Activity "Parallel Processing" -Status "Processed: $processedCount/$totalItems ($percentComplete%)" -PercentComplete $percentComplete
            }
        
            $longPaths = @()
            foreach($rs in $runspaces) {
                try{
                    $output = $rs.PowerShell.EndInvoke($rs.Handle)
                    $longPaths += $output
                }catch{
                    Write-Host "An error occurred during processing. $($_.Exception.Message)"
                }
                finally{
                    $rs.PowerShell.Dispose()
                }
            }
            $pool.Close()
            $pool.Dispose()

        } else { 
            Write-Host "Check Items..." -ForegroundColor Cyan
            $totalItems | ForEach-Object {
                $processedCount++
                $currentPath = $_
                $pathLength = $currentPath.Length
                
                # Progress alle 100 Objekte aktualisieren
                if ($processedCount % 100 -eq 0 -or $processedCount -eq $total) {
                    $percentComplete = if ($total -gt 0) { [math]::Round(($processedCount / $total) * 100, 1) } else { 0 }
                    $elapsed = (Get-Date) - $startTime
                    $rate = if ($elapsed.TotalSeconds -gt 0) { [math]::Round($processedCount / $elapsed.TotalSeconds, 0) } else { 0 }
                    
                    Write-Progress-Safe -Activity "Check path length" `
                        -Status "$processedCount out of $total Items checked ($percentComplete%)" `
                        -PercentComplete $percentComplete `
                        -CurrentOperation "Current: $($_) | Rate: $rate Obj/s"
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
        Write-Host "Error while browsing: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Write-Progress -Activity "Check Path length" -Completed
    }
    return $longPaths
}


# Hauptprogramm
Clear-Host
Write-Host "=== Windows Path Length Checker ===" -ForegroundColor Magenta
Write-Host ""

# Parameter validieren
if (-not (Test-Path $Path)) {
    Write-Host "ERROR: Path not found: $Path" -ForegroundColor Red
    exit 1
}

if ($MaxLength -lt 1) {
    Write-Host "ERROR: MaxLength muss größer als 0 sein" -ForegroundColor Red
    exit 1
}

if ($UseParallel) {
    Write-Host "Recommendation: Parallel processing is ideal for:" -ForegroundColor Cyan
    Write-Host "  - Folders with >10.000 Objects" -ForegroundColor White
    Write-Host "  - Systems with multiple CPU cores" -ForegroundColor White
    Write-Host "  - Slow storage media (network drives)" -ForegroundColor White
    Write-Host ""
}

# Prüfung starten
$stopwatch = [System.Diagnostics.Stopwatch]::new()
$stopwatch.start()
$results = Test-PathLengths -RootPath $Path -MaxLength $MaxLength -UseParallel $UseParallel -ThrottleLimit $ThrottleLimit -BatchSize $BatchSize

# Ergebnisse anzeigen
$stopwatch.Stop()
$duration = $stopwatch.Elapsed

Write-Host ""
Write-Host "=== RESULTS ===" -ForegroundColor Magenta
Write-Host "Processing time: $($duration.TotalSeconds.ToString('F2')) Seconds" -ForegroundColor Green

if ($null -eq $results) {
    Write-Host "No path found longer than $MaxLength characters." -ForegroundColor Green
} else {
    Write-Host "Found: $(($results | Measure-Object).Count) Paths, that are longer than $MaxLength characters" -ForegroundColor Yellow
    Write-Host ""

    if ( $results.Length -gt 50 ) { 
        $results | Out-GridView 
    } else { 
        $results | Format-Table `
            @{Label="Path"; Expression={$_.Path}; Width=80}, 
            Length,
            Excess
    }
    
    # Statistiken
    $maxLength = ($results | Measure-Object -Property Length -Maximum).Maximum
    
    Write-Host "Statistics on excessively long paths:" -ForegroundColor Cyan
    Write-Host "  Longest path: $maxLength character" -ForegroundColor White
}

# Optional: Ergebnisse in Datei speichern
if ($OutputFile -ne "") {
    try {
        $results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
        Write-Host ""
        Write-Host "Result saved in: $OutputFile" -ForegroundColor Green
    }
    catch {
        Write-Host "Error while saving the file: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Check completed." -ForegroundColor Green
Write-Host ""
