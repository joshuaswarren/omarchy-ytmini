import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtMultimedia
import qs.Commons

// YT Mini panel entry point.
// Hosted by omarchy-shell; summoned with:
//   omarchy-shell shell toggle io.github.joshuaswarren.ytmini '{"clipboard":true}'
// Payload: { url, clipboard, grab, radio }
Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "io.github.joshuaswarren.ytmini"
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME")
    || (Quickshell.env("HOME") + "/.cache")) + "/ytmini"
  readonly property int videoWidth: 460
  readonly property int videoHeight: Math.round(videoWidth * 9 / 16)

  // ---- lifecycle + queue state ----
  property bool opened: false
  property string playState: "idle" // idle | resolving | downloading | playing | error
  property string statusText: ""
  property string currentId: ""
  property string currentTitle: ""
  property var queue: [] // [{ id, title, url }]
  property var playedIds: []
  property bool radio: false
  property bool grabMode: false
  property real downloadProgress: 0
  property string nextTitle: queue.length > 0 ? queue[0].title : ""
  readonly property color background: Color.background
  readonly property color surface: Color.background
  readonly property color foreground: Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color muted: foreground

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    root.opened = true
    if (payload.grab === true) root.grabMode = true
    if (payload.grab === false) root.grabMode = false
    if (payload.radio === false) root.radio = false
    if (payload.radio === true) root.radio = true
    if (payload.url) root.handoff(String(payload.url))
    else if (payload.clipboard) clipProcess.running = true
  }

  // Hide only: audio keeps playing (music use case). The stop button ends playback.
  function close() {
    root.opened = false
  }

  function stop() {
    player.stop()
    player.source = ""
    root.queue = []
    root.playState = "idle"
    root.statusText = ""
    root.currentTitle = ""
    root.currentId = ""
    root.opened = false
  }

  // ---- URL handling ----
  function isYouTubeUrl(u) {
    return /^https?:\/\/(www\.|m\.|music\.)?youtube\.com\/(watch|playlist)\?[^ ]*$/.test(u)
      || /^https:\/\/youtu\.be\/[\w-]{6,}/.test(u)
  }

  function queryParam(u, key) {
    var m = u.match(new RegExp("[?&]" + key + "=([\\w-]+)"))
    return m ? m[1] : ""
  }

  function handoff(url) {
    url = url.trim()
    if (!isYouTubeUrl(url)) {
      root.playState = "error"
      root.statusText = "Not a YouTube watch/playlist URL"
      return
    }
    var videoId = queryParam(url, "v") || (url.indexOf("youtu.be/") >= 0 ? url.split("youtu.be/")[1].split("?")[0] : "")
    var listId = queryParam(url, "list")
    root.playedIds = []
    if (listId !== "" && listId.indexOf("RD") !== 0) {
      root.queue = []
      root.playState = "resolving"
      root.statusText = "Loading playlist…"
      root.pendingPlaylistPlay = true
      enumerate(listId, false)
    } else {
      if (videoId === "") {
        root.playState = "error"
        root.statusText = "No video id in URL"
        return
      }
      root.queue = [{
        id: videoId,
        title: "",
        url: "https://www.youtube.com/watch?v=" + videoId
      }]
      if (root.radio) enumerate("RD" + videoId, true)
      playHead()
    }
  }

  property bool pendingPlaylistPlay: false

  function enumerate(listId, isRadio) {
    enumProcess.listId = listId
    enumProcess.isRadio = isRadio
    enumProcess.command = [
      "yt-dlp", "--flat-playlist", "--playlist-items", "1-25", "-J",
      "https://www.youtube.com/playlist?list=" + listId
    ]
    enumProcess.running = true
  }

  function applyPlaylist(jsonText, isRadio) {
    var entries = []
    try {
      var doc = JSON.parse(jsonText)
      entries = doc.entries || []
    } catch (e) {
      if (!isRadio) {
        root.playState = "error"
        root.statusText = "Playlist fetch failed"
      } else if (root.playState === "resolving") {
        root.playState = "idle"
        root.statusText = "Up-next unavailable: YouTube blocks mix listing"
      }
      return
    }
    var fresh = []
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (!e || !e.id) continue
      if (root.playedIds.indexOf(e.id) >= 0) continue
      if (e.id === root.currentId) continue
      var dup = false
      for (var j = 0; j < root.queue.length; j++) if (root.queue[j].id === e.id) { dup = true; break }
      for (var k = 0; k < fresh.length; k++) if (fresh[k].id === e.id) { dup = true; break }
      if (dup) continue
      fresh.push({
        id: e.id,
        title: e.title || e.id,
        url: "https://www.youtube.com/watch?v=" + e.id
      })
    }
    root.queue = root.queue.concat(fresh)
    if (root.pendingPlaylistPlay && root.queue.length > 0) {
      root.pendingPlaylistPlay = false
      playHead()
    } else if (!isRadio && root.queue.length === 0) {
      root.playState = "error"
      root.statusText = "Playlist is empty"
    } else if (isRadio && fresh.length === 0 && root.playState === "resolving") {
      root.playState = "idle"
      root.statusText = "Up-next unavailable: YouTube blocks mix listing"
    }
  }

  function playHead() {
    if (root.queue.length === 0) {
      radioRefill()
      return
    }
    var item = root.queue[0]
    root.queue = root.queue.slice(1)
    root.currentId = item.id
    root.currentTitle = item.title === "" ? item.id : item.title
    root.playedIds = root.playedIds.concat([item.id]).slice(-40)
    if (root.grabMode) startDownload(item)
    else startStream(item)
  }

  function radioRefill() {
    if (root.radio && root.currentId !== "") {
      root.playState = "resolving"
      root.statusText = "Finding next…"
      enumerate("RD" + root.currentId, true)
      // Radio enumeration lands asynchronously; if it yields nothing playable
      // the queue stays empty and the next advance() parks in idle.
      Qt.callLater(function() { if (root.queue.length > 0 && root.playState === "resolving") playHead() })
    } else {
      root.playState = "idle"
      root.statusText = ""
    }
  }

  function advance() {
    if (root.queue.length > 0) {
      playHead()
      return
    }
    radioRefill()
  }

  // ---- playback launchers ----
  function startStream(item) {
    root.playState = "resolving"
    root.statusText = "Resolving stream…"
    streamProcess.item = item
    streamProcess.command = [
      "yt-dlp", "--no-warnings", "--no-playlist",
      "-f", "18/22/best", "-g", item.url
    ]
    streamProcess.running = true
  }

  function startDownload(item) {
    root.playState = "downloading"
    root.downloadProgress = 0
    root.statusText = "Downloading " + item.title + "…"
    grabProcess.item = item
    grabProcess.command = [
      "yt-dlp", "--no-playlist", "--newline", "--no-part",
      "--merge-output-format", "mkv",
      "-f", "bv*[height<=1080]+ba/b",
      "-o", root.cacheDir + "/" + item.id + ".mkv",
      item.url
    ]
    grabProcess.running = true
  }

  function playSource(sourceUrl, title) {
    player.stop()
    player.source = sourceUrl
    root.playState = "playing"
    root.statusText = ""
    player.play()
  }

  function fmt(ms) {
    if (!isFinite(ms) || ms <= 0) return "0:00"
    var s = Math.floor(ms / 1000)
    return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2)
  }

  // ---- processes ----
  Process {
    id: clipProcess
    running: false
    command: ["wl-paste", "--no-newline"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var text = String(text || "").trim()
        if (text !== "" && root.isYouTubeUrl(text)) root.handoff(text)
        else if (root.playState !== "playing") {
          root.playState = "idle"
          root.statusText = text === "" ? "Clipboard is empty — paste a URL below" : "Clipboard has no YouTube URL"
        }
      }
    }
  }

  Process {
    id: enumProcess
    property string listId: ""
    property bool isRadio: false
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyPlaylist(text, enumProcess.isRadio)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text).trim() !== "") console.warn("ytmini", String(text).trim())
    }
  }

  Process {
    id: streamProcess
    property var item: null
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var line = ""
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].trim() !== "") line = lines[i].trim()
        }
        if (line.indexOf("http") === 0) root.playSource(line, streamProcess.item ? streamProcess.item.title : "")
        else {
          root.playState = "error"
          root.statusText = "Stream resolution failed"
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text).trim() !== "") console.warn("ytmini", String(text).trim())
    }
  }

  Process {
    id: grabProcess
    property var item: null
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        var m = String(line).match(/\[download\]\s+([\d.]+)%/)
        if (m) root.downloadProgress = parseFloat(m[1]) / 100
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && grabProcess.item) {
        root.playSource("file://" + root.cacheDir + "/" + grabProcess.item.id + ".mkv", grabProcess.item.title)
      } else if (root.playState === "downloading") {
        root.playState = "error"
        root.statusText = "Download failed (exit " + exitCode + ")"
      }
    }
  }

  MediaPlayer {
    id: player
    audioOutput: AudioOutput {
      id: audio
      volume: 0.9
    }
    onMediaStatusChanged: function(status) {
      if (status === MediaPlayer.EndOfMedia) root.advance()
      if (status === MediaPlayer.InvalidMedia) {
        root.playState = "error"
        root.statusText = "Playback error: " + (player.errorString || "invalid media")
      }
    }
  }

  // ---- window ----
  PanelWindow {
    id: window
    visible: root.opened
    anchors {
      top: false
      left: false
      right: true
      bottom: true
    }
    margins {
      right: 14
      bottom: 14
    }
    width: root.videoWidth
    height: root.playState === "playing" || root.playState === "downloading"
      ? root.videoHeight + 74
      : 148
    color: root.background
    WlrLayershell.namespace: "ytmini"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    Keys.onSpacePressed: function(event) {
      event.accepted = true
      if (player.playbackState === MediaPlayer.PlayingState) player.pause()
      else player.play()
    }
    Keys.onLeftPressed: player.position = (Math.max(0, player.position - 5000))
    Keys.onRightPressed: player.position = (player.position + 5000)

    Column {
      id: column
      anchors.fill: parent
      anchors.margins: 1
      spacing: 0

      // header: title / status + controls
      Rectangle {
        width: parent.width
        height: 30
        color: root.surface

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 130
          elide: Text.ElideRight
          color: root.playState === "error" ? root.urgent : root.foreground
          text: {
            if (root.playState === "error") return root.statusText
            if (root.playState === "resolving" || root.playState === "downloading")
              return root.statusText + (root.playState === "downloading" ? " (" + Math.round(root.downloadProgress * 100) + "%)" : "")
            if (root.playState === "playing") return root.currentTitle
            return root.statusText !== "" ? root.statusText : "YT Mini"
          }
          font.pixelSize: 12
        }

        Text {
          id: radioGlyph
          anchors.right: grabGlyph.right
          anchors.rightMargin: -34
          anchors.verticalCenter: parent.verticalCenter
          color: root.radio ? root.accent : root.muted
          opacity: root.playState === "playing" || root.playState === "resolving" ? 1 : 0.4
          text: "∞"
          font.pixelSize: 14
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.radio = !root.radio
          }
        }

        Text {
          id: grabGlyph
          anchors.right: closeGlyph.right
          anchors.rightMargin: -34
          anchors.verticalCenter: parent.verticalCenter
          color: root.grabMode ? root.accent : root.muted
          opacity: root.playState === "idle" || root.playState === "error" ? 1 : 0.4
          text: "⤓"
          font.pixelSize: 14
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.grabMode = !root.grabMode
          }
        }

        Text {
          id: closeGlyph
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          color: root.foreground
          text: "✕"
          font.pixelSize: 13
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.close()
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: root.accent; opacity: 0.35 }

      // body
      Item {
        width: parent.width
        height: root.playState === "playing" || root.playState === "downloading"
          ? root.videoHeight
          : 0

        VideoOutput {
          anchors.fill: parent
          fillMode: VideoOutput.PreserveAspectFit
          visible: root.playState === "playing"
          // dark plate while a grab downloads
          Rectangle {
            anchors.fill: parent
            visible: root.playState !== "playing"
            color: root.background
            Text {
              anchors.centerIn: parent
              color: root.foreground
              text: Math.round(root.downloadProgress * 100) + "%"
              visible: root.playState === "downloading"
            }
          }
        }
      }

      // idle URL entry
      Column {
        width: parent.width
        height: root.playState === "idle" || root.playState === "error" ? 86 : 0
        visible: height > 0
        spacing: 8
        topPadding: 12

        Rectangle {
          width: parent.width - 20
          x: 10
          height: 34
          radius: Style.cornerRadius
          color: root.background
          border.color: urlInput.activeFocus ? root.accent : root.muted
          border.width: 1
          opacity: 0.9

          TextInput {
            id: urlInput
            anchors.fill: parent
            anchors.margins: 8
            color: root.foreground
            selectionColor: root.accent
            font.pixelSize: 13
            clip: true
            verticalAlignment: TextInput.AlignVCenter
            onAccepted: if (text.trim() !== "") root.handoff(text)
            Keys.onEscapePressed: root.close()

            Text {
              visible: urlInput.text === "" && !urlInput.activeFocus
              anchors.fill: parent
              anchors.margins: 8
              verticalAlignment: Text.AlignVCenter
              color: root.muted
              opacity: 0.6
              font.pixelSize: 13
              text: "Paste a YouTube URL and press Enter…"
            }
          }
        }

        Text {
          x: 12
          color: root.muted
          opacity: 0.7
          font.pixelSize: 11
          text: root.grabMode
            ? "Grab mode: downloads first — full quality, instant seeking"
            : "Stream mode: instant start — toggle ⤓ for grab mode"
        }
      }

      // controls (playing)
      Item {
        width: parent.width
        height: root.playState === "playing" ? 42 : 0
        visible: height > 0

        // seek bar
        Rectangle {
          id: seekBar
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          height: 6
          radius: 3
          color: root.muted
          opacity: 0.25

          Rectangle {
            width: player.duration > 0 ? parent.width * (player.position / player.duration) : 0
            height: parent.height
            radius: 3
            color: root.accent
          }

          MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            function seekTo(x) {
              if (player.duration > 0)
                player.position = (Math.max(0, Math.min(player.duration, (x / width) * player.duration)))
            }
            onPressed: function(mouse) { seekTo(mouse.x) }
            onPositionChanged: function(mouse) { if (pressed) seekTo(mouse.x) }
          }
        }

        Text {
          id: timeLabel
          anchors.left: parent.left
          anchors.leftMargin: 10
          anchors.top: seekBar.bottom
          anchors.topMargin: 6
          color: root.muted
          font.pixelSize: 11
          text: fmt(player.position) + " / " + fmt(player.duration)
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: 6
          anchors.top: seekBar.bottom
          anchors.topMargin: 2
          spacing: 14

          Text {
            color: root.foreground
            font.pixelSize: 15
            text: player.playbackState === MediaPlayer.PlayingState ? "⏸" : "▶"
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
            }
          }

          Text {
            color: root.foreground
            font.pixelSize: 15
            text: "⏭"
            opacity: root.nextTitle !== "" ? 1 : 0.35
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.advance()
            }
          }

          Text {
            color: audio.muted ? root.urgent : root.foreground
            font.pixelSize: 15
            text: audio.muted ? "🔇" : "🔊"
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: audio.muted = !audio.muted
            }
          }

          Text {
            color: root.urgent
            font.pixelSize: 15
            text: "■"
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.stop()
            }
          }
        }
      }
    }
  }

  // Up-next hint for the bar widget: expose next title.
  function nextUpHint() {
    return root.nextTitle !== "" ? root.nextTitle : (root.radio ? "radio on" : "")
  }
}
