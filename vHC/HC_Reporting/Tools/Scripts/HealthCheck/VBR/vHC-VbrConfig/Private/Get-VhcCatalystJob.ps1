#Requires -Version 5.1

function Get-VhcCatalystJob {
    <#
    .Synopsis
        Collects Catalyst copy jobs and Catalyst jobs.
        Exports _catCopyjob.csv, _catalystJob.csv.
        Source: Get-VBRConfig.ps1 lines 1102-1122.
    #>
    [CmdletBinding()]
    param()

    $message = "Collecting Catalyst jobs..."
    Write-LogFile $message

    $catCopy = Get-VBRCatalystCopyJob
    $catJob  = Get-VBRCatalystJob

    $catCopy | Export-VhcCsv -FileName '_catCopyjob.csv'
    $catJob  | Export-VhcCsv -FileName '_catalystJob.csv'

    Write-LogFile ($message + "DONE")
}
