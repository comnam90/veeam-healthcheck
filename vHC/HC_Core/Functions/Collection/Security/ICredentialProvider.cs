// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License

namespace VeeamHealthCheck.Functions.Collection.Security
{
    /// <summary>
    /// Abstraction for credential prompting, allowing GUI and CLI implementations.
    /// The default (CLI) implementation is registered in CGlobals at startup.
    /// The WPF shell registers its own implementation that shows a dialog.
    /// </summary>
    public interface ICredentialProvider
    {
        (string Username, string Password)? GetCreds();
    }
}
