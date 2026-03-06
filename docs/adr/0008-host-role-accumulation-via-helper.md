# ADR 0008: Host-Role Accumulation via Add-VhcHostRoleEntry Helper

* **Status:** Accepted
* **Date:** 2026-03-05
* **Decider:** Nam
* **Consulted:** GitHub Copilot

## Context and Problem Statement

`Get-VhcConcurrencyData` orchestrates four private sub-collectors
(Get-VhcGpProxy, Get-VhcViHvProxy, Get-VhcCdpProxy, Get-VhcRepoGateway)
that all mutate a shared `$hostRoles` hashtable. Each sub-collector
contained an identical "upsert + task-count increment" block:

```
if (-not $HostRoles.ContainsKey($key)) {
    $HostRoles[$key] = [ordered]@{ Roles = @($role); Names = @($name);
                                   TotalTasks = 0; Cores = $c; RAM = $r;
                                   TotalXTasks = 0 }
} else {
    $HostRoles[$key].Roles += $role
    $HostRoles[$key].Names += $name
}
$HostRoles[$key].TotalXTasks += $n
$HostRoles[$key].TotalTasks  += $n
```

This pattern appeared verbatim four times with only the role name,
task-count key name, and hardware values varying. Any change to the
canonical entry shape required touching four files.

## Decision Drivers

- DRY: four copies of the same 10-line block.
- Correctness: inconsistent handling of multi-role servers (some branches
  did not guard the role-specific task-count key for pre-existing entries
  that gain a new role).
- Testability: a pure hashtable-mutation helper has no VBR dependencies
  and can be unit-tested without a live environment.

## Considered Options

### Option A - Return-value composition (no shared hashtable)
Each sub-collector returns a partial hashtable; the orchestrator merges
them. Eliminates mutable shared state.

**Rejected:** Would require changing the public function signature of
`Get-VhcConcurrencyData` (ADR 0006 break) and adds merge complexity that
exceeds the problem being solved.

### Option B - Single `Add-VhcHostRoleEntry` private helper (chosen)
Extract the upsert pattern into a private function with a `$TaskCountKey`
parameter. The shared hashtable remains the accumulation mechanism;
the helper encapsulates the entry-shape and increment logic.

## Decision

Option B. `Add-VhcHostRoleEntry` is the canonical way to add or update
a server entry in the `$HostRoles` map. All four sub-collectors call this
helper instead of duplicating the upsert block.

### Canonical host-role entry shape

```
[ordered]@{
    Roles       = [string[]]  # role labels appended per call
    Names       = [string[]]  # display names appended per call
    TotalTasks  = [int]       # aggregate across all roles
    Cores       = [int]       # set on first creation only
    RAM         = [int]       # set on first creation only
    <TaskCountKey> = [int]    # role-specific counter, e.g. TotalVpProxyTasks
}
```

`Cores` and `RAM` are set only when the entry is first created. If a
host has multiple roles, Cores/RAM reflect the values from whichever
role was discovered first; subsequent roles do not overwrite them because
the hardware belongs to the host, not to the role.

### Task-count key names (by role)

| Role       | TaskCountKey        |
|------------|---------------------|
| Proxy      | TotalVpProxyTasks   |
| GPProxy    | TotalGPProxyTasks   |
| CDPProxy   | TotalCDPProxyTasks  |
| Repository | TotalRepoTasks      |
| Gateway    | TotalGWTasks        |

## Consequences

* **Good:** Single definition of entry shape - changes propagate to all roles.
* **Good:** Multi-role key-guard is always applied consistently.
* **Good:** Helper is purely testable without VBR.
* **Neutral:** Mutable hashtable pattern is unchanged - ADR 0006 compliance
  is unaffected (shared state is infrastructure accumulation, not business
  data exchange between collectors).
