#!/usr/bin/env python3
"""MediaShelf for Linux: a lightweight GTK client for the portable library."""
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import threading
import time
import uuid
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk

APP = "MediaShelf"
VIDEO_EXTENSIONS = {".mp4", ".mkv", ".m4v", ".mov", ".avi", ".webm", ".mpeg", ".mpg", ".ts"}
RELEASE = {"480p", "720p", "1080p", "1080i", "2160p", "4k", "uhd", "bluray", "brrip", "bdrip", "web-dl", "webdl", "webrip", "hdtv", "remux", "x264", "x265", "h264", "h265", "hevc", "av1", "hdr", "hdr10", "dv", "aac", "ac3", "eac3", "dts", "truehd", "atmos", "10bit", "proper", "repack", "extended"}


def app_icon_path():
    """Find the MediaShelf artwork in an AppImage or source checkout."""
    candidates = (
        Path(os.environ.get("APPDIR", "/nonexistent")) / "usr/share/icons/hicolor/512x512/apps/mediashelf.png",
        Path(__file__).resolve().parents[2] / "Resources/AppIcon.png",
        Path(__file__).resolve().parent / "Resources/AppIcon.png",
    )
    return next((path for path in candidates if path.is_file()), None)


def clean_title(value):
    value = re.sub(r"[\[\{].*?[\]\}]", " ", value)
    words = re.sub(r"[._()\[\]{}-]+", " ", value).split()
    kept = []
    for word in words:
        if word.lower().strip(".,") in RELEASE:
            break
        kept.append(word)
    return " ".join(kept).strip(" ._-") or "Untitled"


def parse_name(path):
    base = path.stem
    for pattern in (r"(?i)^(.*?)[\s._-]+S(\d{1,2})E(\d{1,3})(?:[\s._-]+(.*))?$", r"(?i)^(.*?)[\s._-]+(\d{1,2})x(\d{1,3})(?:[\s._-]+(.*))?$"):
        match = re.match(pattern, base)
        if match:
            return "episode", clean_title(match.group(1)), None, int(match.group(2)), int(match.group(3)), clean_title(match.group(4)) if match.group(4) else None
    year_match = re.search(r"(?<!\d)(19\d{2}|20\d{2})(?!\d)", base)
    year = int(year_match.group(1)) if year_match else None
    return "movie", clean_title(base[:year_match.start()] if year_match else base), year, None, None, None


class Store:
    def __init__(self):
        self.config = Path.home() / ".config" / "mediashelf" / "location"
        self.db_path = None
        self.db = None

    def open_for(self, media_folder=None):
        if media_folder:
            data = media_folder.parent / "MediaShelf Data"
            data.mkdir(exist_ok=True)
            self.config.parent.mkdir(parents=True, exist_ok=True)
            self.config.write_text(str(data), encoding="utf-8")
        elif self.config.exists():
            data = Path(self.config.read_text(encoding="utf-8").strip())
        else:
            return False
        data.mkdir(parents=True, exist_ok=True)
        for part in ("Artwork", "Backups", "Cache", "Playback", "Settings", "Thumbnails"):
            (data / part).mkdir(exist_ok=True)
        self.db_path = data / "library.sqlite"
        self.db = sqlite3.connect(self.db_path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.executescript("""
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS libraries (id TEXT PRIMARY KEY, display_name TEXT NOT NULL, path TEXT NOT NULL, bookmark BLOB, is_enabled INTEGER NOT NULL DEFAULT 1, date_added REAL NOT NULL, last_scanned REAL, availability TEXT NOT NULL DEFAULT 'available');
        CREATE TABLE IF NOT EXISTS media_items (id TEXT PRIMARY KEY, library_id TEXT NOT NULL, kind TEXT NOT NULL, absolute_path TEXT NOT NULL, relative_path TEXT NOT NULL, filename TEXT NOT NULL, file_size INTEGER NOT NULL, modified_at REAL NOT NULL, parsed_title TEXT NOT NULL, display_title TEXT NOT NULL, sort_title TEXT, year INTEGER, season_number INTEGER, episode_number INTEGER, episode_title TEXT, summary TEXT, genre TEXT, runtime REAL, date_added REAL NOT NULL, last_watched REAL, playback_position REAL NOT NULL DEFAULT 0, is_watched INTEGER NOT NULL DEFAULT 0, is_favorite INTEGER NOT NULL DEFAULT 0, poster_path TEXT, backdrop_path TEXT, thumbnail_path TEXT, manual_metadata INTEGER NOT NULL DEFAULT 0, manual_poster INTEGER NOT NULL DEFAULT 0, manual_backdrop INTEGER NOT NULL DEFAULT 0, is_available INTEGER NOT NULL DEFAULT 1, last_seen_scan REAL);
        CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS idx_media_title ON media_items(display_title COLLATE NOCASE);
        """)
        self.db.commit()
        return True

    @property
    def data_root(self):
        return self.db_path.parent if self.db_path else None

    def libraries(self):
        return list(self.db.execute("SELECT * FROM libraries ORDER BY date_added")) if self.db else []

    def set_library_enabled(self, lib_id, enabled):
        self.db.execute("UPDATE libraries SET is_enabled=? WHERE id=?", (int(enabled), lib_id)); self.db.commit()

    def remove_library(self, lib_id):
        self.db.execute("DELETE FROM media_items WHERE library_id=?", (lib_id,))
        self.db.execute("DELETE FROM libraries WHERE id=?", (lib_id,)); self.db.commit()

    def update_item(self, media_id, **values):
        allowed = {"display_title", "year", "summary", "genre", "season_number", "episode_number", "episode_title", "is_favorite", "is_watched", "playback_position", "runtime", "last_watched", "poster_path", "backdrop_path", "manual_metadata", "manual_poster", "manual_backdrop"}
        values = {key: value for key, value in values.items() if key in allowed}
        if not values: return
        sql = ",".join(f"{key}=?" for key in values)
        self.db.execute(f"UPDATE media_items SET {sql} WHERE id=?", (*values.values(), media_id)); self.db.commit()

    def setting(self, key, default=None):
        row = self.db.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone() if self.db else None
        return row[0] if row else default

    def set_setting(self, key, value):
        self.db.execute("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, str(value))); self.db.commit()

    def add_library(self, folder):
        folder = Path(folder).resolve()
        if not self.db:
            self.open_for(folder)
        row = self.db.execute("SELECT id FROM libraries WHERE path=?", (str(folder),)).fetchone()
        lib_id = row[0] if row else str(uuid.uuid4()).upper()
        now = time.time()
        self.db.execute("INSERT INTO libraries(id,display_name,path,is_enabled,date_added,availability) VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET path=excluded.path,display_name=excluded.display_name,is_enabled=1,availability='available'", (lib_id, folder.name, str(folder), 1, now, "available"))
        self.db.commit()
        return lib_id

    def scan(self, lib_id, folder, progress=None):
        folder = Path(folder)
        files = [p for p in folder.rglob("*") if p.is_file() and p.suffix.lower() in VIDEO_EXTENSIONS]
        now = time.time()
        self.db.execute("UPDATE media_items SET is_available=0 WHERE library_id=?", (lib_id,))
        for index, path in enumerate(files):
            stat = path.stat(); rel = str(path.relative_to(folder)); parsed = parse_name(path)
            stable = hashlib.sha256((lib_id.lower() + ":" + rel.lower()).encode()).hexdigest()
            kind, title, year, season, episode, episode_title = parsed
            poster = next((str(p) for p in (path.with_suffix(".jpg"), path.parent / "poster.jpg", path.parent / "folder.jpg") if p.exists()), None)
            backdrop = next((str(p) for p in (path.parent / "backdrop.jpg", path.parent / "fanart.jpg", path.parent / "background.jpg") if p.exists()), None)
            thumbnail = self.db_path.parent / "Thumbnails" / f"{stable}.jpg"
            if not poster and not thumbnail.exists():
                try:
                    subprocess.run(["ffmpegthumbnailer", "-i", str(path), "-o", str(thumbnail), "-s", "360", "-t", "15", "-q", "7"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
                except (OSError, subprocess.TimeoutExpired):
                    pass
            thumbnail_value = str(thumbnail) if thumbnail.exists() else None
            self.db.execute("""INSERT INTO media_items(id,library_id,kind,absolute_path,relative_path,filename,file_size,modified_at,parsed_title,display_title,year,season_number,episode_number,episode_title,date_added,poster_path,backdrop_path,is_available,last_seen_scan)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,1,?) ON CONFLICT(id) DO UPDATE SET absolute_path=excluded.absolute_path,file_size=excluded.file_size,modified_at=excluded.modified_at,is_available=1,last_seen_scan=excluded.last_seen_scan,poster_path=COALESCE(media_items.poster_path,excluded.poster_path),backdrop_path=COALESCE(media_items.backdrop_path,excluded.backdrop_path)""",
            (stable, lib_id, kind, str(path), rel, path.name, stat.st_size, stat.st_mtime, title, title, year, season, episode, episode_title, now, poster, backdrop, now))
            if thumbnail_value:
                self.db.execute("UPDATE media_items SET thumbnail_path=COALESCE(thumbnail_path,?) WHERE id=?", (thumbnail_value, stable))
            if progress and index % 10 == 0: progress(index + 1, len(files))
        self.db.execute("UPDATE libraries SET last_scanned=?,availability='available' WHERE id=?", (now, lib_id))
        self.db.commit()
        return len(files)

    def items(self):
        return list(self.db.execute("SELECT * FROM media_items WHERE is_available=1 ORDER BY display_title COLLATE NOCASE,season_number,episode_number")) if self.db else []


CSS = b"""
window { background: #0b0d12; color: #f4f5f7; font-family: Sans; }
.topbar { background: rgba(15,18,25,.96); border-bottom: 1px solid #252936; padding: 12px 20px; }
.brand { font-size: 24px; font-weight: 800; color: #ffffff; }
.muted { color: #9ca3af; }
.section { font-size: 20px; font-weight: 700; padding: 16px 2px 8px; }
.card { background: #171a22; border: 1px solid #292e3a; border-radius: 12px; padding: 0; }
.card:hover { background: #202530; border-color: #67728a; }
.poster { background: #222733; border-radius: 11px 11px 0 0; }
.title { font-size: 14px; font-weight: 700; color: #f8fafc; }
.meta { font-size: 12px; color: #aab1bf; }
.eyebrow { font-size: 11px; font-weight: 800; color: #a78bfa; letter-spacing: 2px; }
.hero { background: #121622; border: 1px solid #292e3a; border-radius: 16px; padding: 24px; }
.progress trough { min-height: 4px; background: #343947; }
.progress progress { min-height: 4px; background: #8b5cf6; }
.pill { border-radius: 18px; background: #7357ff; color: white; padding: 8px 15px; font-weight: 700; }
entry { background: #1a1e28; border: 1px solid #303746; border-radius: 18px; color: white; padding: 8px 14px; }
button { background: #1c212b; border: 1px solid #343b49; border-radius: 8px; color: white; padding: 8px 12px; }
button:hover { background: #2b3240; }
"""


class MediaCard(Gtk.Button):
    def __init__(self, item, activate):
        super().__init__(); self.item = item; self.get_style_context().add_class("card")
        self.set_size_request(178, 282); self.set_relief(Gtk.ReliefStyle.NONE)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        image = Gtk.Image(); image.set_size_request(176, 210); image.get_style_context().add_class("poster")
        artwork = item["poster_path"] or item["thumbnail_path"]
        try:
            if artwork and Path(artwork).exists():
                image.set_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(artwork, 176, 210, True))
            else: image.set_from_icon_name("video-x-generic-symbolic", Gtk.IconSize.DIALOG); image.set_pixel_size(72)
        except GLib.Error: image.set_from_icon_name("video-x-generic-symbolic", Gtk.IconSize.DIALOG)
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2); text.set_border_width(10)
        title = Gtk.Label(label=item["display_title"], xalign=0); title.set_ellipsize(3); title.get_style_context().add_class("title")
        if item["kind"] == "episode": meta = f"S{item['season_number'] or 0:02} E{item['episode_number'] or 0:02}"
        else: meta = str(item["year"] or "Movie")
        subtitle = Gtk.Label(label=meta, xalign=0); subtitle.get_style_context().add_class("meta")
        text.pack_start(title, False, False, 0); text.pack_start(subtitle, False, False, 0)
        box.pack_start(image, True, True, 0)
        if item["playback_position"] and not item["is_watched"]:
            progress = Gtk.ProgressBar(); progress.get_style_context().add_class("progress")
            runtime = item["runtime"] or max(item["playback_position"], 1)
            progress.set_fraction(min(item["playback_position"] / runtime, .98)); box.pack_start(progress, False, False, 0)
        box.pack_start(text, False, False, 0); self.add(box)
        self.connect("clicked", lambda *_: activate(item))


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title=APP); self.set_default_size(1180, 760); self.maximize()
        icon_path = app_icon_path()
        if icon_path: self.set_icon_from_file(str(icon_path))
        self.store = Store(); self.query = ""; self.filter = "all"; self.sort = "title"; self.status = Gtk.Label()
        provider = Gtk.CssProvider(); provider.load_from_data(CSS); Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL); self.add(self.root); self.build_header()
        self.scroll = Gtk.ScrolledWindow(); self.scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC); self.root.pack_start(self.scroll, True, True, 0)
        if self.store.open_for(): self.refresh()
        else: self.welcome()

    def build_header(self):
        bar = Gtk.Box(spacing=12); bar.get_style_context().add_class("topbar")
        brand = Gtk.Label(label="◈  MediaShelf"); brand.get_style_context().add_class("brand"); bar.pack_start(brand, False, False, 4)
        for label, value in (("All", "all"), ("Movies", "movie"), ("TV Shows", "episode"), ("Watched", "watched"), ("Unwatched", "unwatched"), ("Favorites", "favorite")):
            button = Gtk.Button(label=label); button.connect("clicked", self.set_filter, value); bar.pack_start(button, False, False, 0)
        search = Gtk.SearchEntry(); search.set_placeholder_text("Search your library"); search.set_size_request(260, -1); search.connect("search-changed", self.search); bar.pack_start(search, True, False, 12)
        sort = Gtk.ComboBoxText()
        for key, label in (("title", "Title"), ("added", "Recently added"), ("watched", "Recently watched"), ("year", "Year")): sort.append(key, label)
        sort.set_active_id("title"); sort.connect("changed", self.set_sort); bar.pack_start(sort, False, False, 0)
        scan = Gtk.Button(label="↻  Refresh"); scan.connect("clicked", self.rescan); bar.pack_start(scan, False, False, 0)
        art = Gtk.Button(label="✦ Artwork"); art.set_tooltip_text("Find missing artwork and metadata"); art.connect("clicked", self.match_artwork); bar.pack_start(art, False, False, 0)
        settings = Gtk.Button(label="⚙"); settings.set_tooltip_text("Settings"); settings.connect("clicked", self.settings); bar.pack_start(settings, False, False, 0)
        add = Gtk.Button(label="＋ Add folder"); add.get_style_context().add_class("pill"); add.connect("clicked", self.choose_folder); bar.pack_start(add, False, False, 0)
        self.root.pack_start(bar, False, False, 0)

    def content_box(self):
        old = self.scroll.get_child()
        if old: self.scroll.remove(old)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6); box.set_border_width(24); self.scroll.add(box); return box

    def welcome(self):
        box = self.content_box(); box.set_valign(Gtk.Align.CENTER); box.set_halign(Gtk.Align.CENTER)
        icon_path = app_icon_path()
        icon = Gtk.Image.new_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(str(icon_path), 128, 128, True)) if icon_path else Gtk.Image.new_from_icon_name("video-x-generic-symbolic", Gtk.IconSize.DIALOG)
        title = Gtk.Label(label="Your library. Anywhere."); title.get_style_context().add_class("brand")
        copy = Gtk.Label(label="Choose one or more folders and MediaShelf will build a private, offline library\nwithout moving or changing a single video.\n\nPortable data  •  Local artwork  •  No account  •  No telemetry"); copy.set_justify(Gtk.Justification.CENTER); copy.get_style_context().add_class("muted")
        action = Gtk.Button(label="Choose media folder"); action.get_style_context().add_class("pill"); action.connect("clicked", self.choose_folder)
        for widget in (icon, title, copy, action): box.pack_start(widget, False, False, 10)
        self.show_all()

    def choose_folder(self, *_):
        dialog = Gtk.FileChooserDialog("Choose your movies and TV folder", self, Gtk.FileChooserAction.SELECT_FOLDER, ("Cancel", Gtk.ResponseType.CANCEL, "Add folder", Gtk.ResponseType.OK))
        dialog.set_local_only(False); dialog.set_create_folders(False); dialog.set_default_response(Gtk.ResponseType.OK)
        if dialog.run() == Gtk.ResponseType.OK:
            selected = dialog.get_filename() or dialog.get_current_folder()
            if selected and Path(selected).is_dir():
                folder = Path(selected); lib_id = self.store.add_library(folder); dialog.destroy(); self.scan_async(lib_id, folder); return
        dialog.destroy()

    def scan_async(self, lib_id, folder):
        self.status.set_text(f"Scanning {folder.name}…")
        def work():
            try: count = self.store.scan(lib_id, folder); GLib.idle_add(self.scan_done, f"Found {count} video{'s' if count != 1 else ''}")
            except Exception as exc: GLib.idle_add(self.error, "Scan failed", str(exc))
        threading.Thread(target=work, daemon=True).start()

    def scan_done(self, message):
        self.status.set_text(message); self.refresh()
        if self.store.setting("automatic_artwork", "0") == "1": self.match_artwork()
        return False
    def rescan(self, *_):
        if not self.store.db: return self.choose_folder()
        rows = list(self.store.db.execute("SELECT id,path FROM libraries WHERE is_enabled=1"))
        for row in rows:
            if Path(row["path"]).exists(): self.scan_async(row["id"], Path(row["path"]))

    def search(self, entry): self.query = entry.get_text().lower().strip(); self.refresh()
    def set_filter(self, _button, value): self.filter = value; self.refresh()
    def set_sort(self, combo): self.sort = combo.get_active_id() or "title"; self.refresh()

    def refresh(self):
        box = self.content_box(); items = self.store.items()
        items = [x for x in items if self.query in x["display_title"].lower() or self.query in (x["filename"] or "").lower()]
        if self.filter in ("movie", "episode"): items = [x for x in items if x["kind"] == self.filter]
        if self.filter == "watched": items = [x for x in items if x["is_watched"]]
        if self.filter == "unwatched": items = [x for x in items if not x["is_watched"]]
        if self.filter == "favorite": items = [x for x in items if x["is_favorite"]]
        sort_keys = {
            "title": lambda x: ((x["display_title"] or "").lower(), x["season_number"] or 0, x["episode_number"] or 0),
            "added": lambda x: -(x["date_added"] or 0), "watched": lambda x: -(x["last_watched"] or 0),
            "year": lambda x: (-(x["year"] or 0), (x["display_title"] or "").lower()),
        }
        items.sort(key=sort_keys[self.sort])
        if not self.query and self.filter == "all": return self.home(box, items)
        heading = Gtk.Box(); label = Gtk.Label(label={"all":"Your Library","movie":"Movies","episode":"TV Shows","watched":"Watched","unwatched":"Unwatched","favorite":"Favorites"}[self.filter], xalign=0); label.get_style_context().add_class("section")
        self.status.set_text(f"{len(items)} title{'s' if len(items) != 1 else ''}"); self.status.get_style_context().add_class("muted")
        heading.pack_start(label, True, True, 0); heading.pack_end(self.status, False, False, 0); box.pack_start(heading, False, False, 0)
        if not items:
            empty = Gtk.Label(label="No titles here yet. Add a folder or adjust your search."); empty.get_style_context().add_class("muted"); box.pack_start(empty, True, True, 80)
        flow = Gtk.FlowBox(); flow.set_selection_mode(Gtk.SelectionMode.NONE); flow.set_column_spacing(18); flow.set_row_spacing(18); flow.set_max_children_per_line(8); flow.set_homogeneous(True)
        for item in items: flow.add(MediaCard(item, self.details))
        box.pack_start(flow, True, True, 0); self.show_all()

    def home(self, box, items):
        hero = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8); hero.get_style_context().add_class("hero")
        eyebrow = Gtk.Label(label="YOUR PRIVATE MEDIA LIBRARY", xalign=0); eyebrow.get_style_context().add_class("eyebrow")
        title = Gtk.Label(label="Everything you own, ready to watch.", xalign=0); title.get_style_context().add_class("brand")
        copy = Gtk.Label(label=f"{len(items)} videos across {len(self.store.libraries())} folder{'s' if len(self.store.libraries()) != 1 else ''}. Your files stay exactly where they are.", xalign=0); copy.get_style_context().add_class("muted")
        for widget in (eyebrow, title, copy): hero.pack_start(widget, False, False, 0)
        box.pack_start(hero, False, False, 4)
        episodes = [x for x in items if x["kind"] == "episode"]
        series = []
        seen = set()
        for item in episodes:
            key = item["display_title"].casefold()
            if key not in seen: seen.add(key); series.append(item)
        sections = [
            ("Continue Watching", [x for x in items if x["playback_position"] > 0 and not x["is_watched"]]),
            ("Movies", [x for x in items if x["kind"] == "movie"][:20]),
            ("TV Shows", series[:20]),
            ("Recently Added", sorted(items, key=lambda x: -(x["date_added"] or 0))[:20]),
        ]
        genres = sorted({g.strip() for x in items for g in (x["genre"] or "").split(",") if g.strip()})
        sections[3:3] = [(genre, [x for x in items if genre.casefold() in (x["genre"] or "").casefold()][:20]) for genre in genres]
        for name, section_items in sections:
            if not section_items: continue
            label = Gtk.Label(label=name, xalign=0); label.get_style_context().add_class("section"); box.pack_start(label, False, False, 0)
            flow = Gtk.FlowBox(); flow.set_selection_mode(Gtk.SelectionMode.NONE); flow.set_column_spacing(18); flow.set_row_spacing(18); flow.set_max_children_per_line(8); flow.set_homogeneous(True)
            for item in section_items: flow.add(MediaCard(item, self.details))
            box.pack_start(flow, False, False, 0)
        self.status.set_text(f"{len(items)} videos"); self.show_all()
        return None

    def details(self, item):
        dialog = Gtk.Dialog(title=item["display_title"], transient_for=self, flags=Gtk.DialogFlags.MODAL); dialog.set_default_size(920, 650)
        area = dialog.get_content_area(); area.set_border_width(24); area.set_spacing(16)
        hero = Gtk.Box(spacing=24)
        art = Gtk.Image(); artwork = item["poster_path"] or item["thumbnail_path"]
        try:
            if artwork and Path(artwork).exists(): art.set_from_pixbuf(GdkPixbuf.Pixbuf.new_from_file_at_scale(artwork, 220, 330, True))
            else: art.set_from_icon_name("video-x-generic-symbolic", Gtk.IconSize.DIALOG); art.set_pixel_size(96)
        except GLib.Error: pass
        hero.pack_start(art, False, False, 0)
        info_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        title = Gtk.Label(label=item["display_title"], xalign=0); title.set_line_wrap(True); title.get_style_context().add_class("brand"); info_box.pack_start(title, False, False, 0)
        if item["kind"] == "episode": info = f"Season {item['season_number'] or 0}  •  Episode {item['episode_number'] or 0}"
        else: info = f"Movie{('  •  ' + str(item['year'])) if item['year'] else ''}"
        if item["genre"]: info += "  •  " + item["genre"]
        info_box.pack_start(Gtk.Label(label=info, xalign=0), False, False, 0)
        summary = Gtk.Label(label=item["summary"] or "No description yet. Use Edit Details to add one.", xalign=0); summary.set_line_wrap(True); summary.set_max_width_chars(62); summary.get_style_context().add_class("muted"); info_box.pack_start(summary, False, False, 0)
        path = Gtk.Label(label=item["absolute_path"], xalign=0); path.set_line_wrap(True); path.set_selectable(True); path.get_style_context().add_class("muted"); info_box.pack_start(path, False, False, 0)
        buttons = Gtk.Box(spacing=10); play = Gtk.Button(label="▶  Play in Celluloid"); play.get_style_context().add_class("pill"); play.connect("clicked", lambda *_: self.play(item, dialog))
        favorite = Gtk.Button(label="★ Favorite" if not item["is_favorite"] else "★ Favorited"); favorite.connect("clicked", lambda *_: self.toggle_favorite(item, dialog))
        watched = Gtk.Button(label="✓ Mark watched" if not item["is_watched"] else "↶ Mark unwatched"); watched.connect("clicked", lambda *_: self.toggle_watched(item, dialog))
        restart = Gtk.Button(label="↶ Restart"); restart.connect("clicked", lambda *_: self.restart(item, dialog))
        for b in (play, favorite, watched): buttons.pack_start(b, False, False, 0)
        if item["playback_position"] > 0: buttons.pack_start(restart, False, False, 0)
        info_box.pack_start(buttons, False, False, 0)
        tools = Gtk.Box(spacing=8)
        tool_actions = (("Edit Details…", lambda: self.edit_details(item, dialog)), ("Choose Poster…", lambda: self.choose_artwork(item, dialog, "poster")), ("Choose Backdrop…", lambda: self.choose_artwork(item, dialog, "backdrop")), ("Show File", lambda: self.show_file(item, dialog)))
        for label, callback in tool_actions:
            button = Gtk.Button(label=label); button.connect("clicked", lambda _b, cb=callback: cb()); tools.pack_start(button, False, False, 0)
        if item["poster_path"] or item["backdrop_path"]:
            remove_art = Gtk.Button(label="Remove Artwork…"); remove_art.connect("clicked", lambda *_: self.remove_artwork(item, dialog)); tools.pack_start(remove_art, False, False, 0)
        info_box.pack_start(tools, False, False, 0); hero.pack_start(info_box, True, True, 0); area.pack_start(hero, True, True, 0)
        if item["kind"] == "episode":
            episodes = list(self.store.db.execute("SELECT * FROM media_items WHERE kind='episode' AND display_title=? AND is_available=1 ORDER BY season_number,episode_number", (item["display_title"],)))
            if episodes:
                label = Gtk.Label(label="Episodes", xalign=0); label.get_style_context().add_class("section"); area.pack_start(label, False, False, 0)
                episode_box = Gtk.FlowBox(); episode_box.set_max_children_per_line(5); episode_box.set_selection_mode(Gtk.SelectionMode.NONE)
                for episode in episodes:
                    caption = f"S{episode['season_number'] or 0:02} E{episode['episode_number'] or 0:02}  {episode['episode_title'] or ''}".strip()
                    button = Gtk.Button(label=caption); button.connect("clicked", lambda _b, ep=episode: self.play(ep, dialog)); episode_box.add(button)
                area.pack_start(episode_box, False, False, 0)
        dialog.add_button("Back to Browse", Gtk.ResponseType.CLOSE); dialog.show_all(); dialog.run(); dialog.destroy()

    def play(self, item, dialog):
        try:
            player = shutil.which("celluloid") or shutil.which("mpv") or shutil.which("vlc")
            if not player: raise RuntimeError("Install Celluloid, mpv, or VLC to play videos.")
            command = [player]
            if item["playback_position"] and not item["is_watched"]:
                if Path(player).name == "mpv": command.append(f"--start={int(item['playback_position'])}")
                elif Path(player).name == "celluloid": command.append(f"--mpv-options=start={int(item['playback_position'])}")
            command.append(item["absolute_path"]); subprocess.Popen(command, start_new_session=True)
            self.store.db.execute("UPDATE media_items SET last_watched=? WHERE id=?", (time.time(), item["id"])); self.store.db.commit(); dialog.response(Gtk.ResponseType.CLOSE)
        except Exception as exc: self.error("Could not start playback", str(exc))

    def toggle_favorite(self, item, dialog): self._toggle(item, dialog, "is_favorite")
    def toggle_watched(self, item, dialog): self._toggle(item, dialog, "is_watched")
    def restart(self, item, dialog): self.store.update_item(item["id"], playback_position=0, is_watched=0); dialog.response(Gtk.ResponseType.CLOSE); self.refresh()
    def _toggle(self, item, dialog, field):
        self.store.db.execute(f"UPDATE media_items SET {field}=? WHERE id=?", (0 if item[field] else 1, item["id"])); self.store.db.commit(); dialog.response(Gtk.ResponseType.CLOSE); self.refresh()

    def edit_details(self, item, parent):
        dialog = Gtk.Dialog(title="Edit Details", transient_for=parent, flags=Gtk.DialogFlags.MODAL)
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Save", Gtk.ResponseType.OK); dialog.set_default_size(540, 470)
        grid = Gtk.Grid(column_spacing=12, row_spacing=12); grid.set_border_width(20); dialog.get_content_area().add(grid)
        fields = {}
        values = (("Title", "display_title", item["display_title"] or ""), ("Year", "year", item["year"] or ""), ("Genre", "genre", item["genre"] or ""), ("Season", "season_number", item["season_number"] or ""), ("Episode", "episode_number", item["episode_number"] or ""), ("Episode title", "episode_title", item["episode_title"] or ""))
        for row, (label, key, value) in enumerate(values):
            grid.attach(Gtk.Label(label=label, xalign=1), 0, row, 1, 1); entry = Gtk.Entry(); entry.set_text(str(value)); grid.attach(entry, 1, row, 1, 1); fields[key] = entry
        summary = Gtk.TextView(); summary.set_wrap_mode(Gtk.WrapMode.WORD); summary.get_buffer().set_text(item["summary"] or "")
        grid.attach(Gtk.Label(label="Description", xalign=1, yalign=0), 0, len(values), 1, 1); scroll = Gtk.ScrolledWindow(); scroll.set_size_request(-1, 120); scroll.add(summary); grid.attach(scroll, 1, len(values), 1, 1)
        dialog.show_all()
        if dialog.run() == Gtk.ResponseType.OK:
            start, end = summary.get_buffer().get_bounds()
            def number(key):
                value = fields[key].get_text().strip(); return int(value) if value.isdigit() else None
            self.store.update_item(item["id"], display_title=fields["display_title"].get_text().strip() or item["display_title"], year=number("year"), genre=fields["genre"].get_text().strip() or None, season_number=number("season_number"), episode_number=number("episode_number"), episode_title=fields["episode_title"].get_text().strip() or None, summary=summary.get_buffer().get_text(start, end, True).strip() or None, manual_metadata=1)
            parent.response(Gtk.ResponseType.CLOSE); self.refresh()
        dialog.destroy()

    def choose_artwork(self, item, parent, role="poster"):
        label = "Poster" if role == "poster" else "Backdrop"
        chooser = Gtk.FileChooserDialog(f"Choose {label}", parent, Gtk.FileChooserAction.OPEN, ("Cancel", Gtk.ResponseType.CANCEL, f"Use {label}", Gtk.ResponseType.OK))
        image_filter = Gtk.FileFilter(); image_filter.set_name("Images"); [image_filter.add_pattern(pattern) for pattern in ("*.jpg", "*.jpeg", "*.png", "*.webp")]; chooser.add_filter(image_filter)
        if chooser.run() == Gtk.ResponseType.OK:
            source = Path(chooser.get_filename()); target_dir = self.store.data_root / "Artwork" / item["id"]; target_dir.mkdir(parents=True, exist_ok=True); target = target_dir / (role + source.suffix.lower()); shutil.copy2(source, target)
            values = {f"{role}_path": str(target), f"manual_{role}": 1}; self.store.update_item(item["id"], **values); chooser.destroy(); parent.response(Gtk.ResponseType.CLOSE); self.refresh(); return
        chooser.destroy()

    def remove_artwork(self, item, parent):
        dialog = Gtk.MessageDialog(parent, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "Remove artwork")
        dialog.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Poster", 1, "Backdrop", 2)
        response = dialog.run(); dialog.destroy()
        role = "poster" if response == 1 else "backdrop" if response == 2 else None
        if role:
            stored = item[f"{role}_path"]
            if stored and self.store.data_root in Path(stored).parents:
                try: Path(stored).unlink()
                except OSError: pass
            self.store.update_item(item["id"], **{f"{role}_path": None, f"manual_{role}": 0}); parent.response(Gtk.ResponseType.CLOSE); self.refresh()

    def show_file(self, item, _parent):
        try: subprocess.Popen(["xdg-open", str(Path(item["absolute_path"]).parent)], start_new_session=True)
        except Exception as exc: self.error("Could not open folder", str(exc))

    def settings(self, *_):
        if not self.store.db: return self.choose_folder()
        dialog = Gtk.Dialog(title="MediaShelf Settings", transient_for=self, flags=Gtk.DialogFlags.MODAL); dialog.set_default_size(720, 560)
        area = dialog.get_content_area(); area.set_border_width(22); area.set_spacing(14)
        heading = Gtk.Label(label="Library Folders", xalign=0); heading.get_style_context().add_class("section"); area.pack_start(heading, False, False, 0)
        for library in self.store.libraries():
            row = Gtk.Box(spacing=10); toggle = Gtk.CheckButton(label=library["display_name"]); toggle.set_active(bool(library["is_enabled"])); toggle.set_tooltip_text(library["path"])
            toggle.connect("toggled", lambda button, lib_id=library["id"]: self.store.set_library_enabled(lib_id, button.get_active()))
            remove = Gtk.Button(label="Remove"); remove.connect("clicked", lambda _b, lib_id=library["id"], name=library["display_name"]: self.remove_library(lib_id, name, dialog))
            row.pack_start(toggle, True, True, 0); row.pack_end(remove, False, False, 0); area.pack_start(row, False, False, 0)
        artwork = Gtk.CheckButton(label="Automatically match missing posters and metadata after scanning")
        artwork.set_active(self.store.setting("automatic_artwork", "0") == "1"); artwork.connect("toggled", lambda b: self.store.set_setting("automatic_artwork", int(b.get_active()))); area.pack_start(artwork, False, False, 8)
        privacy = Gtk.Label(label="No accounts, analytics, telemetry, advertising, or uploads. Automatic artwork sends only the parsed title, media type, and year to Cinemeta.", xalign=0); privacy.set_line_wrap(True); privacy.get_style_context().add_class("muted"); area.pack_start(privacy, False, False, 0)
        location = Gtk.Label(label=f"Portable data: {self.store.data_root}", xalign=0); location.set_selectable(True); location.get_style_context().add_class("muted"); area.pack_start(location, False, False, 0)
        controls = Gtk.Box(spacing=8); add = Gtk.Button(label="Add Folder…"); add.connect("clicked", lambda *_: (dialog.response(Gtk.ResponseType.CLOSE), self.choose_folder())); refresh = Gtk.Button(label="Refresh Library"); refresh.connect("clicked", lambda *_: (dialog.response(Gtk.ResponseType.CLOSE), self.rescan())); controls.pack_start(add, False, False, 0); controls.pack_start(refresh, False, False, 0); area.pack_start(controls, False, False, 0)
        dialog.add_button("Close", Gtk.ResponseType.CLOSE); dialog.show_all(); dialog.run(); dialog.destroy(); self.refresh()

    def remove_library(self, lib_id, name, parent):
        confirm = Gtk.MessageDialog(parent, Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING, Gtk.ButtonsType.OK_CANCEL, f"Remove {name} from MediaShelf?"); confirm.format_secondary_text("Indexed entries will be removed. Video files are never deleted.")
        if confirm.run() == Gtk.ResponseType.OK: self.store.remove_library(lib_id); parent.response(Gtk.ResponseType.CLOSE)
        confirm.destroy()

    def match_artwork(self, *_):
        if not self.store.db: return
        self.status.set_text("Matching artwork…")
        def work():
            changed = 0
            rows = list(self.store.db.execute("SELECT * FROM media_items WHERE is_available=1 AND (poster_path IS NULL OR summary IS NULL) ORDER BY display_title"))
            handled = {}
            for item in rows:
                key = (item["kind"], item["display_title"].casefold(), item["year"])
                try:
                    match = handled.get(key)
                    if key not in handled:
                        kind = "series" if item["kind"] == "episode" else "movie"
                        url = f"https://v3-cinemeta.strem.io/catalog/{kind}/top/search={quote(item['display_title'])}.json"
                        request = Request(url, headers={"User-Agent": "MediaShelf/0.2"})
                        payload = json.loads(urlopen(request, timeout=12).read().decode("utf-8")); candidates = payload.get("metas", [])
                        match = next((x for x in candidates if (x.get("name") or "").casefold() == item["display_title"].casefold()), candidates[0] if candidates else None); handled[key] = match
                    if not match: continue
                    poster_path = item["poster_path"]
                    if not poster_path and match.get("poster"):
                        target_dir = self.store.data_root / "Artwork" / item["id"]; target_dir.mkdir(parents=True, exist_ok=True); target = target_dir / "poster.jpg"
                        target.write_bytes(urlopen(Request(match["poster"], headers={"User-Agent": "MediaShelf/0.2"}), timeout=15).read()); poster_path = str(target)
                    self.store.update_item(item["id"], poster_path=poster_path, summary=item["summary"] or match.get("description"), genre=item["genre"] or ", ".join(match.get("genres", [])[:3]) or None)
                    changed += 1
                except Exception:
                    continue
            GLib.idle_add(self.artwork_done, changed)
        threading.Thread(target=work, daemon=True).start()

    def artwork_done(self, changed): self.status.set_text(f"Updated artwork for {changed} title{'s' if changed != 1 else ''}"); self.refresh(); return False

    def error(self, title, detail):
        dialog = Gtk.MessageDialog(self, 0, Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE, title); dialog.format_secondary_text(detail); dialog.run(); dialog.destroy(); return False


class Application(Gtk.Application):
    def __init__(self): super().__init__(application_id="earth.degenerate.MediaShelf")
    def do_activate(self):
        window = self.props.active_window or Window(self); window.present()


if __name__ == "__main__":
    raise SystemExit(Application().run(None))
