#Requires -Version 5.1

function Get-VhcBackupSessions {
    <#
    .Synopsis
        Fetches all VBR backup sessions within the report interval and stores them as live
        .NET objects in $script:AllBackupSessions for use by Get-VhcSessionReport.

        Replaces Export-VhcSessionCache, which serialised objects via Export-Clixml. Serialisation
        produces Deserialized.* property-bag objects that lose all .NET methods, making session
        reporting (which requires GetTaskSessions() and Logger.GetLog()) impossible.

        Sessions must remain in the same process as the consumer to keep method access.
    #>
    [CmdletBinding()]
    param()

    Write-LogFile "Fetching backup sessions for the last $script:ReportInterval days..."

    $cutoff = (Get-Date).AddDays(-$script:ReportInterval)
    try {
        $script:AllBackupSessions = @(Get-VBRBackupSession | Where-Object { $_.CreationTime -gt $cutoff })
        Write-LogFile "Fetched $(@($script:AllBackupSessions).Count) backup sessions"
    }
    catch {
        Write-LogFile "Failed to fetch backup sessions: $($_.Exception.Message)" -LogLevel "ERROR"
        $script:AllBackupSessions = $null
        throw
    }
}
