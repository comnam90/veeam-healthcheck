#Requires -Version 5.1

function Get-VhcViHvProxy {
    <#
    .Synopsis
        Collects VMware and Hyper-V proxy data and exports to _Proxies.csv and _HvProxy.csv.
        Appends Proxy role data to the shared HostRoles hashtable.
        Source: Get-VBRConfig.ps1 lines 492–553.
    .Parameter VMwareProxies
        Array of VMware proxy objects returned by Get-VBRViProxy.
    .Parameter HyperVProxies
        Array of Hyper-V proxy objects returned by Get-VBRHvProxy.
    .Parameter VServers
        Array of VBR server objects (from Get-VBRServer) for hardware info fallback.
    .Parameter HostRoles
        Shared hashtable keyed by server name. Modified in-place.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [object[]] $VMwareProxies,
        [Parameter(Mandatory)] [object[]] $HyperVProxies,
        [Parameter(Mandatory)] [object[]] $VServers,
        [Parameter(Mandatory)] [hashtable] $HostRoles
    )

    $message = "Calculating Vi and HV Proxy Data..."
    Write-LogFile $message

    try {
        $VPProxies  = $VMwareProxies + $HyperVProxies
        $ProxyData  = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($Proxy in $VPProxies) {
            $NrofProxyTasks = $Proxy.MaxTasksCount

            try {
                $ProxyCores = $Proxy.GetPhysicalHost().HardwareInfo.CoresCount
                $ProxyRAM   = ConvertToGB($Proxy.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal)
            } catch {
                $Server     = $VServers | Where-Object { $_.Name -eq $Proxy.Name }
                $ProxyCores = $Server.GetPhysicalHost().HardwareInfo.CoresCount
                $ProxyRAM   = ConvertToGB($Server.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal)
            }

            $proxytype = if ($Proxy.Type -eq 'Vi') { 'VMware' } else { $Proxy.Type }

            $ProxyDetails = [pscustomobject][ordered]@{
                Id               = $Proxy.Id
                Name             = $Proxy.Name
                Description      = $Proxy.Description
                Info             = $Proxy.Info
                HostId           = $Proxy.Host.Id
                Host             = $Proxy.Host.Name
                Type             = $proxytype
                IsDisabled       = $Proxy.IsDisabled
                Options          = $Proxy.Options
                MaxTasksCount    = $NrofProxyTasks
                UseSsl           = if ($Proxy.Type -eq 'Vi') { $Proxy.Options.UseSsl }          else { '' }
                FailoverToNetwork = if ($Proxy.Type -eq 'Vi') { $Proxy.Options.FailoverToNetwork } else { '' }
                TransportMode    = if ($Proxy.Type -eq 'Vi') { $Proxy.Options.TransportMode }   else { '' }
                IsVbrProxy       = ''
                ChosenVm         = if ($Proxy.Type -eq 'Vi') { $Proxy.Options.ChosenVm }        else { '' }
                ChassisType      = $Proxy.ChassisType
            }
            $ProxyData.Add($ProxyDetails)

            if (-not $HostRoles.ContainsKey($Proxy.Host.Name)) {
                $HostRoles[$Proxy.Host.Name] = [ordered]@{
                    Roles             = @('Proxy')
                    Names             = @($Proxy.Name)
                    TotalTasks        = 0
                    Cores             = $ProxyCores
                    RAM               = $ProxyRAM
                    TotalVpProxyTasks = 0
                }
            } else {
                $HostRoles[$Proxy.Host.Name].Roles += 'Proxy'
                $HostRoles[$Proxy.Host.Name].Names += $Proxy.Name
            }
            $HostRoles[$Proxy.Host.Name].TotalVpProxyTasks += $NrofProxyTasks
            $HostRoles[$Proxy.Host.Name].TotalTasks        += $NrofProxyTasks
        }

        Write-LogFile ($message + "DONE")

        $ProxyData | Export-VhcCsv -FileName '_Proxies.csv'

        $HyperVProxies | Select-Object `
            Id, Name, Description,
            @{ n = 'HostId'; e = { $_.Host.Id   } },
            @{ n = 'Host';   e = { $_.Host.Name } },
            Type, IsDisabled, Options, MaxTasksCount, Info |
            Export-VhcCsv -FileName '_HvProxy.csv'

    } catch {
        Write-LogFile ($message + "FAILED!")
        Write-LogFile $_.Exception.Message -LogLevel "ERROR"
    }
}
