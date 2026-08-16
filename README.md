# YT Mini — floating YouTube window for Omarchy Quattro

A small YouTube player owned by the Omarchy shell itself: a layer-shell panel
window (no browser, no mpv toplevel, no compositor windowrules). Renders
natively through QtMultimedia inside `omarchy-shell`.

Built for two use cases:

- **Music videos while you code** — hand it a playlist and the queue
  auto-advances all afternoon.
- **Instructional follow-alongs** — grab mode downloads first, so seeking and
  pausing are instant; no rebuffering, no stream expiry.

## Plugin kinds

- `panel` (`YtPanel.qml`) — the floating window
- `bar-widget` (`BarWidget.qml`) — trigger button
- `keepLoaded: true` — hiding the window does not stop playback; queue and
  audio survive, click the bar widget to bring the window back.

## Handing off videos

1. **From the browser (Helium/any Chromium):** a one-time setup registers the
   `ytmini://` scheme, then a bookmarklet throws the current tab in one click —
   see **Throwing from Helium** below.
2. **Clipboard:** copy any YouTube watch/playlist URL (`Ctrl+L Ctrl+C`,
   right-click a link), click the **▶ YT** bar widget. If the clipboard holds
   a YouTube URL it plays immediately; otherwise the window opens with a
   focused URL field (paste + Enter).
3. **Keybind recipe** (add to your Hyprland config, not shipped):
   ```
   bind = SUPER, Y, exec, omarchy-shell shell summon io.github.joshuaswarren.ytmini '{"clipboard":true}'
   ```
4. **Any script or agent** through shell IPC:
   ```
   omarchy-shell shell summon io.github.joshuaswarren.ytmini '{"url":"https://www.youtube.com/watch?v=…"}'
   ```

Payload keys: `url`, `clipboard` (reads `wl-paste`), `grab` (bool), `radio` (bool).

## Throwing from Helium

Helium is Chromium-based, so external protocol handlers and bookmarklets work
like Chrome. One-time setup:

```sh
cp scripts/ytmini-throw ~/.local/bin/                          # on PATH in Omarchy
cp assets/io.github.joshuaswarren.ytmini.desktop ~/.local/share/applications/
update-desktop-database ~/.local/share/applications
xdg-mime default io.github.joshuaswarren.ytmini.desktop x-scheme-handler/ytmini
```

Then add a bookmark in Helium (bookmark bar or Helium's pinned spaces) with
this as the URL:

```
javascript:location.href='ytmini://throw?url='+encodeURIComponent(location.href)
```

Click it on any YouTube tab: Chromium asks once whether to open `ytmini`
links — allow and remember. From then on it is one click, zero typing, works
on watch pages, playlists, and `youtu.be` shorts links.

## Window position

Drag the window by its header bar — the position is clamped to the screen and
persisted to `$XDG_STATE_HOME/ytmini/window.json`, surviving re-summons and
reboots. Scripts can place it absolutely or by corner:

```
omarchy-shell shell summon io.github.joshuaswarren.ytmini '{"corner":"tl"}'   # tl|tr|bl|br
omarchy-shell shell summon io.github.joshuaswarren.ytmini '{"move":{"right":200,"bottom":300}}'
```

Locking the session pauses playback and hides the window; unlocking resumes if
it was playing when locked.


Prefer a toolbar button and keyboard shortcut? That is the planned v0.2
companion extension (native-messaging host + MV3 extension, same pattern as
Omarchy's built-in yt-dlp extension).

## Troubleshooting

`omarchy-shell` watches plugin files and hot-reloads, but an in-place reload
can leave a stale instance running (symptom: summons return `ok` but code
changes or payloads seem ignored). After `omarchy plugin update` or manual
edits, if behavior looks stale:

```
omarchy plugin disable io.github.joshuaswarren.ytmini
omarchy plugin enable io.github.joshuaswarren.ytmini
```

## Playlists and up-next

- A `playlist?list=…` URL is enumerated with `yt-dlp --flat-playlist` (fast,
  no per-video resolution) into the queue; when a video ends the engine
  advances automatically, and ⏭ skips to the next entry.
- **Radio mode (∞) is experimental and off by default:** YouTube currently
  blocks radio-mix (`RD…`) listing ("This playlist type is unviewable"), so
  single-video up-next usually yields nothing. Enabled, it tries the mix and
  falls back cleanly. Use a real playlist for reliable up-next; this should
  start working again if YouTube/yt-dlp re-allow mix enumeration.

## Modes

- **Stream (default):** resolves the best muxed format (`-f 18/22/best` —
  360p/720p progressive) and plays the direct URL. Instant start.
- **Grab (⤓ toggle in the header):** downloads up to 1080p
  (`bv*[height<=1080]+ba/b`, merged to MKV) to
  `$XDG_CACHE_HOME/ytmini/<videoId>.mkv`, then plays the local file. Precise
  seeking; replaying a cached video skips the network entirely.

Controls: space = play/pause, ←/→ = seek ±5s (window focused), seek bar,
mute, skip, stop. `∞` toggles radio, `⤓` toggles grab, `✕` hides
(audio keeps playing), `■` stops and clears.

## Requirements

- Omarchy Quattro (shell plugin system, `omarchy-shell` CLI)
- `yt-dlp` (pacman: `yt-dlp`)
- `wl-clipboard` (`wl-paste`) for the clipboard handoff
- QtMultimedia (ships with the shell's Qt)

## Install

```
omarchy plugin add <this repository's git URL> --enable
omarchy plugin enable io.github.joshuaswarren.ytmini   # bar widget: right section
```

Update: `omarchy plugin update io.github.joshuaswarren.ytmini`.
Remove: `omarchy plugin remove io.github.joshuaswarren.ytmini`.

## Security-relevant behavior

- Spawns `yt-dlp` and `wl-paste` as child processes with **structured argument
  arrays** — never through a shell string, so URLs cannot inject commands.
- URLs are accepted only if they match `youtube.com/watch|playlist` or
  `youtu.be/<id>` before being passed to `yt-dlp`.
- The `ytmini://` handler strips quote/backslash characters before embedding a
  URL in the summon payload, and the panel re-validates it against the same
  YouTube URL shape.
- Reads the clipboard only when explicitly summoned with `{"clipboard":true}`
  (bar-widget click or keybind) and only uses it if it is a YouTube URL.
- Writes only to `$XDG_CACHE_HOME/ytmini/`. No network endpoints other than
  YouTube/googlevideo via `yt-dlp`. No credentials, no elevated access.

## Development

```
omarchy plugin validate /path/to/this/repo
qmllint -I /usr/lib/qt6/qml YtPanel.qml BarWidget.qml   # plus a qs.* shim if you keep one
```

## License

MIT — see [LICENSE](LICENSE).
