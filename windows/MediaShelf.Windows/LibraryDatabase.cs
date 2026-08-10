using Microsoft.Data.Sqlite;

namespace MediaShelf.Windows;

public sealed class LibraryDatabase
{
    private readonly PortablePaths _paths;
    private readonly string _connectionString;
    public LibraryDatabase(PortablePaths paths)
    {
        _paths = paths;
        _connectionString = new SqliteConnectionStringBuilder { DataSource = paths.Database, Mode = SqliteOpenMode.ReadWriteCreate }.ToString();
    }

    public void Initialize()
    {
        Backup();
        using var connection = Open();
        Execute(connection, "PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;");
        Execute(connection, """
            CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY, applied_at REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS libraries(id TEXT PRIMARY KEY, display_name TEXT NOT NULL, path TEXT NOT NULL, bookmark BLOB, is_enabled INTEGER NOT NULL DEFAULT 1, date_added REAL NOT NULL, last_scanned REAL, availability TEXT NOT NULL DEFAULT 'available');
            CREATE TABLE IF NOT EXISTS media_items(id TEXT PRIMARY KEY, library_id TEXT NOT NULL REFERENCES libraries(id) ON DELETE CASCADE, kind TEXT NOT NULL, absolute_path TEXT NOT NULL, relative_path TEXT NOT NULL, filename TEXT NOT NULL, file_size INTEGER NOT NULL, modified_at REAL NOT NULL, parsed_title TEXT NOT NULL, display_title TEXT NOT NULL, sort_title TEXT, year INTEGER, season_number INTEGER, episode_number INTEGER, episode_title TEXT, summary TEXT, genre TEXT, runtime REAL, date_added REAL NOT NULL, last_watched REAL, playback_position REAL NOT NULL DEFAULT 0, is_watched INTEGER NOT NULL DEFAULT 0, is_favorite INTEGER NOT NULL DEFAULT 0, poster_path TEXT, backdrop_path TEXT, thumbnail_path TEXT, manual_metadata INTEGER NOT NULL DEFAULT 0, manual_poster INTEGER NOT NULL DEFAULT 0, manual_backdrop INTEGER NOT NULL DEFAULT 0, is_available INTEGER NOT NULL DEFAULT 1, last_seen_scan REAL);
            CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS idx_media_library ON media_items(library_id);
            CREATE INDEX IF NOT EXISTS idx_media_kind ON media_items(kind);
            CREATE INDEX IF NOT EXISTS idx_media_title ON media_items(display_title COLLATE NOCASE);
            INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES(1, unixepoch());
            """);
    }

    public List<LibraryFolder> Libraries()
    {
        using var connection = Open(); using var command = connection.CreateCommand();
        command.CommandText = "SELECT id,display_name,path,is_enabled,date_added,last_scanned,availability FROM libraries ORDER BY date_added";
        using var reader = command.ExecuteReader(); var result = new List<LibraryFolder>();
        while (reader.Read()) result.Add(new(reader.GetString(0), reader.GetString(1), reader.GetString(2), reader.GetInt64(3) != 0, reader.GetDouble(4), reader.IsDBNull(5) ? null : reader.GetDouble(5), reader.GetString(6)));
        return result;
    }

    public LibraryFolder AddOrReconnectLibrary(string path)
    {
        var name = Path.GetFileName(path.TrimEnd(Path.DirectorySeparatorChar));
        var existing = Libraries().FirstOrDefault(x => !Directory.Exists(x.StoredPath) && x.DisplayName.Equals(name, StringComparison.OrdinalIgnoreCase));
        if (existing is not null) return existing;
        var folder = new LibraryFolder(Guid.NewGuid().ToString().ToUpperInvariant(), name, path, true, Now(), null, "available");
        using var connection = Open(); using var command = connection.CreateCommand();
        command.CommandText = "INSERT INTO libraries(id,display_name,path,bookmark,is_enabled,date_added,availability) VALUES($id,$name,$path,NULL,1,$now,'available')";
        command.Parameters.AddWithValue("$id", folder.Id); command.Parameters.AddWithValue("$name", name); command.Parameters.AddWithValue("$path", path); command.Parameters.AddWithValue("$now", folder.DateAdded); command.ExecuteNonQuery();
        return folder;
    }

    public void Ingest(string libraryId, IReadOnlyList<ScanCandidate> items)
    {
        using var connection = Open(); using var transaction = connection.BeginTransaction();
        using (var mark = connection.CreateCommand()) { mark.Transaction = transaction; mark.CommandText = "UPDATE media_items SET is_available=0 WHERE library_id=$id"; mark.Parameters.AddWithValue("$id", libraryId); mark.ExecuteNonQuery(); }
        var scanDate = Now();
        foreach (var item in items)
        {
            using var command = connection.CreateCommand(); command.Transaction = transaction;
            command.CommandText = """
                INSERT INTO media_items(id,library_id,kind,absolute_path,relative_path,filename,file_size,modified_at,parsed_title,display_title,year,season_number,episode_number,episode_title,date_added,poster_path,backdrop_path,is_available,last_seen_scan)
                VALUES($id,$library,$kind,$absolute,$relative,$filename,$size,$modified,$parsed,$display,$year,$season,$episode,$episodeTitle,$added,$poster,$backdrop,1,$scan)
                ON CONFLICT(id) DO UPDATE SET absolute_path=excluded.absolute_path,relative_path=excluded.relative_path,filename=excluded.filename,file_size=excluded.file_size,modified_at=excluded.modified_at,kind=excluded.kind,parsed_title=excluded.parsed_title,display_title=CASE WHEN media_items.manual_metadata=1 THEN media_items.display_title ELSE excluded.display_title END,year=CASE WHEN media_items.manual_metadata=1 THEN media_items.year ELSE excluded.year END,season_number=excluded.season_number,episode_number=excluded.episode_number,episode_title=CASE WHEN media_items.manual_metadata=1 THEN media_items.episode_title ELSE excluded.episode_title END,poster_path=CASE WHEN media_items.manual_poster=1 THEN media_items.poster_path ELSE COALESCE(excluded.poster_path,media_items.poster_path) END,backdrop_path=CASE WHEN media_items.manual_backdrop=1 THEN media_items.backdrop_path ELSE COALESCE(excluded.backdrop_path,media_items.backdrop_path) END,is_available=1,last_seen_scan=excluded.last_seen_scan
                """;
            Add(command, "$id", item.Id); Add(command, "$library", item.LibraryId); Add(command, "$kind", item.Parsed.Kind); Add(command, "$absolute", item.AbsolutePath); Add(command, "$relative", item.RelativePath); Add(command, "$filename", item.Filename); Add(command, "$size", item.FileSize); Add(command, "$modified", item.ModifiedAt); Add(command, "$parsed", item.Parsed.Title); Add(command, "$display", item.Parsed.Title); Add(command, "$year", item.Parsed.Year); Add(command, "$season", item.Parsed.Season); Add(command, "$episode", item.Parsed.Episode); Add(command, "$episodeTitle", item.Parsed.EpisodeTitle); Add(command, "$added", scanDate); Add(command, "$poster", item.Poster); Add(command, "$backdrop", item.Backdrop); Add(command, "$scan", scanDate); command.ExecuteNonQuery();
        }
        using (var update = connection.CreateCommand()) { update.Transaction = transaction; update.CommandText = "UPDATE libraries SET last_scanned=$now,availability='available' WHERE id=$id"; Add(update, "$now", scanDate); Add(update, "$id", libraryId); update.ExecuteNonQuery(); }
        transaction.Commit();
    }

    public List<MediaItem> AllMedia()
    {
        using var connection = Open(); using var command = connection.CreateCommand();
        command.CommandText = "SELECT id,library_id,kind,absolute_path,relative_path,filename,display_title,sort_title,year,season_number,episode_number,episode_title,summary,genre,runtime,date_added,last_watched,playback_position,is_watched,is_favorite,poster_path,backdrop_path,is_available FROM media_items ORDER BY display_title COLLATE NOCASE,season_number,episode_number";
        using var reader = command.ExecuteReader(); var result = new List<MediaItem>();
        while (reader.Read()) result.Add(new MediaItem { Id=S(reader,0)!, LibraryId=S(reader,1)!, Kind=S(reader,2)!, AbsolutePath=S(reader,3)!, RelativePath=S(reader,4)!, Filename=S(reader,5)!, DisplayTitle=S(reader,6)!, SortTitle=S(reader,7), Year=I(reader,8), SeasonNumber=I(reader,9), EpisodeNumber=I(reader,10), EpisodeTitle=S(reader,11), Summary=S(reader,12), Genre=S(reader,13), Runtime=D(reader,14), DateAdded=reader.GetDouble(15), LastWatched=D(reader,16), PlaybackPosition=reader.GetDouble(17), IsWatched=reader.GetInt64(18)!=0, IsFavorite=reader.GetInt64(19)!=0, PosterPath=S(reader,20), BackdropPath=S(reader,21), IsAvailable=reader.GetInt64(22)!=0 });
        return result;
    }

    public void SetFavorite(string id, bool value) => Update("UPDATE media_items SET is_favorite=$value WHERE id=$id", id, ("$value", value ? 1 : 0));
    public void Restart(string id) => Update("UPDATE media_items SET playback_position=0,is_watched=0 WHERE id=$id", id);
    public void UpdateProgress(string id, double position, double duration)
    {
        using var connection = Open(); using var command = connection.CreateCommand();
        command.CommandText = "UPDATE media_items SET playback_position=$position,runtime=$duration,last_watched=$now,is_watched=$watched WHERE id=$id";
        Add(command,"$position",Math.Max(0,position)); Add(command,"$duration",duration); Add(command,"$now",Now()); Add(command,"$watched",duration>0 && position/duration>=.9 ? 1:0); Add(command,"$id",id); command.ExecuteNonQuery();
    }
    private void Update(string sql, string id, params (string,object)[] values) { using var c=Open(); using var q=c.CreateCommand(); q.CommandText=sql; Add(q,"$id",id); foreach(var v in values) Add(q,v.Item1,v.Item2); q.ExecuteNonQuery(); }
    private SqliteConnection Open() { var connection = new SqliteConnection(_connectionString); connection.Open(); return connection; }
    private static void Execute(SqliteConnection c,string sql) { using var q=c.CreateCommand(); q.CommandText=sql; q.ExecuteNonQuery(); }
    private static void Add(SqliteCommand c,string name,object? value)=>c.Parameters.AddWithValue(name,value??DBNull.Value);
    private static string? S(SqliteDataReader r,int i)=>r.IsDBNull(i)?null:r.GetString(i); private static int? I(SqliteDataReader r,int i)=>r.IsDBNull(i)?null:r.GetInt32(i); private static double? D(SqliteDataReader r,int i)=>r.IsDBNull(i)?null:r.GetDouble(i);
    private static double Now()=>DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()/1000.0;
    private void Backup() { if(!File.Exists(_paths.Database)||new FileInfo(_paths.Database).Length==0)return; Directory.CreateDirectory(_paths.Backups); var target=Path.Combine(_paths.Backups,$"library-{DateTime.Now:yyyyMMdd-HHmmss}-windows.sqlite"); File.Copy(_paths.Database,target,false); foreach(var old in new DirectoryInfo(_paths.Backups).GetFiles("library-*.sqlite").OrderByDescending(x=>x.CreationTimeUtc).Skip(3)) try{old.Delete();}catch{} }
}
