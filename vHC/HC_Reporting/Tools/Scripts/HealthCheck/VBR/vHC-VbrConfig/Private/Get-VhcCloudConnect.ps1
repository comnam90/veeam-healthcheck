#Requires -Version 5.1

function Get-VhcCloudConnect {
    <#
    .Synopsis
        Collects Cloud Connect gateway and tenant data.
        Exports _CloudGateways.csv, _CloudTenants.csv.
        Source: Get-VBRConfig.ps1 lines 1411-1433.
    #>
    [CmdletBinding()]
    param()

    $message = "Collecting Cloud Connect data..."
    Write-LogFile $message

    $cloudGateways = $null
    $cloudTenants  = $null

    try {
        $cloudGateways = Get-VBRCloudGateway
        Write-LogFile "Found $(@($cloudGateways).Count) cloud gateways"
    } catch {
        Write-LogFile "Cloud Connect Gateways collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    try {
        $cloudTenants = Get-VBRCloudTenant
        Write-LogFile "Found $(@($cloudTenants).Count) cloud tenants"
    } catch {
        Write-LogFile "Cloud Connect Tenants collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    $cloudGateways | Export-VhcCsv -FileName '_CloudGateways.csv'
    $cloudTenants  | Export-VhcCsv -FileName '_CloudTenants.csv'

    Write-LogFile ($message + "DONE")
}
