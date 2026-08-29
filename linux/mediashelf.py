#!/usr/bin/env python3
"""MediaShelf for Linux: a lightweight GTK client for the portable library."""
import hashlib
import os
import re
import sqlite3
import subprocess
import threading
import time
import uuid
from pathlib import Path

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk

APP = "MediaShelf"
VIDEO_EXTENSIONS = {".mp4", ".mkv", ".m4v", ".mov", ".avi", ".webm", ".mpeg", ".mpg", ".ts"}
RELEASE = {"480p", "720p", "1080p", "1080i", "2160p", "4k", "uhd", "bluray", "brrip", "bdrip", "web-dl", "webdl", "webrip", "hdtv", "remux", "x264", "x265", "h264", "h265", "hevc", "av1", "hdr", "hdr10", "dv", "aac", "ac3", "eac3", "dts", "truehd", "atmos", "10bit", "proper", "repack", "extended"}


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
            if not data.exists():
                return False
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
            thumbnail = self.db_path.parent / "Thumbnails" / f"{stable}.jpg"
            if not poster and not thumbnail.exists():
                try:
                    subprocess.run(["ffmpegthumbnailer", "-i", str(path), "-o", str(thumbnail), "-s", "360", "-t", "15", "-q", "7"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
                except (OSError, subprocess.TimeoutExpired):
                    pass
            thumbnail_value = str(thumbnail) if thumbnail.exists() else None
            self.db.execute("""INSERT INTO media_items(id,library_id,kind,absolute_path,relative_path,filename,file_size,modified_at,parsed_title,display_title,year,season_number,episode_number,episode_title,date_added,poster_path,is_available,last_seen_scan)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,1,?) ON CONFLICT(id) DO UPDATE SET absolute_path=excluded.absolute_path,file_size=excluded.file_size,modified_at=excluded.modified_at,is_available=1,last_seen_scan=excluded.last_seen_scan,poster_path=COALESCE(media_items.poster_path,excluded.poster_path)""",
            (stable, lib_id, kind, str(path), rel, path.name, stat.st_size, stat.st_mtime, title, title, year, season, episode, episode_title, now, poster, now))
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
        box.pack_start(image, True, True, 0); box.pack_start(text, False, False, 0); self.add(box)
        self.connect("clicked", lambda *_: activate(item))


class Window(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title=APP); self.set_default_size(1180, 760); self.maximize()
        self.store = Store(); self.query = ""; self.filter = "all"; self.status = Gtk.Label()
        provider = Gtk.CssProvider(); provider.load_from_data(CSS); Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL); self.add(self.root); self.build_header()
        self.scroll = Gtk.ScrolledWindow(); self.scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC); self.root.pack_start(self.scroll, True, True, 0)
        if self.store.open_for(): self.refresh()
        else: self.welcome()

    def build_header(self):
        bar = Gtk.Box(spacing=12); bar.get_style_context().add_class("topbar")
        brand = Gtk.Label(label="◈  MediaShelf"); brand.get_style_context().add_class("brand"); bar.pack_start(brand, False, False, 4)
        for label, value in (("All", "all"), ("Movies", "movie"), ("TV Shows", "episode"), ("Favorites", "favorite")):
            button = Gtk.Button(label=label); button.connect("clicked", self.set_filter, value); bar.pack_start(button, False, False, 0)
        search = Gtk.SearchEntry(); search.set_placeholder_text("Search your library"); search.set_size_request(260, -1); search.connect("search-changed", self.search); bar.pack_start(search, True, False, 12)
        scan = Gtk.Button(label="↻  Refresh"); scan.connect("clicked", self.rescan); bar.pack_start(scan, False, False, 0)
        add = Gtk.Button(label="＋ Add folder"); add.get_style_context().add_class("pill"); add.connect("clicked", self.choose_folder); bar.pack_start(add, False, False, 0)
        self.root.pack_start(bar, False, False, 0)

    def content_box(self):
        old = self.scroll.get_child()
        if old: self.scroll.remove(old)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6); box.set_border_width(24); self.scroll.add(box); return box

    def welcome(self):
        box = self.content_box(); box.set_valign(Gtk.Align.CENTER); box.set_halign(Gtk.Align.CENTER)
        icon = Gtk.Image.new_from_icon_name("video-x-generic-symbolic", Gtk.IconSize.DIALOG); icon.set_pixel_size(96)
        title = Gtk.Label(label="Your movies. Your drive. Your private streaming service."); title.get_style_context().add_class("brand")
        copy = Gtk.Label(label="Choose a media folder to build your local library.\nMediaShelf never moves, renames, or uploads your files."); copy.set_justify(Gtk.Justification.CENTER); copy.get_style_context().add_class("muted")
        action = Gtk.Button(label="Choose media folder"); action.get_style_context().add_class("pill"); action.connect("clicked", self.choose_folder)
        for widget in (icon, title, copy, action): box.pack_start(widget, False, False, 10)
        self.show_all()

    def choose_folder(self, *_):
        dialog = Gtk.FileChooserDialog("Choose your movies and TV folder", self, Gtk.FileChooserAction.SELECT_FOLDER, ("Cancel", Gtk.ResponseType.CANCEL, "Add folder", Gtk.ResponseType.OK))
        if dialog.run() == Gtk.ResponseType.OK:
            folder = Path(dialog.get_filename()); lib_id = self.store.add_library(folder); dialog.destroy(); self.scan_async(lib_id, folder); return
        dialog.destroy()

    def scan_async(self, lib_id, folder):
        self.status.set_text(f"Scanning {folder.name}…")
        def work():
            try: count = self.store.scan(lib_id, folder); GLib.idle_add(self.scan_done, f"Found {count} video{'s' if count != 1 else ''}")
            except Exception as exc: GLib.idle_add(self.error, "Scan failed", str(exc))
        threading.Thread(target=work, daemon=True).start()

    def scan_done(self, message): self.status.set_text(message); self.refresh(); return False
    def rescan(self, *_):
        if not self.store.db: return self.choose_folder()
        rows = list(self.store.db.execute("SELECT id,path FROM libraries WHERE is_enabled=1"))
        for row in rows:
            if Path(row["path"]).exists(): self.scan_async(row["id"], Path(row["path"]))

    def search(self, entry): self.query = entry.get_text().lower().strip(); self.refresh()
    def set_filter(self, _button, value): self.filter = value; self.refresh()

    def refresh(self):
        box = self.content_box(); items = self.store.items()
        items = [x for x in items if self.query in x["display_title"].lower() or self.query in (x["filename"] or "").lower()]
        if self.filter in ("movie", "episode"): items = [x for x in items if x["kind"] == self.filter]
        if self.filter == "favorite": items = [x for x in items if x["is_favorite"]]
        heading = Gtk.Box(); label = Gtk.Label(label={"all":"Your Library","movie":"Movies","episode":"TV Shows","favorite":"Favorites"}[self.filter], xalign=0); label.get_style_context().add_class("section")
        self.status.set_text(f"{len(items)} title{'s' if len(items) != 1 else ''}"); self.status.get_style_context().add_class("muted")
        heading.pack_start(label, True, True, 0); heading.pack_end(self.status, False, False, 0); box.pack_start(heading, False, False, 0)
        if not items:
            empty = Gtk.Label(label="No titles here yet. Add a folder or adjust your search."); empty.get_style_context().add_class("muted"); box.pack_start(empty, True, True, 80)
        flow = Gtk.FlowBox(); flow.set_selection_mode(Gtk.SelectionMode.NONE); flow.set_column_spacing(18); flow.set_row_spacing(18); flow.set_max_children_per_line(8); flow.set_homogeneous(True)
        for item in items: flow.add(MediaCard(item, self.details))
        box.pack_start(flow, True, True, 0); self.show_all()

    def details(self, item):
        dialog = Gtk.Dialog(title=item["display_title"], transient_for=self, flags=Gtk.DialogFlags.MODAL); dialog.set_default_size(560, 360)
        area = dialog.get_content_area(); area.set_border_width(24); area.set_spacing(12)
        title = Gtk.Label(label=item["display_title"], xalign=0); title.get_style_context().add_class("brand"); area.pack_start(title, False, False, 0)
        if item["kind"] == "episode": info = f"Season {item['season_number'] or 0}  •  Episode {item['episode_number'] or 0}"
        else: info = f"Movie{('  •  ' + str(item['year'])) if item['year'] else ''}"
        area.pack_start(Gtk.Label(label=info, xalign=0), False, False, 0)
        path = Gtk.Label(label=item["absolute_path"], xalign=0); path.set_line_wrap(True); path.get_style_context().add_class("muted"); area.pack_start(path, False, False, 0)
        buttons = Gtk.Box(spacing=10); play = Gtk.Button(label="▶  Play in Celluloid"); play.get_style_context().add_class("pill"); play.connect("clicked", lambda *_: self.play(item, dialog))
        favorite = Gtk.Button(label="★ Favorite" if not item["is_favorite"] else "★ Favorited"); favorite.connect("clicked", lambda *_: self.toggle_favorite(item, dialog))
        watched = Gtk.Button(label="✓ Mark watched" if not item["is_watched"] else "↶ Mark unwatched"); watched.connect("clicked", lambda *_: self.toggle_watched(item, dialog))
        for b in (play, favorite, watched): buttons.pack_start(b, False, False, 0)
        area.pack_end(buttons, False, False, 0); dialog.add_button("Close", Gtk.ResponseType.CLOSE); dialog.show_all(); dialog.run(); dialog.destroy()

    def play(self, item, dialog):
        try:
            subprocess.Popen(["celluloid", item["absolute_path"]], start_new_session=True)
            self.store.db.execute("UPDATE media_items SET last_watched=? WHERE id=?", (time.time(), item["id"])); self.store.db.commit(); dialog.response(Gtk.ResponseType.CLOSE)
        except Exception as exc: self.error("Could not start playback", str(exc))

    def toggle_favorite(self, item, dialog): self._toggle(item, dialog, "is_favorite")
    def toggle_watched(self, item, dialog): self._toggle(item, dialog, "is_watched")
    def _toggle(self, item, dialog, field):
        self.store.db.execute(f"UPDATE media_items SET {field}=? WHERE id=?", (0 if item[field] else 1, item["id"])); self.store.db.commit(); dialog.response(Gtk.ResponseType.CLOSE); self.refresh()

    def error(self, title, detail):
        dialog = Gtk.MessageDialog(self, 0, Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE, title); dialog.format_secondary_text(detail); dialog.run(); dialog.destroy(); return False


class Application(Gtk.Application):
    def __init__(self): super().__init__(application_id="earth.degenerate.MediaShelf")
    def do_activate(self):
        window = self.props.active_window or Window(self); window.present()


if __name__ == "__main__":
    raise SystemExit(Application().run(None))
