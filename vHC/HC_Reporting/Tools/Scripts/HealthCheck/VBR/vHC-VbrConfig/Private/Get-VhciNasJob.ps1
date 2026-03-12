#Requires -Version 5.1

function Get-VhciNasJob {
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

                # Build lookup: prefer the latest session that has Progress data (TotalSize > 0).
                # A failed session may have all Progress fields at 0; skipping it avoids
                # reporting 0 GB when an earlier successful session has real values.
                foreach ($group in ($allNasSessions | Group-Object { $_.JobId.ToString() })) {
                    $withData = @($group.Group |
                        Where-Object { $_.Progress.TotalSize -gt 0 } |
                        Sort-Object CreationTime -Descending)
                    $nasSessionLookup[$group.Name] = if ($withData.Count -gt 0) {
                        $withData[0]
                    } else {
                        $group.Group | Sort-Object CreationTime -Descending | Select-Object -First 1
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

    $nasBCJ = Get-VBRNASBackupCopyJob
    Write-LogFile "Found $(@($nasBCJ).Count) NAS backup copy jobs"

    $nasBackup | Export-VhciCsv -FileName '_nasBackup.csv'
    $nasBCJ    | Export-VhciCsv -FileName '_nasBCJ.csv'

    Write-LogFile ($message + "DONE")
}
