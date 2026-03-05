#Requires -Version 5.1

function Get-VhcTrafficRules {
    <#
    .Synopsis
        Collects VBR network traffic rules and exports to _trafficRules.csv.
    #>
    [CmdletBinding()]
    param()

    $message      = "Collecting traffic info..."
    $trafficRules = $null
    Write-LogFile $message

    try {
        $trafficRules = Get-VBRNetworkTrafficRule
        Write-LogFile ($message + "DONE")
    } catch {
        Write-LogFile ($message + "FAILED!")
        Write-LogFile $_.Exception.Message -LogLevel "ERROR"
        $script:ModuleErrors.Add([PSCustomObject]@{
            CollectorName = 'TrafficRules'
            Error         = $_.Exception.Message
            Timestamp     = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
        })
    }

    $trafficRules | Export-VhcCsv -FileName '_trafficRules.csv'
}
