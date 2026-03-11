#Requires -Version 5.1

function Get-VhcSessionReport {
    <#
    .Synopsis
        Generates VeeamSessionReport.csv from the backup sessions passed via -BackupSessions.
        Replaces the standalone Get-VeeamSessionReport.ps1 and Get-VeeamSessionReportVersion13.ps1.

        Receives live .NET session objects from Get-VhcBackupSessions via the -BackupSessions
        parameter. Objects must remain in the same process to keep method access.

        Calls GetTaskSessions() on every backup session regardless of VBR version. This produces
        one row per VM (task) rather than one row per job run, giving accurate VMName and
        ProcessingMode values on all supported VBR versions. See ADR 0004.
    .Parameter BackupSessions
        Live Veeam backup session objects returned by Get-VhcBackupSessions. Pass $null or an
        empty array to produce a descriptive error rather than a silent empty CSV.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object[]] $BackupSessions
    )

    if (-not $BackupSessions -or @($BackupSessions).Count -eq 0) {
        throw "No backup sessions available. Ensure Get-VhcBackupSessions completed successfully before calling Get-VhcSessionReport."
    }

    Write-LogFile "Generating session report for $(@($BackupSessions).Count) sessions..."

    [System.Collections.ArrayList]$allOutput = @()

    # Use GetTaskSessions() for all VBR versions - returns one row per VM (task-level detail).
    # See ADR 0004 for the rationale; the >=13 session-level path was removed due to a
    # granularity bug (per-job-run rows, empty ProcessingMode, job-run names as VMName).
    $LogRegex            = [regex]'\bUsing \b.+\s(\[[^\]]*\])'
    $BottleneckRegex     = [regex]'^Busy: (\S+ \d+% > \S+ \d+% > \S+ \d+% > \S+ \d+%)'
    $PrimaryBottleneckRx = [regex]'^Primary bottleneck: (\S+)'

    $taskSessions = @()
    try {
        $taskSessions = @($BackupSessions.GetTaskSessions())
    } catch {
        Write-LogFile "Failed to retrieve task sessions: $($_.Exception.Message)" -LogLevel "ERROR"
        throw
    }

    foreach ($task in $taskSessions) {
        try {
            $logRecords = Get-VhciSessionLogWithTimeout -Session $task -TimeoutSeconds 30

            $ProcessingLogMatches = $logRecords | Where-Object Title -match $LogRegex
            $ProcessingLogTitles  = $(($ProcessingLogMatches.Title -replace '\bUsing \b.+\s\[', '') -replace ']', '')
            $ProcessingMode       = $($ProcessingLogTitles | Select-Object -Unique) -join ';'

            $BottleneckLogMatch       = $logRecords | Where-Object Title -match $BottleneckRegex | Select-Object -Last 1
            $BottleneckDetails        = if ($BottleneckLogMatch) { $BottleneckLogMatch.Title -replace 'Busy: ', '' } else { '' }

            $PrimaryBottleneckMatch   = $logRecords | Where-Object Title -match $PrimaryBottleneckRx | Select-Object -Last 1
            $PrimaryBottleneckDetails = if ($PrimaryBottleneckMatch) { $PrimaryBottleneckMatch.Title -replace 'Primary bottleneck: ', '' } else { '' }

            try { $jobDuration  = $task.JobSess.Progress.Duration.ToString() }               catch { $jobDuration  = '' }
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
                # NAS jobs leave BackupStats at 0; fall back to Progress fields (see ADR 0005)
                'BackupSizeGB'      = if ($task.JobSess.BackupStats.BackupSize -gt 0) {
                    [math]::Round(($task.JobSess.BackupStats.BackupSize / 1GB), 4)
                } else {
                    [math]::Round(($task.JobSess.Progress.TransferedSize / 1GB), 4)
                }
                'DataSizeGB'        = if ($task.JobSess.BackupStats.DataSize -gt 0) {
                    [math]::Round(($task.JobSess.BackupStats.DataSize / 1GB), 4)
                } else {
                    [math]::Round(($task.JobSess.Progress.ReadSize / 1GB), 4)
                }
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
            'BackupSizeGB'=''; 'DataSizeGB'=''; 'DedupRatio'=''; 'CompressRatio'='';
            'BottleneckDetails'=''; 'PrimaryBottleneck'=''; 'JobType'=''
        } | ConvertTo-Csv -NoTypeInformation | Select-Object -First 1)
        Out-File -FilePath $csvPath -InputObject $headerLine -Encoding UTF8
    }

}
