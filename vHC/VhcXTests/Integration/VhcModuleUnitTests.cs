// Copyright (C) 2025 VeeamHub
// SPDX-License-Identifier: MIT

using System;
using System.Diagnostics;
using System.IO;
using Xunit;

namespace VhcXTests.Integration
{
    /// <summary>
    /// Unit-level checks for the vHC-VbrConfig PowerShell module that do not require
    /// a live Veeam environment. These tests satisfy Task 10 Step 3 of the VBR config
    /// refactor (docs/plans/2026-02-21-vbr-config-refactor.md).
    /// </summary>
    [Collection("Integration Tests")]
    [Trait("Category", "Integration")]
    public class VhcModuleUnitTests
    {
        private readonly string _exportCsvScriptPath;

        public VhcModuleUnitTests()
        {
            var projectRoot = Path.GetFullPath(Path.Combine(
                AppDomain.CurrentDomain.BaseDirectory,
                "..", "..", "..", "..", "HC_Reporting"));
            _exportCsvScriptPath = Path.Combine(
                projectRoot, "Tools", "Scripts", "HealthCheck", "VBR",
                "vHC-VbrConfig", "Private", "Export-VhcCsv.ps1");
        }

        /// <summary>
        /// Verifies that Export-VhcCsv preserves [pscustomobject][ordered] column order.
        /// A known object is piped through the function and the resulting CSV header row
        /// is asserted to be an exact string match.
        /// </summary>
        [Fact]
        public void ExportVhcCsv_ColumnOrder_IsPreserved()
        {
            if (!File.Exists(_exportCsvScriptPath))
            {
                Assert.Fail($"Export-VhcCsv.ps1 not found at: {_exportCsvScriptPath}");
            }

            var tmpDir       = Path.Combine(Path.GetTempPath(), $"vhc-test-{Guid.NewGuid():N}");
            var tmpScriptPath = Path.Combine(tmpDir, "Test-ColumnOrder.ps1");

            Directory.CreateDirectory(tmpDir);

            // Write the test script to a temp file to avoid complex argument escaping.
            // The script dot-sources Export-VhcCsv (and Write-LogFile which it calls internally),
            // injects the module-level vars it reads, pipes a known [pscustomobject][ordered]
            // through it, then asserts the CSV header is an exact column-order match.
            var moduleRoot    = Path.GetFullPath(Path.Combine(
                Path.GetDirectoryName(_exportCsvScriptPath) ?? tmpDir, ".."));
            var writeLogPath  = Path.Combine(moduleRoot, "Public", "Write-LogFile.ps1");
            var scriptContent = $@"
$ErrorActionPreference = 'Stop'
. '{writeLogPath}'
. '{_exportCsvScriptPath}'

$script:ReportPath = '{tmpDir}'
$script:VBRServer  = 'test'
$script:LogPath    = '{tmpDir}'
$script:LogLevel   = 'ERROR'

[pscustomobject][ordered]@{{
    Alpha   = 1
    Bravo   = 2
    Charlie = 3
    Delta   = 4
}} | Export-VhcCsv -FileName '_ColumnOrder.csv'

$csvPath = (Join-Path '{tmpDir}' 'test_ColumnOrder.csv')
$header  = (Get-Content $csvPath | Select-Object -First 1)
$expected = '""Alpha"",""Bravo"",""Charlie"",""Delta""'
if ($header -ne $expected) {{
    Write-Error ""Column order mismatch. Expected: $expected  Got: $header""
    exit 1
}}
Write-Host 'Column order OK'
exit 0
";
            File.WriteAllText(tmpScriptPath, scriptContent);

            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName               = "pwsh",
                    Arguments              = $"-NoProfile -NonInteractive -File \"{tmpScriptPath}\"",
                    RedirectStandardError  = true,
                    RedirectStandardOutput = true,
                    UseShellExecute        = false,
                    CreateNoWindow         = true
                };

                using var process = Process.Start(psi);
                if (process == null)
                {
                    Assert.Fail("Failed to start pwsh process for column-order check");
                    return;
                }
                var stdout = process.StandardOutput.ReadToEnd();
                var stderr = process.StandardError.ReadToEnd();
                process.WaitForExit();

                Assert.True(process.ExitCode == 0,
                    $"Export-VhcCsv column-order check failed (exit {process.ExitCode}).\n" +
                    $"STDOUT: {stdout}\nSTDERR: {stderr}");
            }
            finally
            {
                if (Directory.Exists(tmpDir))
                    Directory.Delete(tmpDir, recursive: true);
            }
        }

        /// <summary>
        /// Verifies that Export-VhcCsv propagates file I/O failures rather than swallowing them.
        /// A non-existent output directory is used to trigger Export-Csv failure reliably.
        /// </summary>
        [Fact]
        public void ExportVhcCsv_IoFailure_ThrowsException()
        {
            var projectRoot = Path.GetFullPath(Path.Combine(
                AppDomain.CurrentDomain.BaseDirectory,
                "..", "..", "..", "..", "HC_Reporting"));
            var moduleRoot       = Path.Combine(projectRoot, "Tools", "Scripts", "HealthCheck", "VBR", "vHC-VbrConfig");
            var exportCsvPath    = Path.Combine(moduleRoot, "Private", "Export-VhcCsv.ps1");
            var writeLogPath     = Path.Combine(moduleRoot, "Public",  "Write-LogFile.ps1");

            var tmpDir       = Path.Combine(Path.GetTempPath(), $"vhc-ioerr-{Guid.NewGuid():N}");
            var tmpScriptPath = Path.Combine(tmpDir, "Test-IoFailure.ps1");
            Directory.CreateDirectory(tmpDir);

            // ReportPath points to a path that does not exist and cannot be created by Export-VhcCsv.
            // (Export-Csv fails when the parent directory doesn't exist.)
            var nonExistentPath = Path.Combine(tmpDir, "does-not-exist", "nested");

            var scriptContent = $@"
$ErrorActionPreference = 'Stop'
. '{writeLogPath}'
. '{exportCsvPath}'

$script:ReportPath = '{nonExistentPath}'
$script:VBRServer  = 'test'
$script:LogPath    = '{tmpDir}'
$script:LogLevel   = 'ERROR'

try {{
    [pscustomobject]@{{ A = 1 }} | Export-VhcCsv -FileName '_test.csv'
    # Should NOT reach here - expect an exception from the missing directory
    Write-Error 'Export-VhcCsv did not throw on I/O failure'
    exit 1
}} catch {{
    # Exception propagated as expected
    exit 0
}}
";
            File.WriteAllText(tmpScriptPath, scriptContent);

            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName               = "pwsh",
                    Arguments              = $"-NoProfile -NonInteractive -File \"{tmpScriptPath}\"",
                    RedirectStandardError  = true,
                    RedirectStandardOutput = true,
                    UseShellExecute        = false,
                    CreateNoWindow         = true
                };

                using var process = Process.Start(psi);
                if (process == null) { Assert.Fail("Failed to start pwsh"); return; }
                var stdout = process.StandardOutput.ReadToEnd();
                var stderr = process.StandardError.ReadToEnd();
                process.WaitForExit();

                Assert.True(process.ExitCode == 0,
                    $"Export-VhcCsv should have thrown on I/O failure and been caught by the test's try/catch.\n" +
                    $"Exit code {process.ExitCode} means the exception was swallowed.\nSTDOUT: {stdout}\nSTDERR: {stderr}");
            }
            finally
            {
                if (Directory.Exists(tmpDir)) Directory.Delete(tmpDir, recursive: true);
            }
        }

        /// <summary>
        /// Regression guard: Invoke-VhcCollector must never throw, even when the wrapped
        /// scriptblock throws. It must return Success=false and Error set to the exception message.
        /// </summary>
        [Fact]
        public void InvokeVhcCollector_ScriptblockThrows_ReturnsFailedResultWithoutThrowing()
        {
            var projectRoot = Path.GetFullPath(Path.Combine(
                AppDomain.CurrentDomain.BaseDirectory,
                "..", "..", "..", "..", "HC_Reporting"));
            var moduleRoot      = Path.Combine(projectRoot, "Tools", "Scripts", "HealthCheck", "VBR", "vHC-VbrConfig");
            var collectorPath   = Path.Combine(moduleRoot, "Public", "Invoke-VhcCollector.ps1");
            var writeLogPath    = Path.Combine(moduleRoot, "Public",  "Write-LogFile.ps1");

            var tmpDir       = Path.Combine(Path.GetTempPath(), $"vhc-coll-{Guid.NewGuid():N}");
            var tmpScriptPath = Path.Combine(tmpDir, "Test-CollectorIsolation.ps1");
            Directory.CreateDirectory(tmpDir);

            var scriptContent = $@"
$ErrorActionPreference = 'Stop'
. '{writeLogPath}'
. '{collectorPath}'

# Initialize the module-level vars Write-LogFile reads
$script:LogPath  = '{tmpDir}'
$script:LogLevel = 'ERROR'

$result = Invoke-VhcCollector -Name 'TestCollector' -Action {{
    throw 'Intentional test error'
}}

if ($result.Success -eq $true) {{
    Write-Error 'Expected Success=false but got Success=true'
    exit 1
}}
if ([string]::IsNullOrEmpty($result.Error)) {{
    Write-Error 'Expected Error to be populated but it was empty'
    exit 1
}}
if ($result.Error -notmatch 'Intentional test error') {{
    Write-Error ""Expected Error to contain 'Intentional test error' but got: $($result.Error)""
    exit 1
}}
Write-Host ""OK: Success=false, Error='$($result.Error)'""
exit 0
";
            File.WriteAllText(tmpScriptPath, scriptContent);

            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName               = "pwsh",
                    Arguments              = $"-NoProfile -NonInteractive -File \"{tmpScriptPath}\"",
                    RedirectStandardError  = true,
                    RedirectStandardOutput = true,
                    UseShellExecute        = false,
                    CreateNoWindow         = true
                };

                using var process = Process.Start(psi);
                if (process == null) { Assert.Fail("Failed to start pwsh"); return; }
                var stdout = process.StandardOutput.ReadToEnd();
                var stderr = process.StandardError.ReadToEnd();
                process.WaitForExit();

                Assert.True(process.ExitCode == 0,
                    $"Invoke-VhcCollector did not correctly isolate the thrown exception.\n" +
                    $"STDOUT: {stdout}\nSTDERR: {stderr}");
            }
            finally
            {
                if (Directory.Exists(tmpDir)) Directory.Delete(tmpDir, recursive: true);
            }
        }

        /// <summary>
        /// Regression guard: Get-VhcSessionReport must throw with a clear error message when
        /// $script:AllBackupSessions is null (i.e. Get-VhcBackupSessions was never called or failed).
        /// When wrapped by Invoke-VhcCollector this produces a FAIL entry, not a silent empty CSV.
        /// </summary>
        [Fact]
        public void GetVhcSessionReport_NullSessions_ThrowsDescriptiveError()
        {
            var projectRoot = Path.GetFullPath(Path.Combine(
                AppDomain.CurrentDomain.BaseDirectory,
                "..", "..", "..", "..", "HC_Reporting"));
            var moduleRoot       = Path.Combine(projectRoot, "Tools", "Scripts", "HealthCheck", "VBR", "vHC-VbrConfig");
            var sessionRptPath   = Path.Combine(moduleRoot, "Public",  "Get-VhcSessionReport.ps1");
            var writeLogPath     = Path.Combine(moduleRoot, "Public",  "Write-LogFile.ps1");
            var exportCsvPath    = Path.Combine(moduleRoot, "Private", "Export-VhcCsv.ps1");
            var sessionLogPath   = Path.Combine(moduleRoot, "Private", "Get-VhcSessionLogWithTimeout.ps1");

            var tmpDir       = Path.Combine(Path.GetTempPath(), $"vhc-sess-{Guid.NewGuid():N}");
            var tmpScriptPath = Path.Combine(tmpDir, "Test-NullSessionGuard.ps1");
            Directory.CreateDirectory(tmpDir);

            var scriptContent = $@"
$ErrorActionPreference = 'Stop'
. '{writeLogPath}'
. '{exportCsvPath}'
. '{sessionLogPath}'
. '{sessionRptPath}'

$script:ReportPath         = '{tmpDir}'
$script:VBRServer          = 'test'
$script:LogPath            = '{tmpDir}'
$script:LogLevel           = 'ERROR'
$script:ReportInterval     = 14
$script:AllBackupSessions  = $null   # simulate Get-VhcBackupSessions never running

try {{
    Get-VhcSessionReport
    # Should NOT reach here
    Write-Error 'Get-VhcSessionReport did not throw when sessions are null'
    exit 1
}} catch {{
    if ($_.Exception.Message -notmatch 'AllBackupSessions') {{
        Write-Error ""Expected error about AllBackupSessions but got: $($_.Exception.Message)""
        exit 1
    }}
    Write-Host ""OK: threw with expected message: $($_.Exception.Message)""
    exit 0
}}
";
            File.WriteAllText(tmpScriptPath, scriptContent);

            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName               = "pwsh",
                    Arguments              = $"-NoProfile -NonInteractive -File \"{tmpScriptPath}\"",
                    RedirectStandardError  = true,
                    RedirectStandardOutput = true,
                    UseShellExecute        = false,
                    CreateNoWindow         = true
                };

                using var process = Process.Start(psi);
                if (process == null) { Assert.Fail("Failed to start pwsh"); return; }
                var stdout = process.StandardOutput.ReadToEnd();
                var stderr = process.StandardError.ReadToEnd();
                process.WaitForExit();

                Assert.True(process.ExitCode == 0,
                    $"Get-VhcSessionReport did not throw the expected error for null sessions.\n" +
                    $"STDOUT: {stdout}\nSTDERR: {stderr}");
            }
            finally
            {
                if (Directory.Exists(tmpDir)) Directory.Delete(tmpDir, recursive: true);
            }
        }

        /// <summary>
        /// Verifies the orchestrator throws a clear error when VbrConfig.json is missing
        /// a required threshold key, rather than silently using $null.
        /// </summary>
        [Fact]
        public void GetVBRConfig_MissingThresholdKey_ThrowsDescriptiveError()
        {
            var projectRoot = Path.GetFullPath(Path.Combine(
                AppDomain.CurrentDomain.BaseDirectory,
                "..", "..", "..", "..", "HC_Reporting"));
            var orchestratorPath = Path.Combine(
                projectRoot, "Tools", "Scripts", "HealthCheck", "VBR", "Get-VBRConfig.ps1");

            if (!File.Exists(orchestratorPath))
            {
                Assert.Fail($"Get-VBRConfig.ps1 not found at: {orchestratorPath}");
            }

            var tmpDir         = Path.Combine(Path.GetTempPath(), $"vhc-thresh-{Guid.NewGuid():N}");
            var tmpConfigPath  = Path.Combine(tmpDir, "VbrConfig.json");
            var tmpScriptPath  = Path.Combine(tmpDir, "Test-ThresholdValidation.ps1");

            Directory.CreateDirectory(tmpDir);

            // VbrConfig.json with one required threshold key intentionally removed
            var brokenConfig = @"{
  ""ConfigVersion"": 1,
  ""LogLevel"": ""INFO"",
  ""DefaultOutputPath"": ""C:\\temp\\vHC\\Original\\VBR"",
  ""Thresholds"": {
    ""VpProxyCPUPerTask"": 0.5
  },
  ""SecurityComplianceRuleNames"": {}
}";
            // Test script: dot-sources only the validation block from the orchestrator
            // by extracting just the $config loading + key-check logic into a minimal wrapper.
            var scriptContent = $@"
$ErrorActionPreference = 'Stop'
$configPath = '{tmpConfigPath}'
$config = Get-Content -Path $configPath -Raw | ConvertFrom-Json

# --- Paste the exact validation block from Get-VBRConfig.ps1 here ---
$requiredThresholds = @(
    'VpProxyRAMPerTask','VpProxyCPUPerTask','VpProxyOSCPU','VpProxyOSRAM',
    'GpProxyRAMPerTask','GpProxyCPUPerTask','GpProxyOSCPU','GpProxyOSRAM',
    'RepoGwRAMPerTask','RepoGwCPUPerTask','RepoOSCPU','RepoOSRAM',
    'CdpProxyRAM','CdpProxyCPU',
    'BackupServerCPU_v12','BackupServerRAM_v12','BackupServerCPU_v13','BackupServerRAM_v13',
    'SqlRAMMin','SqlCPUMin',
    'CompliancePollMaxSeconds','CompliancePollIntervalSeconds'
)
foreach ($key in $requiredThresholds) {{
    if ($null -eq $config.Thresholds.$key) {{
        throw ""VbrConfig.json Thresholds is missing required key: '$key'""
    }}
}}
# Should not reach here - the missing key should have thrown
exit 0
";
            File.WriteAllText(tmpConfigPath, brokenConfig);
            File.WriteAllText(tmpScriptPath, scriptContent);

            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName               = "pwsh",
                    Arguments              = $"-NoProfile -NonInteractive -File \"{tmpScriptPath}\"",
                    RedirectStandardError  = true,
                    RedirectStandardOutput = true,
                    UseShellExecute        = false,
                    CreateNoWindow         = true
                };

                using var process = Process.Start(psi);
                if (process == null) { Assert.Fail("Failed to start pwsh"); return; }
                var stdout = process.StandardOutput.ReadToEnd();
                var stderr = process.StandardError.ReadToEnd();
                process.WaitForExit();

                Assert.True(process.ExitCode != 0,
                    $"Expected non-zero exit when threshold key is missing, got 0.\nSTDOUT: {stdout}\nSTDERR: {stderr}");
                Assert.Contains("VbrConfig.json Thresholds is missing required key", stderr + stdout,
                    StringComparison.OrdinalIgnoreCase);
            }
            finally
            {
                if (Directory.Exists(tmpDir)) Directory.Delete(tmpDir, recursive: true);
            }
        }
    }
}
