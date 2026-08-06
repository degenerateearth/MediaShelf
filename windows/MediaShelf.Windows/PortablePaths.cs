using System.Text.Json;

namespace MediaShelf.Windows;

public sealed class PortablePaths
{
    public string Root { get; }
    public string Database => Path.Combine(Root, "library.sqlite");
    public string Artwork => Path.Combine(Root, "Artwork");
    public string Backups => Path.Combine(Root, "Backups");
    public string Cache => Path.Combine(Root, "Cache");
    public string Playback => Path.Combine(Root, "Playback");
    public string Settings => Path.Combine(Root, "Settings");
    public string Thumbnails => Path.Combine(Root, "Thumbnails");
    public string WindowsRootsFile => Path.Combine(Settings, "windows-library-paths.json");

    private PortablePaths(string root) => Root = root;

    public static PortablePaths FromExecutable()
    {
        var exeDirectory = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        var parent = Directory.GetParent(exeDirectory)?.FullName ?? exeDirectory;
        // Works both beside MediaShelf.exe and from the recommended MediaShelf-Windows folder.
        var root = string.Equals(Path.GetFileName(exeDirectory), "MediaShelf-Windows", StringComparison.OrdinalIgnoreCase)
            ? Path.Combine(parent, "MediaShelf Data")
            : Path.Combine(exeDirectory, "MediaShelf Data");
        var paths = new PortablePaths(root);
        foreach (var directory in new[] { paths.Root, paths.Artwork, paths.Backups, paths.Cache, paths.Playback, paths.Settings, paths.Thumbnails })
            Directory.CreateDirectory(directory);
        return paths;
    }

    public Dictionary<string, string> LoadWindowsRoots()
    {
        try { return JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(WindowsRootsFile)) ?? new(); }
        catch { return new(); }
    }

    public void SaveWindowsRoots(Dictionary<string, string> roots)
    {
        var temporary = WindowsRootsFile + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(roots, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temporary, WindowsRootsFile, true);
    }

    public string? ResolvePortableAsset(string? storedPath)
    {
        if (string.IsNullOrWhiteSpace(storedPath)) return null;
        if (File.Exists(storedPath)) return storedPath;
        var normalized = storedPath.Replace('\\', '/');
        var marker = "/MediaShelf Data/";
        var index = normalized.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
        if (index < 0) return null;
        var relative = normalized[(index + marker.Length)..];
        var candidate = Path.Combine(Root, relative.Replace('/', Path.DirectorySeparatorChar));
        return File.Exists(candidate) ? candidate : null;
    }
}
