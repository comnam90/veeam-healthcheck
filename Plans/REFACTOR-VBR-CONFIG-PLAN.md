# Refactor Plan: `Get-VBRConfig.ps1` Modernization

## Objective
Refactor the monolithic `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/Get-VBRConfig.ps1` (2,100+ lines) into a modular, testable, and maintainable collection engine adhering to DRY, SOLID, and KISS principles. 

## Proposed Architecture: Orchestrator-Collector Pattern

The current monolithic script will be decomposed into four primary components, utilizing a standard PowerShell Module structure to prevent variable scope bleeding and improve execution speed.

### 1. Orchestrator (`VBR-Orchestrator.ps1`)
* **Responsibility**: Script lifecycle management and dependency injection.
* **Functions**: Command-line parameter parsing, VBR server connection/disconnection, configuration file parsing (`VbrConfig.json`), and invoking individual collector functions.
* **SOLID (SRP)**: Handles *how* the collection runs and orchestrates the environment, not *what* is collected. 
* **State Management**: Parses external configuration and passes specific threshold arrays/settings to collectors via parameter splatting, eliminating the need for `$global:` variables.

### 2. Common Library Module (`vHC-Common.psm1`)
* **Responsibility**: Shared utility functions and standardized wrappers.
* **Functions**: 
    * `Invoke-VhcCollector`: A wrapper function for collectors that provides unified logging (`Write-LogFile`), error handling, and injects necessary configuration parameters.
    * `Export-VhcCsv`: Standardized CSV export logic acting as a pipeline consumer, directly writing incoming objects to disk to minimize memory footprint.
    * `Get-VhcVbrVersion`: Centralized version detection logic.
* **DRY (Don't Repeat Yourself)**: Eliminates 100+ instances of repetitive try/catch and logging boilerplate.

### 3. Modular Collectors (`Collectors/` -> Exported Module Functions)
* **Responsibility**: Data extraction for specific Veeam entities, utilizing advanced functions (`[CmdletBinding()]`).
* **Examples**:
    * `Get-VhcJob`: Collects all job types (Backup, Copy, Tape, etc.).
    * `Get-VhcRepository`: Collects Repo and SOBR data.
    * `Get-VhcProxy`: Collects VMware, Hyper-V, and NAS proxy data.
* **SOLID (SRP/OCP)**: Each function has one reason to change. New Veeam features can be supported by writing a new function without touching existing code.
* **Memory Optimization**: Collectors emit `[PSCustomObject]` payloads directly to the pipeline rather than aggregating thousands of sessions into memory-heavy arrays.

### 4. Configuration Engine (`VbrConfig.json`)
* **Responsibility**: Externalizing static data, thresholds, and version-specific logic.
* **Content**: Resource requirements (RAM/CPU per task across v12/v13), default output paths, and log levels.
* **KISS**: Simplifies code by removing hardcoded magic numbers, making threshold updates a configuration change rather than a code rewrite.

---

## Implementation Strategy (Phased Approach)

### Phase 1: Foundation & Scaffold
1.  Define the `VBR-Orchestrator.ps1` script and `vHC-Common.psm1` module structure.
2.  Implement the `Invoke-VhcCollector` wrapper and pipeline-ready `Export-VhcCsv`.
3.  Implement the first "Clean" collector (e.g., `Get-VhcServer`) to validate state injection and pipeline memory management.

### Phase 2: Core Decomposition
1.  Extract **Repository/SOBR** collection into `Get-VhcRepository`.
2.  Extract **Job** collection (the largest block) into `Get-VhcJob`.
3.  Extract **Proxy** collection into `Get-VhcProxy`.

### Phase 3: Analysis & Logic Separation
1.  Isolate the "Concurrency Inspector" business logic (lines ~430-800) into `Invoke-VhcConcurrencyAnalysis`.
2.  Ensure this analysis engine operates strictly on the *output* objects of the collectors rather than being tightly coupled to the Veeam cmdlets.

### Phase 4: Integration & Regression Testing
1.  Deploy the original `Get-VBRConfig.ps1` and the new `VBR-Orchestrator.ps1` side-by-side.
2.  To avoid active job states or session IDs skewing the data parity check, run both frameworks against a static, isolated home lab environment running a representative mix of VMware and Hyper-V workloads. 
3.  Compare the resulting CSV outputs to validate accurate data extraction and pipeline handling.

## Benefits
* **Stability**: Errors in one collector (e.g., Entra ID timeout) are caught by the wrapper and won't crash the entire run.
* **Maintainability**: Bug fixes are localized to small, focused module functions.
* **Scalability**: Integrating new Veeam features simply requires adding a new module function and appending it to the Orchestrator's execution list.
* **Performance**: Pipeline-driven execution drastically reduces RAM consumption during large tenant or restore-point iterations.
