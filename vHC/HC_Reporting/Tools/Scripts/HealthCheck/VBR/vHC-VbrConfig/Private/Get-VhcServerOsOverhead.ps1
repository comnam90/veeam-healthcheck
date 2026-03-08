#Requires -Version 5.1

function Get-VhcServerOsOverhead {
    <#
    .Synopsis
        Computes the total OS-level CPU and RAM overhead for a server entry by summing
        the fixed per-role overhead for each role that has active tasks.
        Returns @{ CPU = [int]; RAM = [int] }.
    .Parameter Entry
        The value portion of a HostRoles hashtable entry (not the key).
    .Parameter Thresholds
        The Thresholds object from VbrConfig.json (Config.Thresholds).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)] $Thresholds
    )

    $cpu = 0
    $ram = 0

    if ((SafeValue $Entry.TotalRepoTasks) -gt 0 -or (SafeValue $Entry.TotalGWTasks) -gt 0) {
        $cpu += $Thresholds.RepoOSCPU
        $ram += $Thresholds.RepoOSRAM
    }
    if ((SafeValue $Entry.TotalVpProxyTasks) -gt 0) {
        $cpu += $Thresholds.VpProxyOSCPU
        $ram += $Thresholds.VpProxyOSRAM
    }
    if ((SafeValue $Entry.TotalGPProxyTasks) -gt 0) {
        $cpu += $Thresholds.GpProxyOSCPU
        $ram += $Thresholds.GpProxyOSRAM
    }
    if ((SafeValue $Entry.TotalCDPProxyTasks) -gt 0) {
        $cpu += $Thresholds.CdpProxyOSCPU
        $ram += $Thresholds.CdpProxyOSRAM
    }

    return @{ CPU = $cpu; RAM = $ram }
}
