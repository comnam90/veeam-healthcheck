#Requires -Version 5.1

function Invoke-VhcConcurrencyAnalysis {
    <#
    .Synopsis
        Calculates per-server CPU/RAM requirements and suggested task counts based on the
        aggregated host-role map produced by Get-VhcConcurrencyData. Exports the results to
        _AllServersRequirementsComparison.csv.
        Source: Get-VBRConfig.ps1 lines 719-823.

    .Notes
        Intentional fixes applied vs source:
        1. ($serverName -contains $BackupServerName) changed to (-eq).
           PowerShell -contains on a scalar string behaves identically to -eq, so no output change.
        2. $CDPProxyOSCPUReq / $CDPProxyOSRAMReq were undefined in the source (bug).
           Now read from $Config.Thresholds.CdpProxyOSCPU / CdpProxyOSRAM (both default to 0).
           CDPProxy OS overhead is now correctly included in $RequiredCores / $RequiredRAM,
           but the default value of 0 means no change in practice.

    .Parameter HostRoles
        Hashtable returned by Get-VhcConcurrencyData.
    .Parameter Config
        Parsed VbrConfig.json object. Provides all threshold values.
    .Parameter VBRVersion
        Major VBR version integer. Determines which BackupServer CPU/RAM thresholds to apply.
    .Parameter BackupServerName
        VBR server hostname string. Used to identify the backup server row and add its overhead.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [hashtable]    $HostRoles,
        [Parameter(Mandatory)] [PSCustomObject] $Config,
        [Parameter(Mandatory)] [int]          $VBRVersion,
        [Parameter(Mandatory)] [string]       $BackupServerName
    )

    $message = "Calculating Requirements based on aggregated resources for multi-role servers..."
    Write-LogFile $message

    try {
        $t = $Config.Thresholds

        # Per-task requirements
        $VPProxyRAMReq  = $t.VpProxyRAMPerTask
        $VPProxyCPUReq  = $t.VpProxyCPUPerTask
        $GPProxyRAMReq  = $t.GpProxyRAMPerTask
        $GPProxyCPUReq  = $t.GpProxyCPUPerTask
        $RepoGWRAMReq   = $t.RepoGwRAMPerTask
        $RepoGWCPUReq   = $t.RepoGwCPUPerTask
        $CDPProxyRAMReq = $t.CdpProxyRAM
        $CDPProxyCPUReq = $t.CdpProxyCPU

        # Backup Server thresholds vary by version
        $BSCPUReq = if ($VBRVersion -eq 13) { $t.BackupServerCPU_v13 } else { $t.BackupServerCPU_v12 }
        $BSRAMReq = if ($VBRVersion -eq 13) { $t.BackupServerRAM_v13 } else { $t.BackupServerRAM_v12 }

        $RequirementsComparison = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($server in $HostRoles.GetEnumerator()) {
            $SuggestedTasksByCores = 0
            $SuggestedTasksByRAM   = 0
            $serverName            = $server.Key

            $overhead = Get-VhciServerOsOverhead -Entry $server.Value -Thresholds $t

            $RequiredCores = [Math]::Ceiling(
                (SafeValue $server.Value.TotalRepoTasks)     * $RepoGWCPUReq   +
                (SafeValue $server.Value.TotalGWTasks)       * $RepoGWCPUReq   +
                (SafeValue $server.Value.TotalVpProxyTasks)  * $VPProxyCPUReq  +
                (SafeValue $server.Value.TotalGPProxyTasks)  * $GPProxyCPUReq  +
                (SafeValue $server.Value.TotalCDPProxyTasks) * $CDPProxyCPUReq +
                $overhead.CPU
            )

            $RequiredRAM = [Math]::Ceiling(
                (SafeValue $server.Value.TotalRepoTasks)     * $RepoGWRAMReq   +
                (SafeValue $server.Value.TotalGWTasks)       * $RepoGWRAMReq   +
                (SafeValue $server.Value.TotalVpProxyTasks)  * $VPProxyRAMReq  +
                (SafeValue $server.Value.TotalGPProxyTasks)  * $GPProxyRAMReq  +
                (SafeValue $server.Value.TotalCDPProxyTasks) * $CDPProxyRAMReq +
                $overhead.RAM
            )

            $coresAvailable = $server.Value.Cores
            $ramAvailable   = $server.Value.RAM
            $totalTasks     = $server.Value.TotalTasks

            $SuggestedTasksByCores = [Math]::Floor((SafeValue $coresAvailable) - $overhead.CPU)

            $SuggestedTasksByRAM = [Math]::Floor((SafeValue $ramAvailable) - $overhead.RAM)

            # Fix: source used ($serverName -contains $BackupServerName) which is semantically
            # wrong (scalar -contains). Changed to -eq; no output change.
            if ($serverName -eq $BackupServerName) {
                $RequiredCores         += $BSCPUReq
                $RequiredRAM           += $BSRAMReq
                $SuggestedTasksByCores -= $BSCPUReq
                $SuggestedTasksByRAM   -= $BSRAMReq
            }

            $NonNegativeCores = EnsureNonNegative($SuggestedTasksByCores * 2)
            $NonNegativeRAM   = EnsureNonNegative($SuggestedTasksByRAM)
            $MaxSuggestedTasks = [Math]::Min($NonNegativeCores, $NonNegativeRAM)

            $RequirementComparison = [pscustomobject][ordered]@{
                'Server'             = $serverName
                'Type'               = ($server.Value.Roles -join '/ ')
                'Required Cores'     = $RequiredCores
                'Available Cores'    = $coresAvailable
                'Required RAM (GB)'  = $RequiredRAM
                'Available RAM (GB)' = $ramAvailable
                'Concurrent Tasks'   = $totalTasks
                'Suggested Tasks'    = $MaxSuggestedTasks
                'Names'              = ($server.Value.Names -join '/ ')
            }
            $RequirementsComparison.Add($RequirementComparison)
        }

        Write-LogFile ($message + "DONE")
        $RequirementsComparison | Export-VhciCsv -FileName '_AllServersRequirementsComparison.csv'
        Write-LogFile "Concurrency inspection files are exported."
    } catch {
        Write-LogFile ($message + "FAILED!")
        Write-LogFile $_.Exception.Message -LogLevel "ERROR"
    }
}
