// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System;
using System.Text;
using VeeamHealthCheck.Shared;
using VeeamHealthCheck.Startup;

namespace VeeamHealthCheck.Functions.Collection.Security
{
    /// <summary>
    /// CLI (console-only) implementation of ICredentialProvider.
    /// Used when running headless or without a WPF application context.
    /// The WPF shell (HC_Reporting) registers its own GUI-capable provider at startup.
    /// </summary>
    internal class CliCredentialProvider : ICredentialProvider
    {
        public (string Username, string Password)? GetCreds()
        {
            string host = string.IsNullOrEmpty(CGlobals.REMOTEHOST) ? "localhost" : CGlobals.REMOTEHOST;

            // Check if user requested to clear stored credentials
            if (CGlobals.ClearStoredCreds)
            {
                CGlobals.Logger.Info("Clearing stored credentials as requested by user", false);
                CredentialStore.Clear();
                CGlobals.ClearStoredCreds = false;
            }

            // First, check if we have stored credentials
            var stored = CredentialStore.Get(host);
            if (stored != null)
            {
                CGlobals.Logger.Debug($"Using stored credentials for host: {host}");
                return stored;
            }

            // Prompt via console
            var creds = PromptForCredentialsCli(host);
            if (creds == null)
            {
                CGlobals.Logger.Error("Credentials not provided. Aborting.", false);
            }

            return creds;
        }

        private static (string Username, string Password)? PromptForCredentialsCli(string host)
        {
            CGlobals.Logger.Info($"Credentials required for host: {host}", false);

            try
            {
                Console.WriteLine();
                Console.WriteLine($"=== Authentication Required for {host} ===");
                Console.Write("Username: ");
                string? username = Console.ReadLine();

                if (string.IsNullOrWhiteSpace(username))
                {
                    CGlobals.Logger.Warning("Username cannot be empty.");
                    return null;
                }

                Console.Write("Password: ");
                string password = ReadPasswordMasked();
                Console.WriteLine();

                if (string.IsNullOrEmpty(password))
                {
                    CGlobals.Logger.Warning("Password cannot be empty.");
                    return null;
                }

                CredentialStore.Set(host, username, password);
                CGlobals.Logger.Info($"Credentials stored for host: {host}", false);

                return (username, password);
            }
            catch (Exception ex)
            {
                CGlobals.Logger.Error($"Error reading credentials: {ex.Message}");
                return null;
            }
        }

        private static string ReadPasswordMasked()
        {
            var password = new StringBuilder();

            while (true)
            {
                var keyInfo = Console.ReadKey(intercept: true);

                if (keyInfo.Key == ConsoleKey.Enter)
                {
                    break;
                }
                else if (keyInfo.Key == ConsoleKey.Backspace)
                {
                    if (password.Length > 0)
                    {
                        password.Remove(password.Length - 1, 1);
                        Console.Write("\b \b");
                    }
                }
                else if (!char.IsControl(keyInfo.KeyChar))
                {
                    password.Append(keyInfo.KeyChar);
                    Console.Write("*");
                }
            }

            return password.ToString();
        }
    }
}
