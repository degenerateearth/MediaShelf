using System.Text.RegularExpressions;

namespace MediaShelf.Windows;

public sealed partial class FilenameParser
{
    private static readonly HashSet<string> ReleaseTokens = new(StringComparer.OrdinalIgnoreCase)
    {
        "480p", "720p", "1080p", "1080i", "2160p", "4k", "uhd", "bluray", "brrip", "bdrip",
        "web-dl", "webdl", "webrip", "hdtv", "remux", "x264", "x265", "h264", "h265", "hevc",
        "av1", "hdr", "hdr10", "dv", "dolbyvision", "aac", "ac3", "eac3", "dts", "truehd",
        "atmos", "10bit", "proper", "repack", "extended"
    };

    private static readonly Regex[] EpisodePatterns =
    {
        new(@"^(.*?)[\s._-]+S(\d{1,2})E(\d{1,3})(?:[\s._-]+(.*))?$", RegexOptions.IgnoreCase | RegexOptions.Compiled),
        new(@"^(.*?)[\s._-]+(\d{1,2})x(\d{1,3})(?:[\s._-]+(.*))?$", RegexOptions.IgnoreCase | RegexOptions.Compiled)
    };
    private static readonly Regex SeasonOnly = new(@"^(.*?)[\s._-]+(?:(19\d{2}|20\d{2})[\s._-]+)?S(\d{1,2})(?:[\s._-]+(.*))?$", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex YearPattern = new(@"(?<!\d)(19\d{2}|20\d{2})(?!\d)", RegexOptions.Compiled);

    public ParsedFilename Parse(string path)
    {
        var value = Regex.Replace(Path.GetFileNameWithoutExtension(path), @"\[[^\]]*\]|\{[^}]*\}", " ");
        foreach (var expression in EpisodePatterns)
        {
            var match = expression.Match(value);
            if (!match.Success) continue;
            return new("episode", Clean(match.Groups[1].Value), null,
                int.Parse(match.Groups[2].Value), int.Parse(match.Groups[3].Value),
                NullIfEmpty(Clean(match.Groups[4].Value)));
        }
        var season = SeasonOnly.Match(value);
        if (season.Success)
            return new("episode", Clean(season.Groups[1].Value), ParseInt(season.Groups[2].Value),
                ParseInt(season.Groups[3].Value), null, NullIfEmpty(Clean(season.Groups[4].Value)));

        var year = YearPattern.Match(value);
        return new("movie", Clean(year.Success ? value[..year.Index] : value),
            year.Success ? int.Parse(year.Value) : null, null, null, null);
    }

    private static string Clean(string value)
    {
        var words = Regex.Replace(value.Replace('.', ' ').Replace('_', ' '), @"[()\[\]{}]", " ")
            .Split(new[] { ' ', '\t', '\r', '\n', '-' }, StringSplitOptions.RemoveEmptyEntries);
        return string.Join(" ", words.TakeWhile(word => !ReleaseTokens.Contains(word.Trim('.', ',', ';', ':')))).Trim(' ', '.', ',', '-', '_');
    }
    private static int? ParseInt(string value) => int.TryParse(value, out var result) ? result : null;
    private static string? NullIfEmpty(string value) => string.IsNullOrWhiteSpace(value) ? null : value;
}
