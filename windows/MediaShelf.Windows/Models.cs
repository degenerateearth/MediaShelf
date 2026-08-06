namespace MediaShelf.Windows;

public sealed record LibraryFolder(string Id, string DisplayName, string StoredPath, bool Enabled, double DateAdded, double? LastScanned, string Availability);

public sealed class MediaItem
{
    public string Id { get; init; } = "";
    public string LibraryId { get; init; } = "";
    public string Kind { get; init; } = "movie";
    public string AbsolutePath { get; init; } = "";
    public string RelativePath { get; init; } = "";
    public string Filename { get; init; } = "";
    public string DisplayTitle { get; init; } = "";
    public string? SortTitle { get; init; }
    public int? Year { get; init; }
    public int? SeasonNumber { get; init; }
    public int? EpisodeNumber { get; init; }
    public string? EpisodeTitle { get; init; }
    public string? Summary { get; init; }
    public string? Genre { get; init; }
    public double? Runtime { get; init; }
    public double DateAdded { get; init; }
    public double? LastWatched { get; init; }
    public double PlaybackPosition { get; init; }
    public bool IsWatched { get; init; }
    public bool IsFavorite { get; init; }
    public string? PosterPath { get; init; }
    public string? BackdropPath { get; init; }
    public bool IsAvailable { get; init; }
    public string CardSubtitle => Kind == "episode"
        ? $"Season {SeasonNumber ?? 0} · {EpisodeCountLabel}"
        : Year?.ToString() ?? "Movie";
    public string EpisodeCountLabel { get; set; } = "TV Show";
    public string FavoriteGlyph => IsFavorite ? "★" : "☆";
    public string ProgressLabel => IsWatched ? "Watched" : PlaybackPosition > 0 ? $"Resume at {TimeSpan.FromSeconds(PlaybackPosition):h\\:mm\\:ss}" : "";
}

public sealed record ParsedFilename(string Kind, string Title, int? Year, int? Season, int? Episode, string? EpisodeTitle);
public sealed record ScanCandidate(string Id, string LibraryId, string AbsolutePath, string RelativePath, string Filename, long FileSize, double ModifiedAt, ParsedFilename Parsed, string? Poster, string? Backdrop);
