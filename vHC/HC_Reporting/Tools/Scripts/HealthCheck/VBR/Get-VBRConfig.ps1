#Requires -Version 5.1

<#
.Synopsis
    Backward-compatibility shim. Delegates to VBR-Orchestrator.ps1.
.Notes
    This script is retained for compatibility with external tooling and the C# invoker
    until the next major version. Do not add logic here.
    See: docs/plans/2026-02-21-vbr-config-refactor.md (Task 11, Step 4)
.EXAMPLE
    Get-VBRConfig.ps1 -VBRServer myserver -VBRVersion 12
#>
param(
    [Parameter(Mandatory)]
    [string]$VBRServer,
    [Parameter(Mandatory = $false)]
    [int]$VBRVersion = 0,
    [Parameter(Mandatory = $false)]
    [string]$User = "",
    [Parameter(Mandatory = $false)]
    [string]$Password = "",
    [Parameter(Mandatory = $false)]
    [string]$PasswordBase64 = "",
    [Parameter(Mandatory = $false)]
    [bool]$RemoteExecution = $false,
    [Parameter(Mandatory = $false)]
    [string]$ReportPath = "",
    [Parameter(Mandatory = $false)]
    [int]$ReportInterval = 14,
    [Parameter(Mandatory = $false)]
    [switch]$RescanHosts
)

& "$PSScriptRoot\VBR-Orchestrator.ps1" @PSBoundParameters
