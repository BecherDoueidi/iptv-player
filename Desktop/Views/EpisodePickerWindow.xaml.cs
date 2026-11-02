using System.Windows;
using System.Windows.Controls;
using IPTVPlayer.Desktop.Core;

namespace IPTVPlayer.Desktop.Views;

public partial class EpisodePickerWindow : Window
{
    private readonly List<SeriesEpisode> _episodes;

    public SeriesEpisode? Selected { get; private set; }

    /// <summary>Wrapper so the list shows "3. Episode title" rather than a type name.</summary>
    private sealed record Row(SeriesEpisode Episode)
    {
        public override string ToString() => $"{Episode.EpisodeNumber}.  {Episode.Title}";
    }

    public EpisodePickerWindow(string seriesTitle, List<SeriesEpisode> episodes)
    {
        InitializeComponent();
        Title = seriesTitle;
        _episodes = episodes;

        var seasons = episodes.Select(e => e.SeasonNumber).Distinct().OrderBy(n => n).ToList();
        SeasonPicker.ItemsSource = seasons;
        SeasonPicker.SelectedIndex = 0;
    }

    private void OnSeasonChanged(object sender, SelectionChangedEventArgs e)
    {
        if (SeasonPicker.SelectedItem is not int season) return;
        EpisodeList.ItemsSource = _episodes
            .Where(x => x.SeasonNumber == season)
            .Select(x => new Row(x))
            .ToList();
        if (EpisodeList.Items.Count > 0) EpisodeList.SelectedIndex = 0;
    }

    private void OnPlay(object sender, RoutedEventArgs e)
    {
        if (EpisodeList.SelectedItem is not Row row) return;
        Selected = row.Episode;
        DialogResult = true;
    }

    private void OnCancel(object sender, RoutedEventArgs e) => DialogResult = false;
}
