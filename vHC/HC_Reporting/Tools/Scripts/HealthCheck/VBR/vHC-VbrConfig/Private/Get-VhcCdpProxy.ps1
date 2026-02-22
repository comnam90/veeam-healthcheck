#Requires -Version 5.1

function Get-VhcCdpProxy {
    <#
    .Synopsis
        Collects CDP proxy data and exports to _CdpProxy.csv.
        Appends CDPProxy role data to the shared HostRoles hashtable.
        Source: Get-VBRConfig.ps1 lines 555-602.
    .Parameter CDPProxies
        Array of CDP proxy objects returned by Get-VBRCDPProxy.
    .Parameter VServers
        Array of VBR server objects (from Get-VBRServer) for hardware info lookup.
    .Parameter HostRoles
        Shared hashtable keyed by server name. Modified in-place.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [object[]] $CDPProxies,
        [Parameter(Mandatory)] [object[]] $VServers,
        [Parameter(Mandatory)] [hashtable] $HostRoles
    )

    $message = "Calculating CDP Proxy Data..."
    Write-LogFile $message

    try {
        $CDPProxyData = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($CDPProxy in $CDPProxies) {
            $CDPServer    = $VServers | Where-Object { $_.Id -eq $CDPProxy.ServerId }
            $CDPProxyCores = $CDPServer.GetPhysicalHost().HardwareInfo.CoresCount
            $CDPProxyRAM   = ConvertToGB($CDPServer.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal)

            $CDPProxyDetails = [pscustomobject][ordered]@{
                ServerId                 = $CDPProxy.ServerId
                CacheSize                = $CDPProxy.CacheSize
                CachePath                = $CDPProxy.CachePath
                IsEnabled                = $CDPProxy.IsEnabled
                SourceProxyTrafficPort   = $CDPProxy.SourceProxyTrafficPort
                TargetProxyTrafficPort   = $CDPProxy.TargetProxyTrafficPort
                Id                       = $CDPProxy.Id
                Name                     = $CDPProxy.Name
                Description              = $CDPProxy.Description
            }
            $CDPProxyData.Add($CDPProxyDetails)

            if (-not $HostRoles.ContainsKey($CDPServer.Name)) {
                $HostRoles[$CDPServer.Name] = [ordered]@{
                    Roles              = @('CDPProxy')
                    Names              = @($CDPProxy.Name)
                    TotalTasks         = 0
                    Cores              = $CDPProxyCores
                    RAM                = $CDPProxyRAM
                    TotalCDPProxyTasks = 0
                }
            } else {
                $HostRoles[$CDPServer.Name].Roles += 'CDPProxy'
                $HostRoles[$CDPServer.Name].Names += $CDPProxy.Name
            }
            $HostRoles[$CDPServer.Name].TotalCDPProxyTasks += 1
        }

        Write-LogFile ($message + "DONE")
        $CDPProxyData | Export-VhcCsv -FileName '_CdpProxy.csv'
    } catch {
        Write-LogFile ($message + "FAILED!")
        Write-LogFile $_.Exception.Message -LogLevel "ERROR"
    }
}
