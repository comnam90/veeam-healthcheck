#Requires -Version 5.1

function Get-VhcPluginAndCdpJob {
    <#
    .Synopsis
        Collects plugin backup jobs, CDP policies, and VCD replica jobs.
        Exports _pluginjobs.csv, _cdpjobs.csv, _vcdjobs.csv.
        Source: Get-VBRConfig.ps1 lines 1309-1349.
    #>
    [CmdletBinding()]
    param()

    $message = "Collecting plugin, CDP, and VCD jobs..."
    Write-LogFile $message

    $piJob  = $null
    $cdpJob = $null
    $vcdJob = $null

    try {
        $piJob = Get-VBRPluginJob
        Write-LogFile "Found $(@($piJob).Count) plugin jobs"
    } catch {
        Write-LogFile "Plugin Jobs collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    try {
        $cdpJob = Get-VBRCDPPolicy
        Write-LogFile "Found $(@($cdpJob).Count) CDP policies"
    } catch {
        Write-LogFile "CDP Policy collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    try {
        $vcdJob = Get-VBRvCDReplicaJob
        Write-LogFile "Found $(@($vcdJob).Count) VCD replica jobs"
    } catch {
        Write-LogFile "VCD Replica Jobs collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    $piJob | Export-VhcCsv -FileName '_pluginjobs.csv'

    $vcdJob | Add-Member -MemberType NoteProperty -Name JobType -Value "VCD Replica" -ErrorAction SilentlyContinue
    $vcdJob | Export-VhcCsv -FileName '_vcdjobs.csv'

    $cdpJob | Add-Member -MemberType NoteProperty -Name JobType -Value "CDP Policy" -ErrorAction SilentlyContinue
    $cdpJob | Export-VhcCsv -FileName '_cdpjobs.csv'

    Write-LogFile ($message + "DONE")
}
