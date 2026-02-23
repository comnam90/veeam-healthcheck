# VBR Collection Layer

This directory contains the PowerShell scripts that collect Veeam Backup &
Replication (VBR) configuration data and write it to CSV files consumed by the
C# report compiler.

---

## Invocation flow

```
C# invoker (PSInvoker.cs / PowerShell7Executor.cs)
    └── Get-VBRConfig.ps1          (backward-compat shim)
            └── VBR-Orchestrator.ps1   (canonical entry point)
                    ├── VbrConfig.json             (static configuration)
                    └── vHC-VbrConfig\             (collector module)
                            ├── Initialize-VhcModule
                            ├── Invoke-VhcCollector  (wraps each collector)
                            └── Get-Vhc*, Invoke-Vhc*  (individual collectors)
```

The C# invoker always calls `Get-VBRConfig.ps1`. The shim exists so the C#
layer does not need to change until CSV parity between the old monolith and the
new module is confirmed (Task 11C).

---

## Files

| File | Purpose |
|------|---------|
| `VBR-Orchestrator.ps1` | Canonical entry point. Reads `VbrConfig.json`, imports the `vHC-VbrConfig` module, connects to VBR, runs all collectors in dependency order, disconnects, and prints a run summary. |
| `Get-VBRConfig.ps1` | Backward-compatibility shim. Accepts the same parameters as the old monolith and forwards them to `VBR-Orchestrator.ps1`. **Do not add logic here.** Retained until the C# invoker is updated (Task 11C). |
| `VbrConfig.json` | Static configuration for the collection run. Contains `LogLevel`, `DefaultOutputPath`, resource sizing `Thresholds` used by the concurrency analysis, and the `SecurityComplianceRuleNames` mapping (rule key → human-readable label). Edit this file to adjust thresholds or add new compliance rule mappings without touching script logic. |
| `Get-VeeamSessionReport.ps1` | Standalone script that produces a per-task session detail report for VMware backup jobs. Not part of the main health-check pipeline; intended for ad-hoc use. |
| `Get-VeeamSessionReportVersion13.ps1` | VBR v13+ variant of the session report. Same purpose as above, updated for v13 API changes. |
| `Get-NasInfo.ps1` | Legacy standalone NAS information collector. Not part of the main health-check pipeline. |
| `vHC-VbrConfig\` | PowerShell module containing all individual collector functions. See [`vHC-VbrConfig/README.md`](vHC-VbrConfig/README.md) for full documentation. |

---

## Running manually

```powershell
# Minimal (integrated auth, default output path)
& ".\VBR-Orchestrator.ps1" -VBRServer myserver -VBRVersion 12

# With credentials and explicit output path
& ".\VBR-Orchestrator.ps1" -VBRServer myserver -VBRVersion 12 `
    -User admin -PasswordBase64 <base64-encoded-password> `
    -ReportPath "C:\temp\vHC\Original\VBR\myserver\20260101_120000"

# Via the shim (same parameters - forwarded transparently)
& ".\Get-VBRConfig.ps1" -VBRServer myserver -VBRVersion 12
```

CSV output is written to `<ReportPath>\<VBRServer>_<FileName>.csv`.

---

## Key design notes

**PowerShell version compatibility**
`VBR-Orchestrator.ps1` and all module files target PowerShell 5.1
(`#Requires -Version 5.1`) and are also compatible with PowerShell 7+. VBR
versions below 13 require PS 5.1 (the Orchestrator enforces this at runtime).
The Veeam PS snapin is used under PS 5.1; the `Veeam.Backup.PowerShell` module
is used under PS 7+.

**UTF-8 BOM requirement**
PS 5.1 reads `.ps1` files without a UTF-8 BOM as Windows-1252. Any non-ASCII
characters (em dashes, arrows, smart quotes, etc.) in string literals will
cause a parse error. All scripts in this directory and in `vHC-VbrConfig\` must
be saved as **UTF-8 with BOM**.

**`$ErrorActionPreference = 'Stop'` and `Set-StrictMode -Version Latest`**
Both are set in `VBR-Orchestrator.ps1` and inherited by module functions. This
means:
- All non-terminating errors become terminating (caught by collector try/catch blocks).
- Accessing `.Count` on a single-object `Where-Object` result (not an array) throws
  `PropertyNotFoundStrict`. Wrap such results in `@()` to force array semantics.
- Calling a method on `$null` throws immediately rather than silently continuing.

**`[Parameter()]` and CmdletBinding**
Any function with at least one `[Parameter()]` attribute implicitly gets
`[CmdletBinding()]`, which injects all PowerShell common parameters (`-Verbose`,
`-Confirm`, `-WhatIf`, etc.) into `$PSBoundParameters`. Splatting
`@PSBoundParameters` to a target that lacks `[CmdletBinding()]` will throw
`NamedParameterNotFound`. The shim explicitly filters common parameters before
forwarding to the Orchestrator for exactly this reason.
