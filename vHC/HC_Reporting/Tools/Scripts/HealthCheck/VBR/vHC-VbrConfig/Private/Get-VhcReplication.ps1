#Requires -Version 5.1

function Get-VhcReplication {
    <#
    .Synopsis
        Collects replica jobs, replica objects, and failover plans.
        Exports _ReplicaJobs.csv, _Replicas.csv, _FailoverPlans.csv.
        Source: Get-VBRConfig.ps1 lines 1350–1385.
    .Parameter Jobs
        Array of VBR job objects already retrieved by the parent Get-VhcJob. Used to filter
        replica jobs without an additional Get-VBRJob call.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$Jobs = @()
    )

    $message = "Collecting replication data..."
    Write-LogFile $message

    $replicaJobs  = $null
    $replicas     = $null
    $failoverPlans = $null

    try {
        $replicaJobs = @($Jobs) | Where-Object { $_.JobType -eq "Replica" }
        Write-LogFile "Found $(@($replicaJobs).Count) replica jobs"
    } catch {
        Write-LogFile "Replica Jobs collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    try {
        $replicas = Get-VBRReplica
        Write-LogFile "Found $(@($replicas).Count) replicas"
    } catch {
        Write-LogFile "Replicas collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    try {
        $failoverPlans = Get-VBRFailoverPlan
        Write-LogFile "Found $(@($failoverPlans).Count) failover plans"
    } catch {
        Write-LogFile "Failover Plans collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    $replicaJobs  | Export-VhcCsv -FileName '_ReplicaJobs.csv'
    $replicas      | Export-VhcCsv -FileName '_Replicas.csv'
    $failoverPlans | Export-VhcCsv -FileName '_FailoverPlans.csv'

    Write-LogFile ($message + "DONE")
}
