# ADR 0013 — Bottleneck Data via CBottleneckInfo Structured Property

**Status:** Accepted

**Date:** 2026-03-18

**Decider:** Ben Thomas (@comnam90)

---

## Context

`Get-VhcSessionReport.ps1` extracts two bottleneck columns from each task session:

- `BottleneckDetails` — the busy breakdown string, e.g. `Source 87% > Proxy 33% > Network 0% > Target 27%`
- `PrimaryBottleneck` — the dominant component, e.g. `Source`

Both are currently populated by parsing `$task.Logger.GetLog().UpdatedRecords` for entries
matching:

```powershell
$BottleneckRegex     = [regex]'^Busy: (\S+ \d+% > \S+ \d+% > \S+ \d+% > \S+ \d+%)'
$PrimaryBottleneckRx = [regex]'^Primary bottleneck: (\S+)'
```

This approach was inherited from the original standalone script. At the time ADR 0012 was
written (agent session support), it was confirmed that agent sessions produce no log records
post-completion, leaving `BottleneckDetails` and `PrimaryBottleneck` empty for all
`EpAgentBackup` sessions. ADR 0012 recorded this as a neutral consequence.

During live testing on VBR v13, `$task.JobSess.Progress.BottleneckInfo` was discovered to be
a populated `Veeam.Backup.Model.CBottleneckInfo` object on all session types tested.

---

## Investigation

### CBottleneckInfo properties

```
Bottleneck                  = Source          # primary bottleneck name
Source                      = 87              # percentage
Proxy                       = 33
Target                      = 27
Network                     = 0
SourceStorage               = 87              # granular breakdown
SourceProxy                 = 33
SourceNetwork               = 0
SourceWan                   = -1
TargetStorage               = 27
TargetProxy                 = 33
TargetNetwork               = 0
TargetWan                   = -1
NetworkThrottlingEnabled    = False
RepositoryThrottlingEnabled = False
```

### Cross-session-type availability (confirmed live on VBR v13)

| Session type | `CBottleneckInfo` populated | Log-based entries present |
|---|---|---|
| VM backup (`Backup`) | Yes | Yes |
| Backup Copy (`SimpleBackupCopyWorker`) | Yes | Yes |
| NAS backup (`NasBackup`) | Yes | Yes |
| Agent/computer (`EpAgentManagement`) | Yes | No |

### Value agreement where logs exist

A 20-session sample across VM, Backup Copy, and NAS types was tested. The structured
property values were reconstructed into the log-format string and compared against the
parsed log output:

```
Struct: Source 87% > Proxy 33% > Network 0% > Target 27%
Log:    Source 87% > Proxy 33% > Network 0% > Target 27%
```

**Primary bottleneck: 20/20 match. Detail string: 20/20 match.**

No discrepancy was found between the two sources on any session type.

---

## Options Considered

### Option A — Retain log parsing (status quo)

Continue using `Logger.GetLog().UpdatedRecords` regex matching for all session types.

**Pros:**
- No change to existing working code for VM/NAS/Backup Copy sessions.

**Cons:**
- Agent sessions permanently produce empty `BottleneckDetails` and `PrimaryBottleneck`.
- Requires `Logger.GetLog()` to be called even though it returns nothing useful for bottleneck
  on agent sessions (the call is not free — it performs a DB/XML read).
- Regex against free-text log entries is fragile; log message format is not a versioned API
  surface.

### Option B — CBottleneckInfo structured property (chosen)

Replace log regex matching for both bottleneck columns with `$task.JobSess.Progress.BottleneckInfo`:

```powershell
$bi = $task.JobSess.Progress.BottleneckInfo
$PrimaryBottleneck = if ($bi -and $bi.Bottleneck) { "$($bi.Bottleneck)" } else { '' }
$BottleneckDetails = if ($bi -and $bi.Source -ge 0) {
    "Source $($bi.Source)% > Proxy $($bi.Proxy)% > Network $($bi.Network)% > Target $($bi.Target)%"
} else { '' }
```

**Pros:**
- Populates bottleneck columns for agent sessions (currently always empty).
- Typed, structured object — no regex, no string parsing.
- Values confirmed identical to log-parsed output where both exist (20/20 on live VBR v13).
- `Logger.GetLog()` is still needed for `ProcessingMode` (ADR 0003) but no longer has to carry
  the bottleneck responsibility.

**Cons:**
- `CBottleneckInfo` is an internal Veeam model type, not a public PowerShell surface. However,
  it is accessed via `Progress.BottleneckInfo` which is a stable, named property — not an
  inferred integer mapping as rejected for `SourceProxyMode` in ADR 0003.

### Option C — Structured property with log fallback

Use `CBottleneckInfo` where populated; fall back to log parsing where it returns null.

**Verdict:** Not warranted. `CBottleneckInfo` was populated on every session tested,
including all types where logs were also present. A fallback adds complexity with no
observed benefit.

---

## Decision

**Option B** — replace log-based bottleneck extraction with `$task.JobSess.Progress.BottleneckInfo`
for both `BottleneckDetails` and `PrimaryBottleneck` columns.

`ProcessingMode` (VMware transport mode) continues to use log parsing per ADR 0003 — that
decision is unaffected as `CBottleneckInfo` contains no transport mode information.

---

## Consequences

### Positive
- `BottleneckDetails` and `PrimaryBottleneck` are now populated for agent/computer backup
  sessions, resolving the gap noted in ADR 0012.
- Bottleneck extraction is simpler — no regex, no log record iteration for these two columns.
- Output format is unchanged for VM, NAS, and Backup Copy sessions (values confirmed identical).

### Neutral
- `Logger.GetLog()` continues to be called per task for `ProcessingMode` (ADR 0003).
- The output string format (`Source X% > Proxy X% > Network X% > Target X%`) is reconstructed
  from the structured properties rather than lifted verbatim from the log. The format is
  identical but is now owned by this codebase rather than inherited from Veeam log text.

### Negative
- None identified.

## Validation

Live testing on VBR v13 (`lab-m01-lvbr01.lab.garagecloud.net`):
- `CBottleneckInfo` confirmed populated on VM, Backup Copy, NAS, and agent session types.
- 20-session comparison: structured values match log-parsed values 20/20 on primary bottleneck
  and detail string.
- Agent session (`Physical Servers - Linux`): `Bottleneck=Proxy`, `Source=74`, `Proxy=77`,
  `Target=75`, `Network=24` — previously all empty via log parsing.
