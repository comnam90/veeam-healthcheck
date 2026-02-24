#Requires -Version 5.1

function Export-VhcSessionCache {
    <#
    .Synopsis
        Fetches all VBR backup sessions within the report interval and exports them to
        SessionCache.xml in the report output directory for reuse by Get-VeeamSessionReport.ps1
        and Get-VeeamSessionReportVersion13.ps1.
        Source: Get-VBRConfig.ps1 (pre-refactor) lines 598-631.
    #>
    [CmdletBinding()]
    param()

    Write-LogFile "Exporting session cache..."

    $cutoff           = (Get-Date).AddDays(-$script:ReportInterval)
    $sessionCachePath = Join-Path -Path $script:ReportPath -ChildPath "SessionCache.xml"

    try {
        $allSessions = Get-VBRBackupSession | Where-Object { $_.CreationTime -gt $cutoff }
        Write-LogFile "Found $(@($allSessions).Count) sessions in the last $script:ReportInterval days"
        $allSessions | Export-Clixml -Path $sessionCachePath -Depth 3 -Force
        Write-LogFile "Exported session cache to: $sessionCachePath"
    }
    catch {
        Write-LogFile "Warning: Failed to export session cache: $($_.Exception.Message)" -LogLevel "WARNING"
    }
}
