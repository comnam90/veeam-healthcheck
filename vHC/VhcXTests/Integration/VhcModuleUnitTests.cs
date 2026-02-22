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
            var writeLogPath = Path.Combine(
                Path.GetDirectoryName(_exportCsvScriptPath) ?? tmpDir, "Write-LogFile.ps1");
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
    }
}
