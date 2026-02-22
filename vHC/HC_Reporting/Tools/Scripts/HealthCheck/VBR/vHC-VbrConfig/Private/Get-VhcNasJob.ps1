#Requires -Version 5.1

function Get-VhcNasJob {
    <#
    .Synopsis
        Collects NAS backup jobs (with session-based size metrics) and NAS backup copy jobs.
        Exports _nasBackup.csv, _nasBCJ.csv.
        Source: Get-VBRConfig.ps1 lines 1213-1307.
    .Parameter ReportInterval
        Number of days back to query NAS backup sessions. Must match orchestrator $ReportInterval.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$ReportInterval = 14
    )

    $message = "Collecting NAS jobs..."
    Write-LogFile $message

    $nasBackup = $null
    $nasBCJ    = $null

    try {
        Write-LogFile "Calling Get-VBRUnstructuredBackupJob..."
        $nasBackup = Get-VBRUnstructuredBackupJob
        Write-LogFile "Found $(@($nasBackup).Count) NAS backup jobs"

        if (@($nasBackup).Count -gt 0) {
            Write-LogFile "Fetching NAS backup sessions for the last $ReportInterval days..."
            $cutoffDate = (Get-Date).AddDays(-$ReportInterval)

            $nasSessionLookup = @{}
            try {
                $allNasSessions = @()
                foreach ($nasJob in $nasBackup) {
                    $jobSessions = Get-VBRBackupSession -Name $nasJob.Name |
                        Where-Object { $_.CreationTime -gt $cutoffDate }
                    if ($jobSessions) {
                        $allNasSessions += $jobSessions
                    }
                }
                Write-LogFile "Found $($allNasSessions.Count) NAS sessions in the last $ReportInterval days"

                foreach ($session in $allNasSessions) {
                    $jobId = $session.JobId.ToString()
                    if (-not $nasSessionLookup.ContainsKey($jobId) -or
                        $session.CreationTime -gt $nasSessionLookup[$jobId].CreationTime) {
                        $nasSessionLookup[$jobId] = $session
                    }
                }
                Write-LogFile "Built NAS session lookup with $($nasSessionLookup.Count) unique jobs"
            } catch {
                Write-LogFile "Warning: Failed to get NAS sessions: $($_.Exception.Message)" -LogLevel "WARNING"
            }

            $jobCounter = 0
            foreach ($job in $nasBackup) {
                $jobCounter++
                Write-LogFile "Processing NAS job $jobCounter/$(@($nasBackup).Count): $($job.Name)"

                $onDiskGB = 0
                $sourceGb = 0

                $jobId = $job.Id.ToString()
                if ($nasSessionLookup.ContainsKey($jobId)) {
                    $session = $nasSessionLookup[$jobId]
                    if ($null -ne $session.Progress) {
                        $onDiskGB = $session.Progress.ProcessedUsedSize / 1GB
                        $sourceGb = $session.Progress.TotalSize / 1GB
                        Write-LogFile "  OnDiskGB: $onDiskGB, SourceGB: $sourceGb"
                    }
                } else {
                    Write-LogFile "  No NAS session found in last $ReportInterval days for job: $($job.Name)"
                }

                $job | Add-Member -MemberType NoteProperty -Name JobType  -Value "NAS Backup" -Force
                $job | Add-Member -MemberType NoteProperty -Name OnDiskGB -Value $onDiskGB    -Force
                $job | Add-Member -MemberType NoteProperty -Name SourceGB -Value $sourceGb    -Force
            }
        }
    } catch {
        Write-LogFile "NAS Jobs collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
        $nasBackup = $null
    }

    try {
        $nasBCJ = Get-VBRNASBackupCopyJob
        Write-LogFile "Found $(@($nasBCJ).Count) NAS backup copy jobs"
    } catch {
        Write-LogFile "NAS Backup Copy Jobs collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    $nasBackup | Export-VhcCsv -FileName '_nasBackup.csv'
    $nasBCJ    | Export-VhcCsv -FileName '_nasBCJ.csv'

    Write-LogFile ($message + "DONE")
}
