#Requires -Version 5.1

function Get-VhcTapeInfrastructure {
    <#
    .Synopsis
        Collects tape infrastructure: jobs, servers, libraries, media pools, and vaults.
        Exports _TapeJobs.csv, _TapeServers.csv, _TapeLibraries.csv, _TapeMediaPools.csv, _TapeVaults.csv.
        Source: Get-VBRConfig.ps1 lines 1155-1212.
    #>
    [CmdletBinding()]
    param()

    $message = "Collecting tape infrastructure..."
    Write-LogFile $message

    $tapeJob = Get-VBRTapeJob
    $tapeServers = Get-VBRTapeServer
    Write-LogFile "Found $(@($tapeServers).Count) tape servers"
    $tapeLibraries = Get-VBRTapeLibrary
    Write-LogFile "Found $(@($tapeLibraries).Count) tape libraries"
    $tapeMediaPools = Get-VBRTapeMediaPool
    Write-LogFile "Found $(@($tapeMediaPools).Count) tape media pools"
    $tapeVaults = Get-VBRTapeVault
    Write-LogFile "Found $(@($tapeVaults).Count) tape vaults"

    $tapeJob        | Export-VhcCsv -FileName '_TapeJobs.csv'
    $tapeServers    | Export-VhcCsv -FileName '_TapeServers.csv'
    $tapeLibraries  | Export-VhcCsv -FileName '_TapeLibraries.csv'
    $tapeMediaPools | Export-VhcCsv -FileName '_TapeMediaPools.csv'
    $tapeVaults     | Export-VhcCsv -FileName '_TapeVaults.csv'

    Write-LogFile ($message + "DONE")
}
