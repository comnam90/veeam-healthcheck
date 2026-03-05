#Requires -Version 5.1

function Get-VhcWanAccelerator {
    <#
    .Synopsis
        Collects VBR WAN Accelerator configuration and exports to _WanAcc.csv.
    #>
    [CmdletBinding()]
    param()

    $message = "Collecting WAN ACC info..."
    $wan     = $null
    Write-LogFile $message

    try {
        $wan = Get-VBRWANAccelerator
        Write-LogFile ($message + "DONE")
    } catch {
        Write-LogFile ($message + "FAILED!")
        Write-LogFile $_.Exception.Message -LogLevel "ERROR"
        $script:ModuleErrors.Add([PSCustomObject]@{
            CollectorName = 'WanAccelerator'
            Error         = $_.Exception.Message
            Timestamp     = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
        })
    }

    $wan | Export-VhcCsv -FileName '_WanAcc.csv'
}
