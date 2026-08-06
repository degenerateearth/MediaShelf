using System.Security.Cryptography;
using System.Text;

namespace MediaShelf.Windows;

public sealed class MediaScanner
{
    private static readonly HashSet<string> Extensions = new(StringComparer.OrdinalIgnoreCase) { ".mp4", ".mkv", ".m4v", ".mov" };
    private readonly FilenameParser _parser = new();

    public IReadOnlyList<ScanCandidate> Scan(string libraryId, string root, Action<string>? warning = null)
    {
        var candidates = new List<ScanCandidate>();
        IEnumerable<string> files;
        try { files = Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories); }
        catch (Exception error) { warning?.Invoke(error.Message); return candidates; }
        foreach (var file in files)
        {
            if (!Extensions.Contains(Path.GetExtension(file))) continue;
            try
            {
                var info = new FileInfo(file);
                var relative = Path.GetRelativePath(root, file).Replace('\\', '/');
                var directory = info.DirectoryName!;
                var poster = FirstExisting(directory, "poster.jpg", "poster.jpeg", "poster.png", "folder.jpg", "cover.jpg");
                var backdrop = FirstExisting(directory, "backdrop.jpg", "fanart.jpg", "background.jpg");
                candidates.Add(new(StableId(libraryId, relative, info.Length), libraryId, info.FullName, relative,
                    info.Name, info.Length, new DateTimeOffset(info.LastWriteTimeUtc).ToUnixTimeMilliseconds() / 1000.0,
                    _parser.Parse(file), poster, backdrop));
            }
            catch (Exception error) { warning?.Invoke($"{Path.GetFileName(file)}: {error.Message}"); }
        }
        return candidates;
    }

    public static string StableId(string libraryId, string relativePath, long size)
    {
        var input = $"{libraryId.ToLowerInvariant()}|{relativePath.Replace('\\', '/').ToLowerInvariant()}|{size}";
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(input)).AsSpan(0, 16)).ToLowerInvariant();
    }
    private static string? FirstExisting(string directory, params string[] names) =>
        names.Select(name => Path.Combine(directory, name)).FirstOrDefault(File.Exists);
}
