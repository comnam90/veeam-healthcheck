// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System;
using System.Net;
using VeeamHealthCheck.Startup;
using Xunit;

namespace VhcXTests
{
    /// <summary>
    /// Tests for CHostNameHelper.IsLocalHost.
    /// Cross-platform: no Windows APIs are required.
    /// </summary>
    [Trait("Category", "Unit")]
    public class CHostNameHelperTests
    {
        [Theory]
        [InlineData("localhost")]
        [InlineData("LOCALHOST")]
        [InlineData("LocalHost")]
        public void IsLocalHost_Localhost_ReturnsTrue(string hostname)
        {
            Assert.True(CHostNameHelper.IsLocalHost(hostname),
                $"'{hostname}' should be detected as local host");
        }

        [Fact]
        public void IsLocalHost_LoopbackIPv4_ReturnsTrue()
        {
            Assert.True(CHostNameHelper.IsLocalHost("127.0.0.1"),
                "127.0.0.1 should be detected as local host");
        }

        [Fact]
        public void IsLocalHost_MatchesEnvironmentMachineName_ReturnsTrue()
        {
            Assert.True(CHostNameHelper.IsLocalHost(Environment.MachineName),
                $"Machine name '{Environment.MachineName}' should be detected as local host");
        }

        [Fact]
        public void IsLocalHost_MatchesMachineNameCaseInsensitive_ReturnsTrue()
        {
            string lower = Environment.MachineName.ToLowerInvariant();
            Assert.True(CHostNameHelper.IsLocalHost(lower),
                $"Lowercase machine name '{lower}' should be detected as local host");
        }

        [Fact]
        public void IsLocalHost_MatchesDnsGetHostName_ReturnsTrue()
        {
            string dnsHostName = Dns.GetHostName();
            Assert.True(CHostNameHelper.IsLocalHost(dnsHostName),
                $"DNS host name '{dnsHostName}' should be detected as local host");
        }

        [Fact]
        public void IsLocalHost_FqdnStartingWithMachineName_ReturnsTrue()
        {
            string fqdn = $"{Environment.MachineName}.domain.local";
            Assert.True(CHostNameHelper.IsLocalHost(fqdn),
                $"FQDN '{fqdn}' starting with machine name should be detected as local host");
        }

        [Theory]
        [InlineData("remote-server")]
        [InlineData("vbr-prod")]
        [InlineData("192.168.1.100")]
        [InlineData("10.0.0.1")]
        public void IsLocalHost_ActualRemoteHost_ReturnsFalse(string hostname)
        {
            Assert.False(CHostNameHelper.IsLocalHost(hostname),
                $"'{hostname}' should NOT be detected as local host");
        }

        [Fact]
        public void IsLocalHost_RemoteFqdn_ReturnsFalse()
        {
            Assert.False(CHostNameHelper.IsLocalHost("completely-different-server.domain.com"),
                "Remote FQDN should NOT be detected as local host");
        }

        [Theory]
        [InlineData(null)]
        [InlineData("")]
        [InlineData("   ")]
        public void IsLocalHost_NullOrEmpty_ReturnsFalse(string? hostname)
        {
            Assert.False(CHostNameHelper.IsLocalHost(hostname),
                "Null or empty hostname should return false");
        }

        [Fact]
        public void IsLocalHost_PartialMachineNameMatch_ReturnsFalse()
        {
            string partialMatch = Environment.MachineName + "-backup";
            Assert.False(CHostNameHelper.IsLocalHost(partialMatch),
                $"Partial match '{partialMatch}' should NOT be detected as local (no dot separator)");
        }
    }
}
