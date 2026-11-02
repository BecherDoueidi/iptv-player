using System.Windows;
using System.Windows.Threading;
using IPTVPlayer.Desktop.Core;
using LibVLCSharp.Shared;

namespace IPTVPlayer.Desktop.Views;

public partial class PlayerWindow : Window
{
    /// <summary>
    /// VLC will sit on a dead URL indefinitely without reporting an error — that is
    /// how an unavailable episode becomes a spinner that never resolves. Learned the
    /// hard way on iOS; built in from the start here.
    /// </summary>
    private static readonly TimeSpan StartTimeout = TimeSpan.FromSeconds(25);

    private readonly MediaPlayer? _player;
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(500) };
    private readonly DateTime _startedAt = DateTime.UtcNow;
    private readonly Uri _url;
    private bool _hasStarted;

    public PlayerWindow(Uri url, string title)
    {
        InitializeComponent();
        _url = url;
        Title = title;
        StatusDetail.Text = XtreamClient.Redact(url);

        if (App.LibVlc is null)
        {
            ShowFailure("The video engine isn't available.");
            return;
        }

        _player = new MediaPlayer(App.LibVlc);
        VideoView.MediaPlayer = _player;

        using var media = new Media(App.LibVlc, url);
        _player.Play(media);

        _timer.Tick += OnTick;
        _timer.Start();
    }

    private void OnTick(object? sender, EventArgs e)
    {
        if (_player is null) return;

        // Actual progress, not VLC's state flag: the flag frequently reads "buffering"
        // through perfectly healthy playback.
        if (_player.IsPlaying && _player.Time > 0)
        {
            _hasStarted = true;
            StatusOverlay.Visibility = Visibility.Collapsed;
            TimeLabel.Text = Format(_player.Time) + (_player.Length > 0 ? " / " + Format(_player.Length) : "");
        }

        if (_player.State == VLCState.Error)
        {
            ShowFailure("VLC couldn't open this stream.");
            return;
        }

        if (!_hasStarted && DateTime.UtcNow - _startedAt > StartTimeout)
        {
            ShowFailure("The stream didn't start. The server may not have this title at "
                      + "this address, or all your account's connections are in use.");
        }
    }

    private void ShowFailure(string message)
    {
        _timer.Stop();
        StatusOverlay.Visibility = Visibility.Visible;
        StatusText.Text = message;
        StatusDetail.Text = XtreamClient.Redact(_url);
    }

    private static string Format(long milliseconds)
    {
        var span = TimeSpan.FromMilliseconds(Math.Max(milliseconds, 0));
        return span.TotalHours >= 1
            ? $"{(int)span.TotalHours}:{span.Minutes:D2}:{span.Seconds:D2}"
            : $"{span.Minutes}:{span.Seconds:D2}";
    }

    private void OnPlayPause(object sender, RoutedEventArgs e)
    {
        if (_player is null) return;
        if (_player.IsPlaying)
        {
            _player.Pause();
            PlayPauseButton.Content = "Play";
        }
        else
        {
            _player.Play();
            PlayPauseButton.Content = "Pause";
        }
    }

    private void OnBack(object sender, RoutedEventArgs e) => Seek(-10_000);

    private void OnForward(object sender, RoutedEventArgs e) => Seek(10_000);

    private void Seek(long deltaMilliseconds)
    {
        if (_player is null || _player.Length <= 0) return;
        _player.Time = Math.Clamp(_player.Time + deltaMilliseconds, 0, _player.Length);
    }

    protected override void OnClosed(EventArgs e)
    {
        _timer.Stop();
        if (_player is not null)
        {
            _player.Stop();
            // Detached before disposal: VideoView holds a reference, and disposing the
            // player while it is still attached crashes on the native side.
            VideoView.MediaPlayer = null;
            _player.Dispose();
        }
        base.OnClosed(e);
    }
}
