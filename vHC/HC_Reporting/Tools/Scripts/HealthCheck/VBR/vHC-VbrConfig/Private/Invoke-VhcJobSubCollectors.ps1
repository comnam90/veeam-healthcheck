#Requires -Version 5.1

function Invoke-VhcJobSubCollectors {
    <#
    .Synopsis
        Runs the nine private job-type sub-collectors with individual fault isolation.
        A single sub-collector failure does not abort the remaining ones.
        Called exclusively by Get-VhcJob. See ADR 0007.
    .Parameter Jobs
        Array of VBR job objects (from Get-VBRJob). Passed to Get-VhcReplication.
    .Parameter ReportInterval
        Number of days for NAS session lookback. Passed to Get-VhcNasJob.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)] [object[]] $Jobs          = @(),
        [Parameter(Mandatory = $false)] [int]      $ReportInterval = 14
    )

    Write-LogFile "Running job sub-collectors..."

    try { Get-VhcCatalystJob } catch {
        Write-LogFile "Get-VhcCatalystJob failed: $($_.Exception.Message)" -LogLevel "ERROR"
        Add-VhcModuleError -CollectorName 'Jobs' -ErrorMessage $_.Exception.Message
    }
    try { Get-VhcAgentJob } catch {
        Write-LogFile "Get-VhcAgentJob failed: $($_.Exception.Message)" -LogLevel "ERROR"
        Add-VhcModuleError -CollectorName 'Jobs' -ErrorMessage $_.Exception.Message
    }
    try { Get-VhcSureBackup } catch {
        Write-LogFile "Get-VhcSureBackup failed: $($_.Exception.Message)" -LogLevel "ERROR"
        Add-VhcModuleError -CollectorName 'Jobs' -ErrorMessage $_.Exception.Message
    }
    try { Get-VhcTapeInfrastructure } catch {
        Write-LogFile "Get-VhcTapeInfrastructure failed: $($_.Exception.Message)" -LogLevel "ERROR"
        Add-VhcModuleError -CollectorName 'Jobs' -ErrorMessage $_.Exception.Message
    }
    try { Get-VhcNasJob -ReportInterval $ReportInterval } catch {
        Write-LogFile "Get-VhcNasJob failed: $($_.Exception.Message)" -LogLevel "ERROR"
        Add-VhcModuleError -CollectorName 'Jobs' -ErrorMessage $_.Exception.Message
    }
    try { Get-VhcPluginAndCdpJob } catch {
        Write-LogFile "Get-VhcPluginAndCdpJob failed: $($_.Exception.Message)" -LogLevel "ERROR"
        Add-VhcModuleError -CollectorName 'Jobs' -ErrorMessage $_.Exception.Message
    }
    try { Get-VhcReplication -Jobs @($Jobs) } catch {
        Write-LogFile "Get-VhcReplication failed: $($_.Exception.Message)" -LogLevel "ERROR"
        Add-VhcModuleError -CollectorName 'Jobs' -ErrorMessage $_.Exception.Message
    }
    try { Get-VhcCloudConnect } catch {
        Write-LogFile "Get-VhcCloudConnect failed: $($_.Exception.Message)" -LogLevel "ERROR"
        Add-VhcModuleError -CollectorName 'Jobs' -ErrorMessage $_.Exception.Message
    }
    try { Get-VhcCredentialsAndNotifications } catch {
        Write-LogFile "Get-VhcCredentialsAndNotifications failed: $($_.Exception.Message)" -LogLevel "ERROR"
        Add-VhcModuleError -CollectorName 'Jobs' -ErrorMessage $_.Exception.Message
    }

    Write-LogFile "Job sub-collectors complete."
}
