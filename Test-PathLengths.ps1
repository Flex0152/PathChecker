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

Import-Module .\AllDirectories

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

if ($results -eq $null) {
    Write-Host "No path found longer than $MaxLength characters." -ForegroundColor Green
} else {
    Write-Host "Found: $(($results | Measure-Object).Count) Paths, that are longer than $MaxLength characters" -ForegroundColor Yellow
    Write-Host ""

    if ( $results.Length -gt 50 ) { $results | Out-GridView } else { $results }
    
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
