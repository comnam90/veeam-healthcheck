// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System.Diagnostics;

namespace VeeamHealthCheck.Shared
{
    class CVersionSetter
    {
        public CVersionSetter()
        {
        }

        public static string GetFileVersion()
        {
            string exePath = Process.GetCurrentProcess().MainModule.FileName;

            FileVersionInfo fvi = FileVersionInfo.GetVersionInfo(exePath);
            CGlobals.VHCVERSION = fvi.FileVersion;
            return fvi.FileVersion;
        }
    }
}
