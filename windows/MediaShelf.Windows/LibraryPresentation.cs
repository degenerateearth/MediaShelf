namespace MediaShelf.Windows;

public static class LibraryPresentation
{
    // A later completed episode must not resurrect an earlier abandoned resume point.
    public static List<MediaItem> ContinueWatching(IEnumerable<MediaItem> media) => media
        .Where(x => x.PlaybackPosition > 0 || x.IsWatched)
        .GroupBy(x => x.Kind == "episode" ? "show:" + x.DisplayTitle.ToUpperInvariant() : "movie:" + x.Id)
        .Select(group => group.OrderByDescending(x => x.SeasonNumber ?? 0)
            .ThenByDescending(x => x.EpisodeNumber ?? 0).First())
        .Where(x => !x.IsWatched && x.PlaybackPosition > 0)
        .OrderByDescending(x => x.LastWatched ?? 0).ToList();
}
