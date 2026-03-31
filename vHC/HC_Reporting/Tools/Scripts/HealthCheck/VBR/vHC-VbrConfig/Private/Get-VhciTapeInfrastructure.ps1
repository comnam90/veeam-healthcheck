#Requires -Version 5.1

function Get-VhciTapeInfrastructure {
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

    $tapeJob | Select-Object Name, Type, Id, Description,
        FullBackupMediaPool, IncrementalBackupMediaPool,
        @{N='ProcessIncrementalBackup'; E={
            if ($null -ne $_.ProcessIncrementalBackup) { $_.ProcessIncrementalBackup }
            else { -not [string]::IsNullOrEmpty($_.IncrementalBackupPolicy) }
        }},
        @{N='Objects'; E={
            ($_.Object | Where-Object {$_} | ForEach-Object {
                if ($_ -is [string]) { $_ } elseif ($_.Name) { $_.Name } else { "$_" }
            }) -join ', '
        }},
        UseHardwareCompression, EjectCurrentMedium, ExportCurrentMediaSet,
        Enabled, NextRun, LastResult, LastState |
        Export-VhciCsv -FileName '_TapeJobs.csv'

    $tapeServers | Export-VhciCsv -FileName '_TapeServers.csv'

    $tapeLibraries | Select-Object Name, State, Type, Enabled, Id, Description,
        @{N='SlotsCount'; E={$_.Slots}},
        @{N='DrivesCount'; E={@($_.Drives).Count}} |
        Export-VhciCsv -FileName '_TapeLibraries.csv'

    $tapeMediaPools | Select-Object Name, Type, Description, RetentionPolicy, Id,
        @{N='MediaCount'; E={@($_.Medium).Count}},
        @{N='Encryption'; E={$_.EncryptionOptions}},
        @{N='IsWorm'; E={$_.Worm}} |
        Export-VhciCsv -FileName '_TapeMediaPools.csv'

    $tapeVaults | Export-VhciCsv -FileName '_TapeVaults.csv'

    Write-LogFile ($message + "DONE")
}
