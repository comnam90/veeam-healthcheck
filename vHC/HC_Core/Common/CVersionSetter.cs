// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System;
using System.Diagnostics;

namespace VeeamHealthCheck.Shared
{
    class CVersionSetter
    {
        public CVersionSetter()
        {
        }

        public static string? GetFileVersion()
        {
            string? exePath = Process.GetCurrentProcess().MainModule?.FileName;
            if (string.IsNullOrEmpty(exePath))
                throw new InvalidOperationException("Cannot determine executable path: Process.MainModule is unavailable.");

            FileVersionInfo fvi = FileVersionInfo.GetVersionInfo(exePath);
            CGlobals.VHCVERSION = fvi.FileVersion ?? string.Empty;
            return fvi.FileVersion;
        }
    }
}
