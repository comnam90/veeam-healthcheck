#Requires -Version 5.1

function Invoke-VhcConcurrencyAnalysis {
    <#
    .Synopsis
        Calculates per-server CPU/RAM requirements and suggested task counts based on the
        aggregated host-role map produced by Get-VhcConcurrencyData. Exports the results to
        _AllServersRequirementsComparison.csv.
        Source: Get-VBRConfig.ps1 lines 719–823.

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

        # OS overhead (fixed per-role, applied once regardless of task count)
        $VPProxyOSCPUReq  = $t.VpProxyOSCPU
        $VPProxyOSRAMReq  = $t.VpProxyOSRAM
        $GPProxyOSCPUReq  = $t.GpProxyOSCPU
        $GPProxyOSRAMReq  = $t.GpProxyOSRAM
        $RepoOSCPUReq     = $t.RepoOSCPU
        $RepoOSRAMReq     = $t.RepoOSRAM
        # Fix: was undefined in source — read from config (defaults to 0, no output change)
        $CDPProxyOSCPUReq = $t.CdpProxyOSCPU
        $CDPProxyOSRAMReq = $t.CdpProxyOSRAM

        # Backup Server thresholds vary by version
        $BSCPUReq = if ($VBRVersion -eq 13) { $t.BackupServerCPU_v13 } else { $t.BackupServerCPU_v12 }
        $BSRAMReq = if ($VBRVersion -eq 13) { $t.BackupServerRAM_v13 } else { $t.BackupServerRAM_v12 }

        $RequirementsComparison = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($server in $HostRoles.GetEnumerator()) {
            $SuggestedTasksByCores = 0
            $SuggestedTasksByRAM   = 0
            $serverName            = $server.Key

            # Pre-compute OS overhead conditionals (PS 5.1 compatible — no ternary operator)
            $RepoGWOSCPUOverhead   = if ((SafeValue $server.Value.TotalRepoTasks)    -gt 0 -or
                                         (SafeValue $server.Value.TotalGWTasks)      -gt 0) { $RepoOSCPUReq     } else { 0 }
            $VpProxyOSCPUOverhead  = if ((SafeValue $server.Value.TotalVpProxyTasks) -gt 0) { $VPProxyOSCPUReq  } else { 0 }
            $GPProxyOSCPUOverhead  = if ((SafeValue $server.Value.TotalGPProxyTasks) -gt 0) { $GPProxyOSCPUReq  } else { 0 }
            $CDPProxyOSCPUOverhead = if ((SafeValue $server.Value.TotalCDPProxyTasks) -gt 0) { $CDPProxyOSCPUReq } else { 0 }

            $RepoGWOSRAMOverhead   = if ((SafeValue $server.Value.TotalRepoTasks)    -gt 0 -or
                                         (SafeValue $server.Value.TotalGWTasks)      -gt 0) { $RepoOSRAMReq     } else { 0 }
            $VpProxyOSRAMOverhead  = if ((SafeValue $server.Value.TotalVpProxyTasks) -gt 0) { $VPProxyOSRAMReq  } else { 0 }
            $GPProxyOSRAMOverhead  = if ((SafeValue $server.Value.TotalGPProxyTasks) -gt 0) { $GPProxyOSRAMReq  } else { 0 }
            $CDPProxyOSRAMOverhead = if ((SafeValue $server.Value.TotalCDPProxyTasks) -gt 0) { $CDPProxyOSRAMReq } else { 0 }

            $RequiredCores = [Math]::Ceiling(
                (SafeValue $server.Value.TotalRepoTasks)     * $RepoGWCPUReq   +
                (SafeValue $server.Value.TotalGWTasks)       * $RepoGWCPUReq   +
                (SafeValue $server.Value.TotalVpProxyTasks)  * $VPProxyCPUReq  +
                (SafeValue $server.Value.TotalGPProxyTasks)  * $GPProxyCPUReq  +
                (SafeValue $server.Value.TotalCDPProxyTasks) * $CDPProxyCPUReq +
                $RepoGWOSCPUOverhead  +
                $VpProxyOSCPUOverhead +
                $GPProxyOSCPUOverhead +
                $CDPProxyOSCPUOverhead
            )

            $RequiredRAM = [Math]::Ceiling(
                (SafeValue $server.Value.TotalRepoTasks)     * $RepoGWRAMReq   +
                (SafeValue $server.Value.TotalGWTasks)       * $RepoGWRAMReq   +
                (SafeValue $server.Value.TotalVpProxyTasks)  * $VPProxyRAMReq  +
                (SafeValue $server.Value.TotalGPProxyTasks)  * $GPProxyRAMReq  +
                (SafeValue $server.Value.TotalCDPProxyTasks) * $CDPProxyRAMReq +
                $RepoGWOSRAMOverhead  +
                $VpProxyOSRAMOverhead +
                $GPProxyOSRAMOverhead +
                $CDPProxyOSRAMOverhead
            )

            $coresAvailable = $server.Value.Cores
            $ramAvailable   = $server.Value.RAM
            $totalTasks     = $server.Value.TotalTasks

            $SuggestedTasksByCores = [Math]::Floor(
                (SafeValue $coresAvailable) -
                $RepoGWOSCPUOverhead  -
                $VpProxyOSCPUOverhead -
                $GPProxyOSCPUOverhead -
                $CDPProxyOSCPUOverhead
            )

            $SuggestedTasksByRAM = [Math]::Floor(
                (SafeValue $ramAvailable) -
                $RepoGWOSRAMOverhead  -
                $VpProxyOSRAMOverhead -
                $GPProxyOSRAMOverhead -
                $CDPProxyOSRAMOverhead
            )

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
        $RequirementsComparison | Export-VhcCsv -FileName '_AllServersRequirementsComparison.csv'
        Write-LogFile "Concurrency inspection files are exported."
    } catch {
        Write-LogFile ($message + "FAILED!")
        Write-LogFile $_.Exception.Message -LogLevel "ERROR"
    }
}
