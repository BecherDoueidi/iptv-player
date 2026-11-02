using System.Windows;
using LibVLCSharp.Shared;

namespace IPTVPlayer.Desktop;

public partial class App : Application
{
    /// <summary>
    /// One LibVLC instance for the whole process. Creating one per player leaks native
    /// resources and is slow; VLC is designed to be initialised once.
    /// </summary>
    public static LibVLC? LibVlc { get; private set; }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        try
        {
            LibVLCSharp.Shared.Core.Initialize();
            // --network-caching smooths over the panel's habit of stalling mid-stream;
            // the default is tuned for local files, not a flaky remote server.
            LibVlc = new LibVLC("--network-caching=2000", "--no-video-title-show");
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                $"The video engine failed to start, so playback won't work.\n\n{ex.Message}",
                "IPTV Player",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        LibVlc?.Dispose();
        base.OnExit(e);
    }
}
