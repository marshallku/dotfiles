#!/usr/bin/env python3
"""GTK layer-shell control panel for the waybar YouTube Music module.

Shows album art, title/artist, a seekable progress bar with time, and
previous / play-pause / next controls for the current MPRIS player.

The player is chosen by ytmusic_status.sh --player (single source of truth),
so the panel always drives whatever the bar module is showing.

Deps: python-gobject, gtk3, gtk-layer-shell, playerctl. All already present.
"""
import hashlib
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, GtkLayerShell  # noqa: E402

SCRIPT_DIR = Path(__file__).resolve().parent
STATUS_SH = SCRIPT_DIR / "ytmusic_status.sh"
ART_SIZE = 220
PANEL_W = ART_SIZE + 36
BAR_GAP = 6  # gap below waybar; its exclusive zone already reserves the bar height
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "waybar-ytmusic"

CSS = b"""
window { background-color: transparent; }
.card { background-color: rgba(12, 12, 24, 0.97); border: 1px solid rgba(180,160,255,0.18);
        border-radius: 16px; }
.title  { color: #e2e0f0; font-size: 15px; font-weight: 700; }
.artist { color: #b8b5d0; font-size: 12px; }
.time   { color: #8885a5; font-size: 10px; font-family: "JetBrainsMono Nerd Font", monospace; }
.artph  { background: rgba(30,28,48,0.96); border-radius: 12px; color: #6f6c8f; font-size: 64px; }
scale trough { min-height: 5px; background: rgba(255,255,255,0.12); border-radius: 3px; }
scale highlight { background: #f28b82; border-radius: 3px; }
scale slider { min-width: 12px; min-height: 12px; background: #f28b82; border-radius: 50%;
               margin: -5px; }
button.ctl { background: transparent; border: none; color: #e2e0f0; font-size: 20px;
             font-family: "JetBrainsMono Nerd Font", monospace; padding: 6px 10px; }
button.ctl:hover { background: rgba(180,160,255,0.12); border-radius: 10px; }
button.play { font-size: 26px; color: #f28b82; }
"""

ICON_PREV, ICON_NEXT = "󰒮", "󰒭"
ICON_PLAY, ICON_PAUSE = "󰐊", "󰏦"
ICON_NOTE = "󰎇"


def player() -> str:
    """Current MPRIS instance the bar is showing (empty string if none)."""
    try:
        out = subprocess.run(["bash", str(STATUS_SH), "--player"],
                             capture_output=True, text=True, timeout=3)
        return out.stdout.strip()
    except Exception:
        return ""


def meta(p: str) -> dict:
    """One playerctl call for every field the panel needs."""
    if not p:
        return {}
    fmt = ("{{status}}\t{{mpris:artUrl}}\t{{xesam:title}}\t{{xesam:artist}}"
           "\t{{xesam:album}}\t{{mpris:length}}\t{{position}}")
    try:
        out = subprocess.run(["playerctl", "-p", p, "metadata", "--format", fmt],
                             capture_output=True, text=True, timeout=3)
        if out.returncode != 0:
            return {}
        f = (out.stdout.rstrip("\n").split("\t") + [""] * 7)[:7]
        return {"status": f[0], "art": f[1], "title": f[2], "artist": f[3],
                "album": f[4], "length": _int(f[5]), "position": _int(f[6])}
    except Exception:
        return {}


def _int(s: str) -> int:
    try:
        return int(s)
    except (ValueError, TypeError):
        return 0


def fmt_time(us: int) -> str:
    s = max(0, us) // 1_000_000
    return f"{s // 60}:{s % 60:02d}"


class Panel(Gtk.Window):
    def __init__(self):
        super().__init__()
        self._player = player()
        self._art_key = None      # url currently displayed, to avoid re-fetch
        self._seeking = False     # user is dragging the scale

        visual = self.get_screen().get_rgba_visual()
        if visual is not None:
            self.set_visual(visual)   # so the surface outside the card is truly transparent

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        # No keyboard grab: a full-monitor overlay with keyboard focus disrupts the
        # session. Dismissal is pointer-based (click outside the card) + widget re-click.
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.NONE)
        self._left = self._left_margin()  # pins the cursor's monitor, returns card offset
        # Fill the monitor so a click anywhere outside the card dismisses the panel.
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                     GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
            GtkLayerShell.set_anchor(self, edge, True)

        self._misses = 0          # consecutive refreshes with no player
        self._tick = None

        self._build()

    def _left_margin(self):
        """Anchor the panel under the click: pin to the cursor's monitor and centre
        the panel under the cursor x, clamped to that monitor. Falls back to 8px."""
        display = Gdk.Display.get_default()
        cur = None
        if len(sys.argv) >= 3:
            try:
                cur = (int(sys.argv[1]), int(sys.argv[2]))
            except ValueError:
                cur = None
        mon = display.get_monitor_at_point(*cur) if cur else None
        if mon is None:
            mon = display.get_primary_monitor() or display.get_monitor(0)
        if mon is not None:
            GtkLayerShell.set_monitor(self, mon)
        if cur is None or mon is None:
            return 8
        geo = mon.get_geometry()
        left = cur[0] - geo.x - PANEL_W // 2
        return max(8, min(left, geo.width - PANEL_W - 8))

    def _build(self):
        style = Gtk.CssProvider()
        style.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), style, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        # The card is the visible panel; it floats over a full-monitor transparent
        # event-catcher so any click outside the card closes the panel.
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        root.get_style_context().add_class("card")
        root.set_border_width(18)
        root.set_size_request(PANEL_W, -1)
        root.set_halign(Gtk.Align.START)
        root.set_valign(Gtk.Align.START)
        root.set_margin_start(self._left)
        root.set_margin_top(BAR_GAP)

        catcher = Gtk.EventBox()
        catcher.connect("button-press-event", lambda *_: (self.close_panel(), True)[1])
        overlay = Gtk.Overlay()
        overlay.add(catcher)
        overlay.add_overlay(root)
        self.add(overlay)

        self.art = Gtk.Image()
        self.art_ph = Gtk.Label(label=ICON_NOTE)
        self.art_ph.get_style_context().add_class("artph")
        self.art_ph.set_size_request(ART_SIZE, ART_SIZE)
        self.art_stack = Gtk.Stack()
        self.art_stack.add_named(self.art_ph, "ph")
        self.art_stack.add_named(self.art, "img")
        self.art_stack.set_halign(Gtk.Align.CENTER)
        root.pack_start(self.art_stack, False, False, 0)

        self.title = Gtk.Label(xalign=0)
        self.title.get_style_context().add_class("title")
        self.title.set_line_wrap(True)
        self.title.set_max_width_chars(24)
        self.title.set_lines(2)
        self.title.set_ellipsize(3)  # END
        root.pack_start(self.title, False, False, 0)

        self.artist = Gtk.Label(xalign=0)
        self.artist.get_style_context().add_class("artist")
        self.artist.set_ellipsize(3)
        root.pack_start(self.artist, False, False, 0)

        # Scale + time labels live together so they can be hidden as a unit
        # when the player exposes no track length (e.g. Firefox).
        self.progress = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL)
        self.scale.set_draw_value(False)
        self.scale.set_range(0, 1)
        self.scale.connect("button-press-event", self._seek_start)
        self.scale.connect("button-release-event", self._seek_end)
        self.progress.pack_start(self.scale, False, False, 0)

        times = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.t_pos = Gtk.Label(label="0:00", xalign=0)
        self.t_len = Gtk.Label(label="0:00", xalign=1)
        for w in (self.t_pos, self.t_len):
            w.get_style_context().add_class("time")
        times.pack_start(self.t_pos, True, True, 0)
        times.pack_end(self.t_len, True, True, 0)
        self.progress.pack_start(times, False, False, 0)
        root.pack_start(self.progress, False, False, 0)

        ctl = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        ctl.set_halign(Gtk.Align.CENTER)
        self.b_prev = self._btn(ICON_PREV, "previous")
        self.b_play = self._btn(ICON_PLAY, "play-pause", extra="play")
        self.b_next = self._btn(ICON_NEXT, "next")
        for b in (self.b_prev, self.b_play, self.b_next):
            ctl.pack_start(b, False, False, 0)
        root.pack_start(ctl, False, False, 0)

    def _btn(self, label, action, extra=None):
        b = Gtk.Button(label=label)
        b.get_style_context().add_class("ctl")
        if extra:
            b.get_style_context().add_class(extra)
        b.connect("clicked", lambda _w: self._cmd(action))
        return b

    def _cmd(self, action):
        if self._player:
            subprocess.run(["playerctl", "-p", self._player, action],
                           capture_output=True, timeout=3)
        # One-shot re-read so the new state shows fast (refresh() returns True and
        # would otherwise turn this into a permanent 120ms poll loop).
        GLib.timeout_add(120, lambda: self.refresh() and False)

    def _seek_start(self, *_):
        self._seeking = True

    def _seek_end(self, *_):
        if self._player:
            secs = self.scale.get_value() / 1_000_000
            subprocess.run(["playerctl", "-p", self._player, "position", f"{secs:.0f}"],
                           capture_output=True, timeout=3)
        self._seeking = False
        return False

    def _set_art(self, url):
        if url == self._art_key:
            return
        self._art_key = url
        path = self._art_path(url)
        if path and Path(path).exists():
            try:
                pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, ART_SIZE, ART_SIZE, True)
                self.art.set_from_pixbuf(pb)
                self.art_stack.set_visible_child_name("img")
                return
            except GLib.Error:
                pass
        self.art_stack.set_visible_child_name("ph")

    def _art_path(self, url):
        if not url:
            return None
        if url.startswith("file://"):
            return url[7:]
        if url.startswith("http"):
            CACHE_DIR.mkdir(parents=True, exist_ok=True)
            # Stable key so art is reused across panel launches (hash() is per-process salted).
            dest = CACHE_DIR / (hashlib.md5(url.encode()).hexdigest() + ".img")
            if not dest.exists():
                try:
                    req = urllib.request.Request(url, headers={"User-Agent": "waybar-ytmusic"})
                    with urllib.request.urlopen(req, timeout=4) as r:
                        dest.write_bytes(r.read())
                except Exception:
                    return None
            return str(dest)
        return None

    def start(self):
        """Populate once and begin the update timer (called after the loop starts)."""
        self.refresh()
        self._tick = GLib.timeout_add_seconds(1, self.refresh)
        return False

    def refresh(self):
        self._player = player()
        m = meta(self._player)
        if not m or not m.get("title"):
            # Tolerate a transient miss (e.g. track change) before closing.
            self._misses += 1
            if self._misses >= 2:
                self.close_panel()
                return False
            return True
        self._misses = 0

        self.title.set_text(m["title"])
        self.artist.set_text(m["artist"] or m["album"] or "")
        self.b_play.set_label(ICON_PAUSE if m["status"] == "Playing" else ICON_PLAY)
        self._set_art(m["art"])

        length, pos = m["length"], m["position"]
        if length > 0:
            self.progress.show()
            self.scale.set_range(0, length)
            if not self._seeking:
                self.scale.set_value(min(pos, length))
            self.t_pos.set_text(fmt_time(pos))
            self.t_len.set_text(fmt_time(length))
        else:
            # No length (e.g. Firefox) — hide the useless bar entirely.
            self.progress.hide()
        return True

    def close_panel(self):
        if self._tick:
            GLib.source_remove(self._tick)
            self._tick = None
        if Gtk.main_level() > 0:
            Gtk.main_quit()


def main():
    win = Panel()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    GLib.idle_add(win.start)
    Gtk.main()


if __name__ == "__main__":
    main()
