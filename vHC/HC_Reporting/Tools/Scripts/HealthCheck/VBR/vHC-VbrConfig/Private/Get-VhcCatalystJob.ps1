#Requires -Version 5.1

function Get-VhcCatalystJob {
    <#
    .Synopsis
        Collects Catalyst copy jobs and Catalyst jobs.
        Exports _catCopyjob.csv, _catalystJob.csv.
        Source: Get-VBRConfig.ps1 lines 1102–1122.
    #>
    [CmdletBinding()]
    param()

    $message = "Collecting Catalyst jobs..."
    Write-LogFile $message

    $catCopy = $null
    $catJob  = $null

    try {
        $catCopy = Get-VBRCatalystCopyJob
    } catch {
        Write-LogFile "Catalyst Copy Job collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    try {
        $catJob = Get-VBRCatalystJob
    } catch {
        Write-LogFile "Catalyst Job collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    $catCopy | Export-VhcCsv -FileName '_catCopyjob.csv'
    $catJob  | Export-VhcCsv -FileName '_catalystJob.csv'

    Write-LogFile ($message + "DONE")
}
