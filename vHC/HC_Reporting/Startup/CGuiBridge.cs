// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using VeeamHealthCheck.Resources.Localization;
using VeeamHealthCheck.Shared;

namespace VeeamHealthCheck.Startup
{
    /// <summary>
    /// GUI-only methods extracted from CClientFunctions.
    /// These remain in the WPF shell project and must not move to HC_Core.
    /// </summary>
    internal static class CGuiBridge
    {
        public static void KbLinkAction(System.Windows.Navigation.RequestNavigateEventArgs args)
        {
            CGlobals.Logger.Info("[GUI]\tOpening KB Link");
            Application.Current.Dispatcher.Invoke(delegate
            {
                WebBrowser w1 = new();

                var p = new Process();
                p.StartInfo = new ProcessStartInfo(args.Uri.ToString())
                {
                    UseShellExecute = true
                };
                p.Start();
            });
            CGlobals.Logger.Info("[GUI]\tOpening KB Link...done!");
        }

        /// <summary>
        /// Shows a Yes/No dialog asking the user whether to continue without admin privileges.
        /// Registered as CGlobals.GuiAdminContinuePrompt by VhcGui at startup.
        /// </summary>
        public static bool ConfirmContinueWithoutAdmin(string message)
        {
            var result = MessageBox.Show(
                message,
                "Administrator Privileges Recommended",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);
            return result == MessageBoxResult.Yes;
        }

        public static bool AcceptTerms()
        {
            string message = VbrLocalizationHelper.GuiAcceptText;

            var res = MessageBox.Show(message, "Terms", MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (res.ToString() == "Yes")
            {
                return true;
            }
            else
            {
                return false;
            }
        }
    }
}
