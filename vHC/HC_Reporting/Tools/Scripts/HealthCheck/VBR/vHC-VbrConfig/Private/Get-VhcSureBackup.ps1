#Requires -Version 5.1

function Get-VhcSureBackup {
    <#
    .Synopsis
        Collects SureBackup jobs, application groups, and virtual labs.
        Exports _SureBackupJob.csv, _SureBackupAppGroups.csv, _SureBackupVirtualLabs.csv.
        Source: Get-VBRConfig.ps1 lines 1147–1153 and 1386–1409.
        Note: the SureBackup job export (originally at line 1153) and the app group/virtual lab
        exports (lines 1386–1409) are consolidated here for cohesion.
    #>
    [CmdletBinding()]
    param()

    $message = "Collecting SureBackup data..."
    Write-LogFile $message

    $sbJob        = $null
    $sbAppGroups  = $null
    $sbVirtualLabs = $null

    try {
        $sbJob = Get-VBRSureBackupJob
        Write-LogFile "Found $(@($sbJob).Count) SureBackup jobs"
    } catch {
        Write-LogFile "SureBackup Jobs collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    try {
        $sbAppGroups = Get-VSBApplicationGroup
        Write-LogFile "Found $(@($sbAppGroups).Count) SureBackup application groups"
    } catch {
        Write-LogFile "SureBackup Application Groups collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    try {
        $sbVirtualLabs = Get-VSBVirtualLab
        Write-LogFile "Found $(@($sbVirtualLabs).Count) SureBackup virtual labs"
    } catch {
        Write-LogFile "SureBackup Virtual Labs collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    $sbJob         | Export-VhcCsv -FileName '_SureBackupJob.csv'
    $sbAppGroups   | Export-VhcCsv -FileName '_SureBackupAppGroups.csv'
    $sbVirtualLabs | Export-VhcCsv -FileName '_SureBackupVirtualLabs.csv'

    Write-LogFile ($message + "DONE")
}
