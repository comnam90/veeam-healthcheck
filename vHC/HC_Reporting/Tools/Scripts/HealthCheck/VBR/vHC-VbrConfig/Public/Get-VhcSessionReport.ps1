#Requires -Version 5.1

function Get-VhcSessionReport {
    <#
    .Synopsis
        Generates VeeamSessionReport.csv from the backup sessions held in $script:AllBackupSessions.
        Replaces the standalone Get-VeeamSessionReport.ps1 and Get-VeeamSessionReportVersion13.ps1.

        Must be called after Get-VhcBackupSessions has successfully populated
        $script:AllBackupSessions with live .NET objects in the same process.

        Calls GetTaskSessions() on every backup session regardless of VBR version. This produces
        one row per VM (task) rather than one row per job run, giving accurate VMName and
        ProcessingMode values on all supported VBR versions. See ADR 0004.

    .Notes
        $script:AllBackupSessions is nulled after CSV export to release live .NET objects
        from memory. Large deployments can hold thousands of session objects.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:AllBackupSessions -or @($script:AllBackupSessions).Count -eq 0) {
        throw "No backup sessions in `$script:AllBackupSessions. Ensure Get-VhcBackupSessions completed successfully before calling Get-VhcSessionReport."
    }

    Write-LogFile "Generating session report for $(@($script:AllBackupSessions).Count) sessions..."

    [System.Collections.ArrayList]$allOutput = @()

    # Use GetTaskSessions() for all VBR versions - returns one row per VM (task-level detail).
    # See ADR 0004 for the rationale; the >=13 session-level path was removed due to a
    # granularity bug (per-job-run rows, empty ProcessingMode, job-run names as VMName).
    $LogRegex            = [regex]'\bUsing \b.+\s(\[[^\]]*\])'
    $BottleneckRegex     = [regex]'^Busy: (\S+ \d+% > \S+ \d+% > \S+ \d+% > \S+ \d+%)'
    $PrimaryBottleneckRx = [regex]'^Primary bottleneck: (\S+)'

    $taskSessions = @()
    try {
        $taskSessions = @($script:AllBackupSessions.GetTaskSessions())
    } catch {
        Write-LogFile "Failed to retrieve task sessions: $($_.Exception.Message)" -LogLevel "ERROR"
        throw
    }

    foreach ($task in $taskSessions) {
        try {
            $logRecords = Get-VhcSessionLogWithTimeout -Session $task -TimeoutSeconds 30

            $ProcessingLogMatches = $logRecords | Where-Object Title -match $LogRegex
            $ProcessingLogTitles  = $(($ProcessingLogMatches.Title -replace '\bUsing \b.+\s\[', '') -replace ']', '')
            $ProcessingMode       = $($ProcessingLogTitles | Select-Object -Unique) -join ';'

            $BottleneckLogMatch       = $logRecords | Where-Object Title -match $BottleneckRegex | Select-Object -Last 1
            $BottleneckDetails        = if ($BottleneckLogMatch) { $BottleneckLogMatch.Title -replace 'Busy: ', '' } else { '' }

            $PrimaryBottleneckMatch   = $logRecords | Where-Object Title -match $PrimaryBottleneckRx | Select-Object -Last 1
            $PrimaryBottleneckDetails = if ($PrimaryBottleneckMatch) { $PrimaryBottleneckMatch.Title -replace 'Primary bottleneck: ', '' } else { '' }

            try { $jobDuration  = $task.JobSess.SessionInfo.Progress.Duration.ToString() } catch { $jobDuration  = '' }
            try { $taskDuration = $task.WorkDetails.WorkDuration.ToString() }               catch { $taskDuration = '' }

            $row = [pscustomobject][ordered]@{
                'JobName'           = $task.JobName
                'VMName'            = $task.Name
                'Status'            = $task.Status
                'IsRetry'           = $task.JobSess.IsRetryMode
                'ProcessingMode'    = $ProcessingMode
                'JobDuration'       = $jobDuration
                'TaskDuration'      = $taskDuration
                'TaskAlgorithm'     = $task.WorkDetails.TaskAlgorithm
                'CreationTime'      = $task.JobSess.CreationTime
                'BackupSize(GB)'    = [math]::Round(($task.JobSess.BackupStats.BackupSize / 1GB), 4)
                'DataSize(GB)'      = [math]::Round(($task.JobSess.BackupStats.DataSize / 1GB), 4)
                'DedupRatio'        = $task.JobSess.BackupStats.DedupRatio
                'CompressRatio'     = $task.JobSess.BackupStats.CompressRatio
                'BottleneckDetails' = $BottleneckDetails
                'PrimaryBottleneck' = $PrimaryBottleneckDetails
                'JobType'           = $task.ObjectPlatform.Platform
            }
            if ($row) { $null = $allOutput.Add($row) }
        } catch {
            Write-LogFile "Failed to process task '$($task.Name)' in job '$($task.JobName)': $($_.Exception.Message)" -LogLevel "WARNING"
        }
    }

    $csvPath = Join-Path -Path $script:ReportPath -ChildPath "VeeamSessionReport.csv"
    if ($allOutput.Count -gt 0) {
        $allOutput | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-LogFile "Exported $($allOutput.Count) session rows to $csvPath"
    } else {
        Write-LogFile "No session rows produced - writing header-only CSV" -LogLevel "WARNING"
        # Export-Csv with zero objects writes nothing; write header line explicitly instead.
        $headerLine = ([pscustomobject][ordered]@{
            'JobName'=''; 'VMName'=''; 'Status'=''; 'IsRetry'=''; 'ProcessingMode'='';
            'JobDuration'=''; 'TaskDuration'=''; 'TaskAlgorithm'=''; 'CreationTime'='';
            'BackupSize(GB)'=''; 'DataSize(GB)'=''; 'DedupRatio'=''; 'CompressRatio'='';
            'BottleneckDetails'=''; 'PrimaryBottleneck'=''; 'JobType'=''
        } | ConvertTo-Csv -NoTypeInformation | Select-Object -First 1)
        Out-File -FilePath $csvPath -InputObject $headerLine -Encoding UTF8
    }

    # Release live .NET session objects to free memory - large deployments can hold
    # thousands of sessions with log data as in-process .NET objects.
    $script:AllBackupSessions = $null
}
