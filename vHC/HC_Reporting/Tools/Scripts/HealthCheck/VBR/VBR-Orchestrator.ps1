#Requires -Version 5.1

<#
.Synopsis
    Orchestrator entry point for VBR configuration collection.
    Replaces Get-VBRConfig.ps1 as the canonical entry point after Task 11 shim is in place.
.Notes
    Version: 1.0.0
    Part of the vHC VBR Config refactor — see docs/plans/2026-02-21-vbr-config-refactor.md
.EXAMPLE
    VBR-Orchestrator.ps1 -VBRServer myserver -VBRVersion 12
    VBR-Orchestrator.ps1 -VBRServer myserver -VBRVersion 13 -User admin -PasswordBase64 <base64>
#>
param(
    [Parameter(Mandatory)]
    [string]$VBRServer,

    [Parameter(Mandatory = $false)]
    [int]$VBRVersion = 0,

    [Parameter(Mandatory = $false)]
    [string]$User = "",

    # DEPRECATED: Plain-text password is retained for backward compatibility with manual CLI invocations only.
    # The C# invoker exclusively uses $PasswordBase64. Do not use $Password in new integrations.
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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Load and validate VbrConfig.json
# ---------------------------------------------------------------------------
$configPath = "$PSScriptRoot\VbrConfig.json"
if (-not (Test-Path $configPath)) {
    throw "VbrConfig.json not found at '$configPath'. Cannot proceed without configuration."
}

$config = Get-Content -Path $configPath -Raw | ConvertFrom-Json

foreach ($key in @('ConfigVersion', 'Thresholds', 'SecurityComplianceRuleNames')) {
    if ($null -eq $config.$key) {
        throw "VbrConfig.json is missing required key: '$key'"
    }
}

# ---------------------------------------------------------------------------
# Resolve default output path
# ---------------------------------------------------------------------------
if ([string]::IsNullOrEmpty($ReportPath)) {
    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $ReportPath = "$($config.DefaultOutputPath)\$VBRServer\$timestamp"
}

# ---------------------------------------------------------------------------
# Import the collector module
# ---------------------------------------------------------------------------
Import-Module "$PSScriptRoot\vHC-VbrConfig\vHC-VbrConfig.psd1" -Force

# ---------------------------------------------------------------------------
# Ensure Veeam module / PSSnapin is loaded
# Extracted from Get-VBRConfig.ps1 lines 126–143.
# PS 6+ (Core/7+) only supports modules; PS 5.1 tries the PSSnapin first.
# ---------------------------------------------------------------------------
if ($PSVersionTable.PSVersion.Major -ge 6) {
    if (-not (Get-Module -Name Veeam.Backup.PowerShell -ErrorAction SilentlyContinue)) {
        Import-Module -Name Veeam.Backup.PowerShell -ErrorAction Stop
    }
} else {
    if (-not (Get-PSSnapin -Name VeeamPSSnapIn -ErrorAction SilentlyContinue)) {
        try {
            Add-PSSnapin -Name VeeamPSSnapIn -ErrorAction Stop
        } catch {
            if (-not (Get-Module -Name Veeam.Backup.PowerShell -ErrorAction SilentlyContinue)) {
                Import-Module -Name Veeam.Backup.PowerShell -ErrorAction Stop
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Initialise module-level state (infra concerns shared by all collectors)
# ---------------------------------------------------------------------------
Initialize-VhcModule -ReportPath $ReportPath -VBRServer $VBRServer `
                     -LogLevel $config.LogLevel `
                     -ReportInterval $ReportInterval

# Collector run summary list — each Invoke-VhcCollector call appends a result row.
$collectorResults = [System.Collections.Generic.List[PSCustomObject]]::new()

# ---------------------------------------------------------------------------
# Connect to VBR server
# ---------------------------------------------------------------------------
# Pre-connect cleanup in case a stale session already exists.
try { Disconnect-VBRServer -ErrorAction SilentlyContinue } catch {}

$useCreds = ($User -and $PasswordBase64 -and
             -not [string]::IsNullOrWhiteSpace($User) -and
             -not [string]::IsNullOrWhiteSpace($PasswordBase64))

# Wrap Connect → Collectors → Disconnect in try/finally so Disconnect always runs,
# even if a prerequisite collector aborts the run early.
try {
    if ($useCreds) {
        $passwordBytes  = [System.Convert]::FromBase64String($PasswordBase64)
        $plainPassword  = [System.Text.Encoding]::UTF8.GetString($passwordBytes)
        $securePassword = ConvertTo-SecureString -String $plainPassword -AsPlainText -Force
        $credential     = New-Object System.Management.Automation.PSCredential($User, $securePassword)
        Connect-VBRServer -Server $VBRServer -Credential $credential -ErrorAction Stop
    } else {
        Connect-VBRServer -Server $VBRServer -ErrorAction Stop
    }

# ---------------------------------------------------------------------------
# Version detection — replace parameter-supplied version with detected version
# ---------------------------------------------------------------------------
$VBRVersion = Get-VhcMajorVersion
Write-LogFile "VBR Version: $VBRVersion"

# PS edition guard: VBR < 13 is not supported under PowerShell Core.
if ($VBRVersion -gt 0 -and $VBRVersion -lt 13 -and $PSVersionTable.PSEdition -eq 'Core') {
    throw "VBR version $VBRVersion requires Windows PowerShell 5.1. " +
          "Rerun this script under powershell.exe (not pwsh)."
}

# ---------------------------------------------------------------------------
# Optional host rescan (must run before concurrency collection)
# ---------------------------------------------------------------------------
if ($RescanHosts) {
    Write-Host "[Orchestrator] Rescanning all hosts — this may take several minutes..."
    Rescan-VBREntity -AllHosts -Wait
}

# ---------------------------------------------------------------------------
# Task 4: User roles and server collection
# NOTE: Get-VhcServer is called DIRECTLY (not via wrapper) — its return value
#       ($VServers) is required by downstream concurrency collectors.
# ---------------------------------------------------------------------------
$collectorResults.Add((Invoke-VhcCollector -Name 'UserRoles' -Action { Get-VhcUserRoles }))

$VServers = Get-VhcServer
if ($null -eq $VServers) {
    throw "[Orchestrator] Get-VhcServer returned null — aborting. Check VBR connectivity and logs."
}
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Task 5: Concurrency data and analysis
# NOTE: Get-VhcConcurrencyData is called DIRECTLY (not via wrapper) — its return
#       value ($hostRoles) is required by Invoke-VhcConcurrencyAnalysis.
$hostRoles = Get-VhcConcurrencyData -VServers $VServers -Config $config -VBRServer $VBRServer -VBRVersion $VBRVersion
$collectorResults.Add((Invoke-VhcCollector -Name 'ConcurrencyAnalysis' -Action {
    Invoke-VhcConcurrencyAnalysis -HostRoles $hostRoles -Config $config -VBRVersion $VBRVersion -BackupServerName $VBRServer
}))
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Task 6: EntraId, CapacityTier, ArchiveTier, TrafficRules, Registry, Repository
# NOTE: Get-VhcRepository is called DIRECTLY (not via wrapper) — its return
#       value ($RepositoryDetails) is required by Get-VhcJob in Task 7.
$collectorResults.Add((Invoke-VhcCollector -Name 'EntraId'          -Action { Get-VhcEntraId }))
$collectorResults.Add((Invoke-VhcCollector -Name 'CapacityTier'     -Action { Get-VhcCapacityTier }))
$collectorResults.Add((Invoke-VhcCollector -Name 'ArchiveTier'      -Action { Get-VhcArchiveTier }))
$collectorResults.Add((Invoke-VhcCollector -Name 'TrafficRules'     -Action { Get-VhcTrafficRules }))
$collectorResults.Add((Invoke-VhcCollector -Name 'RegistrySettings' -Action {
    Get-VhcRegistrySettings -RemoteExecution $RemoteExecution
}))

$RepositoryDetails = Get-VhcRepository -VBRVersion $VBRVersion
# $RepositoryDetails may be $null if the collector fails — Get-VhcJob must tolerate a null map
# (repo names will simply be blank in _Jobs.csv).
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Task 7: Job collectors (require $RepositoryDetails from Task 6)
$collectorResults.Add((Invoke-VhcCollector -Name 'Jobs' -Action {
    Get-VhcJob -RepositoryDetails $RepositoryDetails -VBRVersion $VBRVersion -ReportInterval $ReportInterval
}))
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Task 9: WAN accelerators and license (spec positions 17 & 18 — after Jobs, before Malware)
$collectorResults.Add((Invoke-VhcCollector -Name 'WanAccelerator' -Action { Get-VhcWanAccelerator }))
$collectorResults.Add((Invoke-VhcCollector -Name 'License'        -Action { Get-VhcLicense }))
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Task 8: Malware detection, security compliance, protected workloads
$collectorResults.Add((Invoke-VhcCollector -Name 'MalwareDetection'   -Action { Get-VhcMalwareDetection -VBRVersion $VBRVersion }))
$collectorResults.Add((Invoke-VhcCollector -Name 'SecurityCompliance' -Action {
    Get-VhcSecurityCompliance -VBRVersion $VBRVersion -Config $config
}))
$collectorResults.Add((Invoke-VhcCollector -Name 'ProtectedWorkloads' -Action { Get-VhcProtectedWorkloads }))
# ---------------------------------------------------------------------------

# VbrInfo runs last — reads many registry paths that must not block earlier collectors
$collectorResults.Add((Invoke-VhcCollector -Name 'VbrInfo' -Action { Get-VhcVbrInfo -VBRVersion $VBRVersion }))
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Collector run summary
# ---------------------------------------------------------------------------
if ($collectorResults.Count -gt 0) {
    Write-Host "`n[Orchestrator] ===== Collector Summary ====="
    foreach ($r in $collectorResults) {
        $status   = if ($r.Success) { "OK  " } else { "FAIL" }
        $duration = if ($r.Duration) { "$([math]::Round($r.Duration.TotalSeconds, 1))s" } else { "-" }
        $err      = if ($r.Error)    { " | $($r.Error)" } else { "" }
        Write-Host "  [$status] $($r.Name.PadRight(30)) $duration$err"
    }
    Write-Host "[Orchestrator] ============================="
    $failed = $collectorResults | Where-Object { -not $_.Success }
    if ($failed) {
        Write-LogFile "Run completed with $($failed.Count) failed collector(s): $(($failed.Name) -join ', ')" -LogLevel "WARNING"
    }
}

Write-Host "[Orchestrator] Collection complete. Output: $ReportPath"
} finally {
    Disconnect-VBRServer -Confirm:$false -ErrorAction SilentlyContinue
}
