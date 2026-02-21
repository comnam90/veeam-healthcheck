#Requires -Version 5.1

function Get-VhcAgentJob {
    <#
    .Synopsis
        Collects computer backup jobs and legacy endpoint (EP) backup jobs.
        Exports _AgentBackupJob.csv, _EndpointJob.csv.
        Source: Get-VBRConfig.ps1 lines 1117–1145.
    #>
    [CmdletBinding()]
    param()

    $message = "Collecting agent backup jobs..."
    Write-LogFile $message

    $vaBJob = $null
    $epJob  = $null

    try {
        $vaBJob = Get-VBRComputerBackupJob
    } catch {
        Write-LogFile "Computer Backup Job collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    try {
        $epJob = Get-VBREPJob
    } catch {
        Write-LogFile "EP Job collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    $vaBJob | Export-VhcCsv -FileName '_AgentBackupJob.csv'
    $epJob  | Export-VhcCsv -FileName '_EndpointJob.csv'

    Write-LogFile ($message + "DONE")
}
