#Requires -Version 5.1
<#
.Synopsis
    Validates the session report unification by running both the CURRENT path and the
    UNIFIED (GetTaskSessions-only) path against a live VBR server, then comparing output.

.Description
    CURRENT path:
      - VBR >= 13: iterates $sessions directly (per-job-run rows, session-level Logger.GetLog())
      - VBR  < 13: calls GetTaskSessions() on each session (per-VM rows, task-level Logger.GetLog())

    UNIFIED path (proposed):
      - ALL versions: calls GetTaskSessions() on each session (per-VM rows, task-level Logger.GetLog())

    Run this on both a v12 and a v13 VBR server before implementing changes.

    On v12:  CURRENT == UNIFIED (same path) - proves no regression.
    On v13:  UNIFIED produces more rows with actual VM names instead of job-run names.

    Exports two CSV files to -OutputFolder:
      SessionUnification_CURRENT_<timestamp>.csv
      SessionUnification_UNIFIED_<timestamp>.csv

    Then prints a side-by-side summary to the console.

.Parameter SessionCount
    Maximum number of backup sessions to process. Default: 10.
    Increase to get more representative results at the cost of run time.

.Parameter ReportIntervalDays
    Fetch sessions created within this many days. Default: 7.

.Parameter TimeoutSeconds
    Seconds to wait per Logger.GetLog() call before skipping. Default: 20.

.Parameter OutputFolder
    Where to write the comparison CSVs. Default: $env:TEMP.

.Example
    # Quick sanity check (10 sessions, 7 days):
    .\Test-SessionUnification.ps1

    # Larger sample:
    .\Test-SessionUnification.ps1 -SessionCount 50 -ReportIntervalDays 14
#>
[CmdletBinding()]
param(
    [int]$SessionCount      = 10,
    [int]$ReportIntervalDays = 7,
    [int]$TimeoutSeconds    = 20,
    [string]$OutputFolder   = $env:TEMP
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

#region helpers

function Get-LogRecordsSafe {
    param($Session, [int]$TimeoutSeconds = 20)
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable('session', $Session)
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    $ps.AddScript({ try { $session.Logger.GetLog().UpdatedRecords } catch { $null } }) | Out-Null
    $handle    = $ps.BeginInvoke()
    $completed = $handle.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)
    if ($completed) {
        try   { $result = $ps.EndInvoke($handle) } catch { $result = $null }
    } else {
        $result = $null
        $ps.Stop()
    }
    $handle.AsyncWaitHandle.Dispose()
    $ps.Dispose()
    $runspace.Close()
    $runspace.Dispose()
    return $result
}

function Get-VbrMajorVersion {
    try {
        $svc = Get-VBRServer -ErrorAction Stop | Select-Object -First 1
        if ($svc) {
            $ver = [Veeam.Backup.Core.SProduct]::Create().Version
            return [int]($ver.Split('.')[0])
        }
    } catch { }
    try {
        $build = (Get-ItemProperty 'HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication' -ErrorAction Stop).ProductVersion
        return [int]($build.Split('.')[0])
    } catch { }
    return 0
}

$LogRegex            = [regex]'\bUsing \b.+\s(\[[^\]]*\])'
$BottleneckRegex     = [regex]'^Busy: (\S+ \d+% > \S+ \d+% > \S+ \d+% > \S+ \d+%)'
$PrimaryBottleneckRx = [regex]'^Primary bottleneck: (\S+)'

function Build-TaskRow {
    param($task, [array]$logRecords)

    $ProcessingMode = ''
    $BottleneckDetails = ''
    $PrimaryBottleneck = ''

    if ($null -ne $logRecords) {
        $pmMatches      = $logRecords | Where-Object Title -match $LogRegex
        $pmTitles       = $pmMatches.Title -replace '\bUsing \b.+\s\[', '' -replace ']', ''
        $ProcessingMode = ($pmTitles | Select-Object -Unique) -join ';'

        $bnMatch           = $logRecords | Where-Object Title -match $BottleneckRegex | Select-Object -Last 1
        $BottleneckDetails = if ($bnMatch) { $bnMatch.Title -replace '^Busy: ', '' } else { '' }

        $pbMatch           = $logRecords | Where-Object Title -match $PrimaryBottleneckRx | Select-Object -Last 1
        $PrimaryBottleneck = if ($pbMatch) { $pbMatch.Title -replace '^Primary bottleneck: ', '' } else { '' }
    }

    try { $jobDuration  = $task.JobSess.SessionInfo.Progress.Duration.ToString() } catch { $jobDuration  = '' }
    try { $taskDuration = $task.WorkDetails.WorkDuration.ToString() }               catch { $taskDuration = '' }

    return [pscustomobject][ordered]@{
        JobName           = $task.JobName
        VMName            = $task.Name
        Status            = $task.Status
        IsRetry           = $task.JobSess.IsRetryMode
        ProcessingMode    = $ProcessingMode
        JobDuration       = $jobDuration
        TaskDuration      = $taskDuration
        TaskAlgorithm     = $task.WorkDetails.TaskAlgorithm
        CreationTime      = $task.JobSess.CreationTime
        'BackupSize(GB)'  = [math]::Round(($task.JobSess.BackupStats.BackupSize / 1GB), 4)
        'DataSize(GB)'    = [math]::Round(($task.JobSess.BackupStats.DataSize / 1GB), 4)
        DedupRatio        = $task.JobSess.BackupStats.DedupRatio
        CompressRatio     = $task.JobSess.BackupStats.CompressRatio
        BottleneckDetails = $BottleneckDetails
        PrimaryBottleneck = $PrimaryBottleneck
        JobType           = $task.ObjectPlatform.Platform
    }
}

function Build-SessionRow {
    param($session, [array]$logRecords)

    $BottleneckDetails = ''
    $PrimaryBottleneck = ''

    if ($null -ne $logRecords) {
        $bnMatch           = $logRecords | Where-Object Title -Match '^Load: ' | Select-Object -Last 1
        $BottleneckDetails = if ($bnMatch) { $bnMatch.Title -replace '^Load: ', '' } else { '' }

        $pbMatch           = $logRecords | Where-Object Title -Match '^Primary [Bb]ottleneck: ' | Select-Object -Last 1
        $PrimaryBottleneck = if ($pbMatch) { $pbMatch.Title -replace '^Primary [Bb]ottleneck: ', '' } else { '' }
    }

    try { $jobDuration  = $session.Progress.Duration.ToString() }         catch { $jobDuration  = '' }
    try { $taskDuration = $session.WorkDetails.WorkDuration.ToString() }  catch { $taskDuration = '' }

    return [pscustomobject][ordered]@{
        JobName           = $session.JobName
        VMName            = $session.Name
        Status            = $session.Result
        IsRetry           = $session.Info.IsRetryMode
        ProcessingMode    = $session.ProcessingMode
        JobDuration       = $jobDuration
        TaskDuration      = $taskDuration
        TaskAlgorithm     = $session.Info.SessionAlgorithm
        CreationTime      = $session.Info.CreationTime
        'BackupSize(GB)'  = [math]::Round($session.BackupStats.BackupSize / 1GB, 4)
        'DataSize(GB)'    = [math]::Round($session.BackupStats.DataSize / 1GB, 4)
        DedupRatio        = $session.BackupStats.DedupRatio
        CompressRatio     = $session.BackupStats.CompressRatio
        BottleneckDetails = $BottleneckDetails
        PrimaryBottleneck = $PrimaryBottleneck
        JobType           = $session.Platform.Platform
    }
}

#endregion

#region preflight

Write-Host "`n=== VBR Session Report Unification Test ===" -ForegroundColor Cyan
Write-Host "SessionCount=$SessionCount  ReportIntervalDays=$ReportIntervalDays  TimeoutSeconds=$TimeoutSeconds`n"

if (-not (Get-Command 'Get-VBRBackupSession' -ErrorAction SilentlyContinue)) {
    Write-Error "Veeam PowerShell snap-in not loaded. Run: Add-PSSnapin VeeamPSSnapIn"
    exit 1
}

$vbrVersion = Get-VbrMajorVersion
if ($vbrVersion -eq 0) {
    # Fallback: ask the user
    Write-Warning "Could not auto-detect VBR major version."
    $vbrVersion = [int](Read-Host "Enter VBR major version (e.g. 12 or 13)")
}
Write-Host "Detected VBR major version: $vbrVersion" -ForegroundColor Yellow

#endregion

#region fetch sessions

Write-Host "`nFetching sessions (last $ReportIntervalDays days)..." -ForegroundColor Cyan
$cutoff = (Get-Date).AddDays(-$ReportIntervalDays)
$allSessions = @(Get-VBRBackupSession | Where-Object { $_.CreationTime -gt $cutoff })
Write-Host "Total sessions found: $($allSessions.Count)"

$sessions = @($allSessions | Sort-Object CreationTime -Descending | Select-Object -First $SessionCount)
Write-Host "Using first $($sessions.Count) sessions for comparison`n"

#endregion

#region CURRENT path

Write-Host "--- Running CURRENT path ---" -ForegroundColor Magenta
$currentRows = [System.Collections.ArrayList]@()

if ($vbrVersion -ge 13) {
    # Current >=13 path: session-level rows
    $i = 1
    foreach ($session in $sessions) {
        Write-Host "  [Current/$i] $($session.JobName) / $($session.Name)"
        $logs = Get-LogRecordsSafe -Session $session -TimeoutSeconds $TimeoutSeconds
        $row  = Build-SessionRow -session $session -logRecords $logs
        $null = $currentRows.Add($row)
        $i++
    }
} else {
    # Current <13 path: task-level rows (same as unified - proves no regression on v12)
    Write-Host "  (v12: current path IS task-level - running GetTaskSessions() to establish baseline)"
    try { $taskSessions = @($sessions.GetTaskSessions()) } catch { $taskSessions = @() }
    $i = 1
    foreach ($task in $taskSessions) {
        Write-Host "  [Current/$i] $($task.JobName) / $($task.Name)"
        $logs = Get-LogRecordsSafe -Session $task -TimeoutSeconds $TimeoutSeconds
        $row  = Build-TaskRow -task $task -logRecords $logs
        $null = $currentRows.Add($row)
        $i++
    }
}

Write-Host "  -> $($currentRows.Count) rows produced`n"

#endregion

#region UNIFIED path

Write-Host "--- Running UNIFIED path (GetTaskSessions for all versions) ---" -ForegroundColor Magenta
$unifiedRows = [System.Collections.ArrayList]@()

try { $allTasks = @($sessions.GetTaskSessions()) } catch { $allTasks = @() }
$i = 1
foreach ($task in $allTasks) {
    Write-Host "  [Unified/$i] $($task.JobName) / $($task.Name)"
    $logs = Get-LogRecordsSafe -Session $task -TimeoutSeconds $TimeoutSeconds
    $row  = Build-TaskRow -task $task -logRecords $logs
    $null = $unifiedRows.Add($row)
    $i++
}

Write-Host "  -> $($unifiedRows.Count) rows produced`n"

#endregion

#region export CSVs

$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$currentCsv = Join-Path $OutputFolder "SessionUnification_CURRENT_${timestamp}.csv"
$unifiedCsv = Join-Path $OutputFolder "SessionUnification_UNIFIED_${timestamp}.csv"

if ($currentRows.Count -gt 0) { $currentRows | Export-Csv -Path $currentCsv -NoTypeInformation -Encoding UTF8 }
if ($unifiedRows.Count -gt 0) { $unifiedRows | Export-Csv -Path $unifiedCsv -NoTypeInformation -Encoding UTF8 }

Write-Host "CSVs written to:"
Write-Host "  CURRENT: $currentCsv"
Write-Host "  UNIFIED: $unifiedCsv`n"

#endregion

#region comparison summary

Write-Host "=== COMPARISON SUMMARY ===" -ForegroundColor Cyan
Write-Host ""

$rowDelta = $unifiedRows.Count - $currentRows.Count
Write-Host ("Row count:  CURRENT={0}  UNIFIED={1}  delta={2}{3}" -f
    $currentRows.Count, $unifiedRows.Count, $(if ($rowDelta -ge 0) { '+' } else { '' }), $rowDelta)

if ($rowDelta -gt 0) {
    Write-Host "  -> UNIFIED produces more rows (expected on v13: per-VM instead of per-job-run)" -ForegroundColor Green
} elseif ($rowDelta -eq 0) {
    Write-Host "  -> Row counts match (expected on v12: same path both ways)" -ForegroundColor Green
} else {
    Write-Host "  -> WARNING: UNIFIED produced fewer rows than CURRENT" -ForegroundColor Red
}

Write-Host ""
Write-Host "--- VMName sample (first 10 rows) ---"
Write-Host "CURRENT:" -ForegroundColor Yellow
$currentRows | Select-Object -First 10 | Format-Table JobName, VMName, Status, ProcessingMode -AutoSize
Write-Host "UNIFIED:" -ForegroundColor Green
$unifiedRows | Select-Object -First 10 | Format-Table JobName, VMName, Status, ProcessingMode -AutoSize

Write-Host "--- BottleneckDetails sample (first 5 rows with non-empty value) ---"
Write-Host "CURRENT:" -ForegroundColor Yellow
$currentRows | Where-Object { $_.BottleneckDetails -ne '' } | Select-Object -First 5 |
    Format-Table JobName, VMName, BottleneckDetails, PrimaryBottleneck -AutoSize
Write-Host "UNIFIED:" -ForegroundColor Green
$unifiedRows | Where-Object { $_.BottleneckDetails -ne '' } | Select-Object -First 5 |
    Format-Table JobName, VMName, BottleneckDetails, PrimaryBottleneck -AutoSize

Write-Host "--- ProcessingMode sample (first 5 rows with non-empty value) ---"
Write-Host "CURRENT:" -ForegroundColor Yellow
$currentRows | Where-Object { $_.ProcessingMode -ne '' } | Select-Object -First 5 |
    Format-Table JobName, VMName, ProcessingMode -AutoSize
Write-Host "UNIFIED:" -ForegroundColor Green
$unifiedRows | Where-Object { $_.ProcessingMode -ne '' } | Select-Object -First 5 |
    Format-Table JobName, VMName, ProcessingMode -AutoSize

Write-Host ""
Write-Host "=== END ===" -ForegroundColor Cyan
Write-Host "Full results in CSV files above. Open both in Excel/VS Code to diff all columns.`n"

#endregion
