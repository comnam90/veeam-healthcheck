# ADR 0007: Collection Manifest and Module-Scoped Error Registry for Failure Surfacing

* **Status:** Accepted
* **Date:** 2026-03-05
* **Decider:** Nam
* **Consulted:** Claude Code (architecture review)

## Context and Problem Statement

Collector functions in the vHC-VbrConfig module use internal try/catch blocks to prevent
exceptions from escaping when the function is called standalone. This is the correct defensive
posture for exported (public) functions. However, it creates a blind spot when those same
functions are called via `Invoke-VhcCollector` in `Get-VBRConfig.ps1`: because no exception
reaches the wrapper, `$result.Success` is always `true` regardless of whether the function
actually collected any data. The `$collectorResults` list is therefore always all-green, and
C# has no way to distinguish "collector failed, data absent" from "feature not configured".
Users receive a report with silently empty sections.

The problem has two dimensions:
1. **PowerShell side:** Failures in public functions never reach `Invoke-VhcCollector`.
2. **C# side:** Even if failures were tracked, the information is not persisted to disk,
   so the report compilation pipeline cannot act on it.

## Decision Drivers

- **Data integrity:** An empty report section must mean "nothing to report", not "collection failed".
- **Standalone safety:** Exported public functions must remain safe to call without a wrapper.
- **Consistency with ADR 0006:** `$script:` module state is reserved for infrastructure.
  A new shared variable must be justified as infrastructure, not business data.
- **Minimal surface change:** Do not alter the established `Invoke-VhcCollector` contract
  or force callers to change their invocation pattern.

## Considered Options

### Option A — Remove try/catch from public functions; let exceptions propagate to Invoke-VhcCollector
Public functions become unsafe for standalone use: an unhandled exception propagates to
whatever called the function. Users who call `Get-VhcLicense` directly from a session
would receive a terminating error rather than a graceful null.

**Rejected:** Breaks standalone safety of exported functions.

### Option B — Keep catch blocks; add `throw` after logging (re-throw pattern)
Functions catch for logging, then re-throw. Standalone callers get a terminating error
(same risk as Option A). `Invoke-VhcCollector` sees the exception and sets `Success=false`.

**Rejected:** Same standalone safety concern as Option A. Callers must always wrap in
try/catch, which is a burden not present today.

### Option C — Module-scoped error registry (chosen)
Public functions keep their existing catch (standalone safe). The catch block additionally
writes a failure record to `$script:ModuleErrors`, a List initialised by `Initialize-VhcModule`.
`Get-VBRConfig.ps1` reads this registry after all collectors run and merges it with
`$collectorResults` (which captures `Invoke-VhcCollector`-level failures) to produce an
accurate `_CollectionManifest.csv`. Private functions, which are module-internal and never
called standalone, have their try/catch removed so exceptions propagate naturally to their
calling public function's catch.

**ADR 0006 compatibility:** ADR 0006 reserves `$script:` state for "infrastructure
configuration set by `Initialize-VhcModule` and consumed only by infrastructure helpers".
`$script:ModuleErrors` is initialised by `Initialize-VhcModule` and consumed only by the
orchestrator (`Get-VBRConfig.ps1`) — it is not read or written by any collector to exchange
business data with another collector. It is analogous to `$script:LogPath`: a piece of
infrastructure plumbing, not a data channel between collectors.

## Decision

Option C. The module-scoped error registry (`$script:ModuleErrors`) is infrastructure
initialised by `Initialize-VhcModule`. Public collector functions register failures there
without altering their standalone behaviour. Private collector functions are unprotected.
`Get-VBRConfig.ps1` merges both failure sources into `_CollectionManifest.csv`. C# reads
this manifest to surface per-collector failures in the HTML report and CLI output.

## Consequences

* **Good:** Public functions remain safe for standalone invocation.
* **Good:** All collector failures are captured and visible to the report compiler.
* **Good:** `Invoke-VhcCollector`'s contract is unchanged; callers need no modification.
* **Good:** Private functions become simpler (no redundant catch wrapping).
* **Bad:** A new `$script:` variable is introduced, which must be documented as
  infrastructure-only to avoid future misuse (this ADR serves that purpose).
* **Bad:** Collector names in `$script:ModuleErrors` entries must match the names used in
  `Invoke-VhcCollector` calls in `Get-VBRConfig.ps1`; this coupling is a convention, not
  enforced by the type system.
* **Neutral:** `_CollectionManifest.csv` is a new output file. The `CCsvValidator` expected-
  file registry does not need to track it (it is metadata, not report data).

## Validation

Verified by:
- Injected failure test: `throw "test error"` inside `Get-VhcLicense.ps1` (inside the try,
  before any work) → manifest shows `License,False,...,"test error"`, HTML shows red
  collector-error row, CLI prints warning.
- Standalone call test: call `Get-VhcLicense` directly without `Invoke-VhcCollector` →
  function still catches, logs, and returns normally; no regression.
- Private propagation test: `throw "sub error"` in `Get-VhcAgentJob.ps1` → exception
  reaches `Get-VhcJob`'s top-level catch → registry entry for `Jobs`.
- Happy path: all collectors succeed → manifest all `Success=True`, no warnings in HTML or CLI.
