# vHC-VbrConfig Module

A PowerShell module that replaces the original `Get-VBRConfig.ps1` monolith
with a set of focused, independently testable collector functions. Each function
is responsible for one area of VBR configuration, writes its own CSV output,
and fails in isolation — a problem in one collector does not abort the others.

---

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| PowerShell | 5.1 (Windows) or 7+ |
| Veeam PSSnapin / module | `VeeamPSSnapIn` (PS 5.1) or `Veeam.Backup.PowerShell` (PS 7+) |
| VBR connection | Must be connected via `Connect-VBRServer` before calling any collector |
| Module initialisation | `Initialize-VhcModule` must be called once before any other function |

---

## Module structure

```
vHC-VbrConfig\
    vHC-VbrConfig.psd1    # Module manifest
    vHC-VbrConfig.psm1    # Loader: dot-sources Public\ + Private\, exports Public\ BaseName
    Public\               # Exported functions — callable from outside the module
    Private\              # Internal helpers — available within the module only
```

The `.psm1` dot-sources every `.ps1` file in `Public\` and `Private\` at load
time. Only functions whose filename (without extension) is in `Public\` are
exported via `Export-ModuleMember`. Adding a new function to `Public\` is
sufficient to export it — no manifest edit required.

---

## Calling pattern

`VBR-Orchestrator.ps1` uses two calling patterns:

**Direct call** — used when the function's return value is consumed by a
downstream collector. The Orchestrator captures the output and passes it
explicitly.

```powershell
$VServers        = Get-VhcServer                        # feeds Get-VhcConcurrencyData
$hostRoles       = Get-VhcConcurrencyData -VServers $VServers ...   # feeds Invoke-VhcConcurrencyAnalysis
$RepositoryDetails = Get-VhcRepository -VBRVersion $VBRVersion      # feeds Get-VhcJob
```

**`Invoke-VhcCollector` wrapper** — used for fire-and-forget collectors whose
output is only CSVs. Provides timing, error isolation, and a structured result
row for the run summary.

```powershell
$collectorResults.Add((Invoke-VhcCollector -Name 'License' -Action { Get-VhcLicense }))
```

Do **not** wrap direct-call collectors in `Invoke-VhcCollector` — the wrapper
discards the return value.

---

## Public functions

These functions are exported by the module and available to the Orchestrator.

### Infrastructure / control

| Function | Signature | Purpose |
|----------|-----------|---------|
| `Initialize-VhcModule` | `-ReportPath` `-VBRServer` `-LogLevel` `-ReportInterval` `-LogPath` | Sets module-scoped state (`$script:ReportPath`, `$script:VBRServer`, etc.). Must be called once before any collector. |
| `Write-LogFile` | `-Message` `-LogLevel` (TRACE/PROFILE/DEBUG/INFO/WARNING/ERROR/FATAL) `-LogName` | Writes a timestamped log entry to the console and log file. In `Public\` because the Orchestrator calls it directly outside module scope. |
| `Invoke-VhcCollector` | `-Name [string]` `-Action [scriptblock]` | Executes a collector scriptblock with timing and error isolation. Returns `[PSCustomObject]@{Name; Success; Duration; Error; Output}`. |

### Version detection

| Function | Signature | Returns | Purpose |
|----------|-----------|---------|---------|
| `Get-VhcMajorVersion` | _(none)_ | `[int]` | Detects the installed VBR major version. Reads `Get-VBRBackupServerInfo.Build.Major` (v13+) or the `Veeam.Backup.Core.dll` ProductVersion via registry (v10–12). Returns `0` on failure. |

### Infrastructure collectors (return value consumed downstream)

| Function | Signature | Returns | CSV outputs |
|----------|-----------|---------|-------------|
| `Get-VhcServer` | _(none)_ | `[object[]]` raw VBR server objects | `_Servers.csv` |
| `Get-VhcConcurrencyData` | `-VServers` `-Config` `-VBRServer` `-VBRVersion` | `[hashtable]` `$hostRoles` keyed by server name | `_NasProxy.csv` `_Proxies.csv` `_HvProxy.csv` `_CdpProxy.csv` |
| `Get-VhcRepository` | `-VBRVersion` | `[ArrayList]` of `@{ID; Name}` rows, or `$null` | `_Repositories.csv` `_SOBRs.csv` `_SOBRExtents.csv` |

### Fire-and-forget collectors

These write CSVs and return nothing meaningful. Invoke via `Invoke-VhcCollector`.

| Function | Signature | CSV outputs | Notes |
|----------|-----------|-------------|-------|
| `Invoke-VhcConcurrencyAnalysis` | `-HostRoles` `-Config` `-VBRVersion` `-BackupServerName` | `_AllServersRequirementsComparison.csv` | Calculates per-server CPU/RAM requirements from `$hostRoles`. |
| `Get-VhcUserRoles` | _(none)_ | `_UserRoles.csv` | |
| `Get-VhcEntraId` | _(none)_ | `_entraTenants.csv` `_entraLogJob.csv` `_entraTenantJob.csv` | Entire function wrapped in try/catch — no-op when no Entra tenant is configured. |
| `Get-VhcCapacityTier` | _(none)_ | `_capTier.csv` | SOBR capacity extents. DataCloudVault repos infer immutability from `ImmutabilityPeriod > 0`. |
| `Get-VhcArchiveTier` | _(none)_ | `_archTier.csv` | SOBR archive extents. |
| `Get-VhcTrafficRules` | _(none)_ | `_trafficRules.csv` | |
| `Get-VhcRegistrySettings` | `-RemoteExecution [bool]` | `_regkeys.csv` | Skipped when `-RemoteExecution $true` (registry inaccessible on remote agents). |
| `Get-VhcJob` | `-RepositoryDetails` `-VBRVersion` `-ReportInterval` | `_Jobs.csv` `_configBackup.csv` + 9 sub-collector CSVs | Orchestrates nine private sub-collectors (see Private section). `$RepositoryDetails` may be `$null` — repo names will be blank in that case. |
| `Get-VhcWanAccelerator` | _(none)_ | `_WanAcc.csv` | |
| `Get-VhcLicense` | _(none)_ | `_LicInfo.csv` | Socket, instance, and capacity licence summaries. |
| `Get-VhcMalwareDetection` | `-VBRVersion [int]` | `_malware_settings.csv` `_malware_infectedobject.csv` `_malware_events.csv` `_malware_exclusions.csv` | No-op for VBR versions below 12. |
| `Get-VhcSecurityCompliance` | `-VBRVersion [int]` `-Config` | `_SecurityCompliance.csv` | Triggers `Start-VBRSecurityComplianceAnalyzer` and polls up to 45 s. Uses internal API (v12) or `Get-VBRSecurityComplianceAnalyzerResults` cmdlet (v13+). Rule keys resolved from `$Config.SecurityComplianceRuleNames`. Unknown rule types are included with their raw type string rather than dropped. No-op for VBR versions 11 and below. |
| `Get-VhcProtectedWorkloads` | _(none)_ | `_PhysProtected.csv` `_PhysNotProtected.csv` `_HvProtected.csv` `_HvUnprotected.csv` `_ViProtected.csv` `_ViUnprotected.csv` | Per-platform inner try/catch — a failure on VMware does not skip Hyper-V or physical. |
| `Get-VhcVbrInfo` | `-VBRVersion [int]` | `_vbrinfo.csv` | VBR version, database configuration, MFA global setting. Runs last in the Orchestrator — reads many registry paths that must not block earlier collectors. |

---

## Private functions

These are available within the module but not exported. Do not call them directly from the Orchestrator.

### Concurrency sub-collectors (called by `Get-VhcConcurrencyData`)

| Function | Purpose |
|----------|---------|
| `Get-VhcViHvProxy` | Collects VMware and Hyper-V proxy data; exports `_Proxies.csv`, `_HvProxy.csv`; populates `Proxy` role in `$hostRoles`. |
| `Get-VhcGpProxy` | Collects General Purpose (NAS/File) proxy data; exports `_NasProxy.csv`; populates `GPProxy` role in `$hostRoles`. |
| `Get-VhcCdpProxy` | Collects CDP proxy data; exports `_CdpProxy.csv`; populates `CDPProxy` role in `$hostRoles`. |
| `Get-VhcRepoGateway` | Collects repository and gateway server data; exports `_RepositoryServers.csv`, `_Gateways.csv`; populates `Repository` and `Gateway` roles in `$hostRoles`. Cloud-backed repos (`Type=Cloud`, VeeamVault, AmazonS3) are filtered from the no-gateway path because they have no local storage host; however, any gateway server fronting such a repo is always included. |

### Job sub-collectors (called by `Get-VhcJob`)

| Function | CSV outputs | Notes |
|----------|-------------|-------|
| `Get-VhcCatalystJob` | `_catCopyjob.csv` `_catalystJob.csv` | `Get-VBRCatalystJob` is optional — error is caught and logged if the cmdlet is unavailable. |
| `Get-VhcAgentJob` | `_AgentBackupJob.csv` `_EndpointJob.csv` | Computer backup jobs and legacy endpoint jobs. |
| `Get-VhcSureBackup` | `_SureBackupJob.csv` `_SureBackupAppGroups.csv` `_SureBackupVirtualLabs.csv` | |
| `Get-VhcTapeInfrastructure` | `_TapeJobs.csv` `_TapeServers.csv` `_TapeLibraries.csv` `_TapeMediaPools.csv` `_TapeVaults.csv` | |
| `Get-VhcNasJob` | `_nasBackup.csv` `_nasBCJ.csv` | Session-based size metrics require `-ReportInterval` days lookback. |
| `Get-VhcPluginAndCdpJob` | `_pluginjobs.csv` `_cdpjobs.csv` `_vcdjobs.csv` | |
| `Get-VhcReplication` | `_ReplicaJobs.csv` `_Replicas.csv` `_FailoverPlans.csv` | Receives the already-fetched `$Jobs` array to avoid a second `Get-VBRJob` call. |
| `Get-VhcCloudConnect` | `_CloudGateways.csv` `_CloudTenants.csv` | Errors when VCC service provider licence is not installed — caught and logged. |
| `Get-VhcCredentialsAndNotifications` | `_EmailNotification.csv` `_Credentials.csv` | `Get-VBRMailNotification` is optional — error caught if cmdlet unavailable. Veeam cmdlets never expose credential passwords. |

### Utility helpers

| Function | Purpose |
|----------|---------|
| `Export-VhcCsv` | Pipeline-aware CSV writer. Constructs the full output path as `<ReportPath>\<VBRServer><FileName>` from module state set by `Initialize-VhcModule`. |
| `Get-SqlSName` | Reads the VBR database server hostname from the Windows registry. Resolves `"localhost"` to the actual FQDN using the `-VBRServer` parameter. |
| `ConvertToGB` | Converts bytes to whole gigabytes (floor division). |
| `EnsureNonNegative` | Clamps a value to 0 if negative. Used in concurrency requirement calculations. |
| `SafeValue` | Returns `0` if the input is `$null`; otherwise returns the value unchanged. Guards against `$null` arithmetic. |

---

## Error handling conventions

- **`$ErrorActionPreference = 'Stop'`** is set in `VBR-Orchestrator.ps1` and inherited by all module functions. All non-terminating errors become terminating.
- Every public collector wraps its body in `try/catch`. Errors are logged via `Write-LogFile` and the function returns normally (empty / `$null` output).
- `Invoke-VhcCollector` provides an outer catch so that even an unhandled exception in a collector does not propagate to the Orchestrator.
- Functions with multiple independent sub-sections (e.g. `Get-VhcProtectedWorkloads` across VMware / Hyper-V / Physical) use **per-section** inner try/catch blocks so a failure on one platform does not suppress data from the others.
- `Get-VhcJob` similarly wraps each of its nine sub-collector calls individually.

---

## Implementation notes

**`[Parameter()]` triggers CmdletBinding**
Any function with at least one `[Parameter()]` attribute implicitly gets
`[CmdletBinding()]`. This adds all common parameters (`-Verbose`, `-Confirm`,
`-WhatIf`, etc.) to `$PSBoundParameters`. Splatting `@PSBoundParameters` to a
callee that lacks `[CmdletBinding()]` will fail with `NamedParameterNotFound`.

**`@()` wrapping for `Where-Object` results**
Under `Set-StrictMode -Version Latest`, accessing `.Count` on a single
`PSCustomObject` (not a collection) throws `PropertyNotFoundStrict`. When
`Where-Object` returns exactly one match, the result is a bare object rather
than an array. Always wrap such results in `@()` before reading `.Count`:

```powershell
$failed = @($collectorResults | Where-Object { -not $_.Success })
if ($failed.Count -gt 0) { ... }
```

**Cloud / VeeamVault / AmazonS3 repository filtering**
`Get-VBRBackupRepository` returns all repository types, including cloud-backed
ones (`Type=Cloud`, `VeeamVault`, `AmazonS3`). These have no physical host and
must be excluded from concurrency analysis. The filter in `Get-VhcRepoGateway`
is applied only in the **no-gateway branch** of the loop. A repo that has
gateway servers — even if cloud-backed — contributes those gateway servers to
the concurrency map as normal local infrastructure.

**`Disconnect-VBRServer` has no `-Confirm` parameter**
Unlike some Veeam cmdlets, `Disconnect-VBRServer` does not support
`-ShouldProcess`. Do not pass `-Confirm:$false` to it.

**Mandatory empty-array parameters**
`[Parameter(Mandatory)] [object[]]` rejects `@()` with
`ParameterArgumentValidationErrorEmptyArrayNotAllowed`. Proxy and repository
input parameters in the concurrency sub-collectors use
`[Parameter(Mandatory = $false)] [object[]] $Param = @()` to accept empty
arrays from environments with no proxies of a given type.

**UTF-8 BOM**
PS 5.1 reads `.ps1` files without a UTF-8 BOM as Windows-1252. Non-ASCII
characters in string literals cause a `ParseException`. All files in this
module must be saved as **UTF-8 with BOM**.

**`[pscustomobject][ordered]@{}`**
All output objects use `[pscustomobject][ordered]@{}` to ensure deterministic
CSV column order across PowerShell versions.
