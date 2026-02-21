#Requires -Version 5.1

function Get-VhcGpProxy {
    <#
    .Synopsis
        Collects General Purpose (NAS) proxy data and exports to _NasProxy.csv.
        Appends GPProxy role data to the shared HostRoles hashtable.
        Source: Get-VBRConfig.ps1 lines 447–490.
    .Parameter GPProxies
        Array of GP/NAS proxy objects returned by Get-VBRNASProxyServer.
    .Parameter VServers
        Array of VBR server objects (from Get-VBRServer) for hardware info lookup.
    .Parameter HostRoles
        Shared hashtable keyed by server name. Modified in-place.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [object[]] $GPProxies,
        [Parameter(Mandatory)] [object[]] $VServers,
        [Parameter(Mandatory)] [hashtable] $HostRoles
    )

    $message = "Calculating GP Proxy Data..."
    Write-LogFile $message

    try {
        $GPProxyData = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($GPProxy in $GPProxies) {
            $NrofGPProxyTasks = $GPProxy.ConcurrentTaskNumber
            $Serv             = $VServers | Where-Object { $_.Name -eq $GPProxy.Server.Name }
            $GPProxyCores     = $Serv.GetPhysicalHost().HardwareInfo.CoresCount
            $GPProxyRAM       = ConvertToGB($Serv.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal)

            $GPProxyDetails = [pscustomobject][ordered]@{
                ConcurrentTaskNumber = $NrofGPProxyTasks
                Host                 = $GPProxy.Server.Name
                HostId               = $GPProxy.Server.Id
            }
            $GPProxyData.Add($GPProxyDetails)

            if (-not $HostRoles.ContainsKey($GPProxy.Server.Name)) {
                $HostRoles[$GPProxy.Server.Name] = [ordered]@{
                    Roles              = @('GPProxy')
                    Names              = @($GPProxy.Server.Name)
                    TotalTasks         = 0
                    Cores              = $GPProxyCores
                    RAM                = $GPProxyRAM
                    Task               = $NrofGPProxyTasks
                    TotalGPProxyTasks  = 0
                }
            } else {
                $HostRoles[$GPProxy.Server.Name].Roles += 'GPProxy'
                $HostRoles[$GPProxy.Server.Name].Names += $GPProxy.Server.Name
            }
            $HostRoles[$GPProxy.Server.Name].TotalGPProxyTasks += $NrofGPProxyTasks
            $HostRoles[$GPProxy.Server.Name].TotalTasks        += $NrofGPProxyTasks
        }

        Write-LogFile ($message + "DONE")
        $GPProxyData | Export-VhcCsv -FileName '_NasProxy.csv'
    } catch {
        Write-LogFile ($message + "FAILED!")
        Write-LogFile $_.Exception.Message -LogLevel "ERROR"
    }
}
