#Requires -Version 5.1

function Get-VhcRepoGateway {
    <#
    .Synopsis
        Collects repository and gateway server data, exports _RepositoryServers.csv and _Gateways.csv.
        Appends Repository and Gateway role data to the shared HostRoles hashtable.
        Source: Get-VBRConfig.ps1 lines 604-689.
    .Parameter Repositories
        Array of backup repository objects returned by Get-VBRBackupRepository.
    .Parameter VServers
        Array of VBR server objects (from Get-VBRServer) for hardware info lookup.
    .Parameter HostRoles
        Shared hashtable keyed by server name. Modified in-place.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [object[]] $Repositories,
        [Parameter(Mandatory)] [object[]] $VServers,
        [Parameter(Mandatory)] [hashtable] $HostRoles
    )

    $message = "Calculating Repository and GW Data..."
    Write-LogFile $message

    try {
        $RepoData = [System.Collections.Generic.List[PSCustomObject]]::new()
        $GWData   = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($Repository in $Repositories) {
            $NrofRepositoryTasks = $Repository.Options.MaxTaskCount
            $gatewayServers      = $Repository.GetActualGateways()
            $NrofgatewayServers  = $gatewayServers.Count

            # -1 signals unlimited; cap at 128 to match original behaviour
            if ($NrofRepositoryTasks -eq -1) {
                $NrofRepositoryTasks = 128
            }

            if ($NrofgatewayServers -gt 0) {
                foreach ($gatewayServer in $gatewayServers) {
                    $Server  = $VServers | Where-Object { $_.Name -eq $gatewayServer.Name }
                    $GWCores = $Server.GetPhysicalHost().HardwareInfo.CoresCount
                    $GWRAM   = ConvertToGB($Server.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal)

                    $GWDetails = [pscustomobject][ordered]@{
                        'Repository Name'  = $Repository.Name
                        'Gateway Server'   = $gatewayServer.Name
                        'Gateway Cores'    = $GWCores
                        'Gateway RAM (GB)' = $GWRAM
                        'Concurrent Tasks' = $NrofRepositoryTasks / $NrofgatewayServers
                    }
                    $GWData.Add($GWDetails)

                    if (-not $HostRoles.ContainsKey($gatewayServer.Name)) {
                        $HostRoles[$gatewayServer.Name] = [ordered]@{
                            Roles         = @('Gateway')
                            Names         = @($gatewayServer.Name)
                            TotalTasks    = 0
                            Cores         = $GWCores
                            RAM           = $GWRAM
                            TotalGWTasks  = 0
                        }
                    } else {
                        $HostRoles[$gatewayServer.Name].Roles += 'Gateway'
                        $HostRoles[$gatewayServer.Name].Names += $Repository.Name
                    }
                    $HostRoles[$gatewayServer.Name].TotalGWTasks += $NrofRepositoryTasks / $NrofgatewayServers
                    $HostRoles[$gatewayServer.Name].TotalTasks   += $NrofRepositoryTasks / $NrofgatewayServers
                }
            } else {
                $Server    = $VServers | Where-Object { $_.Name -eq $Repository.Host.Name }
                $RepoCores = $Server.GetPhysicalHost().HardwareInfo.CoresCount
                $RepoRAM   = ConvertToGB($Server.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal)

                $RepoDetails = [pscustomobject][ordered]@{
                    'Repository Name'     = $Repository.Name
                    'Repository Server'   = $Repository.Host.Name
                    'Repository Cores'    = $RepoCores
                    'Repository RAM (GB)' = $RepoRAM
                    'Concurrent Tasks'    = $NrofRepositoryTasks
                }
                $RepoData.Add($RepoDetails)

                if (-not $HostRoles.ContainsKey($Repository.Host.Name)) {
                    $HostRoles[$Repository.Host.Name] = [ordered]@{
                        Roles           = @('Repository')
                        Names           = @($Repository.Name)
                        TotalTasks      = 0
                        Cores           = $RepoCores
                        RAM             = $RepoRAM
                        TotalRepoTasks  = 0
                    }
                } else {
                    $HostRoles[$Repository.Host.Name].Roles += 'Repository'
                    $HostRoles[$Repository.Host.Name].Names += $Repository.Name
                }
                $HostRoles[$Repository.Host.Name].TotalRepoTasks += $NrofRepositoryTasks
                $HostRoles[$Repository.Host.Name].TotalTasks     += $NrofRepositoryTasks
            }
        }

        Write-LogFile ($message + "DONE")
        $RepoData | Export-VhcCsv -FileName '_RepositoryServers.csv'
        $GWData   | Export-VhcCsv -FileName '_Gateways.csv'
    } catch {
        Write-LogFile ($message + "FAILED!")
        Write-LogFile $_.Exception.Message -LogLevel "ERROR"
    }
}
