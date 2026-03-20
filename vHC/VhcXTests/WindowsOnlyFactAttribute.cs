using System.Runtime.InteropServices;
using Xunit;

/// <summary>Skips the test on non-Windows platforms.</summary>
public sealed class WindowsOnlyFactAttribute : FactAttribute
{
    public WindowsOnlyFactAttribute()
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            Skip = "Windows-only test";
    }
}

/// <summary>Skips the theory on non-Windows platforms.</summary>
public sealed class WindowsOnlyTheoryAttribute : TheoryAttribute
{
    public WindowsOnlyTheoryAttribute()
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            Skip = "Windows-only test";
    }
}
