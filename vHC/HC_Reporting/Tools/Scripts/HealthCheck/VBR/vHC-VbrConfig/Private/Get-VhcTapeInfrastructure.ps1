#Requires -Version 5.1

function Get-VhcTapeInfrastructure {
    <#
    .Synopsis
        Collects tape infrastructure: jobs, servers, libraries, media pools, and vaults.
        Exports _TapeJobs.csv, _TapeServers.csv, _TapeLibraries.csv, _TapeMediaPools.csv, _TapeVaults.csv.
        Source: Get-VBRConfig.ps1 lines 1155–1212.
    #>
    [CmdletBinding()]
    param()

    $message = "Collecting tape infrastructure..."
    Write-LogFile $message

    $tapeJob        = $null
    $tapeServers    = $null
    $tapeLibraries  = $null
    $tapeMediaPools = $null
    $tapeVaults     = $null

    try {
        $tapeJob = Get-VBRTapeJob
    } catch {
        Write-LogFile "Tape Jobs collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    try {
        $tapeServers = Get-VBRTapeServer
        Write-LogFile "Found $(@($tapeServers).Count) tape servers"
    } catch {
        Write-LogFile "Tape Servers collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    try {
        $tapeLibraries = Get-VBRTapeLibrary
        Write-LogFile "Found $(@($tapeLibraries).Count) tape libraries"
    } catch {
        Write-LogFile "Tape Libraries collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    try {
        $tapeMediaPools = Get-VBRTapeMediaPool
        Write-LogFile "Found $(@($tapeMediaPools).Count) tape media pools"
    } catch {
        Write-LogFile "Tape Media Pools collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    try {
        $tapeVaults = Get-VBRTapeVault
        Write-LogFile "Found $(@($tapeVaults).Count) tape vaults"
    } catch {
        Write-LogFile "Tape Vaults collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    $tapeJob        | Export-VhcCsv -FileName '_TapeJobs.csv'
    $tapeServers    | Export-VhcCsv -FileName '_TapeServers.csv'
    $tapeLibraries  | Export-VhcCsv -FileName '_TapeLibraries.csv'
    $tapeMediaPools | Export-VhcCsv -FileName '_TapeMediaPools.csv'
    $tapeVaults     | Export-VhcCsv -FileName '_TapeVaults.csv'

    Write-LogFile ($message + "DONE")
}
