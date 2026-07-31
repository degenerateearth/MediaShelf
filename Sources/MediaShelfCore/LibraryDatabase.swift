import Foundation
import SQLite3

public enum DatabaseError: LocalizedError {
    case open(String)
    case execute(String)
    case prepare(String)

    public var errorDescription: String? {
        switch self {
        case .open(let message): "Could not open the portable library: \(message)"
        case .execute(let message): "A library update failed: \(message)"
        case .prepare(let message): "A library query failed: \(message)"
        }
    }
}

public actor LibraryDatabase {
    private let paths: PortablePaths
    private var connection: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(paths: PortablePaths) {
        self.paths = paths
    }

    deinit {
        sqlite3_close(connection)
    }

    public func initialize() throws {
        try paths.prepare()
        guard sqlite3_open_v2(
            paths.database.path,
            &connection,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            throw DatabaseError.open(lastError)
        }

        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
        try backupBeforeMigration()

        try execute("""
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            applied_at REAL NOT NULL
        )
        """)

        try execute("""
        CREATE TABLE IF NOT EXISTS libraries (
            id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            path TEXT NOT NULL,
            bookmark BLOB,
            is_enabled INTEGER NOT NULL DEFAULT 1,
            date_added REAL NOT NULL,
            last_scanned REAL,
            availability TEXT NOT NULL DEFAULT 'available'
        )
        """)

        try execute("""
        CREATE TABLE IF NOT EXISTS media_items (
            id TEXT PRIMARY KEY,
            library_id TEXT NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
            kind TEXT NOT NULL,
            absolute_path TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            filename TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            modified_at REAL NOT NULL,
            parsed_title TEXT NOT NULL,
            display_title TEXT NOT NULL,
            sort_title TEXT,
            year INTEGER,
            season_number INTEGER,
            episode_number INTEGER,
            episode_title TEXT,
            summary TEXT,
            genre TEXT,
            runtime REAL,
            date_added REAL NOT NULL,
            last_watched REAL,
            playback_position REAL NOT NULL DEFAULT 0,
            is_watched INTEGER NOT NULL DEFAULT 0,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            poster_path TEXT,
            backdrop_path TEXT,
            thumbnail_path TEXT,
            manual_metadata INTEGER NOT NULL DEFAULT 0,
            manual_poster INTEGER NOT NULL DEFAULT 0,
            manual_backdrop INTEGER NOT NULL DEFAULT 0,
            is_available INTEGER NOT NULL DEFAULT 1,
            last_seen_scan REAL
        )
        """)

        try execute("""
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
        """)

        try execute("CREATE INDEX IF NOT EXISTS idx_media_library ON media_items(library_id)")
        try execute("CREATE INDEX IF NOT EXISTS idx_media_kind ON media_items(kind)")
        try execute("CREATE INDEX IF NOT EXISTS idx_media_title ON media_items(display_title COLLATE NOCASE)")
        try execute("CREATE INDEX IF NOT EXISTS idx_media_progress ON media_items(is_watched, playback_position)")
        try execute("""
        INSERT OR IGNORE INTO schema_migrations(version, applied_at)
        VALUES (1, strftime('%s','now'))
        """)
    }

    public func addLibrary(_ library: LibraryFolder) throws {
        let sql = """
        INSERT INTO libraries(
            id, display_name, path, bookmark, is_enabled, date_added, last_scanned, availability
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            display_name = excluded.display_name,
            path = excluded.path,
            bookmark = excluded.bookmark,
            is_enabled = excluded.is_enabled,
            availability = excluded.availability
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(library.id.uuidString, to: 1, in: statement)
        bind(library.displayName, to: 2, in: statement)
        bind(library.path, to: 3, in: statement)
        bind(library.bookmark, to: 4, in: statement)
        bind(library.isEnabled, to: 5, in: statement)
        bind(library.dateAdded, to: 6, in: statement)
        bind(library.lastScanned, to: 7, in: statement)
        bind(library.availability.rawValue, to: 8, in: statement)
        try stepDone(statement)
    }

    public func libraries() throws -> [LibraryFolder] {
        let statement = try prepare("""
        SELECT id, display_name, path, bookmark, is_enabled, date_added, last_scanned, availability
        FROM libraries ORDER BY date_added
        """)
        defer { sqlite3_finalize(statement) }
        var result: [LibraryFolder] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, 0) ?? "") else { continue }
            result.append(
                LibraryFolder(
                    id: id,
                    displayName: text(statement, 1) ?? "Media",
                    path: text(statement, 2) ?? "",
                    bookmark: blob(statement, 3),
                    isEnabled: boolean(statement, 4),
                    dateAdded: date(statement, 5) ?? .now,
                    lastScanned: date(statement, 6),
                    availability: LibraryAvailability(rawValue: text(statement, 7) ?? "") ?? .available
                )
            )
        }
        return result
    }

    public func removeLibrary(id: UUID) throws {
        let statement = try prepare("DELETE FROM libraries WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: 1, in: statement)
        try stepDone(statement)
    }

    public func setLibraryEnabled(id: UUID, enabled: Bool) throws {
        let statement = try prepare("UPDATE libraries SET is_enabled = ? WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(enabled, to: 1, in: statement)
        bind(id.uuidString, to: 2, in: statement)
        try stepDone(statement)
    }

    public func ingest(_ report: ScanReport, for libraryID: UUID) throws {
        let scanDate = Date()
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let markStatement = try prepare(
                "UPDATE media_items SET is_available = 0 WHERE library_id = ?"
            )
            bind(libraryID.uuidString, to: 1, in: markStatement)
            try stepDone(markStatement)
            sqlite3_finalize(markStatement)

            for candidate in report.candidates {
                try upsert(candidate, scanDate: scanDate)
            }

            let libraryStatement = try prepare("""
            UPDATE libraries SET last_scanned = ?, availability = 'available' WHERE id = ?
            """)
            bind(scanDate, to: 1, in: libraryStatement)
            bind(libraryID.uuidString, to: 2, in: libraryStatement)
            try stepDone(libraryStatement)
            sqlite3_finalize(libraryStatement)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func allMedia() throws -> [MediaItem] {
        let statement = try prepare("""
        SELECT
            id, library_id, kind, absolute_path, relative_path, filename,
            file_size, modified_at, parsed_title, display_title, sort_title,
            year, season_number, episode_number, episode_title, summary, genre,
            runtime, date_added, last_watched, playback_position, is_watched,
            is_favorite, poster_path, backdrop_path, thumbnail_path,
            manual_metadata, manual_poster, manual_backdrop, is_available
        FROM media_items
        ORDER BY display_title COLLATE NOCASE, season_number, episode_number
        """)
        defer { sqlite3_finalize(statement) }
        var items: [MediaItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let item = mediaItem(from: statement) { items.append(item) }
        }
        return items
    }

    public func updateProgress(
        mediaID: String,
        position: Double,
        duration: Double?,
        watchedThreshold: Double = 0.90
    ) throws {
        let watched = duration.map { $0 > 0 && position / $0 >= watchedThreshold } ?? false
        let statement = try prepare("""
        UPDATE media_items
        SET playback_position = ?,
            runtime = COALESCE(?, runtime),
            last_watched = ?,
            is_watched = ?
        WHERE id = ?
        """)
        defer { sqlite3_finalize(statement) }
        bind(max(position, 0), to: 1, in: statement)
        bind(duration, to: 2, in: statement)
        bind(Date(), to: 3, in: statement)
        bind(watched, to: 4, in: statement)
        bind(mediaID, to: 5, in: statement)
        try stepDone(statement)
    }

    public func restart(mediaID: String) throws {
        let statement = try prepare("""
        UPDATE media_items SET playback_position = 0, is_watched = 0 WHERE id = ?
        """)
        defer { sqlite3_finalize(statement) }
        bind(mediaID, to: 1, in: statement)
        try stepDone(statement)
    }

    public func markFinished(mediaID: String, duration: Double? = nil) throws {
        let statement = try prepare("""
        UPDATE media_items
        SET runtime = COALESCE(?, runtime),
            playback_position = COALESCE(?, runtime, playback_position),
            last_watched = ?,
            is_watched = 1
        WHERE id = ?
        """)
        defer { sqlite3_finalize(statement) }
        bind(duration, to: 1, in: statement)
        bind(duration, to: 2, in: statement)
        bind(Date(), to: 3, in: statement)
        bind(mediaID, to: 4, in: statement)
        try stepDone(statement)
    }

    public func setFavorite(mediaID: String, favorite: Bool) throws {
        let statement = try prepare("UPDATE media_items SET is_favorite = ? WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        bind(favorite, to: 1, in: statement)
        bind(mediaID, to: 2, in: statement)
        try stepDone(statement)
    }

    public func updateMetadata(
        mediaID: String,
        title: String,
        year: Int?,
        summary: String?,
        genre: String?,
        runtime: Double?,
        sortTitle: String? = nil,
        episodeTitle: String? = nil
    ) throws {
        let statement = try prepare("""
        UPDATE media_items SET
            display_title = ?, year = ?, summary = ?, genre = ?, runtime = ?,
            sort_title = ?, episode_title = COALESCE(?, episode_title),
            manual_metadata = 1
        WHERE id = ?
        """)
        defer { sqlite3_finalize(statement) }
        bind(title, to: 1, in: statement)
        bind(year, to: 2, in: statement)
        bind(summary, to: 3, in: statement)
        bind(genre, to: 4, in: statement)
        bind(runtime, to: 5, in: statement)
        bind(sortTitle, to: 6, in: statement)
        bind(episodeTitle, to: 7, in: statement)
        bind(mediaID, to: 8, in: statement)
        try stepDone(statement)
    }

    public func applyProviderMetadata(
        mediaID: String,
        summary: String?,
        genre: String?,
        year: Int?
    ) throws {
        let statement = try prepare("""
        UPDATE media_items SET
            summary = CASE WHEN manual_metadata = 1 THEN summary ELSE COALESCE(summary, ?) END,
            genre = CASE WHEN manual_metadata = 1 THEN genre ELSE COALESCE(genre, ?) END,
            year = CASE WHEN manual_metadata = 1 THEN year ELSE COALESCE(year, ?) END
        WHERE id = ?
        """)
        defer { sqlite3_finalize(statement) }
        bind(summary, to: 1, in: statement)
        bind(genre, to: 2, in: statement)
        bind(year, to: 3, in: statement)
        bind(mediaID, to: 4, in: statement)
        try stepDone(statement)
    }

    public func reclassify(mediaID: String, parsed: ParsedFilename) throws {
        let statement = try prepare("""
        UPDATE media_items SET
            kind = ?,
            parsed_title = ?,
            display_title = CASE
                WHEN manual_metadata = 1 THEN display_title
                ELSE ?
            END,
            year = CASE
                WHEN manual_metadata = 1 THEN year
                ELSE ?
            END,
            season_number = ?,
            episode_number = ?,
            episode_title = CASE
                WHEN manual_metadata = 1 THEN episode_title
                ELSE ?
            END
        WHERE id = ?
        """)
        defer { sqlite3_finalize(statement) }
        bind(parsed.kind.rawValue, to: 1, in: statement)
        bind(parsed.title, to: 2, in: statement)
        bind(parsed.title, to: 3, in: statement)
        bind(parsed.year, to: 4, in: statement)
        bind(parsed.seasonNumber, to: 5, in: statement)
        bind(parsed.episodeNumber, to: 6, in: statement)
        bind(parsed.episodeTitle, to: 7, in: statement)
        bind(mediaID, to: 8, in: statement)
        try stepDone(statement)
    }

    public func setArtwork(mediaID: String, role: ArtworkRole, path: String?, manual: Bool) throws {
        let column: String
        let flag: String
        switch role {
        case .poster:
            column = "poster_path"
            flag = "manual_poster"
        case .backdrop:
            column = "backdrop_path"
            flag = "manual_backdrop"
        case .thumbnail:
            column = "thumbnail_path"
            flag = "manual_poster"
        }
        let statement = try prepare(
            "UPDATE media_items SET \(column) = ?, \(flag) = ? WHERE id = ?"
        )
        defer { sqlite3_finalize(statement) }
        bind(path, to: 1, in: statement)
        bind(manual, to: 2, in: statement)
        bind(mediaID, to: 3, in: statement)
        try stepDone(statement)
    }

    public func resetProviderEnrichment(artworkRoot: String) throws -> [String] {
        let prefix = artworkRoot.hasSuffix("/") ? artworkRoot : artworkRoot + "/"
        let likePattern = prefix + "%"
        let select = try prepare("""
        SELECT poster_path, backdrop_path
        FROM media_items
        WHERE (manual_poster = 0 AND poster_path LIKE ?)
           OR (manual_backdrop = 0 AND backdrop_path LIKE ?)
        """)
        bind(likePattern, to: 1, in: select)
        bind(likePattern, to: 2, in: select)
        var paths: Set<String> = []
        while sqlite3_step(select) == SQLITE_ROW {
            if let path = text(select, 0), path.hasPrefix(prefix) { paths.insert(path) }
            if let path = text(select, 1), path.hasPrefix(prefix) { paths.insert(path) }
        }
        sqlite3_finalize(select)

        let update = try prepare("""
        UPDATE media_items SET
            poster_path = CASE
                WHEN manual_poster = 0 AND poster_path LIKE ? THEN NULL
                ELSE poster_path
            END,
            backdrop_path = CASE
                WHEN manual_backdrop = 0 AND backdrop_path LIKE ? THEN NULL
                ELSE backdrop_path
            END,
            summary = CASE WHEN manual_metadata = 0 THEN NULL ELSE summary END,
            genre = CASE WHEN manual_metadata = 0 THEN NULL ELSE genre END,
            year = CASE
                WHEN manual_metadata = 0 AND kind = 'episode' THEN NULL
                ELSE year
            END
        WHERE (manual_poster = 0 AND poster_path LIKE ?)
           OR (manual_backdrop = 0 AND backdrop_path LIKE ?)
        """)
        bind(likePattern, to: 1, in: update)
        bind(likePattern, to: 2, in: update)
        bind(likePattern, to: 3, in: update)
        bind(likePattern, to: 4, in: update)
        try stepDone(update)
        sqlite3_finalize(update)
        return Array(paths)
    }

    public func setting(_ key: String) throws -> String? {
        let statement = try prepare("SELECT value FROM settings WHERE key = ?")
        defer { sqlite3_finalize(statement) }
        bind(key, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return text(statement, 0)
    }

    public func setSetting(_ key: String, value: String) throws {
        let statement = try prepare("""
        INSERT INTO settings(key, value) VALUES(?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """)
        defer { sqlite3_finalize(statement) }
        bind(key, to: 1, in: statement)
        bind(value, to: 2, in: statement)
        try stepDone(statement)
    }

    private func upsert(_ item: ScanCandidate, scanDate: Date) throws {
        let statement = try prepare("""
        INSERT INTO media_items(
            id, library_id, kind, absolute_path, relative_path, filename,
            file_size, modified_at, parsed_title, display_title, year,
            season_number, episode_number, episode_title, date_added,
            poster_path, backdrop_path, is_available, last_seen_scan
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)
        ON CONFLICT(id) DO UPDATE SET
            absolute_path = excluded.absolute_path,
            relative_path = excluded.relative_path,
            filename = excluded.filename,
            file_size = excluded.file_size,
            modified_at = excluded.modified_at,
            kind = excluded.kind,
            parsed_title = excluded.parsed_title,
            display_title = CASE
                WHEN media_items.manual_metadata = 1 THEN media_items.display_title
                ELSE excluded.display_title
            END,
            year = CASE
                WHEN media_items.manual_metadata = 1 THEN media_items.year
                ELSE excluded.year
            END,
            season_number = excluded.season_number,
            episode_number = excluded.episode_number,
            episode_title = CASE
                WHEN media_items.manual_metadata = 1 THEN media_items.episode_title
                ELSE excluded.episode_title
            END,
            poster_path = CASE
                WHEN media_items.manual_poster = 1 THEN media_items.poster_path
                ELSE COALESCE(excluded.poster_path, media_items.poster_path)
            END,
            backdrop_path = CASE
                WHEN media_items.manual_backdrop = 1 THEN media_items.backdrop_path
                ELSE COALESCE(excluded.backdrop_path, media_items.backdrop_path)
            END,
            is_available = 1,
            last_seen_scan = excluded.last_seen_scan
        """)
        defer { sqlite3_finalize(statement) }
        bind(item.stableID, to: 1, in: statement)
        bind(item.libraryID.uuidString, to: 2, in: statement)
        bind(item.parsed.kind.rawValue, to: 3, in: statement)
        bind(item.absolutePath, to: 4, in: statement)
        bind(item.relativePath, to: 5, in: statement)
        bind(item.filename, to: 6, in: statement)
        bind(item.fileSize, to: 7, in: statement)
        bind(item.modifiedAt, to: 8, in: statement)
        bind(item.parsed.title, to: 9, in: statement)
        bind(item.parsed.title, to: 10, in: statement)
        bind(item.parsed.year, to: 11, in: statement)
        bind(item.parsed.seasonNumber, to: 12, in: statement)
        bind(item.parsed.episodeNumber, to: 13, in: statement)
        bind(item.parsed.episodeTitle, to: 14, in: statement)
        bind(scanDate, to: 15, in: statement)
        bind(item.localPosterPath, to: 16, in: statement)
        bind(item.localBackdropPath, to: 17, in: statement)
        bind(scanDate, to: 18, in: statement)
        try stepDone(statement)
    }

    private func mediaItem(from statement: OpaquePointer?) -> MediaItem? {
        guard let libraryID = UUID(uuidString: text(statement, 1) ?? ""),
              let kind = MediaKind(rawValue: text(statement, 2) ?? "")
        else { return nil }
        return MediaItem(
            id: text(statement, 0) ?? "",
            libraryID: libraryID,
            kind: kind,
            absolutePath: text(statement, 3) ?? "",
            relativePath: text(statement, 4) ?? "",
            filename: text(statement, 5) ?? "",
            fileSize: sqlite3_column_int64(statement, 6),
            modifiedAt: date(statement, 7) ?? .distantPast,
            parsedTitle: text(statement, 8) ?? "",
            displayTitle: text(statement, 9) ?? "",
            sortTitle: text(statement, 10),
            year: integer(statement, 11),
            seasonNumber: integer(statement, 12),
            episodeNumber: integer(statement, 13),
            episodeTitle: text(statement, 14),
            summary: text(statement, 15),
            genre: text(statement, 16),
            runtime: double(statement, 17),
            dateAdded: date(statement, 18) ?? .now,
            lastWatched: date(statement, 19),
            playbackPosition: double(statement, 20) ?? 0,
            isWatched: boolean(statement, 21),
            isFavorite: boolean(statement, 22),
            posterPath: text(statement, 23),
            backdropPath: text(statement, 24),
            thumbnailPath: text(statement, 25),
            manualMetadata: boolean(statement, 26),
            manualPoster: boolean(statement, 27),
            manualBackdrop: boolean(statement, 28),
            isAvailable: boolean(statement, 29)
        )
    }

    private func backupBeforeMigration() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: paths.database.path),
              (try? paths.database.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 0
        else { return }
        try manager.createDirectory(at: paths.backups, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let destination = paths.backups.appendingPathComponent(
            "library-\(formatter.string(from: .now)).sqlite"
        )
        try? manager.copyItem(at: paths.database, to: destination)
        let backups = (try? manager.contentsOfDirectory(
            at: paths.backups,
            includingPropertiesForKeys: [.creationDateKey]
        ))?.sorted {
            let left = try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate
            let right = try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate
            return (left ?? .distantPast) > (right ?? .distantPast)
        } ?? []
        for oldBackup in backups.dropFirst(3) {
            try? manager.removeItem(at: oldBackup)
        }
    }

    private func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(connection, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? lastError
            sqlite3_free(errorPointer)
            throw DatabaseError.execute(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepare(lastError)
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.execute(lastError)
        }
    }

    private var lastError: String {
        connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
    }

    private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private func bind(_ value: Data?, to index: Int32, in statement: OpaquePointer?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        _ = value.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(value.count), transient)
        }
    }

    private func bind(_ value: Date?, to index: Int32, in statement: OpaquePointer?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
    }

    private func bind(_ value: Bool, to index: Int32, in statement: OpaquePointer?) {
        sqlite3_bind_int(statement, index, value ? 1 : 0)
    }

    private func bind(_ value: Int?, to index: Int32, in statement: OpaquePointer?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_int64(statement, index, Int64(value))
    }

    private func bind(_ value: Int64, to index: Int32, in statement: OpaquePointer?) {
        sqlite3_bind_int64(statement, index, value)
    }

    private func bind(_ value: Double?, to index: Int32, in statement: OpaquePointer?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_double(statement, index, value)
    }

    private func bind(_ value: Double, to index: Int32, in statement: OpaquePointer?) {
        sqlite3_bind_double(statement, index, value)
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index)
        else { return nil }
        return String(cString: pointer)
    }

    private func blob(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(statement, index)
        else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private func date(_ statement: OpaquePointer?, _ index: Int32) -> Date? {
        double(statement, index).map(Date.init(timeIntervalSince1970:))
    }

    private func double(_ statement: OpaquePointer?, _ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    private func integer(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(statement, index))
    }

    private func boolean(_ statement: OpaquePointer?, _ index: Int32) -> Bool {
        sqlite3_column_int(statement, index) != 0
    }
}
