#Requires -Version 5.1

function Invoke-VhcCollector {
    <#
    .Synopsis
        Executes a collector scriptblock with timing, error isolation, and structured result tracking.
        Use this wrapper for fire-and-forget collectors. Collectors whose return values are consumed
        by downstream collectors (Get-VhcServer, Get-VhcConcurrencyData, Get-VhcRepository) must
        be called directly by the Orchestrator - not via this wrapper.
    .Parameter Name
        Collector display name used in log messages and the result summary.
    .Parameter Action
        Scriptblock to execute. Its output is returned unchanged on success.
    .Outputs
        [PSCustomObject]@{Name; Success; Duration; Error; Output}
        Callers that need the scriptblock's return value should read the .Output property.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]      $Name,
        [Parameter(Mandatory)] [scriptblock] $Action
    )

    $start = Get-Date
    Write-LogFile "[$Name] Starting..." -LogLevel "INFO"

    $result = [PSCustomObject]@{
        Name     = $Name
        Success  = $false
        Duration = $null
        Error    = $null
        Output   = $null
    }

    try {
        $output = & $Action
        $elapsed = (Get-Date) - $start
        $result.Success  = $true
        $result.Duration = $elapsed
        $result.Output   = $output
        Write-LogFile "[$Name] Completed in $([math]::Round($elapsed.TotalSeconds, 1))s" -LogLevel "INFO"
    } catch {
        $elapsed = (Get-Date) - $start
        $result.Duration = $elapsed
        $result.Error    = $_.Exception.Message
        Write-LogFile "[$Name] FAILED: $($_.Exception.Message)" -LogLevel "ERROR"
    }

    return $result
}
