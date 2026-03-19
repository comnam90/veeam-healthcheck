# ADR 0014 — Split HC_Core Library to Remove WPF Build Dependency

**Status:** Accepted

**Date:** 2026-03-20

**Decider:** Ben Thomas (@comnam90)

---

## Context

The solution currently contains a single C# project (`VeeamHealthCheck.csproj`) that targets
`net8.0-windows7.0` and sets `<UseWPF>true</UseWPF>`. The test project (`VhcXTests.csproj`)
references this project directly, which forces it to the same Windows-only target framework.

On non-Windows CI agents, the test project skips compilation entirely:

```xml
<EnableDefaultCompileItems Condition="!$([MSBuild]::IsOSPlatform('Windows'))">false</EnableDefaultCompileItems>
```

This means:

- CI must provision Windows agents to build and test the application.
- Pull request validation requires a Windows runner.
- The majority of the codebase — CSV handling, report compilation, data processing, PowerShell
  orchestration, collection logic — has no actual dependency on WPF and could compile and be
  tested on any platform.

The runtime constraint is separate and immovable: Veeam Backup & Replication runs only on
Windows Server, so the tool must execute on Windows regardless of where it is built.

---

## Investigation

A full audit of `System.Windows` references across `HC_Reporting/` identified eight files with
WPF-namespace imports. These fall into three categories:

### Category 1 — Dead imports (zero behaviour, zero effort)

| File | Import | Actual usage |
|---|---|---|
| `Functions/Collection/DB/CRegReader.cs` | `System.Windows.Documents` | None |
| `Functions/Reporting/Html/Exportables/HtmlToPdfConverter.cs` | `System.Windows.Controls` | None |

### Category 2 — Expected GUI files (stay in the shell project)

| File | WPF usage |
|---|---|
| `Startup/VhcGui.xaml.cs` | Full WPF window |
| `Functions/CredsWindow/CredentialPromptWindow.xaml.cs` | Full WPF window |

### Category 3 — Logic files with WPF leakage (require surgery)

| File | WPF usage | Nature |
|---|---|---|
| `Functions/Collection/CCollections.cs` | `MessageBox.Show` (1 call, `GUIEXEC`-guarded) | Error dialog fallback |
| `Startup/CClientFunctions.cs` | `MessageBox.Show`, `Application.Current.Dispatcher.Invoke`, `WebBrowser`, `Navigation.RequestNavigateEventArgs` | Mixed GUI/logic class |
| `Functions/Reporting/Html/CHtmlExporter.cs` | `Application.Current.Dispatcher.Invoke` with `WebBrowser` | Opens HTML preview in WPF browser control |
| `Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/CJobSessSummaryHelper.cs` | `System.Windows` import | Requires further inspection |

**Key observation:** `CGlobals.cs` is clean. All collection logic, CSV handlers, report
compilers, and data formers carry no WPF dependency other than the leakage listed above.

### Non-WPF Windows-only packages

Two packages in `VeeamHealthCheck.csproj` are Windows-only at runtime but compile on Linux:

| Package | Runtime constraint |
|---|---|
| `Microsoft.Management.Infrastructure` | WMI/CIM — Windows native |
| `TaskScheduler` | Windows Task Scheduler API |

These are runtime-only constraints. A `net8.0` core library that references them will still
compile on Linux; only tests that exercise these code paths would need to be skipped
on non-Windows (consistent with how Veeam snap-in tests are already handled).

---

## Options Considered

### Option A — Conditional compilation directives (`#if WINDOWS`)

Wrap WPF call sites in `#if WINDOWS` preprocessor guards. No structural change to the
solution.

**Pros:**
- Minimal structural change.

**Cons:**
- Compilable on Linux but untestable without surgical `#if` guards around every WPF
  reference, including transitively-imported namespaces. The `using` directives alone cause
  compile errors even when the types are never instantiated at runtime.
- Accumulates technical debt — future contributors must maintain the guards and can
  inadvertently break the Linux build by importing a WPF type without a guard.
- Does not fix the test project's inability to reference the main project on Linux.

**Rejected.**

### Option B — Move to .NET MAUI

Replace the WPF GUI layer with .NET MAUI, targeting Windows/macOS/mobile.

**Pros:**
- Removes WPF as a GUI technology.
- MAUI targets include `net8.0-windows`, `net8.0-maccatalyst`, etc.

**Cons:**
- Significant rewrite of all XAML/code-behind GUI files with no functional benefit.
- MAUI desktop support on Windows is less mature than WPF.
- The tool's runtime is fundamentally Windows-only (Veeam). Cross-platform GUI is
  window dressing on a Windows-only executable.
- Does not address WMI, registry, or TaskScheduler Windows-runtime dependencies.
- Does not eliminate the Windows build constraint; MAUI Windows targets still require
  the Windows SDK.

**Rejected.**

### Option C — Blazor Server local web frontend

Replace the WPF GUI with an ASP.NET Core Blazor Server application served on localhost.
The .exe starts a Kestrel server and opens the default browser.

**Pros:**
- GUI code is platform-neutral HTML/CSS/Razor; no Windows SDK required to build.
- Real-time collection progress via SignalR is a natural fit for the collection pipeline.
- Reports are already HTML; they can be served directly rather than opened as files.
- Build and test of core logic could run on Linux.

**Cons:**
- Substantial rewrite of all GUI code (`VhcGui.xaml.cs`, `CredentialPromptWindow.xaml.cs`,
  `CClientFunctions.cs` GUI methods).
- Introduces Kestrel hosting, browser lifecycle management, and port-conflict handling.
- Adds end-user friction: requires a browser, has no single-window `.exe` feel.
- The primary driver is CI pain, not UX improvement. This option over-invests in UX
  change to solve a build problem.

**Rejected** as the primary intervention. May be revisited as a separate UX initiative.

### Option D — Extract HC_Core library (chosen)

Introduce a new class library project `HC_Core.csproj` targeting `net8.0` (no Windows
suffix, no `UseWPF`). Move all non-GUI source into it. Keep `VeeamHealthCheck.csproj` as
a thin Windows shell containing only WPF files and startup wiring. Update `VhcXTests.csproj`
to reference `HC_Core` instead of `VeeamHealthCheck`.

**Pros:**
- `VhcXTests` references a `net8.0` project — it can compile and run on Linux.
- Core logic is tested on Linux in CI without any Windows agent.
- The WPF shell project still targets `net8.0-windows7.0` and is built only on Windows
  (correct, since only Windows can run the output).
- No user-facing behaviour change: the deployed `.exe` is unchanged.
- Forces a clean architectural boundary between GUI and core that the current single-project
  layout obscures.
- Dead WPF imports in core files are removed as part of the migration, cleaning up existing
  technical debt.

**Cons:**
- Requires splitting `CClientFunctions.cs`: GUI methods (WebBrowser open, MessageBox, KB
  link navigation) stay in the shell; logic methods move to core. This is the largest single
  piece of work.
- `InternalsVisibleTo` in `VeeamHealthCheck.csproj` must be mirrored in `HC_Core.csproj`
  to preserve test access to internal types.
- Tests that exercise WMI or TaskScheduler code paths must still be skipped on non-Windows
  (they are runtime-only failures, not compile failures — same situation as today for
  Veeam snap-in tests).

**Accepted.**

---

## Decision

Extract `HC_Core.csproj` (targeting `net8.0`) containing all non-GUI source. Retain
`VeeamHealthCheck.csproj` (targeting `net8.0-windows7.0`) as the WPF shell. Update
`VhcXTests.csproj` to reference `HC_Core`.

### Assembly naming

- `HC_Core.csproj`: `AssemblyName=HC_Core`, `RootNamespace=VeeamHealthCheck`
- `VeeamHealthCheck.csproj`: `AssemblyName=VeeamHealthCheck` (unchanged)

Using `AssemblyName=VeeamHealthCheck` in both projects is not safe: both would emit a
file named `VeeamHealthCheck.dll`, causing an output-directory collision. `CVersionSetter`
would also report the core DLL version rather than the exe version if both shared the
same assembly name.

Using `RootNamespace=VeeamHealthCheck` in HC_Core ensures embedded resources retain
their existing names (`VeeamHealthCheck.css.css`, `VeeamHealthCheck.banner_string.txt`,
etc.) — no resource renames are needed.

### Project layout after migration

```
HC.sln
├── HC_Core.csproj                  (net8.0)
│     ├── Common/
│     ├── Functions/Collection/
│     ├── Functions/Reporting/
│     ├── Functions/Analysis/
│     ├── Functions/DataFormers/
│     ├── Scrubber/
│     └── Shared/
│
├── VeeamHealthCheck.csproj         (net8.0-windows7.0, UseWPF=true)
│     ├── Startup/EntryPoint.cs
│     ├── Startup/CArgsParser.cs
│     ├── Startup/CClientFunctions.cs  (GUI methods only, post-split)
│     ├── VhcGui.xaml / .cs
│     └── Functions/CredsWindow/
│
└── VhcXTests.csproj                (net8.0)
      └── ProjectReference → HC_Core
```

### Surgery required on Category 3 files

1. **`CRegReader.cs`, `HtmlToPdfConverter.cs`** — remove dead `using System.Windows.*`
   directives.

2. **`CCollections.cs`** — remove `MessageBox.Show` call. The call site is already guarded
   by `CGlobals.GUIEXEC`; replace with a logger warning. The GUI shell can surface the same
   error through its own error-handling path.

3. **`CClientFunctions.cs`** — split into two classes:
   - `CClientFunctions.cs` (moves to `HC_Core`): all logic methods with no WPF dependency.
   - `CGuiFunctions.cs` (stays in `VeeamHealthCheck`): `WebBrowser` open, MessageBox calls,
     `KbLinkAction` navigation handler, and any other methods that directly manipulate WPF
     controls or the `Application` dispatcher.

4. **`CHtmlExporter.cs`** — remove `Application.Current.Dispatcher.Invoke` / `WebBrowser`
   block. Opening the report in a browser is a shell responsibility. The method in
   `CHtmlExporter` should write the file and return the path; the shell calls
   `Process.Start` to open it.

---

## Consequences

### Positive
- CI can compile and run tests on Linux agents without a Windows runner.
- The architectural boundary between GUI and core is explicit and enforced by project
  references rather than by convention.
- Dead WPF imports are removed from core files.
- `CClientFunctions.cs` is decomposed — GUI logic is no longer entangled with collection
  and reporting orchestration.

### Neutral
- The deployed Windows `.exe` is functionally identical to the current build. End users
  see no change.
- Tests covering WMI, TaskScheduler, and Veeam snap-in paths must still be skipped on
  non-Windows. This is unchanged from the current situation.
- `InternalsVisibleTo` must be present in `HC_Core.csproj`; the existing entry in
  `VeeamHealthCheck.csproj` continues to cover any internal types that remain in the shell.

### Negative
- Two-project solution adds a small amount of solution maintenance overhead (two `.csproj`
  files to keep in sync for shared package versions).
- `CClientFunctions.cs` split is the largest individual change and risks merge conflicts if
  other branches have modified that file concurrently.
- `AssemblyName=HC_Core` means `Assembly.GetExecutingAssembly().GetName().Name` returns
  `"HC_Core"` in code running inside the library. `CHtmlCompiler.cs` and
  `CHtmlFormatting.cs` both construct embedded resource names using that value, but the
  resources are named with the `VeeamHealthCheck` prefix (from `RootNamespace`). Both files
  must be fixed to use `typeof(T).Assembly` with a hardcoded `"VeeamHealthCheck."` prefix.
- `CVersionSetter.GetFileVersion()` uses `Assembly.GetExecutingAssembly().Location`, which
  after the move resolves to the core DLL path rather than the exe path. It must be changed
  to use `Process.GetCurrentProcess().MainModule.FileName` directly.

---

## Implementation Order

1. Remove dead WPF imports (`CRegReader.cs`, `HtmlToPdfConverter.cs`).
2. Replace `MessageBox.Show` in `CCollections.cs` with logger call.
3. Refactor `CHtmlExporter.cs` to remove `WebBrowser` / `Dispatcher` usage; return file
   path and let the caller open it.
4. Split `CClientFunctions.cs` into core logic and GUI methods.
5. Create `HC_Core.csproj` targeting `net8.0`; move files; verify solution builds on
   Windows.
6. Update `VhcXTests.csproj` to reference `HC_Core`; remove Windows-only conditionals
   from test project where no longer needed.
7. Verify CI Linux build compiles and tests pass.
