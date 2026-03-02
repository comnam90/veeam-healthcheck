#Requires -Version 5.1

function Get-VhcBackupSessions {
    <#
    .Synopsis
        Fetches VBR backup sessions created within the reporting window and returns them
        as pipeline output. The caller (orchestrator) captures the output and passes it
        explicitly to Get-VhcSessionReport via the -BackupSessions parameter.
    .Parameter ReportInterval
        Number of days back to collect sessions for. Matches the -ReportInterval parameter
        passed to Get-VBRConfig.ps1.
    .Outputs
        [object[]] — Veeam backup session objects.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [int] $ReportInterval
    )

    Write-LogFile "Fetching backup sessions for the last $ReportInterval days..."
    $cutoff = (Get-Date).AddDays(-$ReportInterval)
    $sessions = @(Get-VBRBackupSession | Where-Object { $_.CreationTime -gt $cutoff })
    Write-LogFile "Collected $($sessions.Count) backup sessions."
    return $sessions
}
