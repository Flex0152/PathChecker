
function Get-AllFileSystemEntriesIterative {
    param([string]$RootPath)

    $stack = New-Object System.Collections.Stack
    $stack.Push($RootPath)

    while($stack.Count -gt 0) {
        $current = $stack.Pop()
        try {
            foreach ($entry in [System.IO.Directory]::EnumerateFileSystemEntries($current)){
                $entry
                if ([System.IO.Directory]::Exists($entry)) {
                    $stack.Push($entry)
                }
            }
        }
        catch [System.UnauthorizedAccessException] {
            Write-Verbose "Kein Zugriff auf $current"
        }
        catch {
            Write-Verbose "Fehler bei $current : $($_.Exception.Message)"
        }
    }
}

function Get-AllEntries {
    param (
        [string] $path,
        [switch] $IgnoreInaccessible = $false,
        [switch] $RecurseSubdirectories = $false
    )
    $dirs = [System.Collections.Generic.List[string]]::new()
    if ($PSVersionTable.psversion.major -gt 5){
        Write-Verbose "Zähle Objekte mit PowerShell 7 Methode ..."
        $options = [System.IO.EnumerationOptions]::new()
        $options.IgnoreInaccessible = $IgnoreInaccessible
        $options.RecurseSubdirectories = $RecurseSubdirectories
        $dirs = [System.IO.Directory]::EnumerateFileSystemEntries($path, '*', $options)
    } else {
        Write-Verbose "Zähle Objekte mit PowerShell 5 Methode ..."
        $dirs = Get-AllFileSystemEntriesIterative -RootPath $path
    }
    return $dirs
}


# $stopwatch = [System.Diagnostics.Stopwatch]::new()
# $stopwatch.Start()

# $dirs = AllEntries -path "C:\Windows"
# # $dirs = Get-ChildItem -Path "c:\windows" -Recurse -ErrorAction SilentlyContinue
# Write-Host "Ich habe $($dirs.Length) Elemente gefunden!"

# $stopwatch.Stop()
# $stopwatch.Elapsed