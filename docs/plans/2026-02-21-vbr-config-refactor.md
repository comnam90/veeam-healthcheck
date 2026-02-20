# Refactor VBR Config Monolith Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Decompose the 2,100+ line `Get-VBRConfig.ps1` into a modular PowerShell module (`.psm1`) and a clean Orchestrator script.

**Architecture:** Use an Orchestrator-Collector pattern with a Common Library module. State is passed via parameter splatting. Data flows through the PowerShell pipeline to minimize memory usage.

**Tech Stack:** PowerShell 5.1/7+, JSON for configuration, Pester (for unit testing if available).

---

### Task 1: Module and Orchestrator Scaffolding

**Files:**
- Create: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig.psm1`
- Create: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/VBR-Orchestrator.ps1`
- Create: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/VbrConfig.json`

**Step 1: Create the basic module and config**
Create `vHC-VbrConfig.psm1` with a simple exported function and `VbrConfig.json` with initial thresholds.

**Step 2: Create the Orchestrator**
Implement parameter parsing in `VBR-Orchestrator.ps1` and the logic to import the new module.

**Step 3: Verification**
Run: `pwsh -File vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/VBR-Orchestrator.ps1 -VBRServer localhost -VBRVersion 12`
Expected: Script loads module and exits without error.

**Step 4: Commit**
```bash
git add vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig.psm1 vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/VBR-Orchestrator.ps1 vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/VbrConfig.json
git commit -m "feat: initial module scaffold for VBR config refactor"
```

---

### Task 2: Implement Common Utilities (Logging & Export)

**Files:**
- Modify: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig.psm1`

**Step 1: Extract `Write-LogFile` and `Export-VhcCsv`**
Move the logic from `Get-VBRConfig.ps1` into the module. Refactor `Export-VhcCsv` to be a pipeline consumer.

**Step 2: Implement `Invoke-VhcCollector` wrapper**
Create a function that handles `try/catch`, logging start/stop, and measuring execution time.

**Step 3: Verification**
Create a temporary test script that imports the module and calls `Invoke-VhcCollector` with a dummy scriptblock that pipes objects to `Export-VhcCsv`.
Expected: Log file is created and CSV contains dummy data.

**Step 4: Commit**
```bash
git commit -am "feat: add common logging, export, and collector wrapper to module"
```

---

### Task 3: Extract Server Collector

**Files:**
- Modify: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig.psm1`
- Modify: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/VBR-Orchestrator.ps1`

**Step 1: Create `Get-VhcServer` function**
Extract logic from `Get-VBRConfig.ps1` (approx. lines 300-340) and place into a new function in the module.

**Step 2: Integrate into Orchestrator**
Update `VBR-Orchestrator.ps1` to call `Invoke-VhcCollector -Name "Servers" -Action { Get-VhcServer | Export-VhcCsv -FileName "_Servers.csv" }`.

**Step 3: Verification**
Run the Orchestrator against a VBR server.
Expected: `_Servers.csv` is generated with correct headers and data.

**Step 4: Commit**
```bash
git commit -am "feat: extract Server collection to modular function"
```

---

### Task 4: Extract Version Detection Logic

**Files:**
- Modify: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig.psm1`

**Step 1: Create `Get-VhcVbrVersion`**
Consolidate version detection logic (scattered in the original script) into a single module function that returns a structured version object.

**Step 2: Update Orchestrator**
Use this function at start to set environment variables or splatting parameters.

**Step 3: Commit**
```bash
git commit -am "refactor: consolidate version detection logic"
```

---

### Task 5: Extract Job Collection (Complex Task)

**Files:**
- Modify: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig.psm1`

**Step 1: Create `Get-VhcJob`**
Extract the massive job collection loop (lines ~1300-1800). Refactor to use sub-functions for different job types (NAS, Tape, Plugin, etc.) to keep the main function readable.

**Step 2: Implement Pipeline Output**
Ensure objects are emitted directly to the pipeline as they are processed.

**Step 3: Commit**
```bash
git commit -am "feat: extract modular Job collection with pipeline support"
```

---

### Task 6: Extract Concurrency Analysis Logic

**Files:**
- Modify: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig.psm1`

**Step 1: Create `Invoke-VhcConcurrencyAnalysis`**
Extract the analysis logic (lines ~430-800). This function should take the `ProxyData`, `RepoData`, etc., as inputs and return a `RequirementsComparison` object.

**Step 2: Commit**
```bash
git commit -am "feat: isolate concurrency analysis from data collection"
```

---

### Task 7: Cleanup & Final Integration

**Files:**
- Modify: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/VBR-Orchestrator.ps1`

**Step 1: Finalize Orchestrator**
Ensure all collectors are called in the correct sequence. Add cleanup logic (disconnecting from VBR).

**Step 2: Performance & Memory Check**
Run the new orchestrator and monitor process memory. Compare against original script on a large dataset if possible.

**Step 3: Commit**
```bash
git commit -am "chore: finalize orchestrator and perform cleanup"
```
