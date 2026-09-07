using System.Net.Http.Json;
using System.Net.Http;
using System.Text.Json.Serialization;

namespace MediaShelf.Windows;

public sealed class ArtworkMatcher
{
    private readonly PortablePaths _paths;
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(12) };
    public ArtworkMatcher(PortablePaths paths) => _paths = paths;

    public async Task EnrichAsync(LibraryDatabase database, IReadOnlyList<MediaItem> media, CancellationToken cancellationToken = default)
    {
        foreach (var group in media.Where(x => x.PosterPath is null || x.BackdropPath is null).GroupBy(x => new { Title = x.DisplayTitle, x.Kind }))
        {
            var representative = group.First();
            if (group.All(x => x.PosterPath is not null && x.BackdropPath is not null)) continue;
            try
            {
                var type = representative.Kind == "movie" ? "movie" : "series";
                var encoded = Uri.EscapeDataString(representative.DisplayTitle);
                var response = await Http.GetFromJsonAsync<CatalogResponse>($"https://v3-cinemeta.strem.io/catalog/{type}/top/search={encoded}.json", cancellationToken);
                var expected = Normalize(representative.DisplayTitle);
                var matches = response?.Metas?.Where(x => Normalize(x.Name) == expected).ToList() ?? [];
                var match = representative.Year is int year ? matches.FirstOrDefault(x => ExtractYear(x.ReleaseInfo) == year) : matches.Count == 1 ? matches[0] : null;
                if (match is null) continue;
                var poster = await DownloadAsync(match.Poster, representative.Id, "poster", cancellationToken);
                var backdrop = await DownloadAsync(match.Background, representative.Id, "backdrop", cancellationToken);
                foreach (var item in group)
                {
                    database.ApplyProviderMetadata(item.Id, match.Description, match.Genres is null ? null : string.Join(", ", match.Genres), ExtractYear(match.ReleaseInfo));
                    if (poster is not null) database.SetArtwork(item.Id, "poster", poster);
                    if (backdrop is not null) database.SetArtwork(item.Id, "backdrop", backdrop);
                }
            }
            catch { /* Artwork is best-effort; scanning remains fully usable offline. */ }
        }
    }

    private async Task<string?> DownloadAsync(string? source, string mediaId, string role, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(source)) return null;
        var bytes = await Http.GetByteArrayAsync(source, token);
        var directory = Path.Combine(_paths.Artwork, mediaId);
        Directory.CreateDirectory(directory);
        var destination = Path.Combine(directory, role + ".jpg");
        await File.WriteAllBytesAsync(destination, bytes, token);
        return destination;
    }
    private static string Normalize(string? value) => new string((value ?? "").Where(char.IsLetterOrDigit).ToArray()).ToLowerInvariant();
    private static int? ExtractYear(string? value) => int.TryParse((value ?? "").Split('-', ' ', '.').FirstOrDefault(x => x.Length == 4), out var year) ? year : null;
    private sealed class CatalogResponse { [JsonPropertyName("metas")] public List<CatalogItem>? Metas { get; set; } }
    private sealed class CatalogItem { public string Name { get; set; } = ""; public string? Poster { get; set; } public string? Background { get; set; } public string? Description { get; set; } public string? ReleaseInfo { get; set; } public List<string>? Genres { get; set; } }
}
