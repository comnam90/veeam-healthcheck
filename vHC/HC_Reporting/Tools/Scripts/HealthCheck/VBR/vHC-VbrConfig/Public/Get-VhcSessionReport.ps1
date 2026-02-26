#Requires -Version 5.1

function Get-VhcSessionReport {
    <#
    .Synopsis
        Generates VeeamSessionReport.csv from the backup sessions held in $script:AllBackupSessions.
        Replaces the standalone Get-VeeamSessionReport.ps1 (VBR < 13) and
        Get-VeeamSessionReportVersion13.ps1 (VBR >= 13).

        Must be called after Get-VhcBackupSessions has successfully populated
        $script:AllBackupSessions with live .NET objects in the same process.

    .Parameter VBRVersion
        VBR major version (from Get-VhcMajorVersion).
        >= 13: iterate sessions directly using a timeout-guarded Logger.GetLog() call.
         < 13: call GetTaskSessions() on each session for task-level processing detail.

    .Notes
        PSInvoker.cs previously branched on VBRMAJORVERSION == 13 (only exact v13) when
        choosing which standalone script to invoke. This function uses >= 13, which is correct
        for v14+ as well. This is an intentional bug fix bundled into this refactor.

        $script:AllBackupSessions is nulled after CSV export to release live .NET objects
        from memory. Large deployments can hold thousands of session objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$VBRVersion
    )

    if (-not $script:AllBackupSessions -or @($script:AllBackupSessions).Count -eq 0) {
        throw "No backup sessions in `$script:AllBackupSessions. Ensure Get-VhcBackupSessions completed successfully before calling Get-VhcSessionReport."
    }

    Write-LogFile "Generating session report for $(@($script:AllBackupSessions).Count) sessions (VBR version $VBRVersion)..."

    [System.Collections.ArrayList]$allOutput = @()

    if ($VBRVersion -ge 13) {
        # VBR 13+ path: sessions from Get-VBRBackupSession are one row per VM per job run.
        # Access log records via a timeout-guarded runspace to prevent hanging on bad sessions.
        $i = 1
        foreach ($session in $script:AllBackupSessions) {
            Write-LogFile "[$i/$(@($script:AllBackupSessions).Count)] Processing: Job '$($session.JobName)', VM '$($session.Name)'"
            $i++

            $logRecords       = Get-VhcSessionLogWithTimeout -Session $session -TimeoutSeconds 30
            $BottleneckDetails = ''
            $PrimaryBottleneck = ''

            if ($null -ne $logRecords) {
                # Use '^Load: ' to avoid matching unrelated lines (e.g. 'Loading config', 'Workload').
                # Select-Object -Last 1 handles the case where multiple matching records exist.
                $bottleneckMatch   = $logRecords | Where-Object Title -Match '^Load: ' | Select-Object -Last 1
                $BottleneckDetails = if ($bottleneckMatch) { $bottleneckMatch.Title -replace '^Load: ', '' } else { '' }

                $primaryMatch      = $logRecords | Where-Object Title -Match '^Primary [Bb]ottleneck: ' | Select-Object -Last 1
                $PrimaryBottleneck = if ($primaryMatch) { $primaryMatch.Title -replace '^Primary [Bb]ottleneck: ', '' } else { '' }
            } else {
                Write-LogFile "Warning: Timeout or error getting log for '$($session.Name)' - bottleneck fields will be empty" -LogLevel "WARNING"
            }

            try { $jobDuration  = $session.Progress.Duration.ToString() }  catch { $jobDuration  = '' }
            try { $taskDuration = $session.WorkDetails.WorkDuration.ToString() } catch { $taskDuration = '' }

            $row = [pscustomobject][ordered]@{
                'JobName'           = $session.JobName
                'VMName'            = $session.Name
                'Status'            = $session.Result
                'IsRetry'           = $session.Info.IsRetryMode
                'ProcessingMode'    = $session.ProcessingMode
                'JobDuration'       = $jobDuration
                'TaskDuration'      = $taskDuration
                'TaskAlgorithm'     = $session.Info.SessionAlgorithm
                'CreationTime'      = $session.Info.CreationTime
                'BackupSize(GB)'    = [math]::Round($session.BackupStats.BackupSize / 1GB, 4)
                'DataSize(GB)'      = [math]::Round($session.BackupStats.DataSize / 1GB, 4)
                'DedupRatio'        = $session.BackupStats.DedupRatio
                'CompressRatio'     = $session.BackupStats.CompressRatio
                'BottleneckDetails' = $BottleneckDetails
                'PrimaryBottleneck' = $PrimaryBottleneck
                'JobType'           = $session.Platform.Platform
            }
            if ($row) { $null = $allOutput.Add($row) }
        }

    } else {
        # VBR < 13 path: call GetTaskSessions() on each backup session for task-level detail.
        # Logger.GetLog() is guarded by the same timeout runspace used in the >=13 path.
        $LogRegex            = [regex]'\bUsing \b.+\s(\[[^\]]*\])'
        $BottleneckRegex     = [regex]'^Busy: (\S+ \d+% > \S+ \d+% > \S+ \d+% > \S+ \d+%)'
        $PrimaryBottleneckRx = [regex]'^Primary bottleneck: (\S+)'

        $taskSessions = @()
        try {
            $taskSessions = @($script:AllBackupSessions.GetTaskSessions())
        } catch {
            Write-LogFile "Failed to retrieve task sessions: $($_.Exception.Message)" -LogLevel "ERROR"
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
