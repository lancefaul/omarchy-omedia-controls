import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons
import "Logic.js" as Logic

BarWidget {
  id: root
  moduleName: "lancefaul.omedia-controls"

  // Binds MPRIS directly instead of going through the built-in omarchy.media
  // service, whose service half only runs while that plugin's own bar icon
  // is enabled — this widget replaces that icon, so it can't depend on it.
  readonly property var players: Mpris.players ? Mpris.players.values : []

  function isProxyPlayer(p) {
    var d = String(p && p.dbusName || "").toLowerCase()
    var e = String(p && p.desktopEntry || "").toLowerCase()
    return d.indexOf("playerctld") !== -1 || e === "playerctld"
  }
  function hasMetadata(p) {
    return !!(p && (p.trackTitle || p.trackArtist || p.identity || p.desktopEntry))
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
  readonly property bool pauseOthers: root.setting("pauseOthers", false)

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
  readonly property string artUrl: activePlayer ? Logic.safeArtUrl(activePlayer.trackArtUrl) : ""

  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
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

  // open, close and opened are what the bar looks for to route a hotkey here:
  // `omarchy-shell shell toggle lancefaul.omedia-controls` opens the popup on
  // the focused monitor.
  readonly property bool opened: popupOpen
  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }
  readonly property bool visualizerEnabled: root.setting("visualizerEnabled", true)
  readonly property int maxLabelWidth: root.setting("maxLabelWidth", 260)
  readonly property bool hideWhenIdle: root.setting("hideWhenIdle", false)

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
      var known = !!p.trackTitle && Logic.isKnownLiveStream(root.knownLiveStreams, track)
      root.observedTrack = track
      root.observedLength = length
      root.growingLive = wasLive || known
      root.liveProvisional = wasLive || known
      root.liveFromMemory = known
      root.liveProvisionalSince = Date.now()
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
    case "seekBack": return root.seekBy(-Logic.KEY_SEEK_SECONDS)
    case "seekForward": return root.seekBy(Logic.KEY_SEEK_SECONDS)
    case "volumeUp": return root.adjustVolume("+" + Logic.KEY_VOLUME_PERCENT)
    case "volumeDown": return root.adjustVolume("-" + Logic.KEY_VOLUME_PERCENT)
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

  // Stays on the bar by default, even with nothing playing, so it's a stable
  // click target for opening the popup rather than appearing/disappearing.
  // hideWhenIdle opts into the disappearing behaviour instead.
  visible: root.hideWhenIdle ? root.hasMedia : true
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
      // It scrolls only under the pointer, so an idle bar never animates.
      width: Math.min(contentWidth, root.maxLabelWidth)
      running: barMouse.containsMouse
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
    if (!root.popupOpen) {
      root.seeking = false
      // Nothing probes while the popup is shut, so a kept value would only be
      // interpolated forward from a stale point the next time it opens.
      root.probedPosition = -1
    }
  }
  onActivePlayerChanged: {
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
      position: Math.round(root.trackPosition * 1000) / 1000,
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
    interval: 500
    repeat: true
    onTriggered: root.positionTick++
  }

  // Only captures audio while the popup is open on a playing track, so the
  // parec monitor stream isn't held open in the background the rest of the
  // time.
  Process {
    id: specProc
    running: root.visualizerEnabled && root.popupOpen && root.activePlayer && root.activePlayer.isPlaying
    command: ["python3", root.specScript]
    stdout: SplitParser {
      // One frame per line: nineteen bar levels, a bar, nineteen peak levels.
      // Levels are 0-1; a peak of -1 has fallen out of sight.
      // Parsing is bounded and clamped in Logic.parseSpectrumFrame.
      onRead: function(line) {
        var frame = Logic.parseSpectrumFrame(line)
        root.bands = frame.bars
        root.peaks = frame.peaks
      }
    }
    onRunningChanged: if (!running) { root.bands = []; root.peaks = [] }
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
    contentWidth: popup.fittedContentWidth(Style.space(320))
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
        anchors.fill: parent
        spacing: Style.space(10)

        PanelHero {
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
            Row {
              id: heroSpectrum
              visible: root.visualizerEnabled
              height: Style.space(28)
              spacing: Style.space(1)

              // Winamp's analyser is sixteen pixels tall; one level is one of them.
              readonly property real unit: height / 16
              readonly property bool playing: root.activePlayer !== null && root.activePlayer.isPlaying

              Repeater {
                model: 19

                Item {
                  required property int index
                  readonly property real level: index < root.bands.length ? root.bands[index] : 0
                  readonly property real peak: index < root.peaks.length ? root.peaks[index] : -1

                  // Four units rather than Winamp's three: at this size the
                  // exact proportion read as too thin. Gap stays at one.
                  width: Style.space(4)
                  height: heroSpectrum.height

                  Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Math.round(parent.level * 15) * heroSpectrum.unit
                    radius: 0
                    color: Color.accent
                    opacity: heroSpectrum.playing ? 0.9 : 0.25
                  }

                  // Winamp draws the peak one level above where it sits.
                  Rectangle {
                    visible: parent.peak >= 0 && heroSpectrum.playing
                    width: parent.width
                    height: Math.max(1, heroSpectrum.unit)
                    radius: 0
                    y: parent.height - (Math.round(parent.peak * 15) + 1) * heroSpectrum.unit
                    color: root.bar.foreground
                    opacity: 0.9
                  }
                }
              }
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.bar.foreground
        }

        // Every player with something loaded, once there is more than one. The
        // one the popup is controlling carries the selected fill; clicking a row
        // switches to it, and each row's own button plays or pauses that player
        // without switching — the way to stop one left running by accident.
        PanelSectionHeader {
          visible: root.sourcePlayers.length > 1
          text: "PLAYERS"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
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
                anchors.rightMargin: sourceRow.borderRight + Style.space(8)
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
                  width: parent.width - rowPlayPause.width - parent.spacing
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
              }
            }
          }
        }

        PanelSeparator {
          visible: root.sourcePlayers.length > 1
          width: parent.width
          foreground: root.bar.foreground
        }

        Row {
          spacing: Style.space(10)
          width: parent.width

          BorderSurface {
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
            width: parent.width - Style.space(74)

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

          // Under the bar: elapsed on the left, length or LIVE on the right. A
          // live stream that cannot be moved around in — Apple Music radio —
          // has nothing to count against and nowhere to go, so it reads just
          // LIVE, centred beneath the full bar.
          Item {
            id: timeRow
            width: parent.width
            height: leftTime.implicitHeight
            readonly property bool liveOnly: root.isLive && !root.canGoLive

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.verticalCenter: parent.verticalCenter
              visible: timeRow.liveOnly
              spacing: Style.space(4)

              LiveDot {
                anchors.verticalCenter: parent.verticalCenter
                size: Style.space(6)
                color: Color.accent
                visible: timeRow.liveOnly && root.popupOpen
              }

              Text {
                textFormat: Text.PlainText
                text: "LIVE"
                color: Color.accent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Row {
              width: parent.width
              visible: !timeRow.liveOnly

              Text {
                id: leftTime
                textFormat: Text.PlainText
                // On a live stream this keeps counting how long you've been
                // watching, the way Winamp's counter runs on a radio stream.
                readonly property bool counting: root.hasTimeline
                  || (root.isLive && root.activePlayer.positionSupported)
                text: counting ? root.formatTime(root.displayPosition) : "--:--"
                color: Qt.darker(root.bar.foreground, 1.2)
                opacity: counting ? 1.0 : 0.5
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              Item {
                width: parent.width - leftTime.width - rightLiveDot.width - liveDotGap.width - rightTime.width
                height: 1
              }

              LiveDot {
                id: rightLiveDot
                anchors.verticalCenter: rightTime.verticalCenter
                size: Style.space(6)
                color: Color.accent
                // Present but hidden off a live stream, so the spacer's sum
                // holds either way; width 0 then takes it out of the row.
                width: root.isLive ? size : 0
                visible: root.isLive && root.popupOpen
              }

              Item {
                id: liveDotGap
                width: root.isLive ? Style.space(4) : 0
                height: 1
              }

              // Click to flip between total length and time remaining, the way
              // Winamp's counter does.
              Text {
                id: rightTime
                textFormat: Text.PlainText
                // On a live stream this is the jump-to-live control: it reads LIVE,
                // and GO LIVE under the pointer so it announces itself as clickable.
                text: root.isLive
                  ? (rightTimeArea.containsMouse && root.canGoLive ? "GO LIVE" : "LIVE")
                  : !root.hasTimeline
                    ? "--:--"
                    : root.showRemaining
                      ? "-" + root.formatTime(Math.max(0, root.trackLength - root.displayPosition))
                      : root.formatTime(root.trackLength)
                color: root.isLive ? Color.accent : Qt.darker(root.bar.foreground, 1.2)
                opacity: root.hasTimeline || root.isLive ? 1.0 : 0.5
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: root.isLive

                MouseArea {
                  id: rightTimeArea
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  enabled: root.hasTimeline || root.canGoLive
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: {
                    if (root.isLive) root.jumpToLive()
                    else root.showRemaining = !root.showRemaining
                  }
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
        // Omarchy's DNS picker. Every icon is play-button size so no control
        // reads as more important than another. Shuffle and repeat show their
        // state with the selected fill — the same way DHCP is marked chosen —
        // rather than a tint, so the row stays visually uniform.
        Row {
          id: transport
          width: parent.width
          spacing: Style.spacing.md

          readonly property int cells: 5
          readonly property real cellWidth: (width - spacing * (cells - 1)) / cells

          Button {
            width: transport.cellWidth
            bordered: true
            iconText: "󰒝"
            iconSize: Style.font.iconLarge
            foreground: root.bar.foreground
            tooltipText: "Shuffle"
            enabled: root.hasShuffle
            selected: root.hasShuffle && root.activePlayer.shuffle
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.toggleShuffle()
          }

          Button {
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
            width: transport.cellWidth
            bordered: true
            iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
            iconSize: Style.font.iconLarge
            foreground: root.bar.foreground
            tooltipText: root.activePlayer && root.activePlayer.isPlaying ? "Pause" : "Play"
            enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.runAction("playPause", root.playerKey(root.activePlayer))
          }

          Button {
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

          Button {
            width: transport.cellWidth
            bordered: true
            iconText: root.hasLoop && root.activePlayer.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
            iconSize: Style.font.iconLarge
            foreground: root.bar.foreground
            tooltipText: !root.hasLoop ? "Repeat"
              : root.activePlayer.loopState === MprisLoopState.Track ? "Repeat track"
              : root.activePlayer.loopState === MprisLoopState.Playlist ? "Repeat playlist"
              : "Repeat off"
            enabled: root.hasLoop
            selected: root.hasLoop && root.activePlayer.loopState !== MprisLoopState.None
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.cycleLoop()
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
      }
    }
  }
}
