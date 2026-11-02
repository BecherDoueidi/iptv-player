using System.Windows;
using System.Windows.Controls;
using IPTVPlayer.Desktop.Core;
using IPTVPlayer.Desktop.Views;

namespace IPTVPlayer.Desktop;

public partial class MainWindow : Window
{
    private readonly XtreamClient _client = new();
    private readonly CredentialStore _credentials = new();

    private XtreamCredentials? _signedIn;
    private CatalogCache? _cache;
    private ContentKind _kind = ContentKind.Movie;

    /// <summary>Everything loaded for the current kind, before section or search filtering.</summary>
    private readonly Dictionary<ContentKind, List<MediaCategory>> _categories = new();
    private readonly Dictionary<ContentKind, List<CatalogItem>> _items = new();

    /// <summary>A row in the item list: a movie, a series, or a channel.</summary>
    private sealed record CatalogItem(string Id, string Title, string? CategoryId, string? ContainerExtension)
    {
        public override string ToString() => Title;
    }

    private sealed record SectionRow(string? CategoryId, string Title, int Count)
    {
        public override string ToString() => $"{Title}  ({Count})";
    }

    public MainWindow()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
        => await Guarded("restore session", async () =>
        {
            var saved = _credentials.Load();
            if (saved is null) return;
            await SignInAsync(saved, persist: false);
        });

    /// <summary>
    /// WPF terminates the process when an exception escapes an `async void` event
    /// handler — which is precisely how this app died on its first run, leaving only
    /// an "unhandled .NET exception" in Windows Error Reporting. Every handler runs
    /// through here so a failure becomes a status line and a log entry instead.
    /// </summary>
    private async Task Guarded(string context, Func<Task> work)
    {
        try
        {
            await work();
        }
        catch (XtreamException ex)
        {
            StatusBar.Text = ex.Message;
            ErrorLog.Write(context, ex);
        }
        catch (Exception ex)
        {
            StatusBar.Text = $"Something went wrong ({ex.GetType().Name}). Details in {ErrorLog.FilePath}";
            ErrorLog.Write(context, ex);
        }
    }

    // MARK: - Sign in

    private async void OnSignIn(object sender, RoutedEventArgs e)
        => await Guarded("sign in", async () =>
    {
        var url = CredentialStore.NormaliseServerUrl(ServerBox.Text);
        if (url is null)
        {
            ShowLoginError("That server address doesn't look right.");
            return;
        }
        if (UsernameBox.Text.Trim().Length == 0 || PasswordBox.Password.Length == 0)
        {
            ShowLoginError("Enter your username and password.");
            return;
        }

        // Trimmed: credentials copied from a provider email routinely carry trailing
        // whitespace, and the panel rejects them without saying why.
        await SignInAsync(new XtreamCredentials(url, UsernameBox.Text.Trim(), PasswordBox.Password.Trim()),
                          persist: true);
    });

    private async Task SignInAsync(XtreamCredentials credentials, bool persist)
    {
        SignInButton.IsEnabled = false;
        LoginError.Visibility = Visibility.Collapsed;

        try
        {
            var account = await _client.AuthenticateAsync(credentials);
            if (!account.IsAuthenticated)
            {
                ShowLoginError(account.Message ?? "The server rejected those details.");
                return;
            }

            _signedIn = credentials;
            _cache = new CatalogCache(SourceId.Make(credentials.ServerUrl, credentials.Username));
            if (persist) _credentials.Save(credentials);

            LoginPanel.Visibility = Visibility.Collapsed;
            CatalogPanel.Visibility = Visibility.Visible;
            ShowConnectionStatus(account);

            await LoadKindAsync(_kind);
        }
        catch (XtreamException ex)
        {
            ShowLoginError(ex.Message);
        }
        finally
        {
            SignInButton.IsEnabled = true;
        }
    }

    private void ShowLoginError(string message)
    {
        LoginError.Text = message;
        LoginError.Visibility = Visibility.Visible;
    }

    private void ShowConnectionStatus(AccountInfo account)
    {
        if (account.MaxConnections is not { } max) return;
        var active = account.ActiveConnections ?? 0;
        var expiry = account.ExpiresAt is { } date ? $"   ·   Expires {date:d MMM yyyy}" : "";
        StatusBar.Text = $"{active} of {max} connections in use{expiry}";
    }

    private void OnSignOut(object sender, RoutedEventArgs e)
    {
        _credentials.Clear();
        _cache?.Clear();
        _signedIn = null;
        _categories.Clear();
        _items.Clear();
        SectionList.ItemsSource = null;
        ItemList.ItemsSource = null;
        PasswordBox.Clear();
        CatalogPanel.Visibility = Visibility.Collapsed;
        LoginPanel.Visibility = Visibility.Visible;
    }

    // MARK: - Catalog

    private async void OnKindChanged(object sender, RoutedEventArgs e)
        => await Guarded("switch tab", async () =>
        {
            if (_signedIn is null) return;
            _kind = MoviesTab.IsChecked == true ? ContentKind.Movie
                  : SeriesTab.IsChecked == true ? ContentKind.Series
                  : ContentKind.Live;
            await LoadKindAsync(_kind);
        });

    private async void OnRefresh(object sender, RoutedEventArgs e)
        => await Guarded("refresh", () => RefreshKindAsync(_kind));

    private async Task LoadKindAsync(ContentKind kind)
    {
        if (_cache is null) return;

        // Cache first, so sections and titles are on screen immediately and stay there
        // even if the refresh below is slow or fails outright.
        if (!_categories.ContainsKey(kind))
        {
            var cachedCategories = await _cache.LoadAsync<List<MediaCategory>>($"{kind.Raw()}.categories");
            var cachedItems = await _cache.LoadAsync<List<CatalogItem>>($"{kind.Raw()}.items");
            if (cachedCategories is { Count: > 0 }) _categories[kind] = cachedCategories;
            if (cachedItems is { Count: > 0 }) _items[kind] = cachedItems;
        }

        RenderSections();
        if (!_items.ContainsKey(kind)) await RefreshKindAsync(kind);
    }

    private async Task RefreshKindAsync(ContentKind kind)
    {
        if (_signedIn is null || _cache is null) return;

        StatusBar.Text = "Loading…";
        try
        {
            var categories = await _client.GetCategoriesAsync(_signedIn, kind);
            var items = kind switch
            {
                ContentKind.Movie => (await _client.GetMoviesAsync(_signedIn))
                    .Select(m => new CatalogItem(m.Id, m.Title, m.CategoryId, m.ContainerExtension)).ToList(),
                ContentKind.Series => (await _client.GetSeriesAsync(_signedIn))
                    .Select(s => new CatalogItem(s.Id, s.Title, s.CategoryId, null)).ToList(),
                _ => (await _client.GetLiveChannelsAsync(_signedIn))
                    .Select(c => new CatalogItem(c.Id, c.Name, c.CategoryId, null)).ToList()
            };

            // An empty list from a flaky refresh must not wipe what is already shown.
            if (categories.Count > 0) _categories[kind] = categories;
            if (items.Count > 0) _items[kind] = items;

            RenderSections();
            StatusBar.Text = $"{items.Count:N0} items   ·   {categories.Count:N0} sections";

            await _cache.SaveAsync($"{kind.Raw()}.categories", _categories[kind]);
            await _cache.SaveAsync($"{kind.Raw()}.items", _items[kind]);
        }
        catch (XtreamException ex)
        {
            StatusBar.Text = _items.ContainsKey(kind)
                ? $"{ex.Message}  Showing what was saved locally."
                : ex.Message;
        }
    }

    private void RenderSections()
    {
        var items = _items.GetValueOrDefault(_kind) ?? [];
        var categories = _categories.GetValueOrDefault(_kind) ?? [];

        // Counted in one pass. Asking each row to filter the whole catalog is O(items x
        // sections) per render, which on iOS froze the UI outright on a real catalog.
        var counts = new Dictionary<string, int>();
        foreach (var item in items)
        {
            if (item.CategoryId is null) continue;
            counts[item.CategoryId] = counts.GetValueOrDefault(item.CategoryId) + 1;
        }

        var rows = new List<SectionRow> { new(null, "All", items.Count) };
        rows.AddRange(categories.Select(c => new SectionRow(c.Id, c.Name, counts.GetValueOrDefault(c.Id))));

        SectionList.ItemsSource = rows;
        if (SectionList.SelectedIndex < 0 && rows.Count > 0) SectionList.SelectedIndex = 0;
        RenderItems();
    }

    private void OnSectionChanged(object sender, SelectionChangedEventArgs e) => RenderItems();

    private void OnSearchChanged(object sender, TextChangedEventArgs e) => RenderItems();

    private void RenderItems()
    {
        var items = _items.GetValueOrDefault(_kind) ?? [];
        var query = SearchBox.Text.Trim();

        IEnumerable<CatalogItem> filtered = items;

        // Search spans the whole catalog rather than the selected section: being told
        // "no results" for something that exists, because of which section happened to
        // be selected, is the wrong behaviour.
        if (query.Length > 0)
        {
            filtered = filtered.Where(i => i.Title.Contains(query, StringComparison.OrdinalIgnoreCase));
            ItemsHeader.Text = $"Search results for “{query}”";
        }
        else if (SectionList.SelectedItem is SectionRow { CategoryId: { } categoryId })
        {
            filtered = filtered.Where(i => i.CategoryId == categoryId);
            ItemsHeader.Text = (SectionList.SelectedItem as SectionRow)?.Title ?? "";
        }
        else
        {
            ItemsHeader.Text = "All";
        }

        ItemList.ItemsSource = filtered.Take(2000).ToList();
    }

    // MARK: - Playback

    private async void OnItemActivated(object sender, System.Windows.Input.MouseButtonEventArgs e)
        => await Guarded("open item", async () =>
    {
        if (_signedIn is null || ItemList.SelectedItem is not CatalogItem item) return;

        if (_kind == ContentKind.Series)
        {
            await ShowEpisodesAsync(item);
            return;
        }

        var url = _kind == ContentKind.Movie
            ? XtreamClient.MovieStreamUrl(_signedIn, item.Id, item.ContainerExtension)
            : XtreamClient.LiveStreamUrl(_signedIn, item.Id);

        new PlayerWindow(url, item.Title) { Owner = this }.Show();
    });

    private async Task ShowEpisodesAsync(CatalogItem series)
    {
        if (_signedIn is null) return;

        StatusBar.Text = $"Loading episodes for {series.Title}…";
        try
        {
            var episodes = await _client.GetEpisodesAsync(_signedIn, series.Id);
            if (episodes.Count == 0)
            {
                StatusBar.Text = $"{series.Title} has no episodes listed on the server.";
                return;
            }

            var picker = new EpisodePickerWindow(series.Title, episodes) { Owner = this };
            if (picker.ShowDialog() == true && picker.Selected is { } episode)
            {
                var url = XtreamClient.EpisodeStreamUrl(_signedIn, episode.Id, episode.ContainerExtension);
                new PlayerWindow(url, $"{series.Title} — {episode.Title}") { Owner = this }.Show();
            }
            StatusBar.Text = "";
        }
        catch (XtreamException ex)
        {
            StatusBar.Text = ex.Message;
        }
    }
}
