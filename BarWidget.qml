import QtQuick
import QtQml.Models
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs.Ui
import qs.Commons
import "Logic.js" as Logic

BarWidget {
  id: root
  moduleName: "lancefaul.omedia-controls"

  // A labelled switch for the settings column: the label and a hint on the
  // left, Omarchy's own switch on the right. Clicking the row flips it too.
  // A search box, as the library and the Add browser have: Escape clears it,
  // or with nothing typed hands the keys back to the popup.
  component SearchBox: TextField {
    id: searchBox
    signal leave()
    placeholderText: "Search music"
    font.family: Style.font.family
    rightPadding: horizontalPadding + clearSearch.width + Style.space(4)
    Keys.onEscapePressed: function(event) {
      if (searchBox.text !== "") searchBox.text = ""
      else searchBox.leave()
      event.accepted = true
    }

    Text {
      id: clearSearch
      visible: searchBox.text !== ""
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "󰅖"
      color: searchBox.foreground
      font.pixelSize: Style.font.icon

      MouseArea {
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        cursorShape: Qt.PointingHandCursor
        onClicked: searchBox.text = ""
      }
    }
  }

  // A search result: the track, and its artist and album folders beneath.
  component SearchResultRow: BorderSurface {
    id: resultRow
    property var result: ({})
    property bool picked: false
    property color foreground: "white"
    property string fontFamily: ""
    signal chosen(var mouse)
    signal played()

    height: Style.space(38)
    radius: Style.spacing.labelGap
    color: resultRow.picked ? Style.selectedFillFor(resultRow.foreground, Color.accent)
      : resultArea.containsMouse ? Style.normalFillFor(resultRow.foreground, Color.accent)
      : "transparent"
    borderSpec: resultRow.picked ? Border.controlSpec("normal", resultRow.foreground, Color.accent) : Border.none()

    MouseArea {
      id: resultArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) { resultRow.chosen(mouse) }
      onDoubleClicked: resultRow.played()
    }

    Row {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(10)

      Text {
        id: resultIcon
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "󰝚"
        color: resultRow.foreground
        opacity: resultRow.picked ? 1.0 : 0.7
        font.family: resultRow.fontFamily
        font.pixelSize: Style.font.icon
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - resultIcon.width - parent.spacing
        spacing: Style.space(1)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: resultRow.result.title || ""
          elide: Text.ElideRight
          color: resultRow.foreground
          font.family: resultRow.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: resultRow.picked
        }

        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          text: [resultRow.result.artist, resultRow.result.album].filter(function(t) { return !!t }).join(" · ")
          elide: Text.ElideRight
          color: Qt.darker(resultRow.foreground, 1.5)
          font.family: resultRow.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  component SettingSwitch: Item {
    id: settingSwitch
    property string label: ""
    property string hint: ""
    property bool checked: false
    property color foreground: "white"
    property string fontFamily: ""
    signal toggled()

    width: parent ? parent.width : 0
    implicitHeight: Math.max(settingText.implicitHeight, settingToggle.implicitHeight)
    height: implicitHeight

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: settingSwitch.toggled()
    }

    Column {
      id: settingText
      anchors.left: parent.left
      anchors.right: settingToggle.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: settingSwitch.label
        wrapMode: Text.Wrap
        color: settingSwitch.foreground
        font.family: settingSwitch.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        width: parent.width
        visible: text !== ""
        textFormat: Text.PlainText
        text: settingSwitch.hint
        wrapMode: Text.Wrap
        color: Qt.darker(settingSwitch.foreground, 1.5)
        font.family: settingSwitch.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    ToggleSwitch {
      id: settingToggle
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: settingSwitch.checked
      foreground: settingSwitch.foreground
      onToggled: settingSwitch.toggled()
    }
  }

  // Binds MPRIS directly instead of going through the built-in omarchy.media
  // service, whose service half only runs while that plugin's own bar icon
  // is enabled — this widget replaces that icon, so it can't depend on it.
  readonly property var players: Mpris.players ? Mpris.players.values : []

  function isProxyPlayer(p) {
    var d = String(p && p.dbusName || "").toLowerCase()
    var e = String(p && p.desktopEntry || "").toLowerCase()
    return d.indexOf("playerctld") !== -1 || e === "playerctld"
  }
  // Something to show or control: a track loaded, or playing. A player that
  // is only registered — Brave's, for a Discord web app with nothing playing —
  // stays out of the popup until it has activity.
  function hasMetadata(p) {
    return !!p && Logic.isActivePlayer(p.trackTitle || p.trackArtist, p.isPlaying)
  }
  function canControl(p) {
    return !!(p && (p.canTogglePlaying || p.canPlay || p.canPause || p.canGoNext || p.canGoPrevious))
  }
  function playerKey(p) {
    return p ? String(p.dbusName || p.desktopEntry || p.identity || "") : ""
  }

  // --------------------------------------------------------- which player
  //
  // With two players going at once — one left running by accident, another
  // just started — the popup should follow the one you started most recently,
  // not whichever the session bus happens to list first. Omarchy's built-in
  // media service keeps the *oldest* playing player instead; for a forgotten
  // player that is exactly backwards.
  //
  // playStarts maps a player's key to a serial taken each time it starts
  // playing. Players already playing when the widget loads get 0, so anything
  // started afterwards outranks them. Clicking a row pins that player, until
  // a different one starts.
  property var playStarts: ({})
  property int playSerial: 0
  // When each player last left Playing, to tell a flicker from a real pause.
  property var playStops: ({})
  // Evaluated once, when the widget is created. See
  // Logic.classifyPlaybackStart for why the first seconds are special.
  readonly property real loadedAt: Date.now()
  // Switched from the PLAYERS section and kept in preferences.json.
  property bool pauseOthers: false

  function startSerial(p) {
    var s = playStarts[playerKey(p)]
    return s === undefined ? -1 : s
  }

  function noteAlreadyPlaying(p) {
    var key = playerKey(p)
    if (!key || playStarts[key] !== undefined) return
    var next = Object.assign({}, playStarts)
    next[key] = 0
    playStarts = next
  }

  function noteStopped(p) {
    var key = playerKey(p)
    if (key) playStops[key] = Date.now()
  }

  function noteStarted(p) {
    var key = playerKey(p)
    if (!key) return

    var kind = Logic.classifyPlaybackStart(Date.now(), root.loadedAt, playStops[key],
      playStarts[key] !== undefined)
    if (kind === "initial") { noteAlreadyPlaying(p); return }
    if (kind === "blip") return

    playSerial += 1
    var next = Object.assign({}, playStarts)
    next[key] = playSerial
    playStarts = next

    // A newly started player takes over from an explicit pick of another.
    if (preferredKey && preferredKey !== key) preferredKey = ""
    if (root.pauseOthers) pauseAllExcept(key)
  }

  // Opt-in audio focus, as on a phone: starting one player pauses the rest.
  // Off by default, because playing a video over music is sometimes the point.
  function pauseAllExcept(key) {
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p || isProxyPlayer(p) || playerKey(p) === key) continue
      if (p.isPlaying && p.canPause) p.pause()
    }
  }

  Instantiator {
    model: root.players
    delegate: QtObject {
      required property var modelData
      readonly property bool playing: !!(modelData && modelData.isPlaying)
      Component.onCompleted: if (playing) root.noteAlreadyPlaying(modelData)
      onPlayingChanged: {
        if (playing) root.noteStarted(modelData)
        else root.noteStopped(modelData)
      }
    }
  }

  // The rules live in Logic.choosePlayer, where they are tested.
  function selectActivePlayer() {
    var entries = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue
      entries.push({
        key: playerKey(p),
        proxy: isProxyPlayer(p),
        hasMetadata: hasMetadata(p),
        playing: !!p.isPlaying,
        startSerial: startSerial(p),
        hasTrack: !!(p.trackTitle || p.trackArtist),
        controllable: canControl(p),
      })
    }
    var key = Logic.choosePlayer(entries, preferredKey)
    if (!key) return null
    for (var j = 0; j < players.length; j++)
      if (players[j] && playerKey(players[j]) === key) return players[j]
    return null
  }

  readonly property var activePlayer: selectActivePlayer()
  readonly property var sourcePlayers: {
    var list = []
    for (var i = 0; i < players.length; i++) if (hasMetadata(players[i])) list.push(players[i])
    // Playing first, most recently started at the top; then the rest by name.
    list.sort(function(a, b) {
      if (!!a.isPlaying !== !!b.isPlaying) return a.isPlaying ? -1 : 1
      if (a.isPlaying) {
        var byStart = root.startSerial(b) - root.startSerial(a)
        if (byStart !== 0) return byStart
      }
      return String(a.trackTitle || a.identity || "").localeCompare(String(b.trackTitle || b.identity || ""))
    })
    return list
  }

  function runAction(action, targetKey) {
    var player = targetKey ? players.find(function(p) { return playerKey(p) === targetKey }) : root.activePlayer
    if (!player) return
    if (action === "next" && player.canGoNext) player.next()
    else if (action === "previous" && player.canGoPrevious) player.previous()
    else if (action === "playPause") {
      if (!player.isPlaying && root.checkEndThenPlay(player)) return
      if (player.canTogglePlaying) player.togglePlaying()
      else if (player.isPlaying && player.canPause) player.pause()
      else if (!player.isPlaying && player.canPlay) player.play()
    }
  }
  // A player that stays open after its last track — mpv with keep-open —
  // parks paused at the very end, where Play resumes nothing. Starting the
  // track over is what Play should mean there. MPRIS has no way to jump back
  // to the start of a playlist, so it is the last track that restarts.
  //
  // Neither Quickshell's position nor the widget's own is trustworthy for a
  // paused player — the first is extrapolated, the second is only kept fresh
  // while the popup is open — so the player is asked directly, and Play
  // happens once it answers. Returns false when there is nothing to check,
  // and the caller plays as normal.
  function checkEndThenPlay(player) {
    if (!player || !player.canSeek || !player.positionSupported || !player.lengthSupported) return false
    if (!(player.canPlay || player.canTogglePlaying)) return false
    var name = String(player.dbusName || "")
    if (!Logic.isMprisBusName(name)) return false
    // Only the active player's live state is tracked; for another, a station
    // remembered as live is enough to leave it alone.
    var live = player === root.activePlayer ? root.isLive
      : Logic.isKnownLiveStream(root.knownLiveStreams, root.trackIdentity(player))
    if (live || !(player.length > 0) || Logic.isUnboundedLength(player.length)) return false
    if (endProbe.running) return true
    endProbe.player = player
    endProbe.position = -1
    endProbe.command = ["busctl", "--user", "get-property", name,
      "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "Position"]
    endProbe.running = true
    return true
  }

  function finishPlay(player, position) {
    if (!player || player.isPlaying) return
    if (Logic.isAtTrackEnd(position, player.length, false)) {
      player.position = 0
      if (player === root.activePlayer) {
        root.probedPosition = 0
        root.probedAt = Date.now()
        root.seekSettledAt = Date.now() + Logic.SEEK_SETTLE_MS
        root.positionTick++
      }
    }
    if (player.canPlay) player.play()
    else player.togglePlaying()
  }

  Process {
    id: endProbe
    property var player: null
    property real position: -1
    running: false
    stdout: SplitParser {
      onRead: function(line) { endProbe.position = Logic.parseBusctlPosition(line) }
    }
    // A failed read leaves position at -1, which is never the end: Play then
    // simply resumes.
    onExited: root.finishPlay(endProbe.player, endProbe.position)
  }
  function selectPlayer(key) {
    var player = players.find(function(p) { return playerKey(p) === key })
    if (player) preferredKey = key
  }
  // Raises the player's own window. Not every player implements Raise, so
  // canRaise decides whether the popup's art is clickable at all.
  function raisePlayer() {
    var player = root.activePlayer
    if (!player || !player.canRaise) return false
    player.raise()
    return true
  }
  property string preferredKey: ""

  // Cover art is loaded only as a local file, an https URL or an embedded
  // base64 image — the URL is chosen by whichever app owns the player, and
  // Image would otherwise follow it to any host or scheme. See Logic.safeArtUrl.
  // With web art turned off in settings, an https:// cover is not fetched.
  readonly property string artUrl: {
    var url = activePlayer ? Logic.safeArtUrl(activePlayer.trackArtUrl) : ""
    return !root.webArt && url.indexOf("https://") === 0 ? "" : url
  }

  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  // ------------------------------------------------------------ format chips
  //
  // Winamp's kbps · kHz · stereo. A local file is read with ffprobe, once per
  // track and only while the popup is open; anything else falls back to the
  // sample rate and channels of the PipeWire stream the player is sending.
  readonly property string trackFile: activePlayer ? Logic.fileUrlToPath((activePlayer.metadata || {})["xesam:url"]) : ""
  property string probedFile: ""
  property var fileFormat: ({})

  readonly property var playbackStreams: {
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      // Playback streams: in Quickshell a stream that feeds a sink "is a
      // sink". Recording streams (a microphone, parec itself) are not.
      if (n && n.isStream && n.isSink && n.audio) list.push(n)
    }
    return list
  }

  PwObjectTracker { objects: root.popupOpen ? root.playbackStreams : [] }

  readonly property var streamFormat: {
    var p = root.activePlayer
    if (!p || !root.popupOpen) return {}
    var best = null, bestScore = 0
    for (var i = 0; i < root.playbackStreams.length; i++) {
      var n = root.playbackStreams[i]
      var score = Logic.streamScore(n.properties, p.identity || p.desktopEntry, p.trackTitle)
      if (score > bestScore) { best = n; bestScore = score }
    }
    if (!best) return {}
    return {
      sampleRate: Logic.nodeRate(best.properties ? best.properties["node.rate"] : ""),
      channels: best.audio && best.audio.channels ? best.audio.channels.length : 0,
    }
  }

  readonly property var formatChips: Logic.formatChips(
    root.trackFile !== "" && root.probedFile === root.trackFile ? root.fileFormat : root.streamFormat)

  Process {
    id: formatProbe
    property string file: ""
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.fileFormat = Logic.parseFfprobe(text)
        root.probedFile = formatProbe.file
      }
    }
  }

  // The path goes to ffprobe as an argument list, never through a shell, and
  // is always absolute (Logic.fileUrlToPath), so it cannot be read as an
  // option.
  function probeFormat() {
    if (!root.popupOpen || root.trackFile === "" || root.trackFile === root.probedFile || formatProbe.running) return
    formatProbe.file = root.trackFile
    formatProbe.command = ["ffprobe", "-v", "error", "-select_streams", "a:0",
      "-show_entries", "stream=sample_rate,channels,bit_rate:format=bit_rate",
      "-of", "json", root.trackFile]
    formatProbe.running = true
  }
  onTrackFileChanged: probeFormat()

  readonly property string albumLine: {
    var p = activePlayer
    if (!p) return ""
    var m = p.metadata || {}
    return Logic.albumDetails({
      album: p.trackAlbum,
      albumArtist: p.trackAlbumArtist,
      artist: p.trackArtist,
      date: m["xesam:contentCreated"],
      trackNumber: m["xesam:trackNumber"],
    })
  }

  property bool popupOpen: false
  property var bands: []
  property var peaks: []
  property var scopeColumns: []

  // The visualiser's size in the header: nineteen bars wide, and as tall as
  // the header beside it (its two lines of text, or the icon if taller), so it
  // spans the header from padding to padding. Measured with hidden copies of
  // that text; the settings snapshots use the same proportions.
  // How high the analyser and mirrored bars may reach, as a share of the
  // graph: loud music still tops out, but below the edge rather than against
  // it. Not the VU meter, which should reach its top.
  readonly property real visualiserCap: 0.8

  readonly property real heroVisWidth: Style.space(4) * 19 + Style.space(1) * 18
  readonly property real heroVisHeight: Math.max(measureTitle.implicitHeight + Style.space(2) + measureMeta.implicitHeight,
    measureIcon.implicitHeight)
  readonly property real heroAspect: root.heroVisWidth > 0 ? root.heroVisHeight / root.heroVisWidth : 0.3

  Text { id: measureTitle; visible: false; text: "Now Playing"; font.family: root.bar ? root.bar.fontFamily : ""; font.pixelSize: Style.font.title; font.bold: true }
  Text { id: measureMeta; visible: false; text: "OMEDIA CONTROLS"; font.family: root.bar ? root.bar.fontFamily : ""; font.pixelSize: Style.font.caption; font.bold: true }
  Text { id: measureIcon; visible: false; text: "󰝚"; font.family: root.bar ? root.bar.fontFamily : ""; font.pixelSize: Style.font.display }
  property var vuLevels: [0, 0]
  property var vuPeaks: [0, 0]

  // Which of Winamp's visualisations the header shows. Clicking it swaps
  // them, as clicking Winamp's visualiser does; the choice is kept in the
  // plugin's own state file, never the shell's config. See Logic.parsePreferences.
  property string visualisation: "analyser"
  readonly property bool oscilloscope: root.visualisation === "oscilloscope"
  readonly property bool mirror: root.visualisation === "mirror"

  // The visualisations' colours (see Logic.VIS_COLOURS), and the rows of
  // colour they come to, from the Omarchy theme's accent.
  property string visColour: "gradient"
  readonly property string accentHex: "#" + String(Color.accent).slice(-6).toUpperCase()
  readonly property var visRows: Logic.spectrumColors(root.visColour, root.accentHex)
  readonly property color visPeak: root.visColour === "winamp" ? Logic.WINAMP_PEAK : root.bar.foreground
  // Winamp5's stripes: the gradient's colour for each row, the accent, or
  // for Winamp, plain white.
  readonly property var winamp5Rows: root.visColour === "winamp" ? Logic.spectrumColors("solid", "#FFFFFF") : root.visRows
  readonly property color winamp5Peak: root.visColour === "winamp" ? "#FFFFFF" : root.bar.foreground

  function toggleVisualisation() {
    root.visualisation = Logic.nextVisualisation(root.visualisation)
    root.savePreferences()
  }

  function togglePauseOthers() {
    root.pauseOthers = !root.pauseOthers
    root.savePreferences()
  }

  // ---------------------------------------------------------------- settings
  //
  // Every setting, made in the settings column and kept with the other
  // popup choices in preferences.json. See Logic.preferenceDefaults.
  property string musicFolder: ""
  // The saved playlists' folder; "" is Playlists inside the music folder.
  property string playlistFolder: ""
  property string musicPlayer: ""
  property bool onlineLyrics: true
  property bool webArt: true
  property bool rememberStations: true
  property bool hideWhenIdle: false
  property int seekStep: 5
  property int volumeStep: 5
  readonly property bool settingsOpen: root.sidePanel === "settings"

  function setSetting(name, value) {
    root[name] = value
    root.savePreferences()
  }

  function savePreferences() {
    preferences.setText(Logic.serializePreferences({
      visualisation: root.visualisation,
      visColour: root.visColour,
      pauseOthers: root.pauseOthers,
      libraryDir: root.libraryDir,
      musicFolder: root.musicFolder,
      playlistFolder: root.playlistFolder,
      musicPlayer: root.musicPlayer,
      onlineLyrics: root.onlineLyrics,
      webArt: root.webArt,
      rememberStations: root.rememberStations,
      hideWhenIdle: root.hideWhenIdle,
      seekStep: root.seekStep,
      volumeStep: root.volumeStep,
      titleWidth: root.titleWidth,
      updateCheck: root.updateCheck,
      updateDismissed: root.updateDismissed,
      scrollTitle: root.scrollTitle,
      settingsMigrated: root.settingsMigrated,
    }))
  }

  // The apps the desktop recommends for audio, for the music player setting.
  property var audioApps: []

  Process {
    running: true
    command: ["gio", "mime", "audio/mpeg"]
    stdout: StdioCollector { onStreamFinished: root.audioApps = Logic.parseGioMime(text) }
  }

  // Choosing a music or playlist folder: the desktop's own folder picker.
  function chooseMusicFolder() {
    if (folderChooser.running) return
    folderChooser.forPlaylists = false
    folderChooser.command = ["zenity", "--file-selection", "--directory", "--title=Music folder",
      "--filename=" + root.libraryRoot + "/"]
    folderChooser.running = true
  }

  function choosePlaylistFolder() {
    if (folderChooser.running) return
    folderChooser.forPlaylists = true
    folderChooser.command = ["zenity", "--file-selection", "--directory", "--title=Playlist folder",
      "--filename=" + root.playlistsFolder + "/"]
    folderChooser.running = true
  }

  Process {
    id: folderChooser
    property bool forPlaylists: false
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        var folder = Logic.parseChosenFolder(text)
        if (!folder) return
        if (folderChooser.forPlaylists) {
          root.playlistFolder = folder
          root.closeSavedPlaylist()
        } else {
          root.musicFolder = folder
          root.libraryDir = ""
        }
        root.savePreferences()
      }
    }
  }

  function forgetStations() {
    root.knownLiveStreams = []
    root.saveLiveStreams()
  }

  function clearLyricsCache() {
    root.lyricsCache = []
    lyricsCacheFile.setText(Logic.serializeLyricsCache([]))
    root.lyricsLoadedKey = ""
    root.loadLyrics()
  }

  // ----------------------------------------------------------------- library
  //
  // Winamp's eject: a music browser in the popup, rooted at the user's music
  // folder. Picking something plays it in the active player when that player
  // takes files over MPRIS (mpv does), and otherwise starts the default audio
  // app on it.
  // Which side column is open beside the player: "", "library", "lyrics",
  // "playlist", "playlists" or "settings". One at a time, sharing the same
  // place.
  property string sidePanel: ""
  readonly property bool libraryOpen: root.sidePanel === "library"
  readonly property bool lyricsOpen: root.sidePanel === "lyrics"
  readonly property bool playlistsOpen: root.sidePanel === "playlists"
  function toggleSidePanel(name) { root.sidePanel = root.sidePanel === name ? "" : name }
  // The same width as the player column, so the two halves match. The popup's
  // width includes its padding and border, so the player column is that
  // much narrower than the width asked for.
  readonly property real libraryPanelWidth: Style.space(320)
    - popup.padding * 2 - Border.left(popup.borderSpec) - Border.right(popup.borderSpec)
  readonly property real libraryGap: Style.space(12)
  // Tracks picked in the library, in the order picked, across folders; and
  // the last one clicked, where a shift-click's range starts.
  property var librarySelection: []
  property string librarySelectAnchor: ""

  function selectTrack(path, shift, folderPaths) {
    root.librarySelection = shift && root.librarySelectAnchor
      ? Logic.selectRange(root.librarySelection, folderPaths, root.librarySelectAnchor, path)
      : Logic.toggleSelection(root.librarySelection, path)
    root.librarySelectAnchor = Logic.cleanPath(path)
  }

  // --------------------------------------------------------------- playlists
  //
  // Saved playlists: M3U files in "Playlists" inside the music folder (see
  // Logic.parseM3u), in their own side column, opened from the player's
  // playlist column. The column lists them, or shows one to play, rename,
  // delete or edit, and a player's shared queue can be saved as one. Writes
  // only ever go inside that folder.
  // Where they're kept: the folder chosen in Settings, else Playlists inside
  // the music folder.
  readonly property string playlistsFolder: root.playlistFolder || Logic.playlistsFolder(root.libraryRoot)
  // The playlist shown in the column, or "" for the list of them.
  property string openPlaylist: ""
  property var playlistEntries: []
  // Naming: "" when not, "new" for a new playlist of playlistNamePaths, or
  // "rename" for the open one.
  property string playlistNameMode: ""
  property var playlistNamePaths: []
  property string playlistNameError: ""
  // Where Cancel goes back to: the player's playlist column or saved playlists.
  property string playlistNameReturn: ""
  // Saving the player's queue: the new file becomes the one it's linked to.
  property bool playlistNameLinks: false
  property bool playlistDeleteArmed: false

  function showPlaylists() {
    root.openPlaylist = ""
    root.cancelPlaylistName()
    root.sidePanel = "playlists"
  }

  function openSavedPlaylist(path) {
    var p = Logic.cleanPath(path)
    if (!p || !Logic.isInside(root.playlistsFolder, p)) return
    root.cancelPlaylistName()
    if (p === root.openPlaylist) { playlistReader.reload(); return }
    root.playlistEntries = []
    root.openPlaylist = p
  }

  function closeSavedPlaylist() {
    root.cancelPlaylistName()
    root.openPlaylist = ""
    root.playlistEntries = []
  }

  // Name a new playlist holding these tracks (none for an empty one). from is
  // the column it was started from, where Cancel returns.
  function startNewPlaylist(paths, from) {
    root.playlistNameReturn = from || "playlists"
    root.playlistNameLinks = from === "playlist" && Array.isArray(paths) && paths.length > 0
    root.openPlaylist = ""
    root.sidePanel = "playlists"
    root.playlistNamePaths = Array.isArray(paths) ? paths.slice() : []
    root.playlistNameError = ""
    root.playlistDeleteArmed = false
    root.playlistNameMode = "new"
  }

  function startRenamePlaylist() {
    if (!root.openPlaylist) return
    root.playlistNameError = ""
    root.playlistDeleteArmed = false
    root.playlistNameMode = "rename"
  }

  // Cancel, from the name box: back to where naming started.
  function abandonPlaylistName() {
    var back = root.playlistNameMode === "new" ? root.playlistNameReturn : ""
    root.cancelPlaylistName()
    if (back === "playlist") root.sidePanel = "playlist"
  }

  function cancelPlaylistName() {
    root.playlistNameLinks = false
    root.playlistNameMode = ""
    root.playlistNamePaths = []
    root.playlistNameError = ""
    root.playlistDeleteArmed = false
  }

  function commitPlaylistName(text) {
    var file = Logic.playlistFileName(text)
    if (!file) { root.playlistNameError = "Type a name for the playlist"; return }
    var current = root.openPlaylist ? root.openPlaylist.slice(root.openPlaylist.lastIndexOf("/") + 1) : ""
    var except = root.playlistNameMode === "rename" ? current : ""
    if (Logic.playlistNameTaken(playlistsFiles.names, file, except)) {
      root.playlistNameError = "There's already a playlist called " + Logic.playlistDisplayName(file)
      return
    }
    var target = root.playlistsFolder + "/" + file
    if (root.playlistNameMode === "rename") {
      if (file === current) { root.cancelPlaylistName(); return }
      playlistRename.target = target
      playlistRename.command = ["mv", "-n", "-T", "--", root.openPlaylist, target]
      playlistRename.running = true
    } else {
      root.writePlaylist(target, Logic.entriesFromPaths(root.playlistNamePaths), true)
    }
  }

  // Writes a playlist, creating the folder first. openAfter shows it once
  // saved.
  function writePlaylist(path, entries, openAfter) {
    var p = Logic.cleanPath(path)
    if (!p || !Logic.isInside(root.playlistsFolder, p) || p === root.playlistsFolder) return
    playlistWriter.pendingPath = p
    playlistWriter.pendingText = Logic.serializeM3u(entries)
    playlistWriter.openAfter = !!openAfter
    playlistFolderMaker.command = ["mkdir", "-p", "--", root.playlistsFolder]
    playlistFolderMaker.running = true
  }

  function editOpenPlaylist(entries) {
    if (!root.openPlaylist) return
    root.playlistEntries = entries
    root.writePlaylist(root.openPlaylist, entries, false)
  }

  function deleteOpenPlaylist() {
    if (!root.openPlaylist) return
    if (!root.playlistDeleteArmed) { root.playlistDeleteArmed = true; return }
    // To the trash rather than gone, so a slip can be undone.
    playlistTrash.command = ["gio", "trash", "--", root.openPlaylist]
    playlistTrash.running = true
  }

  // Plays a saved playlist: handed to the active player as the file itself
  // (mpv and archamp both take an M3U over OpenUri), else the music player
  // app is started on it.
  function playSavedPlaylist(path) {
    var p = Logic.cleanPath(path)
    if (!p || !Logic.isInside(root.playlistsFolder, p)) return
    var player = root.activePlayer
    var name = player ? String(player.dbusName || "") : ""
    if (player && Logic.isMprisBusName(name) && !Logic.isChromiumPlayer(name, (player.metadata || {})["mpris:trackid"])) {
      root.linkPlaylist(name, p)
      openUri.fallback = [p]
      openUri.command = ["busctl", "--user", "call", name, "/org/mpris/MediaPlayer2",
        "org.mpris.MediaPlayer2.Player", "OpenUri", "s", Logic.pathToFileUri(p)]
      openUri.running = true
      return
    }
    root.launchAudioApp(p)
  }

  // The player's shared queue, as a new playlist.
  readonly property var queuePaths: {
    var out = []
    for (var i = 0; i < root.playlistIds.length; i++) {
      var info = root.playlistMeta[root.playlistIds[i]]
      if (info && info.path) out.push(info.path)
    }
    return out
  }

  // Every saved playlist's entries by file name, for naming a queue that
  // matches one and saving back to it. Read only while a player shares its
  // playlist and the popup is open.
  property var savedPlaylistEntries: ({})
  readonly property var savedPlaylistPaths: {
    var out = {}
    for (var name in root.savedPlaylistEntries) {
      out[name] = root.savedPlaylistEntries[name].map(function(e) { return e.location })
    }
    return out
  }

  // The saved playlist the player's queue came from: set when the plugin
  // plays one, or when the queue matches one track for track, and kept while
  // the queue is edited, so its name stays and Save can write back to it.
  // Dropped when that player loads something unrelated.
  property string linkedBus: ""
  property string linkedPlaylist: ""
  readonly property string linkedFile: root.linkedPlaylist.slice(root.linkedPlaylist.lastIndexOf("/") + 1)
  readonly property bool linkActive: root.linkedPlaylist !== "" && root.hasTrackList
    && root.linkedBus === root.playerBusName()
  readonly property string linkState: root.linkActive && (root.linkedFile in root.savedPlaylistPaths)
    ? Logic.playlistLinkState(root.queuePaths, root.savedPlaylistPaths[root.linkedFile]) : "same"
  readonly property bool playlistEdited: root.linkState === "edited"

  property real linkedAt: 0

  function linkPlaylist(bus, path) {
    root.linkedBus = bus
    root.linkedPlaylist = path
    root.linkedAt = Date.now()
  }

  function updatePlaylistLink() {
    if (root.linkActive) {
      // A player takes a moment to load what it was just handed, so the old
      // queue doesn't count against a new link.
      if (root.linkState === "unrelated" && Date.now() - root.linkedAt > 5000) root.linkPlaylist("", "")
      else return
    }
    var file = Logic.matchingPlaylistFile(root.queuePaths, root.savedPlaylistPaths)
    var bus = root.playerBusName()
    if (file && bus) root.linkPlaylist(bus, root.playlistsFolder + "/" + file)
  }

  onQueuePathsChanged: root.updatePlaylistLink()
  onSavedPlaylistPathsChanged: root.updatePlaylistLink()

  // Saves the edited queue back over the playlist it came from.
  function saveBackLinked() {
    if (!root.linkActive || root.queuePaths.length === 0) return
    root.writePlaylist(root.linkedPlaylist,
      Logic.entriesWithInfo(root.queuePaths, root.savedPlaylistEntries[root.linkedFile]), false)
  }

  // An edit to a saved playlist, made to the player's queue too when that
  // playlist is what the player is playing, unchanged, so the two stay in step.
  function editSavedEntry(kind, index, delta) {
    var before = root.playlistEntries
    var mirror = root.linkActive && root.openPlaylist === root.linkedPlaylist && root.linkState === "same"
      && root.queuePaths.length === root.playlistIds.length && root.playlistIds.length === before.length
    root.editOpenPlaylist(kind === "move" ? Logic.moveEntry(before, index, delta) : Logic.removeEntry(before, index))
    if (!mirror) return
    if (kind === "move") root.moveQueueTrack(index, delta)
    else root.removeQueueTrack(root.playlistIds[index])
  }

  FolderListModel {
    id: savedPlaylistsScan
    folder: root.popupOpen && root.hasTrackList && root.playlistsFolder ? Logic.pathToFileUri(root.playlistsFolder) : ""
    nameFilters: Logic.PLAYLIST_NAME_FILTERS
    caseSensitive: false
    showDirs: false
    showOnlyReadable: true
  }

  Instantiator {
    model: savedPlaylistsScan
    delegate: FileView {
      required property string fileName
      required property string filePath
      path: filePath
      printErrors: false
      watchChanges: true
      onFileChanged: reload()
      onLoaded: {
        var next = Object.assign({}, root.savedPlaylistEntries)
        next[fileName] = Logic.parseM3u(text(), root.playlistsFolder)
        root.savedPlaylistEntries = next
      }
      Component.onDestruction: {
        if (!(fileName in root.savedPlaylistEntries)) return
        var next = Object.assign({}, root.savedPlaylistEntries)
        delete next[fileName]
        root.savedPlaylistEntries = next
      }
    }
  }

  FolderListModel {
    id: playlistsModel
    folder: root.playlistsOpen && root.playlistsFolder ? Logic.pathToFileUri(root.playlistsFolder) : ""
    nameFilters: Logic.PLAYLIST_NAME_FILTERS
    caseSensitive: false
    showDirs: false
    showHidden: false
    showOnlyReadable: true
    sortCaseSensitive: false
  }

  // The file names in the folder, for checking a new name against.
  QtObject {
    id: playlistsFiles
    readonly property var names: {
      var out = []
      for (var i = 0; i < playlistsModel.count; i++) out.push(playlistsModel.get(i, "fileName"))
      return out
    }
  }

  FileView {
    id: playlistReader
    path: root.openPlaylist
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.playlistEntries = Logic.parseM3u(text(), root.playlistsFolder)
    onLoadFailed: root.playlistEntries = []
  }

  Process {
    id: playlistFolderMaker
    running: false
    onExited: function(code) {
      if (code !== 0) { root.playlistNameError = "Couldn't create " + root.playlistsFolder; return }
      playlistWriter.path = playlistWriter.pendingPath
      playlistWriter.setText(playlistWriter.pendingText)
    }
  }

  FileView {
    id: playlistWriter
    property string pendingPath: ""
    property string pendingText: ""
    property bool openAfter: false
    blockAllReads: true
    atomicWrites: true
    printErrors: false
    onSaved: {
      if (!playlistWriter.openAfter) return
      playlistWriter.openAfter = false
      var saved = playlistWriter.pendingPath
      if (root.playlistNameLinks) root.linkPlaylist(root.playerBusName(), saved)
      root.cancelPlaylistName()
      root.openSavedPlaylist(saved)
    }
    onSaveFailed: root.playlistNameError = "Couldn't save the playlist"
  }

  Process {
    id: playlistRename
    property string target: ""
    running: false
    onExited: function(code) {
      if (code !== 0) { root.playlistNameError = "Couldn't rename the playlist"; return }
      if (root.linkedPlaylist === root.openPlaylist) root.linkedPlaylist = playlistRename.target
      root.cancelPlaylistName()
      root.openSavedPlaylist(playlistRename.target)
    }
  }

  Process {
    id: playlistTrash
    running: false
    onExited: function(code) {
      if (code !== 0) { root.playlistDeleteArmed = false; return }
      if (root.linkedPlaylist === root.openPlaylist) root.linkPlaylist("", "")
      root.closeSavedPlaylist()
    }
  }

  // ------------------------------------------------------------------ lyrics
  //
  // For the playing track, while the popup is open: a .lrc beside a local
  // file first, else LRCLIB (lrclib.net), which is sent the artist, title,
  // album and length and nothing else. LRCLIB answers, found or not, are
  // cached in the plugin's state folder so a song is only asked about once.
  // Looked up before the column is opened so the lyrics button can be dimmed
  // when there are none, rather than opening an empty column. Nothing is
  // fetched while the popup is shut.
  property var lyricsLines: []
  property bool lyricsSynced: false
  property string lyricsStatus: ""
  property string lyricsSource: ""
  property string lyricsLoadedKey: ""
  property var lyricsCache: []

  readonly property string lyricsKey: {
    var p = root.activePlayer
    if (!p || root.isLive || !p.trackTitle) return ""
    return Logic.lyricsKey(p.trackArtist, p.trackTitle, p.trackAlbum, root.trackLength)
  }
  // Which lyrics are loaded is decided by the song and its file together: a
  // track change can update the title before the file, and loading a .lrc
  // on the title alone would pick up the previous song's.
  readonly property string lyricsSourceKey: root.lyricsKey ? root.lyricsKey + "\n" + root.trackFile : ""
  readonly property bool lyricsAvailable: root.lyricsLines.length > 0
  readonly property int lyricsActive: root.lyricsSynced ? Logic.activeLyricIndex(root.lyricsLines, root.trackPosition) : -1

  function showLyrics(parsed, source) {
    root.lyricsLines = parsed.lines
    root.lyricsSynced = parsed.synced
    root.lyricsSource = source
    root.lyricsStatus = parsed.lines.length > 0 ? "" : "No lyrics found"
  }

  function clearLyrics(status) {
    root.lyricsLines = []
    root.lyricsSynced = false
    root.lyricsSource = ""
    root.lyricsStatus = status
  }

  function loadLyrics() {
    if (!root.popupOpen || root.lyricsSourceKey === root.lyricsLoadedKey) return
    root.lyricsLoadedKey = root.lyricsSourceKey
    if (!root.lyricsKey) {
      root.clearLyrics(root.isLive ? "No lyrics for live streams" : "Nothing playing")
      return
    }
    root.clearLyrics("Looking for lyrics…")
    var lrc = Logic.lrcPathFor(root.trackFile)
    if (lrc) {
      localLyrics.forKey = root.lyricsSourceKey
      localLyrics.path = ""
      localLyrics.path = lrc
      return
    }
    root.lookUpLyrics(root.lyricsKey)
  }

  function lookUpLyrics(key) {
    var hit = Logic.cachedLyrics(root.lyricsCache, key, Date.now())
    if (hit) {
      if (hit.instrumental) root.clearLyrics("Instrumental")
      else if (hit.found) root.showLyrics(Logic.parseLrc(hit.text), "LRCLIB")
      else root.clearLyrics("No lyrics found")
      return
    }
    if (!root.onlineLyrics) { root.clearLyrics("No lyrics file, and online lyrics are off in Settings"); return }
    var p = root.activePlayer
    var url = p ? Logic.lrclibUrl(p.trackArtist, p.trackTitle, p.trackAlbum, root.trackLength) : ""
    if (!url) { root.clearLyrics("No lyrics found"); return }

    var xhr = new XMLHttpRequest()
    xhr.open("GET", url)
    xhr.setRequestHeader("Lrclib-Client", "OMedia Controls (https://github.com/lancefaul/omarchy-omedia-controls)")
    xhr.timeout = 10000
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      // The track may have changed while this was on its way.
      if (key !== root.lyricsKey) return
      if (xhr.status === 200 || xhr.status === 404) {
        var result = xhr.status === 200 ? Logic.parseLrclib(xhr.responseText) : { found: false, instrumental: false }
        var text = ""
        if (result.found && !result.instrumental) {
          text = result.lyrics.lines.map(function(l) {
            if (l.time < 0) return l.text
            var m = Math.floor(l.time / 60), sec = l.time - m * 60
            return "[" + (m < 10 ? "0" : "") + m + ":" + (sec < 10 ? "0" : "") + sec.toFixed(2) + "]" + l.text
          }).join("\n")
        }
        root.lyricsCache = Logic.rememberLyrics(root.lyricsCache,
          { key: key, at: Date.now(), found: result.found, instrumental: result.instrumental, text: text })
        lyricsCacheFile.setText(Logic.serializeLyricsCache(root.lyricsCache))
        if (result.instrumental) root.clearLyrics("Instrumental")
        else if (result.found) root.showLyrics(result.lyrics, "LRCLIB")
        else root.clearLyrics("No lyrics found")
      } else {
        // Offline, timed out, or LRCLIB having a bad moment: not cached, so
        // opening the column again tries again.
        root.lyricsLoadedKey = ""
        root.clearLyrics("Couldn't reach LRCLIB")
      }
    }
    xhr.send()
  }

  // After the rest of the metadata has landed, so title and file agree.
  onLyricsSourceKeyChanged: Qt.callLater(root.loadLyrics)
  // A new track with no lyrics closes the column instead of leaving it empty;
  // one still being looked up keeps it open.
  onLyricsStatusChanged: {
    if (root.lyricsOpen && !root.lyricsAvailable && root.lyricsStatus !== "Looking for lyrics…") root.sidePanel = ""
  }

  FileView {
    id: localLyrics
    property string forKey: ""
    printErrors: false
    onLoaded: {
      if (localLyrics.forKey !== root.lyricsSourceKey) return
      var parsed = Logic.parseLrc(text())
      if (parsed.lines.length > 0) root.showLyrics(parsed, "Local .lrc")
      else root.lookUpLyrics(root.lyricsKey)
    }
    onLoadFailed: if (localLyrics.forKey === root.lyricsSourceKey) root.lookUpLyrics(root.lyricsKey)
  }

  FileView {
    id: lyricsCacheFile
    path: root.liveStoreDir + "/lyrics-cache.json"
    printErrors: false
    atomicWrites: true
    onLoaded: root.lyricsCache = Logic.parseLyricsCache(text())
  }

  // ------------------------------------------------------------------- video
  //
  // For a player that shows video (a browser tab, mpv, VLC), a live capture of
  // its window takes the album art's place, as wide as the popup, with the
  // track's details beneath it. The window is the one belonging to the process
  // that owns the player's MPRIS name, and for a browser the one whose title
  // names the track. It captures the whole window; only while the popup is
  // open. See Logic.chooseVideoWindow.
  property int playerPid: 0
  property int windowsTick: 0

  readonly property bool videoCapable: {
    var p = root.activePlayer
    if (!p) return false
    var chromium = Logic.isChromiumPlayer(p.dbusName, (p.metadata || {})["mpris:trackid"])
    return Logic.isVideoPlayer(p.dbusName, p.identity, p.desktopEntry, chromium)
  }

  readonly property var videoWindow: {
    root.windowsTick
    if (!root.popupOpen || !root.videoCapable || root.playerPid <= 0) return null
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var list = tops.map(function(t) {
      var ipc = t.lastIpcObject || {}
      return { pid: ipc.pid, title: t.title, windowClass: ipc["class"] }
    })
    var p = root.activePlayer
    var chromium = Logic.isChromiumPlayer(p.dbusName, (p.metadata || {})["mpris:trackid"])
    var i = Logic.chooseVideoWindow(list, root.playerPid, p.trackTitle, chromium)
    return i >= 0 && tops[i].wayland ? tops[i] : null
  }
  readonly property bool showVideo: root.videoWindow !== null
  // Whether the preview is still getting frames: see Logic.feedLost. Judged
  // from the first sample on, so opening the popup doesn't flash the notice
  // before the first frame arrives.
  readonly property string feedSampleDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  property var feedLastSample: null
  property int feedStall: 0
  property bool feedChecked: false
  property bool feedHasContent: true
  readonly property bool videoFeedLost: root.feedChecked && Logic.feedLost(root.feedHasContent, root.feedStall)
  function resetFeedCheck() {
    root.feedLastSample = null
    root.feedStall = 0
    root.feedChecked = false
  }
  onVideoWindowChanged: root.resetFeedCheck()
  function addFeedSample(pixels) {
    var playing = !!(root.activePlayer && root.activePlayer.isPlaying)
    root.feedStall = Logic.nextStallCount(root.feedStall, Logic.sameFrame(root.feedLastSample, pixels), playing)
    root.feedLastSample = pixels
  }
  readonly property real videoAspect: {
    var ipc = root.videoWindow ? (root.videoWindow.lastIpcObject || {}) : {}
    var size = ipc.size || []
    return Logic.videoAspect(size[0], size[1])
  }

  function checkPlayerPid() {
    root.playerPid = 0
    var name = root.activePlayer ? String(root.activePlayer.dbusName || "") : ""
    if (!Logic.isMprisBusName(name) || pidProbe.running) return
    pidProbe.command = ["busctl", "--user", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", name]
    pidProbe.running = true
  }

  Process {
    id: pidProbe
    running: false
    stdout: StdioCollector { onStreamFinished: root.playerPid = Logic.parseBusctlUint(text) }
  }

  // Window titles and sizes change as tabs and tracks do; refreshed while the
  // popup is open on a player that might show video.
  Timer {
    running: root.popupOpen && root.videoCapable
    interval: 2000
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      Hyprland.refreshToplevels()
      root.windowsTick++
    }
  }

  // ---------------------------------------------------------------- playlist
  //
  // For a player that publishes its playlist (MPRIS TrackList, which archamp
  // does): the song's place and the time through the list above the art, and
  // the list itself in the side column. Quickshell has no TrackList, so it is
  // read with busctl: whether the player has one when it becomes active, and
  // the tracks every two seconds while the popup is open.
  property bool hasTrackList: false
  property var playlistIds: []
  property var playlistMeta: ({})
  // The playlist's name: the player's own, when it implements MPRIS
  // Playlists, else the saved playlist its queue matches.
  property string playerPlaylistName: ""
  readonly property string playlistName: root.playerPlaylistName
    || (root.linkActive ? Logic.playlistDisplayName(root.linkedPlaylist)
      : Logic.matchingPlaylistName(root.queuePaths, root.savedPlaylistPaths))
  readonly property bool playlistOpen: root.sidePanel === "playlist"
  readonly property string currentTrackId: root.activePlayer
    ? Logic.objectPathText((root.activePlayer.metadata || {})["mpris:trackid"]) : ""
  readonly property var playlistProgress: {
    root.positionTick
    return Logic.playlistProgress(root.playlistIds, root.playlistMeta, root.currentTrackId, root.trackPosition)
  }
  // The bar shows for a player that shares a playlist (MPRIS HasTrackList),
  // or that at least has shuffle or repeat, such as mpv or Spotify; within
  // the bar, anything the player can't do is dimmed and says so. Never for a
  // Chromium browser: it has none of the three, and never will.
  readonly property bool showPlaylistBar: {
    var p = root.activePlayer
    if (!root.hasMedia || !p) return false
    if (Logic.isChromiumPlayer(p.dbusName, (p.metadata || {})["mpris:trackid"])) return false
    return root.hasTrackList || root.hasShuffle || root.hasLoop
  }
  readonly property bool sharesPlaylist: root.hasTrackList && root.playlistIds.length > 0
  readonly property string playerName: root.activePlayer ? String(root.activePlayer.identity || root.activePlayer.desktopEntry || "This player") : "This player"

  function playerBusName() {
    var p = root.activePlayer
    var name = p ? String(p.dbusName || "") : ""
    if (!Logic.isMprisBusName(name) || Logic.isChromiumPlayer(name, (p.metadata || {})["mpris:trackid"])) return ""
    return name
  }

  function checkTrackList() {
    root.hasTrackList = false
    root.canEditTracks = false
    root.canMoveTracks = false
    root.queueAdding = false
    root.playlistIds = []
    root.playlistMeta = ({})
    root.playerPlaylistName = ""
    var name = root.playerBusName()
    if (!name || hasTrackListProbe.running) return
    hasTrackListProbe.command = ["busctl", "--user", "get-property", name, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2", "HasTrackList"]
    hasTrackListProbe.running = true
  }

  function refreshPlaylist() {
    var name = root.playerBusName()
    if (!name || !root.hasTrackList || tracksProbe.running) return
    tracksProbe.command = ["busctl", "--user", "--json=short", "get-property", name, "/org/mpris/MediaPlayer2",
      "org.mpris.MediaPlayer2.TrackList", "Tracks"]
    tracksProbe.running = true
    if (!playlistNameProbe.running) {
      playlistNameProbe.command = ["busctl", "--user", "--json=short", "get-property", name, "/org/mpris/MediaPlayer2",
        "org.mpris.MediaPlayer2.Playlists", "ActivePlaylist"]
      playlistNameProbe.running = true
    }
  }

  // Jumps to a playlist entry and plays it.
  function goToTrack(id) {
    var name = root.playerBusName()
    if (!name || !Logic.isObjectPath(id) || root.playlistIds.indexOf(id) === -1) return
    Quickshell.execDetached(["busctl", "--user", "call", name, "/org/mpris/MediaPlayer2",
      "org.mpris.MediaPlayer2.TrackList", "GoTo", "o", id])
    if (root.activePlayer && !root.activePlayer.isPlaying && root.activePlayer.canPlay) playAfterGoTo.restart()
  }

  Timer {
    id: playAfterGoTo
    interval: 150
    onTriggered: if (root.activePlayer && !root.activePlayer.isPlaying) root.activePlayer.play()
  }

  Process {
    id: hasTrackListProbe
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.hasTrackList = /^\s*b\s+true\s*$/.test(text)
        if (!root.hasTrackList) return
        root.refreshPlaylist()
        var name = root.playerBusName()
        if (name && !canEditProbe.running) {
          canEditProbe.command = ["busctl", "--user", "get-property", name, "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.TrackList", "CanEditTracks"]
          canEditProbe.running = true
        }
        // Moving has no MPRIS call; archamp offers its own. Anything else
        // fails this, which reads as no.
        if (name && !canMoveProbe.running) {
          canMoveProbe.command = ["busctl", "--user", "get-property", name, "/org/mpris/MediaPlayer2",
            "org.archamp.TrackList", "CanMoveTracks"]
          canMoveProbe.running = true
        }
      }
    }
  }

  Process {
    id: canEditProbe
    running: false
    stdout: StdioCollector { onStreamFinished: root.canEditTracks = /^\s*b\s+true\s*$/.test(text) }
  }

  Process {
    id: canMoveProbe
    running: false
    stdout: StdioCollector { onStreamFinished: root.canMoveTracks = /^\s*b\s+true\s*$/.test(text) }
  }

  // Editing the player's playlist: adding (MPRIS AddTrack, see
  // Logic.addTrackCommands) and removing (RemoveTrack) where the player allows
  // it, and moving where it offers archamp's MoveTrack. Calls run one at a
  // time, then the list is read again.
  property bool canEditTracks: false
  property bool canMoveTracks: false
  property var trackEditQueue: []

  function addTracksToQueue(paths) {
    var name = root.playerBusName()
    if (!name || !root.canEditTracks) return
    var last = root.playlistIds.length > 0 ? root.playlistIds[root.playlistIds.length - 1] : ""
    root.runTrackEdits(Logic.addTrackCommands(name, paths, last))
  }

  function removeQueueTrack(id) {
    var name = root.playerBusName()
    if (!name || !root.canEditTracks || root.playlistIds.indexOf(id) === -1) return
    root.runTrackEdits([["busctl", "--user", "call", name, "/org/mpris/MediaPlayer2",
      "org.mpris.MediaPlayer2.TrackList", "RemoveTrack", "o", id]])
  }

  // One place up or down: after the track two above, or the one below.
  function moveQueueTrack(index, delta) {
    var name = root.playerBusName()
    var ids = root.playlistIds
    var to = index + delta
    if (!name || !root.canMoveTracks || index < 0 || index >= ids.length || to < 0 || to >= ids.length) return
    var after = delta < 0 ? (to > 0 ? ids[to - 1] : Logic.NO_TRACK) : ids[to]
    root.runTrackEdits([["busctl", "--user", "call", name, "/org/mpris/MediaPlayer2",
      "org.archamp.TrackList", "MoveTrack", "oo", ids[index], after]])
  }

  function runTrackEdits(commands) {
    root.trackEditQueue = root.trackEditQueue.concat(commands)
    root.runTrackEditQueue()
  }

  function runTrackEditQueue() {
    if (trackEditCall.running) return
    if (root.trackEditQueue.length === 0) { root.refreshPlaylist(); return }
    trackEditCall.command = root.trackEditQueue[0]
    root.trackEditQueue = root.trackEditQueue.slice(1)
    trackEditCall.running = true
  }

  Process {
    id: trackEditCall
    running: false
    onExited: root.runTrackEditQueue()
  }

  // Browsing the music folder for tracks to add, inside the playlist column.
  property bool queueAdding: false
  property string queueAddFolder: ""
  property var queueAddSelection: []
  property string queueAddAnchor: ""

  // ---------------------------------------------------------------- updates
  //
  // A newer release of the plugin: found by asking GitHub for the latest
  // release (Logic.parseLatestRelease), shown as a button above Now Playing
  // until updated or dismissed, and installed with Omarchy's own plugin
  // update. The last answer is kept in update.json, so the notice is there as
  // soon as the popup opens.
  property string installedVersion: ""
  property var latestRelease: null
  property real updateCheckedAt: 0
  property bool updateChecking: false
  property string updateCheckError: ""
  property bool updateCheck: true
  property string updateDismissed: ""
  property bool updateRunning: false
  property string updateResult: ""
  property bool updateFailed: false
  // The version an update was last started for, kept in update.json so the
  // reloaded plugin can say how it went (see Logic.updateAttemptState).
  property var updateAttempt: null
  property string updatedVersion: ""
  readonly property bool updateOpen: root.sidePanel === "update"
  readonly property bool updateAvailable: root.latestRelease !== null && root.installedVersion !== ""
    && Logic.isNewerVersion(root.latestRelease.version, root.installedVersion)
  readonly property bool showUpdateNotice: root.updatedVersion !== ""
    || (root.updateAvailable && root.updateDismissed !== root.latestRelease.version)
  readonly property string updateCommandText: Logic.UPDATE_COMMAND.join(" ")

  function checkForUpdates() {
    if (root.updateChecking) return
    root.updateChecking = true
    root.updateCheckError = ""
    var xhr = new XMLHttpRequest()
    xhr.open("GET", Logic.RELEASES_API)
    xhr.setRequestHeader("Accept", "application/vnd.github+json")
    xhr.setRequestHeader("User-Agent", "OMedia Controls (https://github.com/lancefaul/omarchy-omedia-controls)")
    xhr.timeout = 15000
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      root.updateChecking = false
      if (xhr.status === 200) {
        var release = Logic.parseLatestRelease(xhr.responseText)
        if (!release) { root.updateCheckError = "GitHub's answer couldn't be read"; return }
        root.latestRelease = release
      } else if (xhr.status === 404) {
        root.latestRelease = null
      } else {
        root.updateCheckError = "Couldn't reach GitHub"
        return
      }
      root.updateCheckedAt = Date.now()
      root.saveUpdateCache()
    }
    xhr.send()
  }

  function saveUpdateCache() {
    updateCacheFile.setText(JSON.stringify({
      checkedAt: root.updateCheckedAt,
      release: root.latestRelease,
      attempt: root.updateAttempt,
    }))
  }

  // Updating reloads the plugin, taking this widget with it, so the attempt
  // is written down first and read back by whatever loads next.
  function runUpdate() {
    if (root.updateRunning || !root.latestRelease) return
    root.updateRunning = true
    root.updateFailed = false
    root.updateResult = ""
    root.updateAttempt = { version: root.latestRelease.version, at: Date.now() }
    root.saveUpdateCache()
    updateRunner.running = true
  }

  // What became of an attempt made before the reload.
  function readUpdateAttempt() {
    var state = Logic.updateAttemptState(root.updateAttempt, root.installedVersion, Date.now())
    if (state === "") return
    if (state === "applied") {
      root.updatedVersion = root.updateAttempt.version
      root.updateResult = "Updated to " + root.updatedVersion + "."
      root.updateFailed = false
    } else if (root.updateResult === "") {
      root.updateResult = "The update didn't finish."
      root.updateFailed = true
    }
    root.updateAttempt = null
    root.saveUpdateCache()
  }

  function finishUpdated() {
    root.updatedVersion = ""
    root.updateResult = ""
    if (root.updateOpen) root.sidePanel = ""
  }

  function restartShell() {
    Quickshell.execDetached(Logic.RESTART_COMMAND)
  }

  function dismissUpdate() {
    if (root.latestRelease) root.setSetting("updateDismissed", root.latestRelease.version)
    if (root.updateOpen) root.sidePanel = ""
  }

  FileView {
    path: Qt.resolvedUrl("manifest.json")
    printErrors: false
    onLoaded: {
      try { root.installedVersion = String(JSON.parse(text()).version || "") } catch (e) { root.installedVersion = "" }
      root.readUpdateAttempt()
    }
  }

  FileView {
    id: updateCacheFile
    path: root.liveStoreDir + "/update.json"
    printErrors: false
    atomicWrites: true
    onLoaded: {
      var cache = Logic.parseUpdateCache(text())
      root.updateCheckedAt = cache.checkedAt
      root.latestRelease = cache.release
      root.updateAttempt = cache.attempt
      root.readUpdateAttempt()
    }
  }

  // Omarchy's plugin update: fetch, validate (rolling back a failure), and
  // reload. A successful update reloads this widget, so only a failure
  // stays to be read.
  Process {
    id: updateRunner
    command: Logic.UPDATE_COMMAND
    running: false
    stdout: StdioCollector { id: updateStdout }
    stderr: StdioCollector { id: updateStderr }
    onExited: function(code) {
      root.updateRunning = false
      root.updateFailed = code !== 0
      var out = (String(updateStderr.text || "") + "\n" + String(updateStdout.text || "")).trim()
      root.updateResult = code === 0 ? (out || "Updated.") : (out || "The update failed.")
      if (code !== 0) {
        root.updateAttempt = null
        root.saveUpdateCache()
      }
    }
  }

  // Search: every file in the music folder, listed once per library or Add
  // browser opening (see Logic.libraryFindCommand), then filtered as you type.
  property var libraryIndex: []
  property string libraryIndexRoot: ""
  property string librarySearch: ""
  property string queueAddSearch: ""
  readonly property bool librarySearching: Logic.searchText(root.librarySearch).length >= Logic.LIBRARY_SEARCH_MIN
  readonly property bool queueAddSearching: Logic.searchText(root.queueAddSearch).length >= Logic.LIBRARY_SEARCH_MIN
  readonly property var librarySearchResult: Logic.searchLibrary(root.libraryIndex, root.libraryRoot, root.librarySearch)
  readonly property var queueAddSearchResult: Logic.searchLibrary(root.libraryIndex, root.libraryRoot, root.queueAddSearch)

  function indexLibrary() {
    if (libraryIndexer.running || !root.libraryRoot) return
    if (root.libraryIndexRoot === root.libraryRoot && root.libraryIndex.length > 0) return
    libraryIndexer.forRoot = root.libraryRoot
    libraryIndexer.command = Logic.libraryFindCommand(root.libraryRoot)
    libraryIndexer.running = true
  }

  Process {
    id: libraryIndexer
    property string forRoot: ""
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.libraryIndex = Logic.parseFileList(text, libraryIndexer.forRoot)
        root.libraryIndexRoot = libraryIndexer.forRoot
      }
    }
  }

  // Opening the library or the Add browser lists the folder afresh, so files
  // added since show up; closing either clears its search.
  onLibraryOpenChanged: {
    librarySearchBox.text = ""
    if (root.libraryOpen) root.libraryIndexRoot = ""
  }

  function startQueueAdd() {
    root.queueAddFolder = root.libraryFolder || root.libraryRoot
    root.queueAddSelection = []
    root.queueAddAnchor = ""
    queueAddSearchBox.text = ""
    root.libraryIndexRoot = ""
    root.queueAdding = true
  }

  onPlaylistOpenChanged: if (!root.playlistOpen) root.finishQueueAdd(false)

  function finishQueueAdd(add) {
    if (add && root.queueAddSelection.length > 0) root.addTracksToQueue(root.queueAddSelection)
    root.queueAdding = false
    queueAddSearchBox.text = ""
    root.queueAddSelection = []
    root.queueAddAnchor = ""
  }

  Process {
    id: tracksProbe
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        var ids = Logic.parseTrackIds(text)
        var changed = JSON.stringify(ids) !== JSON.stringify(root.playlistIds)
        root.playlistIds = ids
        // Titles and lengths too, when the list changed or some are missing
        // (a player fills in tags as it reads them).
        var missing = ids.some(function(id) { return !root.playlistMeta[id] || !root.playlistMeta[id].length })
        if ((changed || missing) && ids.length > 0 && !metadataProbe.running) {
          var name = root.playerBusName()
          if (!name) return
          metadataProbe.command = ["busctl", "--user", "--json=short", "call", name, "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.TrackList", "GetTracksMetadata", "ao", String(ids.length)].concat(ids)
          metadataProbe.running = true
        }
      }
    }
  }

  // A player without the Playlists interface makes busctl fail with nothing on
  // stdout, which reads as no name.
  Process {
    id: playlistNameProbe
    running: false
    stdout: StdioCollector { onStreamFinished: root.playerPlaylistName = Logic.activePlaylistName(text) }
  }

  Process {
    id: metadataProbe
    running: false
    stdout: StdioCollector {
      onStreamFinished: root.playlistMeta = Logic.parseTracksMetadata(text)
    }
  }

  Timer {
    running: root.popupOpen && root.hasTrackList
    interval: 2000
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshPlaylist()
  }

  // Several tracks: a player that takes one item over MPRIS gets a playlist
  // of them, written to the plugin's private state folder first; the default
  // audio app gets the tracks themselves.
  function playPaths(paths) {
    var clean = []
    for (var i = 0; i < paths.length; i++) {
      var p = Logic.cleanPath(paths[i])
      if (p && Logic.isInside(root.libraryRoot, p)) clean.push(p)
    }
    if (clean.length === 0) return
    if (clean.length === 1) { root.playPath(clean[0]); return }
    var player = root.activePlayer
    var name = player ? String(player.dbusName || "") : ""
    if (player && Logic.isMprisBusName(name) && !Logic.isChromiumPlayer(name, (player.metadata || {})["mpris:trackid"])) {
      selectionPlaylist.pending = clean
      selectionPlaylist.setText(Logic.playlistText(clean))
      return
    }
    root.launchAudioApp(clean)
  }

  FileView {
    id: selectionPlaylist
    property var pending: []
    path: root.liveStoreDir + "/selection.m3u"
    printErrors: false
    atomicWrites: true
    onSaved: {
      var player = root.activePlayer
      var name = player ? String(player.dbusName || "") : ""
      if (!Logic.isMprisBusName(name)) { root.launchAudioApp(selectionPlaylist.pending); return }
      openUri.fallback = selectionPlaylist.pending
      openUri.command = ["busctl", "--user", "call", name, "/org/mpris/MediaPlayer2",
        "org.mpris.MediaPlayer2.Player", "OpenUri", "s", Logic.pathToFileUri(selectionPlaylist.path)]
      openUri.running = true
    }
    onSaveFailed: root.launchAudioApp(selectionPlaylist.pending)
  }
  property string desktopMusicFolder: Logic.libraryRoot("", Quickshell.env("HOME"))
  // The chosen music folder, else the desktop's.
  readonly property string libraryRoot: root.musicFolder || root.desktopMusicFolder
  property string libraryDir: ""
  readonly property string libraryFolder: Logic.libraryFolder(root.libraryRoot, root.libraryDir)
  property string desktopAudioApp: ""
  // The chosen music player, else the desktop's app for audio files.
  readonly property string audioAppId: root.musicPlayer || root.desktopAudioApp

  function openLibraryFolder(path) {
    root.libraryDir = Logic.libraryFolder(root.libraryRoot, path)
    root.savePreferences()
  }

  function playPath(path) {
    var clean = Logic.cleanPath(path)
    if (!clean || !Logic.isInside(root.libraryRoot, clean)) return
    var p = root.activePlayer
    var name = p ? String(p.dbusName || "") : ""
    // Chromium players have no OpenUri to speak of; don't try.
    if (p && Logic.isMprisBusName(name) && !Logic.isChromiumPlayer(name, (p.metadata || {})["mpris:trackid"])) {
      openUri.fallback = [clean]
      openUri.command = ["busctl", "--user", "call", name, "/org/mpris/MediaPlayer2",
        "org.mpris.MediaPlayer2.Player", "OpenUri", "s", Logic.pathToFileUri(clean)]
      openUri.running = true
      return
    }
    root.launchAudioApp(clean)
  }

  // Anything played from the library (a double-click, a folder's play button,
  // Play all, Play selected) closes it: the pick is made.
  function playFromLibrary(paths) {
    if (Array.isArray(paths)) root.playPaths(paths)
    else root.playPath(paths)
    if (root.libraryOpen) root.sidePanel = ""
  }

  // Starts the desktop's audio app on one path or several.
  function launchAudioApp(paths) {
    var list = Array.isArray(paths) ? paths : [paths]
    if (list.length === 0) return
    if (root.audioAppId) Quickshell.execDetached(["gtk-launch", root.audioAppId].concat(list))
    else Quickshell.execDetached(["xdg-open", list[0]])
  }

  // The player refusing OpenUri (or not having it) exits non-zero: start the
  // default audio app instead.
  Process {
    id: openUri
    property var fallback: []
    running: false
    onExited: function(code) { if (code !== 0) root.launchAudioApp(openUri.fallback) }
  }

  Process {
    running: true
    command: ["xdg-user-dir", "MUSIC"]
    stdout: StdioCollector {
      onStreamFinished: root.desktopMusicFolder = Logic.libraryRoot(text, Quickshell.env("HOME"))
    }
  }

  // The app the desktop opens audio files with, e.g. mpv-headless-audio.
  Process {
    running: true
    command: ["xdg-mime", "query", "default", "audio/mpeg"]
    stdout: StdioCollector {
      onStreamFinished: {
        var id = String(text || "").trim()
        root.desktopAudioApp = Logic.isDesktopId(id) ? id : ""
      }
    }
  }

  FileView {
    id: preferences
    path: root.liveStoreDir + "/preferences.json"
    printErrors: false
    atomicWrites: true
    onLoaded: root.applyPreferences(Logic.parsePreferences(text()))
    // No file yet: a fresh install, or 1.0's first run as 2.0.
    onLoadFailed: root.applyPreferences(Logic.parsePreferences(""))
  }

  // Takes in saved preferences, carrying over 1.0's config settings the first
  // time (see Logic.migrateSettings).
  function applyPreferences(loaded) {
      var prefs = loaded.settingsMigrated ? loaded : Logic.migrateSettings(loaded, root.settings)
      root.settingsMigrated = true
      root.titleWidth = prefs.titleWidth
      root.updateCheck = prefs.updateCheck
      root.updateDismissed = prefs.updateDismissed
      root.scrollTitle = prefs.scrollTitle
      root.visualisation = prefs.visualisation
      root.visColour = prefs.visColour
      root.pauseOthers = prefs.pauseOthers
      root.libraryDir = prefs.libraryDir
      root.musicFolder = prefs.musicFolder
      root.playlistFolder = prefs.playlistFolder
      root.musicPlayer = prefs.musicPlayer
      root.onlineLyrics = prefs.onlineLyrics
      root.webArt = prefs.webArt
      root.rememberStations = prefs.rememberStations
      root.hideWhenIdle = prefs.hideWhenIdle
      root.seekStep = prefs.seekStep
      root.volumeStep = prefs.volumeStep
      if (!loaded.settingsMigrated) root.savePreferences()
  }

  // open, close and opened are what the bar looks for to route a hotkey here:
  // `omarchy-shell shell toggle lancefaul.omedia-controls` opens the popup on
  // the focused monitor.
  readonly property bool opened: popupOpen
  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }
  // Widest the bar title gets before it elides (it scrolls under the pointer),
  // chosen in Settings; 0 is no limit.
  property int titleWidth: 260
  // Whether a bar title too long for that width keeps scrolling.
  property bool scrollTitle: true
  property bool settingsMigrated: false
  readonly property int maxLabelWidth: root.titleWidth > 0 ? root.titleWidth : 100000

  // ---------------------------------------------------------------- position
  //
  // MPRIS position doesn't notify on its own — a player reports where it is
  // when asked, not as it plays. positionTick is the dependency that makes the
  // binding below re-read it, and the timer only runs while the popup is open
  // on a playing track, so a closed popup costs nothing.
  property int positionTick: 0
  property bool seeking: false
  property real seekPreview: 0

  readonly property bool canSeek: !!(activePlayer && activePlayer.canSeek && activePlayer.positionSupported)
  // A live stream reports a sentinel length (INT64_MAX microseconds from
  // Chromium) rather than none. That is not a duration, so it never becomes
  // trackLength — the popup shows LIVE instead of a nine-trillion-second
  // counter. See Logic.isUnboundedLength.
  readonly property bool unboundedLive: !!(activePlayer && activePlayer.lengthSupported
    && Logic.isUnboundedLength(activePlayer.length))

  // The other kind of live stream: a finite length that grows as it plays, as
  // Apple Music radio reports. Latched per track once growth is seen, and
  // cleared when the track or player changes. See Logic.isGrowingLength.
  property bool growingLive: false
  property real observedLength: 0
  property string observedTrack: ""
  // LIVE carried across a track change, awaiting growth to confirm it. See
  // Logic.provisionalLiveExpired.
  property bool liveProvisional: false
  // Whether that provisional LIVE came from the remembered stations, rather
  // than being carried over from the previous track. See
  // Logic.provisionalExpiryRuns.
  property bool liveFromMemory: false
  property real liveProvisionalSince: 0
  // The player being controlled, and the last live one that went away with
  // when, so a player re-registering on a station switch keeps LIVE.
  property string activeKey: ""
  property string liveGoneKey: ""
  property real liveGoneAt: 0

  // Stations already detected, remembered by app and title so they read as
  // LIVE the moment they start instead of after a segment. Stored under the
  // user's state directory in a folder only they can read; the format and
  // its validation live in Logic.js.
  readonly property string liveStoreDir: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")) + "/omedia-controls"
  readonly property string liveStorePath: liveStoreDir + "/live-streams.json"
  property var knownLiveStreams: []
  // The track already written this session, so a stream that grows every
  // sixteen seconds is saved once rather than on every segment.
  property string rememberedTrack: ""

  FileView {
    id: liveStore
    path: root.liveStorePath
    printErrors: false
    atomicWrites: true
    Component.onCompleted: Quickshell.execDetached(["install", "-d", "-m", "700", root.liveStoreDir])
    onLoaded: {
      root.knownLiveStreams = Logic.parseLiveStreamStore(text())
      // The store can finish loading after the current track was first seen.
      if (!root.growingLive) {
        root.observedTrack = ""
        root.watchLength()
      }
    }
    onLoadFailed: root.knownLiveStreams = []
  }

  function saveLiveStreams() {
    liveStore.setText(Logic.serializeLiveStreamStore(root.knownLiveStreams))
  }

  function rememberLive(track) {
    if (!root.rememberStations) return
    root.knownLiveStreams = Logic.rememberLiveStream(root.knownLiveStreams, track, Date.now())
    root.saveLiveStreams()
  }

  function forgetLive(track) {
    // Clear the write-once marker too, or a station forgotten by mistake could
    // never be remembered again until the shell restarted.
    if (root.rememberedTrack === track) root.rememberedTrack = ""
    if (!Logic.isKnownLiveStream(root.knownLiveStreams, track)) return
    root.knownLiveStreams = Logic.forgetLiveStream(root.knownLiveStreams, track)
    root.saveLiveStreams()
  }

  function trackIdentity(p) {
    return p ? String(p.identity || "") + " | " + String(p.trackTitle || "") : ""
  }

  function watchLength() {
    var p = root.activePlayer
    if (!p || !p.lengthSupported) return
    var length = p.length
    var track = trackIdentity(p)
    if (track !== root.observedTrack) {
      // Stay LIVE provisionally, rather than flash a timeline first, when the
      // player was just playing a live stream (a new track is almost always
      // another station) or this is a station heard before.
      var wasLive = Logic.carriesLive(root.growingLive, root.liveProvisional)
      var known = root.rememberStations && !!p.trackTitle && Logic.isKnownLiveStream(root.knownLiveStreams, track)
      root.observedTrack = track
      root.observedLength = length
      root.growingLive = wasLive || known
      root.liveProvisional = wasLive || known
      root.liveFromMemory = known
      root.liveProvisionalSince = Date.now()
      // A station never heard before: ask where playback started, in case it
      // is a radio station tuning in. See Logic.looksLikeRadioTuneIn.
      if (!wasLive && !known && p.trackTitle
          && Logic.isChromiumPlayer(p.dbusName, (p.metadata || {})["mpris:trackid"]))
        root.checkTuneIn(p, track)
      return
    }
    if (p.isPlaying && Logic.isGrowingLength(root.observedLength, length)) {
      root.growingLive = true
      root.liveProvisional = false
      if (p.trackTitle && root.rememberedTrack !== track) {
        root.rememberedTrack = track
        root.rememberLive(track)
      }
    }
    root.observedLength = length
  }

  // Chromium never announces position changes, so Quickshell's value can be
  // left over from the previous track; the player is asked directly, after a
  // moment for the new track's position to settle.
  function checkTuneIn(player, track) {
    var name = String(player.dbusName || "")
    if (!Logic.isMprisBusName(name)) return
    tuneInProbe.track = track
    tuneInProbe.command = ["busctl", "--user", "get-property", name,
      "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "Position"]
    tuneInDelay.restart()
  }

  Timer {
    id: tuneInDelay
    interval: 400
    onTriggered: if (!tuneInProbe.running) tuneInProbe.running = true
  }

  Process {
    id: tuneInProbe
    property string track: ""
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        var p = root.activePlayer
        // Only for the track it was asked about, and only if nothing has
        // decided it is live in the meantime.
        if (!p || root.growingLive || root.trackIdentity(p) !== tuneInProbe.track) return
        if (!Logic.looksLikeRadioTuneIn(Logic.parseBusctlPosition(line), p.length)) return
        root.growingLive = true
        root.liveProvisional = true
        root.liveFromMemory = false
        root.liveProvisionalSince = Date.now()
      }
    }
  }

  // Ends a provisional LIVE whose length never grew: it was a song.
  Timer {
    running: root.liveProvisional && root.activePlayer !== null
      && Logic.provisionalExpiryRuns(root.activePlayer.isPlaying, root.liveFromMemory)
    interval: 2000
    repeat: true
    onTriggered: {
      if (!Logic.provisionalLiveExpired(root.liveProvisionalSince, Date.now())) return
      // Never grew: a song after all. If it was remembered as a station,
      // that memory was wrong, so drop it.
      root.forgetLive(root.observedTrack)
      root.growingLive = false
      root.liveProvisional = false
    }
  }

  Connections {
    target: root.activePlayer
    ignoreUnknownSignals: true
    function onLengthChanged() { root.watchLength() }
    function onTrackTitleChanged() { root.watchLength() }
  }

  readonly property bool isLive: root.unboundedLive || root.growingLive
  readonly property real trackLength: activePlayer && activePlayer.lengthSupported && !root.isLive
    ? Math.max(0, activePlayer.length) : 0
  // Whether there is a timeline to show at all. The controls stay put either
  // way — only their contents and enabled state follow this — so the popup
  // keeps one shape whether or not anything is playing.
  readonly property bool hasTimeline: !!(activePlayer && activePlayer.positionSupported && root.trackLength > 0)

  // Quickshell's position is extrapolated from whenever it last heard from the
  // player, and nothing forces it to re-read: emitting positionChanged() does
  // not, and a player restarting a track on repeat sends no Seeked signal. The
  // value then runs off the end of the track — measured at 28.98 on a
  // ten-second file — and a bar clamped to the length just sits at full.
  //
  // So the position is read straight off the player's own D-Bus property while
  // the popup is open, and interpolated between reads. probedAt is measured in
  // the same clock as the reads, so the two never disagree about "now".
  property real probedPosition: -1
  property real probedAt: 0
  // Position reads are ignored until this time, after a seek from the panel.
  property real seekSettledAt: 0

  readonly property real quickshellPosition: {
    root.positionTick
    if (!activePlayer || !activePlayer.positionSupported) return 0
    return Math.max(0, activePlayer.position)
  }
  readonly property real trackPosition: {
    root.positionTick
    if (!activePlayer || !activePlayer.positionSupported) return 0

    var raw = root.quickshellPosition
    if (root.probedPosition >= 0) {
      // Scaled by the playback rate, or at 1.5x the bar would lag and then
      // jump forward at every read.
      var elapsed = activePlayer.isPlaying
        ? (Date.now() - root.probedAt) / 1000 * Logic.effectiveRate(activePlayer.rate) : 0
      raw = root.probedPosition + elapsed
    }
    return Math.max(0, root.trackLength > 0 ? Math.min(raw, root.trackLength) : raw)
  }
  // What the slider and counter show: the drag target while scrubbing, so the
  // number under the cursor is the one you're aiming at, not the one playing.
  readonly property real displayPosition: root.seeking ? root.seekPreview : root.trackPosition

  property bool showRemaining: false

  function formatTime(seconds) { return Logic.formatTime(seconds) }

  function seekTo(seconds) {
    if (!root.canSeek || !activePlayer) return
    var target = Math.max(0, root.trackLength > 0 ? Math.min(seconds, root.trackLength) : seconds)
    activePlayer.position = target
    // Treat the seek as a fresh sync point, and hold it until the player has
    // caught up: seeks land asynchronously, and a read in the gap would drag
    // the bar back to where it was dragged from. See Logic.SEEK_SETTLE_MS.
    // With the popup shut nothing re-reads it, so it would only go stale.
    root.probedPosition = root.popupOpen ? target : -1
    root.probedAt = Date.now()
    root.seekSettledAt = Date.now() + Logic.SEEK_SETTLE_MS
    root.positionTick++
  }

  // ------------------------------------------------------------------ volume
  //
  // A player can publish Volume and still ignore it: Chromium browsers
  // hard-code 1.0. Quickshell keeps the value last sent rather than the
  // player's, so such a slider would move, do nothing, and then show a volume
  // the player never had. Chromium is recognised up front; any other player is
  // checked by reading its volume back after a change. A player caught
  // ignoring it has the controls disabled, with its real volume shown.
  // See Logic.isChromiumPlayer.
  property var ignoredVolumes: ({})
  readonly property bool volumeLocked: !!(activePlayer && activePlayer.volumeSupported
    && (Logic.isChromiumPlayer(activePlayer.dbusName, (activePlayer.metadata || {})["mpris:trackid"])
      || root.ignoredVolumes[root.playerKey(activePlayer)] !== undefined))
  // What the player really reports while locked: 1.0 for Chromium, otherwise
  // the value read back.
  readonly property real lockedVolume: {
    if (!root.volumeLocked) return 0
    var v = root.ignoredVolumes[root.playerKey(activePlayer)]
    return v === undefined ? 1 : v
  }
  readonly property bool hasVolume: !!(activePlayer && activePlayer.volumeSupported && !root.volumeLocked)
  property real lastVolume: 0.5

  function setVolume(value) {
    if (!root.hasVolume || !activePlayer) return
    var v = Math.max(0, Math.min(1, value))
    if (v > 0) root.lastVolume = v
    activePlayer.volume = v
    root.checkVolume(v)
  }
  function toggleMute() {
    if (!root.hasVolume || !activePlayer) return
    var target
    if (activePlayer.volume > 0.001) {
      root.lastVolume = activePlayer.volume
      target = 0
    } else {
      target = root.lastVolume > 0.001 ? root.lastVolume : 0.5
    }
    activePlayer.volume = target
    root.checkVolume(target)
  }

  // Reads the volume back shortly after a change, once the player has had time
  // to apply it. Restarted by each change, so a drag is checked once, at rest.
  function checkVolume(target) {
    var name = activePlayer ? String(activePlayer.dbusName || "") : ""
    if (!Logic.isMprisBusName(name)) return
    volumeCheck.key = root.playerKey(activePlayer)
    volumeCheck.target = target
    volumeCheck.command = ["busctl", "--user", "get-property", name,
      "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "Volume"]
    volumeCheckDelay.restart()
  }

  Timer {
    id: volumeCheckDelay
    interval: 600
    onTriggered: if (!volumeCheck.running) volumeCheck.running = true
  }

  Process {
    id: volumeCheck
    property string key: ""
    property real target: 0
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        var reported = Logic.parseBusctlDouble(line)
        if (!Logic.volumeWasIgnored(volumeCheck.target, reported)) return
        var next = Object.assign({}, root.ignoredVolumes)
        next[volumeCheck.key] = reported
        root.ignoredVolumes = next
      }
    }
  }

  // ------------------------------------------------------- shuffle and loop
  readonly property bool hasShuffle: !!(activePlayer && activePlayer.shuffleSupported)
  readonly property bool hasLoop: !!(activePlayer && activePlayer.loopSupported)

  function toggleShuffle() {
    if (!root.hasShuffle || !activePlayer) return
    activePlayer.shuffle = !activePlayer.shuffle
  }
  // Winamp's order: off, repeat everything, repeat this one.
  function cycleLoop() {
    if (!root.hasLoop || !activePlayer) return
    if (activePlayer.loopState === MprisLoopState.None) activePlayer.loopState = MprisLoopState.Playlist
    else if (activePlayer.loopState === MprisLoopState.Playlist) activePlayer.loopState = MprisLoopState.Track
    else activePlayer.loopState = MprisLoopState.None
  }

  // ------------------------------------------------------------------- speed
  // Most players report a fixed rate — browsers and Spotify a range of 1 to 1
  // — so the chips stay disabled there. mpv reports 0.01 to 100.
  readonly property bool hasRate: !!(activePlayer && Logic.canChangeRate(activePlayer.minRate, activePlayer.maxRate))

  function setRate(rate) {
    if (!root.hasRate || !Logic.rateInRange(rate, activePlayer.minRate, activePlayer.maxRate)) return false
    activePlayer.rate = rate
    return true
  }
  function stepRate(direction) {
    if (!root.hasRate) return false
    var rate = Logic.stepRate(activePlayer.rate, direction, activePlayer.minRate, activePlayer.maxRate)
    return rate > 0 && root.setRate(rate)
  }

  // ---------------------------------------------------------------- commands
  // One place for everything the popup's keys and the IPC commands can do, so
  // the two never drift apart. Returns false when the player can't do it.
  function perform(action) {
    var p = root.activePlayer
    if (action === "close") { root.close(); return true }
    if (!p) return false
    switch (action) {
    case "playPause":
      if (!(p.canTogglePlaying || p.canPlay || p.canPause)) return false
      root.runAction("playPause", root.playerKey(p)); return true
    case "next":
      if (!p.canGoNext) return false
      root.runAction("next", root.playerKey(p)); return true
    case "previous":
      if (!p.canGoPrevious) return false
      root.runAction("previous", root.playerKey(p)); return true
    case "seekBack": return root.seekBy(-root.seekStep)
    case "seekForward": return root.seekBy(root.seekStep)
    case "volumeUp": return root.adjustVolume("+" + root.volumeStep)
    case "volumeDown": return root.adjustVolume("-" + root.volumeStep)
    case "mute":
      if (!root.hasVolume) return false
      root.toggleMute(); return true
    case "shuffle":
      if (!root.hasShuffle) return false
      root.toggleShuffle(); return true
    case "repeat":
      if (!root.hasLoop) return false
      root.cycleLoop(); return true
    case "faster": return root.stepRate(1)
    case "slower": return root.stepRate(-1)
    case "goLive":
      if (!root.canGoLive) return false
      root.jumpToLive(); return true
    }
    return false
  }

  // Seeking on a live stream has no timeline to aim at, so it is refused
  // rather than sent as a guess.
  function seekBy(seconds) {
    if (!root.canSeek || !root.hasTimeline) return false
    root.seekTo(root.trackPosition + seconds)
    return true
  }
  function seekCommand(text) {
    if (!root.canSeek || !root.hasTimeline) return false
    var target = Logic.seekTarget(root.trackPosition, root.trackLength, text)
    if (target < 0) return false
    root.seekTo(target)
    return true
  }
  function adjustVolume(text) {
    if (!root.hasVolume) return false
    var v = Logic.volumeTarget(activePlayer.volume, text)
    if (v < 0) return false
    root.setVolume(v)
    return true
  }
  readonly property string specScript: String(Qt.resolvedUrl("spectrum.py")).replace("file://", "")

  // On the bar even with nothing playing, as a stable click target, unless
  // "hide when nothing is playing" is on. Then it still comes back the moment
  // a player has a track, and stays while its popup is open.
  visible: !root.hideWhenIdle || root.hasMedia || root.popupOpen
  implicitWidth: row.implicitWidth + Style.space(14)
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    BorderSurface {
      id: artThumb
      anchors.verticalCenter: parent.verticalCenter
      width: root.barSize - Style.space(8)
      height: width
      radius: Style.space(3)
      opacity: root.hasMedia ? 1.0 : 0.5
      color: Style.normalFillFor(root.bar.barForeground, Color.accent)
      borderSpec: Border.controlSpec("normal", root.bar.barForeground, Color.accent)

      Image {
        anchors.fill: parent
        anchors.margins: Style.space(1)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        source: root.artUrl
        visible: source !== ""
      }

      Text {
        anchors.centerIn: parent
        visible: root.artUrl === ""
        text: "󰝚"
        color: root.bar.barForeground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Marquee {
      id: labelText
      anchors.verticalCenter: parent.verticalCenter
      text: root.hasMedia ? root.title : "No media"
      // Capped so a long title can't push the bar's other sections around.
      // Too long for the cap, it scrolls while there is a track, unless
      // scrolling is off in Settings; then it's cut short. Marquee only
      // moves when the text overflows, so a title that fits stays still.
      width: Math.min(contentWidth, root.maxLabelWidth)
      running: root.scrollTitle && root.hasMedia
      color: root.bar.barForeground
      opacity: root.hasMedia ? 1.0 : 0.5
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      visible: !root.bar.vertical
    }
  }

  // Tells the bar's open-panel underline to span this widget's full painted
  // width instead of the default 55%-of-slot fraction.
  readonly property real openPanelIndicatorWidth: implicitWidth

  // A drag that never gets its release — the popup closing under the cursor,
  // the focus grab taking the pointer, a mouse-up outside the slider — would
  // otherwise leave `seeking` stuck true, which freezes the bar where it was
  // and stops the timer below, since that only runs while not seeking.
  // PanelSlider has no canceled signal to hook, so the flag is cleared
  // wherever a drag cannot still be in progress.
  onPopupOpenChanged: {
    root.probeFormat()
    root.loadLyrics()
    if (root.popupOpen && root.updateCheck && Logic.updateCheckDue(root.updateCheckedAt, Date.now())) root.checkForUpdates()
    if (!root.popupOpen) {
      root.seeking = false
      // Nothing probes while the popup is shut, so a kept value would only be
      // interpolated forward from a stale point the next time it opens.
      root.probedPosition = -1
    }
  }
  onActivePlayerChanged: {
    Qt.callLater(root.checkTrackList)
    Qt.callLater(root.checkPlayerPid)
    var now = Date.now()

    // Leaving a live player: note which, in case it is only re-registering.
    if (root.growingLive && root.activeKey) {
      root.liveGoneKey = root.activeKey
      root.liveGoneAt = now
    }

    var key = root.playerKey(root.activePlayer)
    root.activeKey = key

    // The same live player back under the same name moments later keeps LIVE,
    // provisionally; anything else is a different player and starts fresh.
    // See Logic.isReturningLivePlayer.
    var returning = Logic.isReturningLivePlayer(key, root.liveGoneKey, root.liveGoneAt, now)
    root.observedTrack = ""
    root.growingLive = returning
    root.liveProvisional = returning
    root.liveFromMemory = returning
    if (returning) root.liveProvisionalSince = now
    root.watchLength()
    root.seeking = false
    root.probedPosition = -1
    root.positionTick++
  }

  // A track restarting on repeat moves the position backwards without any
  // other state changing, so the bar has to be told to look again — otherwise
  // it sits at the end until something else happens to refresh it.
  Connections {
    target: root.activePlayer
    ignoreUnknownSignals: true

    function onTrackChanged() { root.seeking = false; root.positionTick++ }
    function onPostTrackChanged() { root.positionTick++ }
    function onMetadataChanged() { root.positionTick++ }
    function onPlaybackStateChanged() {
      root.positionTick++
      // A remembered station's window to prove itself counts playing time: a
      // station switched to while paused and resumed a minute later would
      // otherwise be judged at once, before it had the chance to grow, and
      // forgotten.
      if (root.liveProvisional && root.liveFromMemory && root.activePlayer.isPlaying)
        root.liveProvisionalSince = Date.now()
    }
    function onPositionChanged() { root.positionTick++ }
  }

  // Reads Position off the player's own D-Bus interface. Only while the popup
  // is open on a playing track, and not while scrubbing, which is the same
  // rule the visualiser and the tick timer follow.
  Process {
    id: positionProbe
    running: false
    stdout: SplitParser {
      onRead: function(line) {
        // Anything but a clean `x <microseconds>` line is ignored, and the
        // bar keeps interpolating from the last good read.
        var seconds = Logic.parseBusctlPosition(line)
        if (seconds < 0) return
        // Still settling after a seek: this read may predate it.
        if (Date.now() < root.seekSettledAt) return
        root.probedPosition = seconds
        root.probedAt = Date.now()
        root.positionTick++
      }
    }
  }

  Timer {
    running: root.popupOpen && root.activePlayer !== null && root.activePlayer.isPlaying && !root.seeking
    interval: 2000
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      var name = root.activePlayer ? String(root.activePlayer.dbusName || "") : ""
      // The name is chosen by whichever app registered the player. It goes to
      // busctl as an argument list, never a shell, but it is still refused
      // unless it is shaped like an MPRIS well-known name.
      if (!Logic.isMprisBusName(name) || positionProbe.running) return
      positionProbe.command = ["busctl", "--user", "get-property", name,
        "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "Position"]
      positionProbe.running = true
    }
  }

  // Sends a live stream back to its live edge, by asking for a position a year
  // ahead, which the player caps at the newest point it has. Written through
  // MprisPlayer.position, i.e. SetPosition, because Chromium turns a relative
  // Seek into a fixed five-second skip. See Logic.LIVE_EDGE_POSITION_SECONDS.
  //
  // The panel cannot tell whether you are live or behind — after a rewind,
  // Brave reports the same unbounded length and a position counter restarted
  // at zero, exactly as at the edge — so this is always available on a live
  // stream that can rewind rather than lighting up only when you are behind.
  // A growing stream such as Apple Music radio gets none; see
  // Logic.liveEdgeTarget.
  readonly property bool canGoLive: root.canSeek
    && Logic.liveEdgeTarget(root.activePlayer ? root.activePlayer.length : 0, root.unboundedLive) >= 0
  function jumpToLive() {
    if (!root.canGoLive) return
    var target = Logic.liveEdgeTarget(root.activePlayer.length, root.unboundedLive)
    if (target < 0) return
    root.activePlayer.position = target
    // The counter restarts on the seek; forget the old sync point, and don't
    // let a read from before the seek landed put it back.
    root.probedPosition = -1
    root.seekSettledAt = Date.now() + Logic.SEEK_SETTLE_MS
    root.positionTick++
  }

  // ------------------------------------------------------------------- IPC
  //
  //   omarchy-shell lancefaul.omedia-controls playPause
  //   omarchy-shell lancefaul.omedia-controls seek +10
  //   omarchy-shell lancefaul.omedia-controls volume -5
  //
  // for binding media keys without the popup open. A bar exists per monitor
  // and only one copy of this handler receives calls, so each command is
  // handed to the copy on the focused monitor, whose player pick is the one
  // you are looking at. Replies "ok", or "unavailable" when the player can't.
  function focusedInstance() {
    var items = root.bar ? root.bar.moduleWidgets(root.moduleName) : []
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    for (var i = 0; i < items.length; i++) {
      var w = items[i] && items[i].QsWindow ? items[i].QsWindow.window : null
      if (name && w && w.screen && String(w.screen.name) === name) return items[i]
    }
    return root
  }
  function reply(ok) { return ok ? "ok" : "unavailable" }

  // What is playing, as JSON, for scripts and status bars. The strings come
  // from the player and are only ever encoded here, never interpreted.
  function statusJson() {
    var p = root.activePlayer
    if (!p) return JSON.stringify({ player: "", status: "none" })
    return JSON.stringify({
      player: String(p.identity || p.desktopEntry || ""),
      status: p.isPlaying ? "playing" : (p.playbackState === MprisPlaybackState.Paused ? "paused" : "stopped"),
      title: root.title,
      artist: root.artist,
      album: String(p.trackAlbum || ""),
      // A live stream's reported position means nothing (see the time row).
      position: root.isLive ? -1 : Math.round(root.trackPosition * 1000) / 1000,
      length: root.isLive ? -1 : Math.round(root.trackLength * 1000) / 1000,
      live: root.isLive,
      volume: root.hasVolume ? Math.round(p.volume * 100)
        : root.volumeLocked ? Math.round(root.lockedVolume * 100) : -1,
      rate: Logic.effectiveRate(p.rate),
    })
  }

  IpcHandler {
    target: root.moduleName

    function playPause(): string { return root.reply(root.focusedInstance().perform("playPause")) }
    function next(): string { return root.reply(root.focusedInstance().perform("next")) }
    function previous(): string { return root.reply(root.focusedInstance().perform("previous")) }
    function mute(): string { return root.reply(root.focusedInstance().perform("mute")) }
    function shuffle(): string { return root.reply(root.focusedInstance().perform("shuffle")) }
    function repeat(): string { return root.reply(root.focusedInstance().perform("repeat")) }
    function goLive(): string { return root.reply(root.focusedInstance().perform("goLive")) }
    // "+10" and "-10" seek relative to now; "90" seeks to that second.
    function seek(seconds: string): string { return root.reply(root.focusedInstance().seekCommand(seconds)) }
    // "+5" and "-5" in percent; "40" sets it.
    function volume(percent: string): string { return root.reply(root.focusedInstance().adjustVolume(percent)) }
    // "faster", "slower", or a rate such as "1.5".
    function speed(rate: string): string {
      var w = root.focusedInstance()
      var p = w.activePlayer
      if (!w.hasRate) return "unavailable"
      return root.reply(w.setRate(Logic.rateTarget(p.rate, rate, p.minRate, p.maxRate)))
    }
    function open(): void { root.focusedInstance().open() }
    function close(): void { root.focusedInstance().close() }
    function toggle(): void { root.focusedInstance().toggle() }
    function status(): string { return root.focusedInstance().statusJson() }
  }

  // Drives the seek bar and the counter. Same rule as the visualiser: only
  // while the popup is open on a playing track.
  Timer {
    running: root.popupOpen && root.activePlayer !== null && root.activePlayer.isPlaying && !root.seeking
    // Quicker while synced lyrics are following along, so a line lights up
    // when it is sung rather than up to half a second later.
    interval: root.lyricsOpen && root.lyricsSynced ? 150 : 500
    repeat: true
    onTriggered: root.positionTick++
  }

  // Only captures audio while the popup is open on a playing track, so the
  // parec monitor stream isn't held open in the background the rest of the
  // time.
  property bool visualisationRestarting: false

  readonly property real visualiserGain: root.activePlayer && root.activePlayer.volumeSupported && !root.volumeLocked
    ? Logic.visualiserGain(root.activePlayer.volume, Logic.volumeIsCubic(root.activePlayer.dbusName)) : 1
  onVisualiserGainChanged: root.sendVisualiserGain()

  function sendVisualiserGain() {
    if (specProc.running) specProc.write("gain " + root.visualiserGain.toFixed(4) + "\n")
  }

  // The active player's own playback stream, so the visualisers hear that
  // player alone rather than the whole output (a voice call, a game, a
  // notification), and the gain above only scales the audio it belongs to.
  // "-" when no stream matches: the whole output, as before.
  readonly property string visualiserStream: {
    var p = root.activePlayer
    if (!p) return "-"
    var best = null, bestScore = 0
    for (var i = 0; i < root.playbackStreams.length; i++) {
      var n = root.playbackStreams[i]
      var score = Logic.streamScore(n.properties, p.identity || p.desktopEntry, p.trackTitle)
      if (score > bestScore) { best = n; bestScore = score }
    }
    var serial = best && best.properties ? String(best.properties["object.serial"] || "") : ""
    return /^\d{1,10}$/.test(serial) ? serial : "-"
  }
  onVisualiserStreamChanged: root.sendVisualiserStream()

  function sendVisualiserStream() {
    if (specProc.running) specProc.write("stream " + root.visualiserStream + "\n")
  }

  Process {
    id: specProc
    running: root.popupOpen && root.activePlayer && root.activePlayer.isPlaying
      && !root.visualisationRestarting && root.visualisation !== "off"
    command: root.oscilloscope ? ["python3", root.specScript, "--oscilloscope"]
      : root.visualisation === "vu" ? ["python3", root.specScript, "--vu"]
      : ["python3", root.specScript]
    // Winamp draws before its volume control; the capture is after the
    // player's. The analyser is told how far to scale back up whenever it
    // starts, the player changes or its volume moves. See Logic.visualiserGain.
    stdinEnabled: true
    onStarted: {
      root.sendVisualiserStream()
      root.sendVisualiserGain()
    }

    // A running Process keeps its old arguments, so switching visualisation
    // stops it for a moment and starts it again with the new ones.
    onCommandChanged: {
      root.bands = []
      root.peaks = []
      root.scopeColumns = []
      root.vuLevels = [0, 0]
      root.vuPeaks = [0, 0]
      if (!running) return
      root.visualisationRestarting = true
      Qt.callLater(function() { root.visualisationRestarting = false })
    }
    stdout: SplitParser {
      // One frame per line. The analyser: nineteen bar levels, a bar, nineteen
      // peak levels, each 0-1, a peak of -1 having fallen out of sight. The
      // oscilloscope: "o|top:bottom:row" for 75 columns. Parsing is bounded
      // and clamped in Logic.parseSpectrumFrame and Logic.parseScopeFrame.
      onRead: function(line) {
        if (root.visualisation === "vu") {
          var vu = Logic.parseVuFrame(line)
          root.vuLevels = vu.levels
          root.vuPeaks = vu.peaks
          return
        }
        if (root.oscilloscope) {
          root.scopeColumns = Logic.parseScopeFrame(line)
          return
        }
        var frame = Logic.parseSpectrumFrame(line)
        root.bands = frame.bars
        root.peaks = frame.peaks
      }
    }
    onRunningChanged: if (!running) {
      root.bands = []
      root.peaks = []
      root.scopeColumns = []
      root.vuLevels = [0, 0]
      root.vuPeaks = [0, 0]
    }
  }

  // Also called by an open popup: its overlay covers the bar and hands clicks
  // on bar widgets back through triggerPress, so clicking another icon swaps
  // popups in one click. Registering is what makes this widget one of them.
  function triggerPress(button) {
    if (root.bar) root.bar.hideTooltip(root)
    if (button === Qt.LeftButton) {
      root.toggle()
      return
    }
    if (!root.activePlayer) return
    if (button === Qt.MiddleButton) root.runAction("next")
    else if (button === Qt.RightButton) root.runAction("playPause")
  }
  property var registeredBar: null
  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)
    registeredBar = root.bar
    if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(root)
  }
  onBarChanged: syncClickRegistration()
  Component.onCompleted: syncClickRegistration()
  Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)

  // The bar asks the open popup to close this way when another icon's popup
  // takes over, so the two can hand off without a flicker.
  property bool popoutSwitchClosing: false
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  MouseArea {
    id: barMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) { root.triggerPress(mouse.button) }
    onWheel: function(wheel) {
      if (!root.activePlayer) return
      if (wheel.angleDelta.y > 0) root.runAction("previous")
      else if (wheel.angleDelta.y < 0) root.runAction("next")
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.hasMedia ? (root.title + (root.artist ? " — " + root.artist : "")) : "No media playing")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  // Qt key codes to the names Logic.keyAction maps. A modifier other than
  // Shift means the key belongs to something else, such as a global binding.
  function keyName(event) {
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return ""
    switch (event.key) {
    case Qt.Key_Space: return "space"
    case Qt.Key_Left: return "left"
    case Qt.Key_Right: return "right"
    case Qt.Key_Up: return "up"
    case Qt.Key_Down: return "down"
    case Qt.Key_Escape: return "escape"
    case Qt.Key_MediaPlay: case Qt.Key_MediaPause: case Qt.Key_MediaTogglePlayPause: return "media-play"
    case Qt.Key_MediaNext: return "media-next"
    case Qt.Key_MediaPrevious: return "media-previous"
    }
    return String(event.text || "").toLowerCase()
  }

  // KeyboardPanel rather than PopupCard, as Omarchy's own panels use: a popup
  // attached to the bar only receives keys once a click has routed focus
  // through the bar, so it could never have keyboard shortcuts, and could not
  // be opened from a hotkey either.
  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: keyCatcher
    // Wider while the library is open: it takes its own column on the right.
    contentWidth: popup.fittedContentWidth(Style.space(320)
      + (root.sidePanel !== "" ? root.libraryPanelWidth + root.libraryGap * 2 + 1 : 0))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      // Ahead of the buttons inside, so Space is play/pause rather than a
      // press of whichever control last had focus.
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        var action = Logic.keyAction(root.keyName(event))
        if (!action) return
        root.perform(action)
        event.accepted = true
      }

      // Laid out like Omarchy's own panels (network, tailscale): a PanelHero at
      // the top, then sections each introduced by a PanelSectionHeader and closed
      // by a PanelSeparator. Using the shell's components rather than imitating
      // them keeps the popup in step with the theme and with any future changes
      // to how those panels look.
      Column {
        id: column
        anchors.left: parent.left
        anchors.top: parent.top
        width: root.sidePanel !== "" ? parent.width - root.libraryPanelWidth - root.libraryGap * 2 - 1 : parent.width
        spacing: Style.space(10)

        // Where the side columns' header divider sits: level with Now Playing's,
        // measured from the Now Playing header, so an update notice above it
        // doesn't make their headers taller.
        readonly property real sideSeparatorY: heroSeparator.y - nowPlayingHero.y

        // A newer release: styled like the Settings button, with a pulsing
        // dot on its left like LIVE's. Opens the release in the side column.
        Button {
          id: updateNotice
          visible: root.showUpdateNotice
          width: parent.width
          bordered: true
          text: root.updatedVersion !== "" ? "Updated to " + root.updatedVersion
            : "Update available" + (root.latestRelease ? ": " + root.latestRelease.version : "")
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          selected: root.updateOpen
          onClicked: root.toggleSidePanel("update")

          LiveDot {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            size: Style.space(8)
            color: Color.accent
            visible: updateNotice.visible && root.popupOpen
          }
        }

        PanelSeparator {
          visible: updateNotice.visible
          width: parent.width
          foreground: root.bar.foreground
        }

        PanelHero {
          id: nowPlayingHero
          width: parent.width
          title: "Now Playing"
          // PanelHero uppercases and letter-spaces this line itself.
          meta: "OMedia Controls"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: "󰝚"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          // The spectrum lives in the hero's trailing slot — the place tailscale
          // puts its on/off switch — since the header no longer changes with the
          // track and has the room; the hero insets the title by its width.
          //
          // Drawn the way Winamp's classic analyser is: nineteen flat bars with a
          // one-unit gap on sixteen quantised levels, with a peak chip
          // above each bar. No easing: Winamp snaps up and steps down, and all
          // of that motion comes from spectrum.py, not from animation here.
          trailingControl: Component {
            Item {
              id: heroVis
              implicitWidth: root.heroVisWidth
              implicitHeight: root.heroVisHeight
              width: implicitWidth
              height: implicitHeight

              // Winamp's visualiser background, a faint dot matrix, on a
              // whole-pixel grid so it stays even. Painted once, and again
              // only when the size or the theme changes.
              // Off leaves the corner empty, dots and all; a click there
              // still brings the analyser back.
              Canvas {
                id: dotMatrix
                visible: root.visualisation !== "off"
                anchors.fill: parent
                readonly property color dotColor: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.50)
                onDotColorChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                  var ctx = getContext("2d")
                  ctx.clearRect(0, 0, width, height)
                  Logic.drawDotMatrix(ctx, width, height, Style.space(4), Style.space(1), dotColor)
                }
              }

              Row {
                id: heroSpectrum
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.visualisation === "analyser"
                height: heroVis.height
                spacing: Style.space(1)

                // Winamp's analyser is sixteen pixels tall; one level is one of them.
                readonly property real unit: height / 16
                readonly property bool playing: root.activePlayer !== null && root.activePlayer.isPlaying

                Repeater {
                  model: 19

                  Item {
                    required property int index
                    readonly property real level: Math.min(root.visualiserCap, index < root.bands.length ? root.bands[index] : 0)
                    readonly property real peak: index < root.peaks.length ? Math.min(root.visualiserCap, root.peaks[index]) : -1

                    // Four units rather than Winamp's three: at this size the
                    // exact proportion read as too thin. Gap stays at one.
                    width: Style.space(4)
                    height: heroSpectrum.height

                    // A bar is its rows, each in the colour for its height, as
                    // Winamp paints them; the bar reveals them from the bottom.
                    Item {
                      anchors.bottom: parent.bottom
                      width: parent.width
                      height: Math.round(parent.level * 15) * heroSpectrum.unit
                      clip: true
                      opacity: heroSpectrum.playing ? 0.9 : 0.25

                      Column {
                        anchors.bottom: parent.bottom
                        width: parent.width

                        Repeater {
                          model: 16

                          Rectangle {
                            required property int index
                            width: parent.width
                            height: heroSpectrum.unit
                            color: root.visRows[index]
                          }
                        }
                      }
                    }

                    // Winamp draws the peak one level above where it sits.
                    Rectangle {
                      visible: parent.peak >= 0 && heroSpectrum.playing
                      width: parent.width
                      height: Math.max(1, heroSpectrum.unit)
                      radius: 0
                      y: parent.height - (Math.round(parent.peak * 15) + 1) * heroSpectrum.unit
                      color: root.visPeak
                      opacity: 0.9
                    }
                  }
                }
              }

              // Winamp5 Classified's analyser: the same bars, striped a row lit
              // and a row empty. Rows are whole pixels, so every stripe and
              // every gap is the same height; the grid sits on the bottom.
              Row {
                id: heroWinamp5
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                visible: root.visualisation === "winamp5"
                height: heroVis.height
                spacing: Style.space(1)

                readonly property int unit: Math.max(1, Math.floor(height / 16))
                readonly property bool playing: root.activePlayer !== null && root.activePlayer.isPlaying

                Repeater {
                  model: 19

                  Item {
                    id: stripedBar
                    required property int index
                    readonly property int rows: Math.round(Math.min(root.visualiserCap, index < root.bands.length ? root.bands[index] : 0) * 15)
                    readonly property real peak: index < root.peaks.length ? Math.min(root.visualiserCap, root.peaks[index]) : -1

                    width: Style.space(4)
                    height: heroWinamp5.height
                    opacity: heroWinamp5.playing ? 0.9 : 0.25

                    // Sixteen fixed rows, shown as the level reaches them, so
                    // nothing is created and destroyed as the music moves.
                    Repeater {
                      model: 16

                      Rectangle {
                        required property int index
                        visible: index < stripedBar.rows && Logic.winamp5RowLit(index)
                        width: stripedBar.width
                        height: heroWinamp5.unit
                        y: stripedBar.height - (index + 1) * heroWinamp5.unit
                        color: root.winamp5Rows[15 - index]
                      }
                    }

                    Rectangle {
                      visible: stripedBar.peak >= 0 && heroWinamp5.playing
                      width: parent.width
                      height: heroWinamp5.unit
                      y: parent.height - (Math.round(stripedBar.peak * 15) + 1) * heroWinamp5.unit
                      color: root.winamp5Peak
                    }
                  }
                }
              }

              // Winamp's oscilloscope in its default "lines" style: 75 columns
              // across the same space as the analyser, each a run of rows on
              // the same sixteen-row grid, brightest near the middle. Drawn
              // flat, with no easing, like the analyser.
              Item {
                id: heroScope
                anchors.fill: parent
                visible: root.oscilloscope

                readonly property real unit: height / 16
                readonly property bool playing: root.activePlayer !== null && root.activePlayer.isPlaying

                Repeater {
                  model: 75

                  Rectangle {
                    required property int index
                    readonly property var column: index < root.scopeColumns.length ? root.scopeColumns[index] : null

                    visible: column !== null
                    x: Math.round(index * heroScope.width / 75)
                    width: Math.round((index + 1) * heroScope.width / 75) - x
                    y: column ? column.top * heroScope.unit : 0
                    height: column ? (column.bottom - column.top + 1) * heroScope.unit : 0
                    radius: 0
                    readonly property var rowColour: column ? Logic.scopeColor(root.visColour, root.visRows, column.row) : null
                    color: rowColour || Color.accent
                    // Solid dims the accent away from the middle; the others
                    // carry that in their colours.
                    opacity: (column && !rowColour ? Logic.scopeBrightness(column.row) : 1) * (heroScope.playing ? 1 : 0.25)
                  }
                }
              }

              // Mirrored bars, like a voice recorder's: the analyser's levels,
              // lowest band in the middle and fanning out both ways, each bar
              // growing up and down from the centre line. A silent bar is a
              // thin two-unit line, so the shape is there before the sound is. Smoothed a
              // little, since this one is meant to breathe rather than snap.
              Row {
                id: heroMirror
                anchors.centerIn: parent
                visible: root.mirror
                spacing: Style.space(1)

                readonly property bool playing: root.activePlayer !== null && root.activePlayer.isPlaying

                Repeater {
                  model: Logic.MIRROR_BARS

                  Item {
                    required property int index
                    readonly property int band: Logic.mirrorBand(index)
                    readonly property real level: band < root.bands.length ? root.bands[band] : 0

                    // As thick as the analyser's bars, with the same gap.
                    width: Style.space(4)
                    height: heroVis.height

                    Rectangle {
                      anchors.centerIn: parent
                      width: parent.width
                      height: Math.max(Style.space(2), Math.min(root.visualiserCap, parent.level) * parent.height)
                      // Square, like the analyser and Omarchy's own edges.
                      radius: 0
                      color: Logic.spectrumColorAt(root.visRows, Math.min(root.visualiserCap, parent.level))
                      opacity: heroMirror.playing ? 0.9 : 0.25

                      Behavior on height {
                        NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
                      }
                    }
                  }
                }
              }

              // A stereo VU meter: left channel above, right below, each a row
              // of nineteen square segments at the analyser's bar thickness.
              // Lit segments show the level; the held peak is one segment in
              // the colour the analyser uses for its peaks; the rest stay
              // faintly visible, like an unlit LED strip.
              Column {
                id: heroVu
                anchors.centerIn: parent
                visible: root.visualisation === "vu"
                // Two rows filling the height, with a gap between them in the
                // same proportion as at the original 28-unit height.
                spacing: Math.round(heroVis.height * 4 / 28)

                readonly property bool playing: root.activePlayer !== null && root.activePlayer.isPlaying

                Repeater {
                  model: 2

                  Row {
                    id: vuChannel
                    required property int index
                    // No cap here: a level meter should reach its top.
                    readonly property int lit: Logic.vuLit(root.vuLevels[index])
                    readonly property int peakSegment: Logic.vuPeakSegment(root.vuPeaks[index], root.vuLevels[index])
                    spacing: Style.space(1)

                    Repeater {
                      model: Logic.VU_SEGMENTS

                      Rectangle {
                        required property int index
                        readonly property bool isPeak: heroVu.playing && index === vuChannel.peakSegment && index >= vuChannel.lit - 1
                        width: Style.space(4)
                        height: Math.round(heroVis.height * 8 / 28)
                        radius: 0
                        color: isPeak ? root.visPeak : Logic.vuSegmentColor(root.visRows, index)
                        opacity: isPeak ? 0.9
                          : index < vuChannel.lit && heroVu.playing ? 0.9
                          : 0.15
                      }
                    }
                  }
                }
              }

              // Click for the next visualisation, as clicking Winamp's
              // visualiser does: analyser, mirrored bars, VU meter, oscilloscope.
              MouseArea {
                id: visArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleVisualisation()

                PanelToolTip {
                  visible: visArea.containsMouse
                  text: Logic.VISUALISATION_NAMES[root.visualisation] + ". Click for "
                    + Logic.VISUALISATION_NAMES[Logic.nextVisualisation(root.visualisation)].toLowerCase() + "."
                }
              }
            }
          }
        }

        PanelSeparator {
          id: heroSeparator
          width: parent.width
          foreground: root.bar.foreground
        }

        // Every player with something loaded, once there is more than one. The
        // one the popup is controlling carries the selected fill; clicking a row
        // switches to it, and each row's own button plays or pauses that player
        // without switching — the way to stop one left running by accident.
        // The header carries the one option that only matters with several
        // players: whether starting one pauses the rest, like audio focus on a
        // phone. Off by default, since a video over music is sometimes the point.
        Item {
          visible: root.sourcePlayers.length > 1
          width: parent.width
          // Only as tall as the header text, as it was before the switch: the
          // switch is centred on it and allowed past its edges, so the section
          // keeps its old spacing.
          height: playersHeader.implicitHeight

          PanelSectionHeader {
            id: playersHeader
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "PLAYERS"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: pauseOthersRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Pause others"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.togglePauseOthers()
              }
            }

            ToggleSwitch {
              anchors.verticalCenter: parent.verticalCenter
              checked: root.pauseOthers
              foreground: root.bar.foreground
              onToggled: root.togglePauseOthers()
            }
          }
        }

        Column {
          id: sourceList
          visible: root.sourcePlayers.length > 1
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            // ScriptModel diffs the list by identity instead of resetting it, so
            // rows survive metadata changes. As a plain array, every row was
            // destroyed and rebuilt on each change — six times over one Spotify
            // track change — which flickered hover and could swallow a click
            // that landed mid-rebuild.
            model: ScriptModel {
              values: root.sourcePlayers
            }

            BorderSurface {
              id: sourceRow
              required property var modelData

              readonly property var player: modelData
              readonly property bool selected: root.activePlayer && player
                && root.playerKey(root.activePlayer) === root.playerKey(player)
              readonly property string sourceTitle: player ? (player.trackTitle || player.identity || player.desktopEntry || "Media source") : "Media source"
              // Artist and the app it is playing in, since two apps playing the
              // same kind of content can otherwise look identical. (Tabs in one
              // browser never both appear: Chromium publishes a single player
              // for the whole browser, showing whichever tab was active last.)
              readonly property string sourceDetail: {
                if (!player) return ""
                var parts = []
                if (player.trackArtist) parts.push(player.trackArtist)
                var app = player.identity || player.desktopEntry || ""
                if (app && app !== player.trackArtist) parts.push(app)
                return parts.join(" · ")
              }

              width: sourceList.width
              height: sourceInner.implicitHeight + Style.space(10)
              radius: Style.spacing.labelGap
              color: selected ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
              borderSpec: selected ? Border.controlSpec("normal", root.bar.foreground, Color.accent) : Border.none()

              // Declared before the row's contents so the play/pause button sits
              // above it and keeps its own clicks.
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectPlayer(root.playerKey(sourceRow.player))
              }

              Row {
                id: sourceInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: sourceRow.borderLeft + Style.space(4)
                anchors.rightMargin: sourceRow.borderRight + Style.space(14)
                spacing: Style.space(6)

                Button {
                  id: rowPlayPause
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                  foreground: root.bar.foreground
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  tooltipText: sourceRow.player && sourceRow.player.isPlaying ? "Pause" : "Play"
                  enabled: root.canControl(sourceRow.player)
                  opacity: enabled ? 1.0 : 0.4
                  onClicked: root.runAction("playPause", root.playerKey(sourceRow.player))
                }

                Column {
                  width: parent.width - rowPlayPause.width - rowClose.width
                    - parent.spacing * (rowClose.visible ? 2 : 1)
                  spacing: Style.space(1)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    textFormat: Text.PlainText
                    text: sourceRow.sourceTitle
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: sourceRow.selected
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: sourceRow.sourceDetail
                    color: Qt.darker(root.bar.foreground, 1.5)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                    visible: text !== ""
                  }
                }

                // Closes the player itself, for one left open by accident.
                // Only for players that say they can quit, such as mpv; a
                // browser tab belongs to the page and offers no such thing.
                Button {
                  id: rowClose
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !!(sourceRow.player && sourceRow.player.canQuit)
                  width: visible ? implicitWidth : 0
                  bordered: true
                  iconText: "󰅖"
                  iconSize: Style.font.caption
                  foreground: root.bar.foreground
                  horizontalPadding: Style.space(5)
                  verticalPadding: Style.space(1)
                  tooltipText: "Close " + (sourceRow.player ? (sourceRow.player.identity || "player") : "player")
                  onClicked: if (sourceRow.player && sourceRow.player.canQuit) sourceRow.player.quit()
                }
              }
            }
          }
        }

        PanelSeparator {
          visible: root.sourcePlayers.length > 1
          width: parent.width
          foreground: root.bar.foreground
        }

        // With more than one song in the player's playlist: which song this
        // is, with the time through the whole list beneath it, and the list
        // itself on the right.
        Item {
          visible: root.showPlaylistBar
          width: parent.width
          height: Math.max(playlistPlace.implicitHeight, playlistButtons.implicitHeight)

          Column {
            id: playlistPlace
            anchors.left: parent.left
            anchors.right: playlistButtons.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            // The playlist's name in capitals when the player shares one,
            // else PLAYLIST.
            PanelSectionHeader {
              width: parent.width
              text: Logic.playlistHeading(root.playlistName)
              elide: Text.ElideRight
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            // Scrolls when it outgrows the space beside the buttons, as a long
            // playlist's times will.
            Marquee {
              width: parent.width
              text: !root.sharesPlaylist ? "No shared playlist"
                : "Song " + (root.playlistProgress.index > 0 ? root.playlistProgress.index : "–") + "/" + root.playlistProgress.count
                  + " · " + root.formatTime(root.playlistProgress.elapsed) + " / " + root.formatTime(root.playlistProgress.total)
              running: root.popupOpen
              // The times tick every second; keep scrolling through that.
              restartOnTextChange: false
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // Shuffle and repeat for the playlist, then the playlist itself.
          Row {
            id: playlistButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Button {
              bordered: true
              iconText: "󰒝"
              foreground: root.bar.foreground
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              // Left enabled when unsupported, only dimmed, so the tooltip
              // explaining why still shows on hover.
              tooltipText: root.hasShuffle ? "Shuffle" : "Shuffle isn't supported by " + root.playerName
              selected: root.hasShuffle && root.activePlayer.shuffle
              opacity: root.hasShuffle ? 1.0 : 0.4
              onClicked: if (root.hasShuffle) root.toggleShuffle()
            }

            Button {
              bordered: true
              iconText: root.hasLoop && root.activePlayer.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
              foreground: root.bar.foreground
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              tooltipText: !root.hasLoop ? "Repeat isn't supported by " + root.playerName
                : root.activePlayer.loopState === MprisLoopState.Track ? "Repeat track"
                : root.activePlayer.loopState === MprisLoopState.Playlist ? "Repeat playlist"
                : "Repeat off"
              selected: root.hasLoop && root.activePlayer.loopState !== MprisLoopState.None
              opacity: root.hasLoop ? 1.0 : 0.4
              onClicked: if (root.hasLoop) root.cycleLoop()
            }

            Button {
              id: playlistButton
              bordered: true
              iconText: "󰲸"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              selected: root.playlistOpen
              tooltipText: !root.sharesPlaylist ? root.playerName + " doesn't share its playlist"
                : root.playlistOpen ? "Close playlist" : "View playlist"
              opacity: root.sharesPlaylist || root.playlistOpen ? 1.0 : 0.4
              onClicked: if (root.sharesPlaylist || root.playlistOpen) root.toggleSidePanel("playlist")
            }
          }
        }

        PanelSeparator {
          visible: root.showPlaylistBar
          width: parent.width
          foreground: root.bar.foreground
        }

        // The player's window, live, when it shows video: across the popup,
        // in the album art's place. Click to bring the window forward.
        BorderSurface {
          visible: root.showVideo
          width: parent.width
          height: Math.round(width * root.videoAspect)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.bar.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
          clip: true

          ScreencopyView {
            id: videoCapture
            anchors.fill: parent
            anchors.margins: Style.space(2)
            captureSource: root.showVideo ? root.videoWindow.wayland : null
            live: true
          }

          // A lost feed covers the still frame with what happened. The
          // capture keeps running underneath, so the picture comes back by
          // itself once the app draws again.
          Rectangle {
            anchors.fill: videoCapture
            visible: root.videoFeedLost
            color: parent.color

            Column {
              anchors.centerIn: parent
              width: parent.width - Style.space(24)
              spacing: Style.space(4)

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: "No picture from " + (root.activePlayer && root.activePlayer.identity ? root.activePlayer.identity : "the player")
                wrapMode: Text.WordWrap
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: "Its window hasn't changed while playing. Apps stop drawing windows that are out of sight: bring it into view, or click here to switch to it."
                wrapMode: Text.WordWrap
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // The feed check: a tiny snapshot of the capture every two seconds,
          // compared with the last. A Canvas can't load a grab's in-memory
          // URL, so each snapshot goes through the runtime directory (memory,
          // not disk) under an alternating name, cache-busted.
          Canvas {
            id: feedSampler
            visible: false
            width: 64
            height: 36
            property string pending: ""
            property int serial: 0
            onImageLoaded: {
              var ctx = getContext("2d")
              ctx.clearRect(0, 0, 64, 36)
              ctx.drawImage(pending, 0, 0, 64, 36)
              var data = ctx.getImageData(0, 0, 64, 36).data
              var copy = new Array(data.length)
              for (var i = 0; i < data.length; i++) copy[i] = data[i]
              root.addFeedSample(copy)
            }
          }

          Timer {
            running: root.showVideo && root.popupOpen
            interval: 2000
            repeat: true
            onRunningChanged: if (!running) root.resetFeedCheck()
            onTriggered: {
              root.feedHasContent = videoCapture.hasContent
              root.feedChecked = true
              if (!videoCapture.hasContent) return
              videoCapture.grabToImage(function(result) {
                if (feedSampler.pending) feedSampler.unloadImage(feedSampler.pending)
                var file = root.feedSampleDir + "/omedia-feed-" + (feedSampler.serial++) % 2 + ".png"
                if (!result.saveToFile(file)) return
                feedSampler.pending = "file://" + file + "?" + Date.now()
                feedSampler.loadImage(feedSampler.pending)
              }, Qt.size(64, 36))
            }
          }

          MouseArea {
            anchors.fill: parent
            enabled: root.activePlayer && root.activePlayer.canRaise
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (root.raisePlayer()) root.close()
          }
        }

        Row {
          spacing: Style.space(10)
          width: parent.width

          BorderSurface {
            visible: !root.showVideo
            width: Style.space(64)
            height: Style.space(64)
            radius: Style.spacing.labelGap
            color: Style.normalFillFor(root.bar.foreground, Color.accent)
            borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

            Image {
              anchors.fill: parent
              anchors.margins: Style.space(2)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              source: root.artUrl
              visible: source !== ""
            }

            Text {
              anchors.centerIn: parent
              visible: root.artUrl === ""
              text: "󰝚"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.displayLarge
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              enabled: root.activePlayer && root.activePlayer.canRaise
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: {
                if (root.raisePlayer()) root.close()
              }
            }
          }

          Column {
            spacing: Style.space(4)
            // The full width when the video has taken the art's place above.
            width: root.showVideo ? parent.width : parent.width - Style.space(74)

            // Each line scrolls while the popup is open if it is too long to fit.
            Marquee {
              text: root.title || "Nothing playing"
              running: root.popupOpen
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              width: parent.width
            }

            Marquee {
              text: root.artist
              running: root.popupOpen
              color: Qt.darker(root.bar.foreground, 1.3)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              width: parent.width
              visible: text !== ""
            }

            // Album, then album artist, year and track number where tagged.
            Marquee {
              text: root.albumLine
              running: root.popupOpen
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              width: parent.width
              visible: text !== ""
            }

            // Winamp's kbps · kHz · stereo, as small square chips lined up
            // with the text above.
            Row {
              visible: root.formatChips.length > 0
              spacing: Style.space(4)
              topPadding: Style.space(2)

              Repeater {
                model: root.formatChips

                BorderSurface {
                  required property string modelData
                  width: chipText.implicitWidth + Style.space(10)
                  height: chipText.implicitHeight + Style.space(4)
                  radius: 0
                  color: "transparent"
                  // A faint outline, so they read as labels rather than buttons.
                  borderSpec: Border.flat(Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.16),
                    Math.max(1, Style.space(1)))

                  Text {
                    id: chipText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: parent.modelData
                    color: Qt.darker(root.bar.foreground, 1.3)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }
        }

        // Seek bar and the counter beneath it. Always present, so the popup does
        // not change shape when playback starts or stops; with nothing to seek it
        // sits empty and disabled, and the counter reads --:-- on both sides.
        Column {
          id: seekSection
          width: parent.width
          spacing: Style.space(2)

          PanelSlider {
            id: seekSlider
            width: parent.width
            bar: root.bar
            minimum: 0
            maximum: root.hasTimeline ? Math.max(1, root.trackLength) : 1
            step: Math.max(1, root.trackLength / 200)
            enabled: root.canSeek && root.hasTimeline
            // A live stream is not "unavailable", it is at its live edge: drawn
            // full, in the accent, with no knob to suggest it can be dragged —
            // the way YouTube draws its own live bar.
            opacity: enabled || root.isLive ? 1.0 : 0.4
            fillColor: root.isLive ? Color.accent : root.bar.foreground
            knobColor: root.isLive ? "transparent" : root.bar.foreground
            // While dragging, the slider owns the value; otherwise it follows
            // playback. Without this the timer would yank the knob back mid-drag.
            value: root.isLive ? 1
              : !root.hasTimeline ? 0
              : (root.seeking ? root.seekPreview : root.trackPosition)

            onMoved: function(v) {
              root.seeking = true
              root.seekPreview = v
            }
            onReleased: function(v) {
              root.seekTo(v)
              root.seeking = false
            }

            // PanelSlider rings its knob in the bar's background colour, which
            // a transparent knob still leaves as a notch near the end of a
            // full bar. Live, a plain full track is laid over the top instead.
            Rectangle {
              visible: root.isLive
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.right: parent.right
              height: seekSlider.trackHeight
              radius: height / 2
              color: Color.accent
            }
          }

          // Under the bar: elapsed on the left and length on the right, or on a
          // live stream just LIVE, centred beneath the full bar. A live stream
          // has no position worth showing: Apple radio's is a buffer offset, and
          // YouTube TV's restarts at zero every thirty seconds while the video
          // plays on. Where the stream can jump to live, LIVE reads GO LIVE
          // under the pointer and does it.
          Item {
            id: timeRow
            width: parent.width
            height: root.isLive ? leftTime.implicitHeight : timesAndSkips.height

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.verticalCenter: parent.verticalCenter
              visible: root.isLive
              spacing: Style.space(4)

              LiveDot {
                anchors.verticalCenter: parent.verticalCenter
                size: Style.space(6)
                color: Color.accent
                visible: root.isLive && root.popupOpen
              }

              Text {
                textFormat: Text.PlainText
                text: liveArea.containsMouse && root.canGoLive ? "GO LIVE" : "LIVE"
                color: Color.accent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true

                MouseArea {
                  id: liveArea
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  enabled: root.canGoLive
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.jumpToLive()
                }
              }
            }

            // Elapsed on the left, length on the right, and between them skip
            // back and forward by the seek step chosen in Settings.
            Item {
              id: timesAndSkips
              width: parent.width
              // Room beneath the buttons, so they don't sit on the line below.
              height: Math.max(leftTime.implicitHeight, skipButtons.height) + Style.space(1)
              visible: !root.isLive

              Text {
                id: leftTime
                anchors.left: parent.left
                anchors.verticalCenter: skipButtons.verticalCenter
                textFormat: Text.PlainText
                text: root.hasTimeline ? root.formatTime(root.displayPosition) : "--:--"
                color: Qt.darker(root.bar.foreground, 1.2)
                opacity: root.hasTimeline ? 1.0 : 0.5
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              Row {
                id: skipButtons
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                spacing: Style.spacing.md

                Button {
                  bordered: true
                  iconText: Logic.skipIcon(root.seekStep, false)
                  iconSize: Style.font.icon
                  foreground: root.bar.foreground
                  horizontalPadding: Style.space(10)
                  verticalPadding: Style.space(2)
                  tooltipText: "Back " + root.seekStep + " seconds"
                  enabled: root.canSeek
                  opacity: enabled ? 1.0 : 0.4
                  onClicked: root.perform("seekBack")
                }

                Button {
                  bordered: true
                  iconText: Logic.skipIcon(root.seekStep, true)
                  iconSize: Style.font.icon
                  foreground: root.bar.foreground
                  horizontalPadding: Style.space(10)
                  verticalPadding: Style.space(2)
                  tooltipText: "Forward " + root.seekStep + " seconds"
                  enabled: root.canSeek
                  opacity: enabled ? 1.0 : 0.4
                  onClicked: root.perform("seekForward")
                }
              }

              // Click to flip between total length and time remaining, the way
              // Winamp's counter does.
              Text {
                id: rightTime
                anchors.right: parent.right
                anchors.verticalCenter: skipButtons.verticalCenter
                textFormat: Text.PlainText
                text: !root.hasTimeline
                  ? "--:--"
                  : root.showRemaining
                    ? "-" + root.formatTime(Math.max(0, root.trackLength - root.displayPosition))
                    : root.formatTime(root.trackLength)
                color: Qt.darker(root.bar.foreground, 1.2)
                opacity: root.hasTimeline ? 1.0 : 0.5
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  enabled: root.hasTimeline
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.showRemaining = !root.showRemaining
                }
              }
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.bar.foreground
        }

        PanelSectionHeader {
          text: "PLAYBACK CONTROLS"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        // Five equal cells across the full width, bordered like the chips in
        // Omarchy's DNS picker, every icon play-button size so no control reads
        // as more important than another. Shuffle and repeat live in the
        // PLAYLIST bar, beside the list they apply to.
        Row {
          id: transport
          width: parent.width
          spacing: Style.spacing.md

          // Play is the wide one, the same height as the four around it.
          readonly property real playWidth: (width - spacing * 4) * 0.28
          readonly property real cellWidth: (width - spacing * 4 - playWidth) / 4

          // Lyrics for the playing track, in the side column.
          Button {
            anchors.verticalCenter: parent.verticalCenter
            width: transport.cellWidth
            bordered: true
            iconText: "󰍰"
            iconSize: Style.font.iconLarge
            foreground: root.bar.foreground
            // Left enabled when there are none, only dimmed, so the tooltip
            // saying why still shows on hover.
            tooltipText: root.lyricsOpen ? "Close lyrics"
              : root.lyricsAvailable ? "Lyrics"
              : root.lyricsStatus === "Looking for lyrics…" ? "Looking for lyrics…"
              : root.lyricsStatus || "No lyrics"
            selected: root.lyricsOpen
            opacity: root.lyricsAvailable || root.lyricsOpen ? 1.0 : 0.4
            onClicked: if (root.lyricsAvailable || root.lyricsOpen) root.toggleSidePanel("lyrics")
          }

          Button {
            id: transportPrevious
            anchors.verticalCenter: parent.verticalCenter
            width: transport.cellWidth
            bordered: true
            iconText: "󰒮"
            iconSize: Style.font.iconLarge
            foreground: root.bar.foreground
            tooltipText: "Previous"
            enabled: root.activePlayer && root.activePlayer.canGoPrevious
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.runAction("previous", root.playerKey(root.activePlayer))
          }

          Button {
            anchors.verticalCenter: parent.verticalCenter
            width: transport.playWidth
            // Wider than the rest, but the same height as the row.
            height: transportPrevious.height
            bordered: true
            iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
            iconSize: Style.font.display
            foreground: root.bar.foreground
            tooltipText: root.activePlayer && root.activePlayer.isPlaying ? "Pause" : "Play"
            enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.runAction("playPause", root.playerKey(root.activePlayer))
          }

          Button {
            anchors.verticalCenter: parent.verticalCenter
            width: transport.cellWidth
            bordered: true
            iconText: "󰒭"
            iconSize: Style.font.iconLarge
            foreground: root.bar.foreground
            tooltipText: "Next"
            enabled: root.activePlayer && root.activePlayer.canGoNext
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.runAction("next", root.playerKey(root.activePlayer))
          }

          // Winamp's eject: opens the music library in a column beside the player.
          Button {
            anchors.verticalCenter: parent.verticalCenter
            width: transport.cellWidth
            bordered: true
            iconText: "󰇪"
            iconSize: Style.font.iconLarge
            foreground: root.bar.foreground
            tooltipText: root.libraryOpen ? "Close library" : "Open library"
            selected: root.libraryOpen
            onClicked: root.toggleSidePanel("library")
          }
        }


        PanelSeparator {
          width: parent.width
          foreground: root.bar.foreground
        }

        PanelSectionHeader {
          text: "SPEED"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        // Browsers and Spotify offer speed in their own UI but not to other
        // programs, so a row that never lights up would read as broken. Said
        // plainly above it, naming the player, whenever that is the case.
        Text {
          width: parent.width
          visible: root.activePlayer !== null && !root.hasRate
          textFormat: Text.PlainText
          text: Logic.fixedRateMessage(root.activePlayer ? (root.activePlayer.identity || root.activePlayer.desktopEntry) : "")
          wrapMode: Text.Wrap
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        // The common steps as chips, five across like the transport row. Disabled
        // on players with a fixed rate, and a step outside the player's range
        // stays disabled on its own.
        Row {
          id: speedRow
          width: parent.width
          spacing: Style.spacing.md

          readonly property real cellWidth: (width - spacing * (Logic.SPEED_STEPS.length - 1)) / Logic.SPEED_STEPS.length

          Repeater {
            model: Logic.SPEED_STEPS

            Button {
              required property var modelData
              width: speedRow.cellWidth
              bordered: true
              text: Logic.formatRate(modelData)
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              enabled: root.hasRate && Logic.rateInRange(modelData, root.activePlayer.minRate, root.activePlayer.maxRate)
              // Lit even on a player that won't take a rate, when it reports
              // one: a speed chosen in the page still shows here.
              selected: root.activePlayer !== null && Logic.sameRate(root.activePlayer.rate, modelData)
              opacity: enabled ? 1.0 : 0.4
              onClicked: root.setRate(modelData)
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.bar.foreground
        }

        PanelSectionHeader {
          text: "VOLUME"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        // Volume: a quiet speaker on the left and a loud one on the right, both
        // display-only markers of the same width, so the slider sits centred
        // and neither end looks clickable. Muting is its own clearly labelled
        // button underneath — a speaker glyph that silently muted on click was a
        // control nobody could find.
        // Always shown, disabled when the player has no volume to set, for the
        // same reason as the seek bar.
        // Same treatment as speed: a player that won't take a volume says so.
        Text {
          width: parent.width
          visible: root.volumeLocked
          textFormat: Text.PlainText
          text: Logic.fixedVolumeMessage(root.activePlayer ? (root.activePlayer.identity || root.activePlayer.desktopEntry) : "")
          wrapMode: Text.Wrap
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          id: volumeRow
          width: parent.width
          spacing: Style.space(8)

          readonly property real markerWidth: Style.font.icon + Style.spacing.controlPaddingX * 2

          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: volumeRow.markerWidth
            height: volumeSlider.height
            opacity: root.hasVolume ? 1.0 : 0.4

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "󰕿"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.icon
            }
          }

          PanelSlider {
            id: volumeSlider
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - volumeRow.markerWidth * 2 - parent.spacing * 2
            bar: root.bar
            minimum: 0
            maximum: 1
            step: 0.02
            enabled: root.hasVolume
            opacity: enabled ? 1.0 : 0.4
            value: root.hasVolume ? root.activePlayer.volume : root.lockedVolume
            onMoved: function(v) { root.setVolume(v) }
            onReleased: function(v) { root.setVolume(v) }
          }

          Item {
            anchors.verticalCenter: parent.verticalCenter
            width: volumeRow.markerWidth
            height: volumeSlider.height
            opacity: root.hasVolume ? 1.0 : 0.4

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "󰕾"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.icon
            }
          }
        }

        // Styled like the transport cells — bordered, full width — with a label
        // so what it does is never a guess. Shows the selected fill while muted,
        // the same way shuffle and repeat show they are on.
        Button {
          width: parent.width
          bordered: true
          readonly property bool muted: root.hasVolume && root.activePlayer.volume <= 0.001
          iconText: muted ? "󰝟" : "󰖁"
          text: muted ? "Unmute" : "Mute"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          enabled: root.hasVolume
          selected: muted
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.toggleMute()
        }

        PanelSeparator {
          width: parent.width
          foreground: root.bar.foreground
        }

        // Settings, in the side column. Styled like Mute: bordered, full width,
        // icon and label.
        Button {
          width: parent.width
          bordered: true
          iconText: "󰒓"
          text: "Settings"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          selected: root.settingsOpen
          onClicked: root.toggleSidePanel("settings")
        }
      }

      // The divider between the player and the side column.
      Rectangle {
        visible: root.sidePanel !== ""
        x: column.width + root.libraryGap
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
      }

      // The library, opened by eject, in its own column on the right so it
      // gets the popup's full height. Folders first, then audio. A click
      // selects a track, shift-click selects a run, double-click plays one;
      // a folder opens on click and plays whole from its play button.
      Item {
        id: library
        visible: root.libraryOpen
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.libraryPanelWidth

        readonly property real rowHeight: Style.space(30)
        // The tracks shown, in order, for range selection: the search's
        // results, or the current folder's tracks.
        readonly property var trackPaths: {
          if (root.librarySearching) return root.librarySearchResult.results.map(function(r) { return r.path })
          var list = []
          for (var i = 0; i < libraryModel.count; i++) {
            if (!libraryModel.get(i, "fileIsDir")) list.push(libraryModel.get(i, "filePath"))
          }
          return list
        }

        FolderListModel {
          id: libraryModel
          folder: root.libraryOpen && root.libraryFolder ? Logic.pathToFileUri(root.libraryFolder) : ""
          nameFilters: Logic.LIBRARY_NAME_FILTERS
          caseSensitive: false
          showDirsFirst: true
          showDotAndDotDot: false
          showHidden: false
          showOnlyReadable: true
          sortCaseSensitive: false
        }

        Item {
          id: libraryHeaderRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          // As tall as the Now Playing header, so the lines beneath them meet.
          height: Math.max(0, column.sideSeparatorY - column.spacing)

          // LIBRARY, with the folder beneath it.
          Column {
            id: libraryTitle
            anchors.left: parent.left
            anchors.right: playAll.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            PanelSectionHeader {
              text: "LIBRARY"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              // Full foreground, like "Now Playing": this heads its own column.
              color: root.bar.foreground
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: !root.librarySearching ? Logic.libraryCrumb(root.libraryRoot, root.libraryFolder)
                : Logic.searchCountText(root.librarySearchResult)
              elide: Text.ElideLeft
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Button {
            id: playAll
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            bordered: true
            iconText: "󰐊"
            text: "Play all"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.librarySearching ? library.trackPaths.length > 0
              : library.trackPaths.length > 0 || root.libraryFolder !== root.libraryRoot
            opacity: enabled ? 1.0 : 0.4
            tooltipText: root.librarySearching ? "Play every result shown" : "Play everything in this folder"
            onClicked: root.librarySearching ? root.playFromLibrary(library.trackPaths) : root.playFromLibrary(root.libraryFolder)
          }
        }

        SearchBox {
          id: librarySearchBox
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: librarySeparator.bottom
          anchors.topMargin: column.spacing
          foreground: root.bar.foreground
          // Typing, the clear button and Escape all land here.
          onTextChanged: {
            root.librarySearch = text
            if (text !== "") root.indexLibrary()
          }
          onLeave: keyCatcher.forceActiveFocus()
          onVisibleChanged: if (!visible) keyCatcher.forceActiveFocus()
        }

        PanelSeparator {
          id: librarySearchSeparator
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: librarySearchBox.bottom
          anchors.topMargin: column.spacing
          foreground: root.bar.foreground
        }

        // While searching: the matches from the whole music folder.
        ListView {
          id: libraryResults
          visible: root.librarySearching
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: librarySearchSeparator.bottom
          anchors.topMargin: column.spacing
          anchors.bottom: libraryList.bottom
          clip: true
          spacing: Style.space(2)
          model: root.librarySearchResult.results
          boundsBehavior: Flickable.StopAtBounds

          delegate: SearchResultRow {
            required property var modelData
            width: libraryResults.width
            result: modelData
            picked: root.librarySelection.indexOf(modelData.path) !== -1
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onChosen: function(mouse) { root.selectTrack(modelData.path, (mouse.modifiers & Qt.ShiftModifier) !== 0, library.trackPaths) }
            onPlayed: root.playFromLibrary(modelData.path)
          }
        }

        Text {
          anchors.top: librarySearchSeparator.bottom
          anchors.topMargin: column.spacing
          anchors.left: parent.left
          anchors.right: parent.right
          visible: root.librarySearching && root.librarySearchResult.results.length === 0
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: libraryIndexer.running || root.libraryIndexRoot !== root.libraryRoot ? "Searching…"
            : "Nothing in your music folder matches “" + root.librarySearch.trim() + "”."
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        ListView {
          id: libraryList
          visible: !root.librarySearching
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: librarySearchSeparator.bottom
          anchors.topMargin: column.spacing
          anchors.bottom: elsewhereNote.visible ? elsewhereNote.top
            : selectionBar.visible ? selectionBar.top : parent.bottom
          anchors.bottomMargin: selectionBar.visible ? Style.space(8) : 0
          clip: true
          model: libraryModel
          boundsBehavior: Flickable.StopAtBounds

          header: BorderSurface {
            visible: root.libraryFolder !== root.libraryRoot
            width: libraryList.width
            height: visible ? library.rowHeight : 0
            radius: Style.spacing.labelGap
            color: upArea.containsMouse ? Style.normalFillFor(root.bar.foreground, Color.accent) : "transparent"
            borderSpec: Border.none()

            MouseArea {
              id: upArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openLibraryFolder(Logic.parentFolder(root.libraryRoot, root.libraryFolder))
            }

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              Text {
                textFormat: Text.PlainText
                text: "󰁍"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.icon
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Back"
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          delegate: BorderSurface {
            id: entry
            required property string fileName
            required property string filePath
            required property bool fileIsDir
            readonly property bool picked: !fileIsDir && root.librarySelection.indexOf(filePath) !== -1

            width: libraryList.width
            height: library.rowHeight
            radius: Style.spacing.labelGap
            color: entry.picked ? Style.selectedFillFor(root.bar.foreground, Color.accent)
              : entryArea.containsMouse ? Style.normalFillFor(root.bar.foreground, Color.accent)
              : "transparent"
            borderSpec: entry.picked ? Border.controlSpec("normal", root.bar.foreground, Color.accent) : Border.none()

            MouseArea {
              id: entryArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                if (entry.fileIsDir) root.openLibraryFolder(entry.filePath)
                else root.selectTrack(entry.filePath, (mouse.modifiers & Qt.ShiftModifier) !== 0, library.trackPaths)
              }
              onDoubleClicked: if (!entry.fileIsDir) root.playFromLibrary(entry.filePath)
            }

            Row {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              Text {
                id: entryIcon
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: entry.fileIsDir ? "󰉋" : "󰝚"
                color: root.bar.foreground
                opacity: entry.fileIsDir || entry.picked ? 1.0 : 0.7
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.icon
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - entryIcon.width - folderPlay.width - parent.spacing * 2
                textFormat: Text.PlainText
                text: entry.fileName
                elide: Text.ElideRight
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: entry.picked
              }

              // Plays the whole folder; mpv takes a folder as a playlist.
              Button {
                id: folderPlay
                anchors.verticalCenter: parent.verticalCenter
                visible: entry.fileIsDir
                width: visible ? implicitWidth : 0
                // Bordered like every other button, so it reads as a button and
                // not as a "this folder has more inside" arrow.
                bordered: true
                iconText: "󰐊"
                iconSize: Style.font.caption
                foreground: root.bar.foreground
                horizontalPadding: Style.space(5)
                verticalPadding: Style.space(1)
                tooltipText: "Play folder"
                onClicked: root.playFromLibrary(entry.filePath)
              }
            }
          }
        }

        PanelSeparator {
          id: librarySeparator
          anchors.left: parent.left
          anchors.right: parent.right
          y: column.sideSeparatorY
          foreground: root.bar.foreground
        }

        Text {
          anchors.top: librarySearchSeparator.bottom
          // Below the Back row, when there is one.
          anchors.topMargin: column.spacing + (root.libraryFolder !== root.libraryRoot ? library.rowHeight + Style.space(4) : 0)
          visible: !root.librarySearching && libraryModel.status === FolderListModel.Ready && libraryList.count === 0
          textFormat: Text.PlainText
          text: "Nothing to play in this folder."
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        // Selections carry across folders; say so when some of it isn't in
        // the folder shown, so the count below never includes tracks you
        // can't see.
        Text {
          id: elsewhereNote
          readonly property int count: Logic.selectedElsewhere(root.librarySelection, library.trackPaths)
          visible: root.libraryOpen && count > 0
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: selectionBar.top
          anchors.bottomMargin: Style.space(8)
          textFormat: Text.PlainText
          text: count + (count === 1 ? " selected track is" : " selected tracks are") + " in other folders"
          elide: Text.ElideRight
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        // Shown once anything is selected: play the selection in the order it
        // was picked, or clear it.
        Row {
          id: selectionBar
          visible: root.librarySelection.length > 0
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.spacing.md

          Button {
            id: playSelected
            width: (parent.width - parent.spacing) * 0.68
            bordered: true
            iconText: "󰐊"
            text: "Play " + root.librarySelection.length + " selected"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.playFromLibrary(root.librarySelection)
          }

          // An icon like Play's, so the two buttons are the same height.
          Button {
            width: (parent.width - parent.spacing) * 0.32
            height: playSelected.height
            bordered: true
            iconText: "󰅖"
            text: "Clear"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: {
              root.librarySelection = []
              root.librarySelectAnchor = ""
            }
          }
        }
      }

      // Lyrics for the playing track, in the side column. Synced lyrics follow
      // the song, the line being sung lit and kept in view; scroll to read
      // ahead and it waits a few seconds before following again. Click a
      // synced line to jump there.
      Item {
        id: lyricsPanel
        visible: root.lyricsOpen
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.libraryPanelWidth

        property real userScrolledAt: 0

        Column {
          id: lyricsTitle
          anchors.left: parent.left
          anchors.right: parent.right
          // Centred in a band as tall as the Now Playing header.
          y: Math.max(0, (column.sideSeparatorY - column.spacing - implicitHeight) / 2)
          spacing: Style.space(2)

          PanelSectionHeader {
            text: "LYRICS"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            // Full foreground, like "Now Playing": this heads its own column.
            color: root.bar.foreground
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.lyricsSource !== "" ? root.lyricsSource + (root.lyricsSynced ? " · synced" : "") : root.lyricsStatus
            elide: Text.ElideRight
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator {
          id: lyricsSeparator
          anchors.left: parent.left
          anchors.right: parent.right
          y: column.sideSeparatorY
          foreground: root.bar.foreground
        }

        ListView {
          id: lyricsList
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: lyricsSeparator.bottom
          anchors.topMargin: column.spacing
          anchors.bottom: parent.bottom
          clip: true
          model: root.lyricsLines
          spacing: Style.space(6)
          boundsBehavior: Flickable.StopAtBounds
          highlightRangeMode: ListView.NoHighlightRange
          onMovementStarted: lyricsPanel.userScrolledAt = Date.now()

          delegate: Text {
            required property var modelData
            required property int index
            readonly property bool current: index === root.lyricsActive
            width: lyricsList.width
            textFormat: Text.PlainText
            text: modelData.text === "" ? "♪" : modelData.text
            wrapMode: Text.Wrap
            color: root.lyricsSynced && !current ? Qt.darker(root.bar.foreground, 1.6) : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: current

            MouseArea {
              anchors.fill: parent
              enabled: root.lyricsSynced && root.canSeek && root.hasTimeline
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.seekTo(parent.modelData.time)
            }
          }

          // Keep the sung line about a third of the way down, unless the
          // list was scrolled by hand in the last few seconds.
          Connections {
            target: root
            function onLyricsActiveChanged() {
              if (!root.lyricsOpen || root.lyricsActive < 0) return
              if (Date.now() - lyricsPanel.userScrolledAt < 4000) return
              lyricsFollow.stop()
              var item = lyricsList.itemAtIndex(root.lyricsActive)
              if (!item) {
                lyricsList.positionViewAtIndex(root.lyricsActive, ListView.Center)
                return
              }
              var target = item.y - lyricsList.height / 3
              target = Math.max(lyricsList.originY, Math.min(target, lyricsList.contentHeight + lyricsList.originY - lyricsList.height))
              lyricsFollow.to = target
              lyricsFollow.start()
            }
          }

          NumberAnimation {
            id: lyricsFollow
            target: lyricsList
            property: "contentY"
            duration: 250
            easing.type: Easing.OutCubic
          }
        }

        Text {
          anchors.centerIn: lyricsList
          visible: root.lyricsLines.length === 0 && root.lyricsStatus !== ""
          textFormat: Text.PlainText
          text: root.lyricsStatus
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // The player's playlist, in the side column: the current song lit, each
      // row with its number, title, artist and length. Double-click to play.
      Item {
        id: playlistPanel
        visible: root.playlistOpen
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.libraryPanelWidth

        readonly property real rowHeight: Style.space(38)

        Column {
          id: playlistTitle
          anchors.left: parent.left
          anchors.right: openSaved.left
          anchors.rightMargin: Style.space(8)
          y: Math.max(0, (column.sideSeparatorY - column.spacing - implicitHeight) / 2)
          spacing: Style.space(2)

          PanelSectionHeader {
            width: parent.width
            text: Logic.playlistHeading(root.playlistName)
            elide: Text.ElideRight
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            color: root.bar.foreground
          }

          // Scrolls when it runs into the buttons beside it.
          Marquee {
            width: parent.width
            text: !root.hasTrackList ? "This player doesn't share its playlist"
              : root.playlistProgress.count + (root.playlistProgress.count === 1 ? " song · " : " songs · ")
                + root.formatTime(root.playlistProgress.total) + (root.playlistEdited ? " · edited" : "")
            running: root.popupOpen && root.playlistOpen
            restartOnTextChange: false
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // Saved playlists, opened in this column, and a new one.
        Button {
          id: openSaved
          anchors.right: newSaved.left
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: playlistTitle.verticalCenter
          bordered: true
          iconText: "󰝰"
          text: "Open"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          tooltipText: "Saved playlists"
          onClicked: root.showPlaylists()
        }

        Button {
          id: newSaved
          anchors.right: parent.right
          anchors.verticalCenter: playlistTitle.verticalCenter
          height: openSaved.height
          bordered: true
          iconText: "󰲸"
          text: "New"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          tooltipText: "A new, empty saved playlist"
          onClicked: root.startNewPlaylist([], "playlist")
        }

        PanelSeparator {
          id: playlistSeparator
          anchors.left: parent.left
          anchors.right: parent.right
          y: column.sideSeparatorY
          foreground: root.bar.foreground
        }

        ListView {
          id: playlistList
          anchors.left: parent.left
          anchors.right: parent.right
          visible: !root.queueAdding
          anchors.top: playlistSeparator.bottom
          anchors.topMargin: column.spacing
          anchors.bottom: queueBarSeparator.top
          anchors.bottomMargin: column.spacing
          clip: true
          model: root.playlistIds
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds

          delegate: BorderSurface {
            id: track
            required property string modelData
            required property int index
            readonly property var info: root.playlistMeta[modelData] || ({})
            readonly property bool current: modelData === root.currentTrackId

            width: playlistList.width
            height: playlistPanel.rowHeight
            radius: Style.spacing.labelGap
            color: track.current ? Style.selectedFillFor(root.bar.foreground, Color.accent)
              : trackArea.containsMouse ? Style.normalFillFor(root.bar.foreground, Color.accent)
              : "transparent"
            borderSpec: track.current ? Border.controlSpec("normal", root.bar.foreground, Color.accent) : Border.none()

            MouseArea {
              id: trackArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onDoubleClicked: root.goToTrack(track.modelData)
            }

            Row {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(4)
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(14)

              Text {
                id: trackNumber
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(22)
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                // 01, 02, … padded to the list's longest number, at least two digits.
                text: Logic.trackNumber(track.index + 1, root.playlistIds.length)
                color: Qt.darker(root.bar.foreground, track.current ? 1.0 : 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - trackNumber.width - trackLength.width - trackTools.width
                  - parent.spacing * (trackTools.visible ? 3 : 2)
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: track.info.title || "Loading…"
                  elide: Text.ElideRight
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: track.current
                }

                Text {
                  width: parent.width
                  visible: text !== ""
                  textFormat: Text.PlainText
                  text: track.info.artist || ""
                  elide: Text.ElideRight
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                id: trackLength
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: track.info.length > 0 ? root.formatTime(track.info.length) : ""
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              // Move and remove, like a saved playlist's, for players that
              // allow them.
              Row {
                id: trackTools
                anchors.verticalCenter: parent.verticalCenter
                visible: root.canMoveTracks || root.canEditTracks
                width: visible ? implicitWidth : 0
                spacing: Style.space(4)

                Button {
                  visible: root.canMoveTracks
                  bordered: true
                  iconText: "󰁝"
                  iconSize: Style.font.caption
                  foreground: root.bar.foreground
                  horizontalPadding: Style.space(5)
                  verticalPadding: Style.space(1)
                  opacity: track.index > 0 ? 1.0 : 0.4
                  tooltipText: "Move up"
                  onClicked: if (track.index > 0) root.moveQueueTrack(track.index, -1)
                }

                Button {
                  visible: root.canMoveTracks
                  bordered: true
                  iconText: "󰁅"
                  iconSize: Style.font.caption
                  foreground: root.bar.foreground
                  horizontalPadding: Style.space(5)
                  verticalPadding: Style.space(1)
                  opacity: track.index < root.playlistIds.length - 1 ? 1.0 : 0.4
                  tooltipText: "Move down"
                  onClicked: if (track.index < root.playlistIds.length - 1) root.moveQueueTrack(track.index, 1)
                }

                Button {
                  visible: root.canEditTracks
                  bordered: true
                  iconText: "󰅖"
                  iconSize: Style.font.caption
                  foreground: root.bar.foreground
                  horizontalPadding: Style.space(5)
                  verticalPadding: Style.space(1)
                  tooltipText: "Remove from playlist"
                  onClicked: root.removeQueueTrack(track.modelData)
                }
              }
            }
          }
        }

        // Tracks to add, from the music folder: click selects, shift-click
        // selects a run, a folder opens.
        FolderListModel {
          id: queueAddModel
          folder: root.queueAdding && root.queueAddFolder ? Logic.pathToFileUri(root.queueAddFolder) : ""
          nameFilters: Logic.LIBRARY_NAME_FILTERS
          caseSensitive: false
          showDirsFirst: true
          showDotAndDotDot: false
          showHidden: false
          showOnlyReadable: true
          sortCaseSensitive: false
        }

        SearchBox {
          id: queueAddSearchBox
          visible: root.queueAdding
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: playlistSeparator.bottom
          anchors.topMargin: column.spacing
          foreground: root.bar.foreground
          onTextChanged: {
            root.queueAddSearch = text
            if (text !== "") root.indexLibrary()
          }
          onLeave: keyCatcher.forceActiveFocus()
          onVisibleChanged: if (!visible) keyCatcher.forceActiveFocus()
        }

        PanelSeparator {
          id: queueAddSearchSeparator
          visible: root.queueAdding
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: queueAddSearchBox.bottom
          anchors.topMargin: column.spacing
          foreground: root.bar.foreground
        }

        ListView {
          id: queueAddResults
          visible: root.queueAdding && root.queueAddSearching
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: queueAddSearchSeparator.bottom
          anchors.topMargin: column.spacing
          anchors.bottom: queueBarSeparator.top
          anchors.bottomMargin: column.spacing
          clip: true
          spacing: Style.space(2)
          model: root.queueAddSearchResult.results
          boundsBehavior: Flickable.StopAtBounds

          delegate: SearchResultRow {
            required property var modelData
            width: queueAddResults.width
            result: modelData
            picked: root.queueAddSelection.indexOf(modelData.path) !== -1
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onChosen: function(mouse) {
              var shift = (mouse.modifiers & Qt.ShiftModifier) !== 0
              root.queueAddSelection = shift && root.queueAddAnchor
                ? Logic.selectRange(root.queueAddSelection, queueAddList.trackPaths, root.queueAddAnchor, modelData.path)
                : Logic.toggleSelection(root.queueAddSelection, modelData.path)
              root.queueAddAnchor = Logic.cleanPath(modelData.path)
            }
            onPlayed: {
              root.queueAddSelection = [modelData.path]
              root.finishQueueAdd(true)
            }
          }
        }

        Text {
          anchors.top: queueAddSearchSeparator.bottom
          anchors.topMargin: column.spacing
          anchors.left: parent.left
          anchors.right: parent.right
          visible: root.queueAdding && root.queueAddSearching && root.queueAddSearchResult.results.length === 0
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: libraryIndexer.running || root.libraryIndexRoot !== root.libraryRoot ? "Searching…"
            : "Nothing in your music folder matches “" + root.queueAddSearch.trim() + "”."
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        ListView {
          id: queueAddList
          visible: root.queueAdding && !root.queueAddSearching
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: queueAddSearchSeparator.bottom
          anchors.topMargin: column.spacing
          anchors.bottom: queueBarSeparator.top
          anchors.bottomMargin: column.spacing
          clip: true
          model: queueAddModel
          boundsBehavior: Flickable.StopAtBounds

          readonly property var trackPaths: {
            if (root.queueAddSearching) return root.queueAddSearchResult.results.map(function(r) { return r.path })
            var list = []
            for (var i = 0; i < queueAddModel.count; i++) {
              if (!queueAddModel.get(i, "fileIsDir")) list.push(queueAddModel.get(i, "filePath"))
            }
            return list
          }

          header: BorderSurface {
            visible: root.queueAddFolder !== root.libraryRoot
            width: queueAddList.width
            height: visible ? Style.space(30) : 0
            radius: Style.spacing.labelGap
            color: queueUpArea.containsMouse ? Style.normalFillFor(root.bar.foreground, Color.accent) : "transparent"
            borderSpec: Border.none()

            MouseArea {
              id: queueUpArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.queueAddFolder = Logic.parentFolder(root.libraryRoot, root.queueAddFolder)
            }

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              Text {
                textFormat: Text.PlainText
                text: "󰁍"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.icon
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Back"
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          delegate: BorderSurface {
            id: addEntry
            required property string fileName
            required property string filePath
            required property bool fileIsDir
            readonly property bool picked: !fileIsDir && root.queueAddSelection.indexOf(filePath) !== -1

            width: queueAddList.width
            height: Style.space(30)
            radius: Style.spacing.labelGap
            color: addEntry.picked ? Style.selectedFillFor(root.bar.foreground, Color.accent)
              : addEntryArea.containsMouse ? Style.normalFillFor(root.bar.foreground, Color.accent)
              : "transparent"
            borderSpec: addEntry.picked ? Border.controlSpec("normal", root.bar.foreground, Color.accent) : Border.none()

            MouseArea {
              id: addEntryArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                if (addEntry.fileIsDir) { root.queueAddFolder = Logic.libraryFolder(root.libraryRoot, addEntry.filePath); return }
                var shift = (mouse.modifiers & Qt.ShiftModifier) !== 0
                root.queueAddSelection = shift && root.queueAddAnchor
                  ? Logic.selectRange(root.queueAddSelection, queueAddList.trackPaths, root.queueAddAnchor, addEntry.filePath)
                  : Logic.toggleSelection(root.queueAddSelection, addEntry.filePath)
                root.queueAddAnchor = Logic.cleanPath(addEntry.filePath)
              }
            }

            Row {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              Text {
                id: addEntryIcon
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: addEntry.fileIsDir ? "󰉋" : "󰝚"
                color: root.bar.foreground
                opacity: addEntry.fileIsDir || addEntry.picked ? 1.0 : 0.7
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.icon
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - addEntryIcon.width - parent.spacing
                textFormat: Text.PlainText
                text: addEntry.fileName
                elide: Text.ElideRight
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: addEntry.picked
              }
            }
          }
        }

        PanelSeparator {
          id: queueBarSeparator
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: queueBar.top
          anchors.bottomMargin: column.spacing
          foreground: root.bar.foreground
        }

        // Add tracks, or save the list as a playlist;
        // while adding, add the selection or go back.
        Row {
          id: queueBar
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.spacing.md

          // Three buttons when the queue came from a saved playlist: Save writes
          // back to it, Save as makes a new one.
          readonly property int buttons: root.linkActive ? 3 : 2
          readonly property real third: (width - spacing * (buttons - 1)) / buttons

          Button {
            id: queueAddButton
            visible: !root.queueAdding
            width: queueBar.third
            bordered: true
            iconText: "󰐒"
            text: "Add"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            // Left enabled when the player can't take tracks, only dimmed,
            // so the tooltip saying why still shows.
            opacity: root.canEditTracks ? 1.0 : 0.4
            tooltipText: root.canEditTracks ? "Add tracks from your music folder"
              : !root.hasTrackList ? root.playerName + " doesn't share its playlist"
              : root.playerName + " doesn't allow adding tracks"
            onClicked: if (root.canEditTracks) root.startQueueAdd()
          }

          Button {
            visible: !root.queueAdding
            width: queueBar.third
            height: queueAddButton.height
            bordered: true
            iconText: "󰆓"
            text: "Save"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            readonly property bool can: root.linkActive ? root.playlistEdited && root.queuePaths.length > 0 : root.queuePaths.length > 0
            opacity: can ? 1.0 : 0.4
            tooltipText: root.linkActive
              ? (root.playlistEdited ? "Save changes to " + root.playlistName : "No changes to save")
              : root.queuePaths.length > 0 ? "Save as a playlist" : "No local files in this playlist to save"
            onClicked: {
              if (!can) return
              if (root.linkActive) root.saveBackLinked()
              else root.startNewPlaylist(root.queuePaths, "playlist")
            }
          }

          Button {
            visible: !root.queueAdding && root.linkActive
            width: queueBar.third
            height: queueAddButton.height
            bordered: true
            iconText: "󰆔"
            text: "Save as"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            opacity: root.queuePaths.length > 0 ? 1.0 : 0.4
            tooltipText: "Save as a new playlist"
            onClicked: if (root.queuePaths.length > 0) root.startNewPlaylist(root.queuePaths, "playlist")
          }

          Button {
            id: queueAddConfirm
            visible: root.queueAdding
            width: (queueBar.width - queueBar.spacing) * 0.68
            bordered: true
            iconText: "󰐒"
            text: root.queueAddSelection.length > 0 ? "Add " + root.queueAddSelection.length + " selected" : "Select tracks to add"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            opacity: root.queueAddSelection.length > 0 ? 1.0 : 0.4
            onClicked: if (root.queueAddSelection.length > 0) root.finishQueueAdd(true)
          }

          Button {
            visible: root.queueAdding
            width: (queueBar.width - queueBar.spacing) * 0.32
            height: queueAddConfirm.height
            bordered: true
            iconText: "󰅖"
            text: "Cancel"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.finishQueueAdd(false)
          }
        }
      }

      // A newer release, in the side column: its notes, the exact command the
      // update runs (to run here or copy into a terminal), Update and Dismiss.
      Item {
        id: updatePanel
        visible: root.updateOpen
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.libraryPanelWidth

        Column {
          id: updateTitle
          anchors.left: parent.left
          anchors.right: parent.right
          y: Math.max(0, (column.sideSeparatorY - column.spacing - implicitHeight) / 2)
          spacing: Style.space(2)

          PanelSectionHeader {
            width: parent.width
            text: root.updatedVersion !== "" ? "UPDATED TO " + root.updatedVersion
              : root.latestRelease ? "OMEDIA CONTROLS " + root.latestRelease.version : "UPDATE"
            elide: Text.ElideRight
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            color: root.bar.foreground
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Installed " + (root.installedVersion || "?")
              + (root.latestRelease && root.latestRelease.published ? " · released " + root.latestRelease.published : "")
            elide: Text.ElideRight
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator {
          id: updateSeparator
          anchors.left: parent.left
          anchors.right: parent.right
          y: column.sideSeparatorY
          foreground: root.bar.foreground
        }

        // The release notes, as written.
        Flickable {
          id: updateNotes
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: updateSeparator.bottom
          anchors.topMargin: column.spacing
          anchors.bottom: updateCommandBox.top
          anchors.bottomMargin: column.spacing
          clip: true
          contentHeight: updateNotesText.implicitHeight
          boundsBehavior: Flickable.StopAtBounds

          // A section per heading, each with its own header and dividing
          // line, as the rest of the popup has (see Logic.releaseNoteSections).
          Column {
            id: updateNotesText
            width: updateNotes.width
            spacing: Style.space(8)

            Repeater {
              model: root.latestRelease ? Logic.releaseNoteSections(root.latestRelease.notes) : []

              Column {
                required property var modelData
                required property int index
                width: updateNotesText.width
                spacing: Style.space(8)

                PanelSeparator {
                  width: parent.width
                  visible: index > 0
                  foreground: root.bar.foreground
                }

                PanelSectionHeader {
                  width: parent.width
                  visible: modelData.title !== ""
                  text: modelData.title
                  elide: Text.ElideRight
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                }

                Text {
                  width: parent.width
                  visible: modelData.body !== ""
                  // Markdown with images and HTML already removed (see
                  // Logic.releaseNotesText); links are shown, not followed.
                  textFormat: Text.MarkdownText
                  text: modelData.body
                  wrapMode: Text.Wrap
                  color: root.bar.foreground
                  linkColor: Color.accent
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            Text {
              width: parent.width
              visible: root.latestRelease !== null && Logic.releaseNoteSections(root.latestRelease.notes).length === 0
              textFormat: Text.PlainText
              text: "No release notes."
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // What Update runs, word for word, with a copy button; then how it
        // went, and the two actions.
        Column {
          id: updateCommandBox
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.space(8)

          PanelSeparator { width: parent.width; foreground: root.bar.foreground }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.updatedVersion !== ""
              ? "The new version is loaded. Restart the shell if anything looks stale."
              : "Update runs this command. You can also copy it into a terminal."
            wrapMode: Text.Wrap
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          BorderSurface {
            width: parent.width
            visible: root.updatedVersion === ""
            height: visible ? commandText.implicitHeight + Style.space(16) : 0
            radius: Style.spacing.labelGap
            color: Style.normalFillFor(root.bar.foreground, Color.accent)
            borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

            TextEdit {
              id: commandText
              anchors.left: parent.left
              anchors.right: copyCommand.left
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              readOnly: true
              selectByMouse: true
              wrapMode: TextEdit.WrapAnywhere
              textFormat: TextEdit.PlainText
              text: root.updateCommandText
              color: root.bar.foreground
              selectionColor: Style.selectionFillFor(root.bar.foreground, Color.accent)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Button {
              id: copyCommand
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              bordered: true
              iconText: "󰆏"
              iconSize: Style.font.caption
              foreground: root.bar.foreground
              horizontalPadding: Style.space(5)
              verticalPadding: Style.space(1)
              tooltipText: "Copy"
              onClicked: Quickshell.execDetached(["wl-copy", "--", root.updateCommandText])
            }
          }

          Text {
            width: parent.width
            visible: root.updateRunning || root.updateResult !== ""
            textFormat: Text.PlainText
            text: root.updateRunning ? "Updating…" : root.updateResult
            wrapMode: Text.Wrap
            maximumLineCount: 6
            elide: Text.ElideRight
            color: root.updateFailed ? Color.urgent : Qt.darker(root.bar.foreground, 1.2)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            width: parent.width
            spacing: Style.spacing.md

            Button {
              id: runUpdateButton
              width: (parent.width - parent.spacing) * 0.68
              bordered: true
              iconText: root.updatedVersion !== "" ? "󰜉" : "󰚰"
              text: root.updatedVersion !== "" ? "Restart shell" : root.updateRunning ? "Updating…" : "Update"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              opacity: root.updateRunning ? 0.4 : 1.0
              tooltipText: root.updatedVersion !== "" ? "Reloads the whole shell" : ""
              onClicked: root.updatedVersion !== "" ? root.restartShell() : root.runUpdate()
            }

            Button {
              width: (parent.width - parent.spacing) * 0.32
              height: runUpdateButton.height
              bordered: true
              iconText: root.updatedVersion !== "" ? "󰄬" : "󰅖"
              text: root.updatedVersion !== "" ? "Done" : "Dismiss"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              tooltipText: root.updatedVersion !== "" ? "Clear this notice" : "Hide this notice until a newer release"
              onClicked: root.updatedVersion !== "" ? root.finishUpdated() : root.dismissUpdate()
            }
          }
        }
      }

      // Saved playlists, in the side column: the list of them, or one opened
      // to play, rename, delete or edit. Opened from the library's header, or
      // by saving or adding a selection. See the playlists section above.
      Item {
        id: playlistsPanel
        visible: root.playlistsOpen
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.libraryPanelWidth

        readonly property real rowHeight: Style.space(30)
        readonly property bool naming: root.playlistNameMode !== ""
        readonly property string openName: Logic.playlistDisplayName(root.openPlaylist)

        Item {
          id: playlistsHeaderRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: Math.max(0, column.sideSeparatorY - column.spacing)

          Column {
            anchors.left: parent.left
            anchors.right: playlistsAction.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            PanelSectionHeader {
              width: parent.width
              text: root.openPlaylist ? Logic.playlistHeading(playlistsPanel.openName) : "PLAYLISTS"
              elide: Text.ElideRight
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              color: root.bar.foreground
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.openPlaylist
                  ? root.playlistEntries.length + (root.playlistEntries.length === 1 ? " track" : " tracks")
                  : playlistsModel.count === 0 ? "None saved yet"
                  : playlistsModel.count + (playlistsModel.count === 1 ? " playlist" : " playlists")
              elide: Text.ElideRight
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // Play the open playlist, or start a new one.
          Button {
            id: playlistsAction
            visible: !playlistsPanel.naming
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            bordered: true
            iconText: root.openPlaylist ? "󰐊" : "󰐒"
            text: root.openPlaylist ? "Play" : "New"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            opacity: root.openPlaylist && root.playlistEntries.length === 0 ? 0.4 : 1.0
            tooltipText: root.openPlaylist ? (root.playlistEntries.length > 0 ? "Play this playlist" : "Nothing to play yet")
              : "A new, empty playlist"
            onClicked: {
              if (root.openPlaylist) {
                if (root.playlistEntries.length > 0) root.playSavedPlaylist(root.openPlaylist)
              } else {
                root.startNewPlaylist([], "playlists")
              }
            }
          }
        }

        PanelSeparator {
          id: playlistsSeparator
          anchors.left: parent.left
          anchors.right: parent.right
          y: column.sideSeparatorY
          foreground: root.bar.foreground
        }

        // Back: to the player's playlist from the list, to the list from a
        // saved playlist.
        component BackRow: BorderSurface {
          id: back
          property string label: ""
          signal activated()
          height: playlistsPanel.rowHeight
          radius: Style.spacing.labelGap
          color: backArea.containsMouse ? Style.normalFillFor(root.bar.foreground, Color.accent) : "transparent"
          borderSpec: Border.none()

          MouseArea {
            id: backArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: back.activated()
          }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            Text {
              textFormat: Text.PlainText
              text: "󰁍"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.icon
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: back.label
              color: Qt.darker(root.bar.foreground, 1.3)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // The list of playlists. Click to open.
        ListView {
          id: playlistsList
          visible: !root.openPlaylist && !playlistsPanel.naming
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: playlistsSeparator.bottom
          anchors.topMargin: column.spacing
          anchors.bottom: parent.bottom
          clip: true
          model: playlistsModel
          boundsBehavior: Flickable.StopAtBounds

          header: BackRow {
            width: playlistsList.width
            label: "Back"
            onActivated: {
              root.cancelPlaylistName()
              root.sidePanel = "playlist"
            }
          }

          delegate: BorderSurface {
            id: saved
            required property string fileName
            required property string filePath

            width: playlistsList.width
            height: playlistsPanel.rowHeight
            radius: Style.spacing.labelGap
            color: savedArea.containsMouse ? Style.normalFillFor(root.bar.foreground, Color.accent) : "transparent"
            borderSpec: Border.none()

            MouseArea {
              id: savedArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openSavedPlaylist(saved.filePath)
            }

            Row {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)

              Text {
                id: savedIcon
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "󰲸"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.icon
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - savedIcon.width - savedPlay.width - parent.spacing * 2
                textFormat: Text.PlainText
                text: Logic.playlistDisplayName(saved.fileName)
                elide: Text.ElideRight
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Button {
                id: savedPlay
                anchors.verticalCenter: parent.verticalCenter
                bordered: true
                iconText: "󰐊"
                iconSize: Style.font.caption
                foreground: root.bar.foreground
                horizontalPadding: Style.space(5)
                verticalPadding: Style.space(1)
                tooltipText: "Play playlist"
                onClicked: root.playSavedPlaylist(saved.filePath)
              }
            }
          }
        }

        Text {
          anchors.top: playlistsSeparator.bottom
          anchors.topMargin: column.spacing + playlistsPanel.rowHeight + Style.space(4)
          anchors.left: parent.left
          anchors.right: parent.right
          visible: !root.openPlaylist && playlistsModel.count === 0 && !playlistsPanel.naming
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "No playlists yet. Save what a player is playing from its playlist column, or press New. They're kept in " + root.playlistsFolder + "."
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        // One playlist's tracks, in order, each with move and remove buttons.
        // Every change is saved straight away.
        ListView {
          id: entriesList
          visible: root.openPlaylist !== "" && !playlistsPanel.naming
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: playlistsSeparator.bottom
          anchors.topMargin: column.spacing
          anchors.bottom: playlistEditBar.top
          anchors.bottomMargin: Style.space(8)
          clip: true
          model: root.playlistEntries
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds

          header: BackRow {
            width: entriesList.width
            label: "Back"
            onActivated: root.closeSavedPlaylist()
          }

          delegate: BorderSurface {
            id: entryRow
            required property var modelData
            required property int index
            readonly property var label: Logic.playlistEntryLabel(entryRow.modelData)

            width: entriesList.width
            height: Style.space(38)
            radius: Style.spacing.labelGap
            color: entryHover.hovered ? Style.normalFillFor(root.bar.foreground, Color.accent) : "transparent"
            borderSpec: Border.none()

            HoverHandler { id: entryHover }

            Row {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(4)
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(14)

              Text {
                id: entryNumber
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(22)
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: Logic.trackNumber(entryRow.index + 1, root.playlistEntries.length)
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - entryNumber.width - entryTools.width - parent.spacing * 2
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: entryRow.label.title
                  elide: Text.ElideRight
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  width: parent.width
                  visible: text !== ""
                  textFormat: Text.PlainText
                  text: entryRow.label.folder
                  elide: Text.ElideRight
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Row {
                id: entryTools
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Button {
                  bordered: true
                  iconText: "󰁝"
                  iconSize: Style.font.caption
                  foreground: root.bar.foreground
                  horizontalPadding: Style.space(5)
                  verticalPadding: Style.space(1)
                  opacity: entryRow.index > 0 ? 1.0 : 0.4
                  tooltipText: "Move up"
                  onClicked: if (entryRow.index > 0) root.editSavedEntry("move", entryRow.index, -1)
                }

                Button {
                  bordered: true
                  iconText: "󰁅"
                  iconSize: Style.font.caption
                  foreground: root.bar.foreground
                  horizontalPadding: Style.space(5)
                  verticalPadding: Style.space(1)
                  opacity: entryRow.index < root.playlistEntries.length - 1 ? 1.0 : 0.4
                  tooltipText: "Move down"
                  onClicked: if (entryRow.index < root.playlistEntries.length - 1) root.editSavedEntry("move", entryRow.index, 1)
                }

                Button {
                  bordered: true
                  iconText: "󰅖"
                  iconSize: Style.font.caption
                  foreground: root.bar.foreground
                  horizontalPadding: Style.space(5)
                  verticalPadding: Style.space(1)
                  tooltipText: "Remove from playlist"
                  onClicked: root.editSavedEntry("remove", entryRow.index, 0)
                }
              }
            }
          }
        }

        Text {
          anchors.top: playlistsSeparator.bottom
          anchors.topMargin: column.spacing + playlistsPanel.rowHeight + Style.space(4)
          anchors.left: parent.left
          anchors.right: parent.right
          visible: root.openPlaylist !== "" && root.playlistEntries.length === 0 && playlistReader.loaded && !playlistsPanel.naming
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "This playlist is empty."
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        // Rename or delete the open playlist. Delete asks once more, and moves
        // the file to the trash.
        Row {
          id: playlistEditBar
          visible: root.openPlaylist !== "" && !playlistsPanel.naming
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.spacing.md

          Button {
            id: renamePlaylist
            width: (parent.width - parent.spacing) / 2
            bordered: true
            iconText: "󰑕"
            text: "Rename"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.startRenamePlaylist()
          }

          Button {
            width: (parent.width - parent.spacing) / 2
            height: renamePlaylist.height
            bordered: true
            iconText: "󰩺"
            text: root.playlistDeleteArmed ? "Confirm delete" : "Delete"
            selected: root.playlistDeleteArmed
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            tooltipText: root.playlistDeleteArmed ? "Moves the file to the trash" : ""
            onClicked: root.deleteOpenPlaylist()
          }
        }

        // Naming a new playlist, or renaming the open one, in place of
        // everything else under the header. Enter saves, Escape cancels.
        Column {
          id: playlistNamer
          visible: playlistsPanel.naming
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: playlistsSeparator.bottom
          anchors.topMargin: column.spacing
          spacing: Style.space(8)

          onVisibleChanged: {
            if (visible) {
              playlistNameField.text = root.playlistNameMode === "rename" ? playlistsPanel.openName : ""
              playlistNameField.forceActiveFocus()
              playlistNameField.selectAll()
            } else {
              keyCatcher.forceActiveFocus()
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.playlistNameMode === "rename" ? "Rename playlist"
              : root.playlistNamePaths.length > 0
                ? "Save " + root.playlistNamePaths.length + (root.playlistNamePaths.length === 1 ? " track" : " tracks") + " as a playlist"
                : "New playlist"
            elide: Text.ElideRight
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          TextField {
            id: playlistNameField
            width: parent.width
            placeholderText: "Playlist name"
            foreground: root.bar.foreground
            font.family: root.bar.fontFamily
            maximumLength: Logic.MAX_PLAYLIST_NAME
            onTextEdited: root.playlistNameError = ""
            Keys.onReturnPressed: function(event) { root.commitPlaylistName(text); event.accepted = true }
            Keys.onEnterPressed: function(event) { root.commitPlaylistName(text); event.accepted = true }
            Keys.onEscapePressed: function(event) { root.abandonPlaylistName(); event.accepted = true }
          }

          Text {
            width: parent.width
            visible: root.playlistNameError !== ""
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.playlistNameError
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            width: parent.width
            spacing: Style.spacing.md

            Button {
              id: namerSave
              width: (parent.width - parent.spacing) * 0.68
              bordered: true
              iconText: "󰆓"
              text: "Save"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.commitPlaylistName(playlistNameField.text)
            }

            Button {
              width: (parent.width - parent.spacing) * 0.32
              height: namerSave.height
              bordered: true
              iconText: "󰅖"
              text: "Cancel"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.abandonPlaylistName()
            }
          }
        }
      }

      // Settings, in the side column: every choice the plugin offers, made
      // here and remembered. Scrolls when it outgrows the popup.
      Item {
        id: settingsPanel
        visible: root.settingsOpen
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.libraryPanelWidth

        Column {
          id: settingsTitle
          anchors.left: parent.left
          anchors.right: parent.right
          y: Math.max(0, (column.sideSeparatorY - column.spacing - implicitHeight) / 2)
          spacing: Style.space(2)

          PanelSectionHeader {
            text: "SETTINGS"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            color: root.bar.foreground
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Saved as you change them"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator {
          id: settingsSeparator
          anchors.left: parent.left
          anchors.right: parent.right
          y: column.sideSeparatorY
          foreground: root.bar.foreground
        }

        Flickable {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: settingsSeparator.bottom
          anchors.topMargin: column.spacing
          anchors.bottom: parent.bottom
          clip: true
          contentHeight: settingsColumn.implicitHeight
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: settingsColumn
            width: parent.width
            spacing: Style.space(10)

            // ------------------------------------------------------- updates
            PanelSectionHeader {
              text: "UPDATES"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            // Two lines whose height never depends on what they say, so
            // nothing below them moves while a check runs.
            Column {
              width: parent.width
              spacing: 0

              Text {
                id: updateLineProbe
                visible: false
                text: "Ag"
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                width: parent.width
                height: updateLineProbe.implicitHeight
                textFormat: Text.PlainText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                text: "Installed " + (root.installedVersion || "?") + " · "
                  + (root.updateCheckError !== "" ? root.updateCheckError
                    : root.updateAvailable ? root.latestRelease.version + " available"
                    : root.updateCheckedAt > 0 ? "up to date"
                    : "not checked yet")
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                width: parent.width
                height: updateLineProbe.implicitHeight
                textFormat: Text.PlainText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                text: root.updateChecking ? "Checking…"
                  : root.updateCheckedAt > 0
                    ? "Last checked " + new Date(root.updateCheckedAt).toLocaleString(Qt.locale(), Locale.ShortFormat)
                    : "Not checked yet"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              width: parent.width
              spacing: Style.spacing.md

              Button {
                width: (parent.width - parent.spacing) / 2
                // From the button beside it, whose label never changes, so
                // "Checking…" can't resize the row.
                height: viewUpdateButton.implicitHeight
                bordered: true
                iconText: "󰑐"
                text: root.updateChecking ? "Checking…" : "Check now"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                opacity: root.updateChecking ? 0.4 : 1.0
                onClicked: root.checkForUpdates()
              }

              Button {
                id: viewUpdateButton
                width: (parent.width - parent.spacing) / 2
                bordered: true
                iconText: "󰚰"
                text: "View update"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                opacity: root.updateAvailable ? 1.0 : 0.4
                tooltipText: root.updateAvailable ? "Release notes and Update" : "No newer release"
                onClicked: if (root.updateAvailable) root.sidePanel = "update"
              }
            }

            SettingSwitch {
              label: "Check for updates daily"
              hint: "Asks GitHub for the latest release once a day while the popup is open. Nothing else is sent."
              checked: root.updateCheck
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onToggled: root.setSetting("updateCheck", !root.updateCheck)
            }

            PanelSeparator { width: parent.width; foreground: root.bar.foreground }

            // ---------------------------------------------------- visualiser
            PanelSectionHeader {
              text: "VISUALISER"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            // The colours, for every visualisation at once.
            Row {
              id: visColourRow
              width: parent.width
              spacing: Style.spacing.md

              Repeater {
                model: Logic.VIS_COLOURS

                Button {
                  required property string modelData
                  width: (visColourRow.width - visColourRow.spacing * (Logic.VIS_COLOURS.length - 1)) / Logic.VIS_COLOURS.length
                  bordered: true
                  text: Logic.VIS_COLOUR_NAMES[modelData]
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  selected: root.visColour === modelData
                  onClicked: root.setSetting("visColour", modelData)
                }
              }
            }

            Grid {
              id: visGrid
              width: parent.width
              columns: 2
              columnSpacing: Style.spacing.md
              rowSpacing: Style.spacing.md

              Repeater {
                model: Logic.VISUALISATIONS

                // A tile per visualisation: a still of it, drawn the way the
                // header draws it on a frame of made-up music, and its name.
                BorderSurface {
                  id: visTile
                  required property string modelData
                  readonly property bool picked: root.visualisation === modelData
                  width: (visGrid.width - visGrid.columnSpacing) / 2
                  height: visTileContent.implicitHeight + Style.space(16)
                  radius: Style.cornerRadius
                  color: picked ? Style.selectedFillFor(root.bar.foreground, Color.accent)
                    : visTileArea.containsMouse ? Style.normalFillFor(root.bar.foreground, Color.accent)
                    : "transparent"
                  borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

                  MouseArea {
                    id: visTileArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setSetting("visualisation", visTile.modelData)
                  }

                  Column {
                    id: visTileContent
                    anchors.centerIn: parent
                    width: parent.width - Style.space(16)
                    spacing: Style.space(6)

                    Canvas {
                      id: visPreview
                      width: parent.width
                      height: Math.round(width * root.heroAspect)
                      readonly property color accent: Color.accent
                      readonly property color fg: root.bar.foreground
                      readonly property string mode: root.visColour
                      readonly property var rows: root.visRows
                      onAccentChanged: requestPaint()
                      onFgChanged: requestPaint()
                      onModeChanged: requestPaint()
                      onRowsChanged: requestPaint()
                      onWidthChanged: requestPaint()

                      function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

                      onPaint: {
                        var ctx = getContext("2d")
                        var w = width, h = height
                        ctx.clearRect(0, 0, w, h)
                        // The dot matrix, as behind the header's visualiser.
                        // Scaled to the tile, with the same proportions.
                        if (visTile.modelData === "off") return
                        var scale = w / root.heroVisWidth
                        Logic.drawDotMatrix(ctx, w, h, Style.space(4) * scale, Style.space(1) * scale, rgba(fg, 0.50))
                        var cw = w / 75

                        var kind = visTile.modelData
                        var barW = w * 4 / 94, gap = w / 94, unit = h / 16
                        var bars = Logic.PREVIEW_BARS, peaks = Logic.PREVIEW_PEAKS
                        ctx.globalAlpha = 0.9
                        if (kind === "analyser") {
                          for (var i = 0; i < 19; i++) {
                            var x = i * (barW + gap)
                            var lit = Math.round(bars[i] * 15)
                            for (var r = 0; r < lit; r++) {
                              ctx.fillStyle = rows[15 - r]
                              ctx.fillRect(x, h - (r + 1) * unit, barW, unit)
                            }
                            ctx.fillStyle = root.visPeak
                            ctx.fillRect(x, h - (Math.round(peaks[i] * 15) + 1) * unit, barW, Math.max(1, unit))
                          }
                        } else if (kind === "winamp5") {
                          var wu = Math.max(1, Math.floor(unit))
                          for (var b5 = 0; b5 < 19; b5++) {
                            var x5 = b5 * (barW + gap)
                            for (var r5 = 0; r5 < Math.round(bars[b5] * 15); r5++) {
                              ctx.fillStyle = root.winamp5Rows[15 - r5]
                              if (Logic.winamp5RowLit(r5)) ctx.fillRect(x5, h - (r5 + 1) * wu, barW, wu)
                            }
                            ctx.fillStyle = root.winamp5Peak
                            ctx.fillRect(x5, h - (Math.round(peaks[b5] * 15) + 1) * wu, barW, wu)
                          }
                        } else if (kind === "mirror") {
                          for (var m = 0; m < 19; m++) {
                            var level = bars[Logic.mirrorBand(m)]
                            ctx.fillStyle = Logic.spectrumColorAt(rows, level)
                            var mh = Math.max(Style.space(2) * scale, level * h)
                            ctx.fillRect(m * (barW + gap), (h - mh) / 2, barW, mh)
                          }
                        } else if (kind === "vu") {
                          var rowH = h * 8 / 28, rowGap = h * 4 / 28
                          var levels = [0.84, 0.74], vpeaks = [0.95, 0.84]
                          for (var c = 0; c < 2; c++) {
                            var y0 = (h - rowH * 2 - rowGap) / 2 + c * (rowH + rowGap)
                            var vlit = Logic.vuLit(levels[c]), peak = Logic.vuPeakSegment(vpeaks[c], levels[c])
                            for (var sgm = 0; sgm < 19; sgm++) {
                              ctx.fillStyle = sgm === peak ? root.visPeak : Logic.vuSegmentColor(rows, sgm)
                              ctx.globalAlpha = sgm === peak || sgm < vlit ? 0.9 : 0.15
                              ctx.fillRect(sgm * (barW + gap), y0, barW, rowH)
                            }
                            ctx.globalAlpha = 0.9
                          }
                        } else {
                          var cols = Logic.previewScope()
                          for (var k = 0; k < cols.length; k++) {
                            var sc = Logic.scopeColor(mode, rows, cols[k].row)
                            ctx.fillStyle = sc || rgba(accent, Logic.scopeBrightness(cols[k].row))
                            ctx.fillRect(Math.round(k * cw), cols[k].top * unit, Math.max(1, Math.round(cw)), (cols[k].bottom - cols[k].top + 1) * unit)
                          }
                        }
                      }
                    }

                    Text {
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      textFormat: Text.PlainText
                      text: Logic.VISUALISATION_NAMES[visTile.modelData]
                      elide: Text.ElideRight
                      color: root.bar.foreground
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: visTile.picked
                    }
                  }
                }
              }
            }

            PanelSeparator { width: parent.width; foreground: root.bar.foreground }

            // ------------------------------------------------------- library
            PanelSectionHeader {
              text: "LIBRARY FOLDER"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.libraryRoot + (root.musicFolder === "" ? "  (desktop default)" : "")
              elide: Text.ElideMiddle
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              width: parent.width
              spacing: Style.spacing.md

              Button {
                width: (parent.width - parent.spacing) / 2
                bordered: true
                iconText: "󱍙"
                text: "Change…"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.chooseMusicFolder()
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                bordered: true
                iconText: "󰦛"
                text: "Default"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                enabled: root.musicFolder !== ""
                opacity: enabled ? 1.0 : 0.4
                onClicked: {
                  root.musicFolder = ""
                  root.libraryDir = ""
                  root.savePreferences()
                }
              }
            }

            PanelSeparator { width: parent.width; foreground: root.bar.foreground }

            // ----------------------------------------------------- playlists
            PanelSectionHeader {
              text: "PLAYLIST FOLDER"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.playlistsFolder + (root.playlistFolder === "" ? "  (default)" : "")
              elide: Text.ElideMiddle
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              width: parent.width
              spacing: Style.spacing.md

              Button {
                width: (parent.width - parent.spacing) / 2
                bordered: true
                iconText: "󱍙"
                text: "Change…"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.choosePlaylistFolder()
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                bordered: true
                iconText: "󰦛"
                text: "Default"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                enabled: root.playlistFolder !== ""
                opacity: enabled ? 1.0 : 0.4
                onClicked: {
                  root.playlistFolder = ""
                  root.closeSavedPlaylist()
                  root.savePreferences()
                }
              }
            }

            PanelSeparator { width: parent.width; foreground: root.bar.foreground }

            PanelSectionHeader {
              text: "MUSIC PLAYER"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Plays picks from the library when the active player can't take them."
              wrapMode: Text.Wrap
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Button {
                width: parent.width
                bordered: true
                text: "Desktop default" + (root.desktopAudioApp ? " (" + Logic.desktopIdLabel(root.desktopAudioApp) + ")" : "")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                selected: root.musicPlayer === ""
                onClicked: root.setSetting("musicPlayer", "")
              }

              Repeater {
                model: root.audioApps

                Button {
                  id: appButton
                  required property string modelData
                  width: parent.width
                  bordered: true
                  text: appName.name || Logic.desktopIdLabel(modelData)
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  selected: root.musicPlayer === modelData
                  onClicked: root.setSetting("musicPlayer", modelData)

                  // The app's own name, from its desktop file.
                  FileView {
                    id: appName
                    property string name: ""
                    printErrors: false
                    path: Quickshell.env("HOME") + "/.local/share/applications/" + appButton.modelData
                    onLoaded: appName.name = Logic.desktopEntryName(appName.text())
                    onLoadFailed: if (appName.path.indexOf("/usr/share/") !== 0) appName.path = "/usr/share/applications/" + appButton.modelData
                  }
                }
              }
            }

            PanelSeparator { width: parent.width; foreground: root.bar.foreground }

            // ------------------------------------------------ lyrics and art
            PanelSectionHeader {
              text: "PRIVACY"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            SettingSwitch {
              label: "Look up lyrics online"
              hint: "Asks lrclib.net for tracks with no .lrc file, sending artist, title, album and length."
              checked: root.onlineLyrics
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onToggled: {
                root.setSetting("onlineLyrics", !root.onlineLyrics)
                root.lyricsLoadedKey = ""
                root.loadLyrics()
              }
            }

            SettingSwitch {
              label: "Load cover art from the web"
              hint: "Off shows the placeholder instead of fetching https:// art. Local art still shows."
              checked: root.webArt
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onToggled: root.setSetting("webArt", !root.webArt)
            }

            SettingSwitch {
              label: "Remember live stations"
              hint: "So a station shows LIVE at once next time. Kept on this machine only."
              checked: root.rememberStations
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onToggled: root.setSetting("rememberStations", !root.rememberStations)
            }

            Row {
              width: parent.width
              spacing: Style.spacing.md

              Button {
                width: (parent.width - parent.spacing) / 2
                bordered: true
                text: "Forget stations"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                enabled: root.knownLiveStreams.length > 0
                opacity: enabled ? 1.0 : 0.4
                tooltipText: root.knownLiveStreams.length + " remembered"
                onClicked: root.forgetStations()
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                bordered: true
                text: "Clear lyrics"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                enabled: root.lyricsCache.length > 0
                opacity: enabled ? 1.0 : 0.4
                tooltipText: root.lyricsCache.length + " songs cached"
                onClicked: root.clearLyricsCache()
              }
            }

            PanelSeparator { width: parent.width; foreground: root.bar.foreground }

            // ---------------------------------------------- bar and players
            PanelSectionHeader {
              text: "BEHAVIOUR"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            SettingSwitch {
              label: "Hide when nothing is playing"
              hint: "The widget comes back as soon as a player has a track."
              checked: root.hideWhenIdle
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onToggled: root.setSetting("hideWhenIdle", !root.hideWhenIdle)
            }

            SettingSwitch {
              label: "Pause others"
              hint: "Starting one player pauses the rest."
              checked: root.pauseOthers
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onToggled: root.togglePauseOthers()
            }

            Text {
              textFormat: Text.PlainText
              text: "Bar title width"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Row {
              id: titleWidths
              width: parent.width
              spacing: Style.spacing.md

              Repeater {
                model: Logic.TITLE_WIDTHS

                Button {
                  required property int modelData
                  width: (titleWidths.width - titleWidths.spacing * (Logic.TITLE_WIDTHS.length - 1)) / Logic.TITLE_WIDTHS.length
                  bordered: true
                  text: modelData > 0 ? String(modelData) : "Full"
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  selected: root.titleWidth === modelData
                  tooltipText: modelData > 0 ? "Up to " + modelData + " px" : "The whole title"
                  onClicked: root.setSetting("titleWidth", modelData)
                }
              }
            }

            // Only the bar's title; the popup's long lines always scroll.
            // Nothing to scroll at full width, so it's dimmed there.
            SettingSwitch {
              label: "Scroll the bar title"
              hint: root.titleWidth > 0 ? "A title longer than its width keeps moving. Off cuts it short."
                : "The title has its full width, so it never needs to scroll."
              checked: root.scrollTitle
              opacity: root.titleWidth > 0 ? 1.0 : 0.4
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onToggled: root.setSetting("scrollTitle", !root.scrollTitle)
            }

            PanelSeparator { width: parent.width; foreground: root.bar.foreground }

            // ------------------------------------------------------ keyboard
            PanelSectionHeader {
              text: "KEYBOARD"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Text {
              textFormat: Text.PlainText
              text: "← → seek by"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Row {
              id: seekSteps
              width: parent.width
              spacing: Style.spacing.md

              Repeater {
                model: Logic.SEEK_STEPS

                Button {
                  required property int modelData
                  width: (seekSteps.width - seekSteps.spacing * (Logic.SEEK_STEPS.length - 1)) / Logic.SEEK_STEPS.length
                  bordered: true
                  text: modelData + " s"
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  selected: root.seekStep === modelData
                  onClicked: root.setSetting("seekStep", modelData)
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "↑ ↓ volume by"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Row {
              id: volumeSteps
              width: parent.width
              spacing: Style.spacing.md

              Repeater {
                model: Logic.VOLUME_STEPS

                Button {
                  required property int modelData
                  width: (volumeSteps.width - volumeSteps.spacing * 2) / 3
                  bordered: true
                  text: modelData + " %"
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  selected: root.volumeStep === modelData
                  onClicked: root.setSetting("volumeStep", modelData)
                }
              }
            }
          }
        }
      }
    }
  }
}
