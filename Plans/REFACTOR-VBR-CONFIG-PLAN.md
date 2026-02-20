# Refactor Plan: `Get-VBRConfig.ps1` Modernization

## Objective
Refactor the monolithic `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/Get-VBRConfig.ps1` (2,100+ lines) into a modular, testable, and maintainable collection engine adhering to DRY, SOLID, and KISS principles.

## Proposed Architecture: Orchestrator-Collector Pattern

The current monolithic script will be decomposed into four primary components:

### 1. Orchestrator (`VBR-Orchestrator.ps1`)
*   **Responsibility**: Script lifecycle management.
*   **Functions**: Command-line parameter parsing, VBR server connection/disconnection, error boundary management, and invoking individual collectors.
*   **SOLID (SRP)**: Handles *how* the collection runs, not *what* is collected.

### 2. Common Library (`vHC-Common.ps1m` or similar)
*   **Responsibility**: Shared utility functions.
*   **Functions**: 
    *   `Invoke-VhcCollector`: A wrapper function for collectors that provides unified logging (`Write-LogFile`) and error handling.
    *   `Export-VhcCsv`: Standardized CSV export logic with path/server name handling.
    *   `Get-VhcVbrVersion`: Centralized version detection logic.
*   **DRY (Don't Repeat Yourself)**: Eliminates 100+ instances of repetitive try/catch and logging boilerplate.

### 3. Modular Collectors (`Collectors/*.ps1`)
*   **Responsibility**: Data extraction for specific Veeam entities.
*   **Examples**:
    *   `Get-VhcJobs.ps1`: Collects all job types (Backup, Copy, Tape, etc.).
    *   `Get-VhcRepositories.ps1`: Collects Repo and SOBR data.
    *   `Get-VhcProxies.ps1`: Collects VMware, Hyper-V, and NAS proxy data.
*   **SOLID (SRP/OCP)**: Each file has one reason to change. New Veeam features can be supported by adding a new collector file without touching existing ones.

### 4. Configuration Engine (`VbrConfig.json`)
*   **Responsibility**: Externalizing data and thresholds.
*   **Content**: Resource requirements (RAM/CPU per task), default paths, and log levels.
*   **KISS**: Simplifies code by removing hardcoded magic numbers and metadata.

---

## Implementation Strategy (Phased Approach)

### Phase 1: Foundation & Scaffold
1.  Define the `VBR-Orchestrator.ps1` structure.
2.  Implement the `Invoke-VhcCollector` wrapper in the Common library.
3.  Implement the first "Clean" collector (e.g., `Get-VhcServers.ps1`) to validate the pattern.

### Phase 2: Core Decomposition
1.  Extract **Repository/SOBR** collection into `Get-VhcRepositories.ps1`.
2.  Extract **Job** collection (the largest block) into `Get-VhcJobs.ps1`.
3.  Extract **Proxy** collection into `Get-VhcProxies.ps1`.

### Phase 3: Analysis & Logic Separation
1.  The "Concurrency Inspector" (lines ~430-800) is pure business logic. Move this into `Invoke-VhcConcurrencyAnalysis.ps1`.
2.  Ensure it operates on the *output* of the collectors rather than being tightly coupled to the Veeam cmdlets.

### Phase 4: Integration & Regression Testing
1.  Develop a side-by-side validation test.
2.  Run the original `Get-VBRConfig.ps1` and the new `VBR-Orchestrator.ps1` against the same VBR server.
3.  Compare the resulting CSV outputs to ensure 100% data parity.

## Benefits
*   **Stability**: Errors in one collector (e.g., Entra ID failure) won't crash the entire script.
*   **Maintainability**: Bug fixes are localized to small (100-200 line) files.
*   **Scalability**: Adding support for new Veeam features (e.g., Object Storage, VB365 integration) becomes trivial.
*   **Readability**: The orchestrator provides a high-level "table of contents" for the entire collection process.
