# YT Mini for Omarchy Quattro

[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink)](https://github.com/sponsors/joshuaswarren)

Play YouTube videos in a floating Omarchy shell panel. QtMultimedia plays
inside the shell; no browser or separate mpv window is needed for playback.
Hiding the panel leaves audio and the queue running.

## Install

```sh
omarchy plugin add https://github.com/joshuaswarren/omarchy-ytmini --enable
```

Requirements:

- Omarchy Quattro and its shell plugin system.
- `yt-dlp` for stream resolution, playlist listing and downloads.
- `wl-clipboard` (`wl-paste`) for clipboard handoff.
- QtMultimedia, supplied with the shell's Qt.
- `ffmpeg` to merge separate audio/video streams in grab mode.
- `python3` only for the optional bookmark installer.

## Open a video

Copy a YouTube watch or playlist URL, then click the YT bar widget. If the
clipboard holds a supported URL, playback starts; otherwise paste into the
URL field and press Enter.

A keybind or script can request the same clipboard handoff:

```sh
omarchy-shell shell summon io.github.joshuaswarren.ytmini '{"clipboard":true}'
```

Payload keys are `url`, `clipboard`, `grab`, `radio`, `corner` and `move`.

## Window and controls

Drag the header to move the panel. Position is clamped to the screen and
saved across later summons and shell sessions.

```sh
omarchy-shell shell summon io.github.joshuaswarren.ytmini '{"corner":"tl"}'
omarchy-shell shell summon io.github.joshuaswarren.ytmini '{"move":{"right":200,"bottom":300}}'
```

Corners are `tl`, `tr`, `bl` and `br`. With the window focused, Space toggles
play/pause and Left/Right seek five seconds. The panel also offers seek,
mute, skip, stop, radio and grab controls. Hide keeps audio playing; Stop
clears playback. Locking the session pauses and hides the panel. Unlocking
resumes it if it was playing when locked.

## Playlists and modes

Playlists are listed through `yt-dlp --flat-playlist`, with at most 25 entries
per request. The queue advances when a video ends; Skip moves to the next.

Radio is experimental and off by default. It asks for YouTube's `RD` mix,
up to 25 entries. If listing fails or yields no new playable entries,
up-next is unavailable. Use a normal playlist when you need auto-advance.

- Stream mode resolves a muxed format and plays its direct URL.
- Grab mode downloads up to 1080p and merges to MKV when needed. It plays
  the local file, but starting a grab still invokes `yt-dlp`. There is no
  promise of offline replay or automatic cache cleanup.

## Browser handoff (optional)

The checked-in browser integration is a bookmarklet and `ytmini://` handler,
not a browser extension. Run these commands from the repository root:

```sh
mkdir -p ~/.local/bin ~/.local/share/applications
cp scripts/ytmini-throw ~/.local/bin/
cp assets/io.github.joshuaswarren.ytmini.desktop ~/.local/share/applications/
update-desktop-database ~/.local/share/applications
xdg-mime default io.github.joshuaswarren.ytmini.desktop x-scheme-handler/ytmini
```

Add a bookmark with this URL:

```text
javascript:location.href='ytmini://throw?url='+encodeURIComponent(location.href)
```

Click it on a YouTube tab and allow the external-protocol prompt.

The optional `scripts/add-browser-bookmark.py` edits a chosen Chromium
profile's `Bookmarks` file. Close the browser first: it rewrites that file
from memory on exit. `--dry` previews without writing. Example profile paths:

- Helium: `~/.config/net.imput.helium/Default/Bookmarks`.
- Chrome: `~/.config/google-chrome/Default/Bookmarks`.

## State and security

Panel operation saves position in
`${XDG_STATE_HOME:-~/.local/state}/ytmini/window.json` and grab files under
`${XDG_CACHE_HOME:-~/.cache}/ytmini/`. Grab files remain until you remove them.
Optional browser setup also installs the helper and desktop entry above,
and changes the browser bookmark file.

`yt-dlp` and `wl-paste` commands use argument arrays, not shell strings. Input URLs are
checked for supported YouTube shapes before reaching `yt-dlp`; clipboard
reads happen only for clipboard summons. Stream listing and playback need
network access. Resolved media is not restricted to a googlevideo-only
host list.

## Update, remove and troubleshoot

```sh
omarchy plugin update io.github.joshuaswarren.ytmini
omarchy plugin remove io.github.joshuaswarren.ytmini
```

Plugin removal does not undo the optional browser setup. Remove its
bookmark, helper and desktop entry separately if you no longer use them.

If an update appears stale, disable and enable the plugin:

```sh
omarchy plugin disable io.github.joshuaswarren.ytmini
omarchy plugin enable io.github.joshuaswarren.ytmini
```

## Support

[Sponsor on GitHub](https://github.com/sponsors/joshuaswarren) or use
Lightning at `joshuaswarren@strike.me`.

## License

MIT. See [LICENSE](LICENSE).
