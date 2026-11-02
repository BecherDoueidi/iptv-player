using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using IPTVPlayer.Desktop.Core;
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
        InstallCrashHandlers();

        try
        {
            LibVLCSharp.Shared.Core.Initialize();
            // --network-caching smooths over the panel's habit of stalling mid-stream;
            // the default is tuned for local files, not a flaky remote server.
            LibVlc = new LibVLC("--network-caching=2000", "--no-video-title-show");
        }
        catch (Exception ex)
        {
            ErrorLog.Write("LibVLC initialisation", ex);
            MessageBox.Show(
                $"The video engine failed to start, so playback won't work.\n\n{ex.Message}",
                "IPTV Player",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }

        if (e.Args.Contains("--smoke"))
        {
            _ = RunSmokeTestAsync();
        }
    }

    /// <summary>
    /// An unhandled exception on the UI thread kills a WPF app outright, which is
    /// exactly what happened on the first run here — leaving nothing but a Windows
    /// Error Reporting entry. Showing it and carrying on is far more useful than
    /// vanishing, and the log means a failure is diagnosable after the fact.
    /// </summary>
    private void InstallCrashHandlers()
    {
        DispatcherUnhandledException += (_, args) =>
        {
            ErrorLog.Write("Unhandled UI exception", args.Exception);
            MessageBox.Show(
                $"Something went wrong:\n\n{args.Exception.Message}\n\nDetails were written to:\n{ErrorLog.FilePath}",
                "IPTV Player",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            args.Handled = true;
        };

        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
        {
            if (args.ExceptionObject is Exception ex) ErrorLog.Write("Unhandled background exception", ex);
        };

        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            ErrorLog.Write("Unobserved task exception", args.Exception);
            args.SetObserved();
        };
    }

    /// <summary>
    /// Exercises every provider call against the saved account and writes a report,
    /// so the whole data layer can be verified without driving the UI by hand.
    /// Credentials are read from the encrypted store and never written to the report.
    /// </summary>
    private async Task RunSmokeTestAsync()
    {
        var report = new List<string> { $"Smoke test {DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss}" };
        var credentials = new CredentialStore().Load();

        if (credentials is null)
        {
            report.Add("FAIL  no saved credentials — sign in once first");
        }
        else
        {
            var client = new XtreamClient();
            report.Add($"server {credentials.ServerUrl.Host}:{credentials.ServerUrl.Port}");

            await Step(report, "authenticate", async () =>
            {
                var account = await client.AuthenticateAsync(credentials);
                return $"auth={account.IsAuthenticated} status={account.Status} "
                     + $"connections={account.ActiveConnections}/{account.MaxConnections}";
            });

            foreach (var kind in new[] { ContentKind.Movie, ContentKind.Series, ContentKind.Live })
            {
                await Step(report, $"{kind.Raw()} categories", async () =>
                    $"{(await client.GetCategoriesAsync(credentials, kind)).Count} sections");
            }

            await Step(report, "movies", async () =>
            {
                var movies = await client.GetMoviesAsync(credentials);
                var first = movies.FirstOrDefault();
                var url = first is null ? "—"
                    : XtreamClient.Redact(XtreamClient.MovieStreamUrl(credentials, first.Id, first.ContainerExtension));
                return $"{movies.Count} items; first url {url}";
            });

            await Step(report, "series", async () =>
            {
                var series = await client.GetSeriesAsync(credentials);
                var first = series.FirstOrDefault();
                if (first is null) return $"{series.Count} items";

                var episodes = await client.GetEpisodesAsync(credentials, first.Id);
                var episode = episodes.FirstOrDefault();
                var url = episode is null ? "—"
                    : XtreamClient.Redact(XtreamClient.EpisodeStreamUrl(credentials, episode.Id, episode.ContainerExtension));
                return $"{series.Count} items; first series has {episodes.Count} episodes; url {url}";
            });

            await Step(report, "live", async () =>
            {
                var channels = await client.GetLiveChannelsAsync(credentials);
                var first = channels.FirstOrDefault();
                var url = first is null ? "—"
                    : XtreamClient.Redact(XtreamClient.LiveStreamUrl(credentials, first.Id));
                return $"{channels.Count} channels; first url {url}";
            });
        }

        var path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "IPTVPlayer", "smoke-report.txt");
        System.IO.Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        await File.WriteAllLinesAsync(path, report);
        Shutdown();
    }

    private static async Task Step(List<string> report, string name, Func<Task<string>> work)
    {
        try
        {
            report.Add($"OK    {name}: {await work()}");
        }
        catch (Exception ex)
        {
            report.Add($"FAIL  {name}: {ex.GetType().Name}: {ex.Message}");
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        LibVlc?.Dispose();
        base.OnExit(e);
    }
}
