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
    }

    $wan | Export-VhcCsv -FileName '_WanAcc.csv'
}
