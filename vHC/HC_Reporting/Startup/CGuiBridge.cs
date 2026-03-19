// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using VeeamHealthCheck.Resources.Localization;

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
