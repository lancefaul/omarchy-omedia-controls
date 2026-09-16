.pragma library

// Pure functions used by BarWidget.qml, kept here so tests/tst_logic.qml can
// exercise exactly the code the widget runs.
//
// Several of these guard input that crosses a trust boundary. Every track
// title, artist, art URL and bus name comes from whichever application
// registered an MPRIS interface on the session bus, trusted or not.

// A cover-art URL the widget is willing to load.
//
// Any MPRIS application picks this value, and QML's Image will follow almost
// anything: an arbitrary remote host (a tracking request that leaks the
// user's IP whenever a track is shown), plain http, or image:// and qrc:
// schemes that reach into the shell's own image providers and resources.
//
// Three forms are accepted, which between them cover real players:
//
//   file:///absolute/path  cached art from browsers and most desktop players
//   https://host/...       Spotify and web players
//   data:image/...;base64  art embedded in the track itself, which is how
//                          mpv-mpris publishes a file's own cover
//
// Anything else, or anything with whitespace or control characters, becomes ""
// and the widget shows its placeholder glyph instead.
var MAX_ART_URL_LENGTH = 2048

// Embedded art is inline image data: no request, no file access, nothing in
// the shell's resources, so it is the safest form of all. It is also large by
// nature — mpv sends a typical cover as ~78 KB of base64 — so it gets its own
// cap, sized for a generous embedded cover rather than a URL.
var MAX_DATA_ART_LENGTH = 10 * 1024 * 1024

// Raster types only. SVG is left out: it is a document format rather than
// plain image data, and no player needs it for a cover.
var DATA_ART_PATTERN = /^data:image\/(png|jpeg|jpg|gif|webp|bmp);base64,[A-Za-z0-9+\/]+={0,2}$/

function safeArtUrl(url) {
  if (url === undefined || url === null) return ""
  var s = String(url)
  if (s.length === 0) return ""

  if (s.lastIndexOf("data:", 0) === 0) {
    if (s.length > MAX_DATA_ART_LENGTH) return ""
    return DATA_ART_PATTERN.test(s) ? s : ""
  }

  if (s.length > MAX_ART_URL_LENGTH) return ""
  if (/[\s\u0000-\u001f\u007f]/.test(s)) return ""
  if (/^file:\/\/\//.test(s)) return s
  if (/^https:\/\//.test(s)) {
    // The whole authority — everything up to the first / ? or # — has to be
    // present and free of @. Checking only a prefix of it let
    // https://user:pass@host through, and credentials in the authority are
    // how a URL shows one host while connecting to another.
    var authority = s.slice("https://".length).split(/[\/?#]/)[0]
    if (authority.length > 0 && authority.indexOf("@") === -1) return s
  }
  return ""
}

// Whether a bus name is safe to hand to busctl as the destination for the
// position probe.
//
// It already travels as an argument list, never through a shell, so this is
// defence in depth rather than injection prevention: refuse anything that is
// not shaped like an MPRIS player's well-known name. D-Bus caps names at 255
// characters, and each element is letters, digits, underscores and hyphens.
function isMprisBusName(name) {
  if (name === undefined || name === null) return false
  var s = String(name)
  if (s.length === 0 || s.length > 255) return false
  return /^org\.mpris\.MediaPlayer2\.[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$/.test(s)
}

// Seconds from a `busctl get-property ... Position` line, or -1.
//
// busctl prints the D-Bus type then the value, `x 8882398`: an int64 of
// microseconds. Anything else — an error message, a different type, a
// negative position — is -1, and the caller keeps its previous value.
function parseBusctlPosition(line) {
  var m = /^\s*x\s+(\d+)\s*$/.exec(String(line === undefined || line === null ? "" : line))
  if (!m) return -1
  var seconds = parseInt(m[1], 10) / 1000000
  return isFinite(seconds) && seconds >= 0 ? seconds : -1
}

// One analyser frame from spectrum.py: `bars|peaks`, each a comma-separated
// list of levels from 0 to 1, with -1 for a peak that has fallen out of view.
//
// The script is ours, but the output is still parsed defensively: bounded to
// the bar count so a runaway line cannot grow the model, and every level
// clamped, so a bad value draws as empty rather than as a bar taller than the
// widget.
var BAR_COUNT = 19

function parseSpectrumFrame(line) {
  var halves = String(line === undefined || line === null ? "" : line).split("|")
  var bars = []
  var peaks = []

  var barParts = halves[0] === "" ? [] : halves[0].split(",")
  for (var i = 0; i < barParts.length && i < BAR_COUNT; i++) {
    var b = parseFloat(barParts[i])
    bars.push(isFinite(b) ? Math.max(0, Math.min(1, b)) : 0)
  }

  if (halves.length > 1 && halves[1] !== "") {
    var peakParts = halves[1].split(",")
    for (var j = 0; j < peakParts.length && j < BAR_COUNT; j++) {
      var p = parseFloat(peakParts[j])
      peaks.push(isFinite(p) && p >= 0 ? Math.min(1, p) : -1)
    }
  }

  return { bars: bars, peaks: peaks }
}

// A length that means "this never ends" rather than a real duration.
//
// Live streams have no length, and players say so with a sentinel instead of
// leaving the field out: Chromium reports YouTube TV's live stream as INT64_MAX
// microseconds, which Quickshell turns into 9,223,372,036,854 seconds — drawn
// naively as a counter reading 2562047788:00:54. No real track is anywhere near
// that, so anything from about three years up is treated as unbounded. Unknown
// or invalid lengths (zero, negative, NaN) are a different case — no timeline
// at all — and are not live.
var UNBOUNDED_SECONDS = 1e8

function isUnboundedLength(seconds) {
  return typeof seconds === "number" && isFinite(seconds) && seconds >= UNBOUNDED_SECONDS
}

// Where to send a live stream to reach its live edge.
//
// MPRIS has no "go live" call. The approach is an absolute position far past
// any rewind window, which the player caps at the newest point it has.
//
// It has to be absolute. Measured in Brave on YouTube: a relative Seek of +1 s
// and one of +30 s both moved exactly +5.00 s — Chromium turns MPRIS Seek into
// the page's "seek forward" action, which skips a fixed step and ignores the
// requested offset. SetPosition, which is what writing MprisPlayer.position
// sends, landed exactly where asked. So a relative seek would nudge a live
// stream a few seconds, never reach the edge.
//
// A year is far past any real rewind window, and stays well below
// UNBOUNDED_SECONDS, so it can never be mistaken for a live stream's length.
var LIVE_EDGE_POSITION_SECONDS = 365 * 24 * 60 * 60

// Whether a track's length grew while it played — a live stream delivered in
// chunks, rather than a song.
//
// Not every live stream uses the "never ends" sentinel. Apple Music radio in
// Brave reports a finite length that grows as segments load: measured on Apple
// Music 1, 160.1 s, then 176.2 s, then 192.2 s, sixteen seconds at a time, with
// the position running thirty-odd seconds behind. Drawn as a song, that is a
// three-minute track always about to end, whose bar jumps backwards every
// sixteen seconds. A real song's length does not grow mid-play.
//
// A previous length of zero is excluded: players often report 0 before the
// real length arrives, and that first report is not growth.
//
// So is a jump bigger than a segment could be. Spotify's web player reports a
// placeholder length until playback starts, then the real one: measured on a
// podcast episode, 15.9 s became 8899.8 s in one step. That is a finite
// episode arriving late, not a stream growing.
var LENGTH_GROWTH_SECONDS = 2
var MAX_LENGTH_GROWTH_SECONDS = 60

function isGrowingLength(previousSeconds, currentSeconds) {
  if (typeof previousSeconds !== "number" || typeof currentSeconds !== "number") return false
  if (!isFinite(previousSeconds) || !isFinite(currentSeconds)) return false
  if (previousSeconds <= 0) return false
  var growth = currentSeconds - previousSeconds
  return growth >= LENGTH_GROWTH_SECONDS && growth <= MAX_LENGTH_GROWTH_SECONDS
}

// Carrying live across a track change.
//
// Growth takes one segment to show — about sixteen seconds on Apple Music 1 —
// so every station switch used to show a song-style timeline first, then flip
// to LIVE. But a track change in a player that was just playing a live stream
// is almost always another station. The widget keeps LIVE across the change
// provisionally: growth confirms it, and a length that holds still for longer
// than a segment interval means it was a song after all.
//
// PROVISIONAL_LIVE_MS is one and a half of Apple's measured segments, so a
// real stream has grown well before it expires.
var PROVISIONAL_LIVE_MS = 24000

// Whether a player that has just appeared is the live one that vanished a
// moment ago, rather than a different player.
//
// Brave does not change track when you switch Apple Music stations: it
// unregisters its MPRIS player and registers it again under the same bus
// name. Measured, the player was gone for one to two seconds each switch.
// Treated as a new player, that reset the live state, so carry-over never
// happened and every new station showed a timeline first. Same name, back
// within LIVE_PLAYER_RETURN_MS, is the same player.
var LIVE_PLAYER_RETURN_MS = 5000

function isReturningLivePlayer(key, liveKey, liveGoneAt, nowMs) {
  if (typeof key !== "string" || key.length === 0 || key !== liveKey) return false
  if (typeof liveGoneAt !== "number" || typeof nowMs !== "number") return false
  var gone = nowMs - liveGoneAt
  return gone >= 0 && gone <= LIVE_PLAYER_RETURN_MS
}

// Whether LIVE carries over to the next track. Only a stream actually seen
// growing does: a carry that was never confirmed would otherwise pass itself
// along. Measured: Apple Music Hits, then YouTube TV for eight seconds, then
// a Spotify podcast in another tab — the podcast inherited a LIVE that no
// stream in the chain had confirmed, and showed it for ten seconds.
function carriesLive(growingLive, provisional) {
  return !!growingLive && !provisional
}

// Whether a provisional LIVE's clock is running. A remembered station only
// grows while it plays, so its window counts playing time — expiring it while
// paused would forget a real station. A LIVE merely carried over from the
// previous track runs regardless: Brave hands its one player to another tab
// when the playing one pauses, and a paused podcast in that tab otherwise
// kept the carried LIVE for as long as it sat paused.
function provisionalExpiryRuns(playing, fromMemory) {
  return !!playing || !fromMemory
}

function provisionalLiveExpired(sinceMs, nowMs) {
  if (typeof sinceMs !== "number" || typeof nowMs !== "number") return true
  return nowMs - sinceMs >= PROVISIONAL_LIVE_MS
}

// Remembered live streams.
//
// Growth takes a segment to show, so a station heard before is remembered by
// app and title, and recognised as live the moment it starts. The store is a
// small JSON file the widget writes itself:
//
//   { "version": 1, "streams": [ { "key": "Brave Origin | Apple Music 1", "seen": 1789 } ] }
//
// It is read back defensively — anything can have edited it — bounded in
// count and key length, most recently seen first. A remembered stream still
// has to grow: if it holds still past PROVISIONAL_LIVE_MS it is forgotten.
var MAX_LIVE_STREAMS = 200
var MAX_LIVE_STREAM_KEY_LENGTH = 512

function parseLiveStreamStore(text) {
  var data
  try { data = JSON.parse(String(text === undefined || text === null ? "" : text)) } catch (e) { return [] }
  if (!data || typeof data !== "object" || !Array.isArray(data.streams)) return []

  var out = []
  var seenKeys = {}
  for (var i = 0; i < data.streams.length && out.length < MAX_LIVE_STREAMS; i++) {
    var s = data.streams[i]
    if (!s || typeof s.key !== "string") continue
    if (s.key.length === 0 || s.key.length > MAX_LIVE_STREAM_KEY_LENGTH) continue
    if (/[\u0000-\u001f\u007f]/.test(s.key)) continue
    if (seenKeys[s.key]) continue
    seenKeys[s.key] = true
    out.push({ key: s.key, seen: typeof s.seen === "number" && isFinite(s.seen) ? s.seen : 0 })
  }
  return out
}

function isKnownLiveStream(list, key) {
  if (!Array.isArray(list) || typeof key !== "string" || key.length === 0) return false
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].key === key) return true
  return false
}

// A new list with key at the front, seen now, and the oldest dropped past the
// cap. Keys that could not be read back are refused rather than stored.
function rememberLiveStream(list, key, nowMs) {
  var current = Array.isArray(list) ? list : []
  if (typeof key !== "string" || key.length === 0 || key.length > MAX_LIVE_STREAM_KEY_LENGTH) return current
  if (/[\u0000-\u001f\u007f]/.test(key)) return current
  var out = [{ key: key, seen: typeof nowMs === "number" ? nowMs : 0 }]
  for (var i = 0; i < current.length && out.length < MAX_LIVE_STREAMS; i++)
    if (current[i] && current[i].key !== key) out.push(current[i])
  return out
}

function forgetLiveStream(list, key) {
  if (!Array.isArray(list)) return []
  return list.filter(function(s) { return s && s.key !== key })
}

function serializeLiveStreamStore(list) {
  return JSON.stringify({ version: 1, streams: Array.isArray(list) ? list : [] }, null, 2) + "\n"
}

// Where Go Live should send a live stream, or -1 where it has no business.
//
// With the unbounded sentinel (YouTube TV), a position a year ahead is still
// inside the reported length, and the player caps it at the live edge.
//
// A growing finite length (Apple Music radio) gets no Go Live at all. Its
// playback already sits at live, about 47 s behind the end of what has loaded
// — that gap is its buffer — and the page can neither rewind nor pause (pause
// ends the stream). Measured: jumping to a second short of the end starved
// that buffer, and Brave stalled for 12 s, 12 s and 5 s while sixteen-second
// segments arrived, before settling 45 s later.
function liveEdgeTarget(lengthSeconds, unbounded) {
  return unbounded ? LIVE_EDGE_POSITION_SECONDS : -1
}

// How long after a seek to ignore position reads from the player.
//
// Seeks apply asynchronously: measured in Brave, a read 4 ms after the seek
// still returned the old position, and the new one appeared by 58 ms. A read
// in that gap drags the bar back to where it was dragged from, and the next
// read throws it forward again. A second of trusting the target covers the
// gap, plus the buffering that often follows a seek.
var SEEK_SETTLE_MS = 1000

// Whether a player that has just begun playing really "started" — enough to
// take over the popup from a player started earlier.
//
// Measured with mpv and Brave side by side, playback status flickers without
// anyone touching a player: mpv drops out of Playing for an instant each time
// it restarts a looped file, and YouTube does the same while it buffers.
// Counted as starts, those blips handed the popup back and forth between
// players. And when the shell loads, players that were already playing report
// in over the next moments in whatever order D-Bus delivers, which would rank
// them arbitrarily.
//
// So:
//   "initial" — within PLAYER_STARTUP_GRACE_MS of the widget loading: it was
//               already playing, and ranks below anything started afterwards
//   "blip"    — playing again within PLAYBACK_BLIP_MS of stopping, having been
//               ranked before: keep its old rank
//   "start"   — anything else: a real start, which takes over
var PLAYER_STARTUP_GRACE_MS = 3000
var PLAYBACK_BLIP_MS = 2000

function classifyPlaybackStart(now, loadedAt, stoppedAt, alreadyRanked) {
  if (now - loadedAt < PLAYER_STARTUP_GRACE_MS) return "initial"
  if (alreadyRanked && typeof stoppedAt === "number" && now - stoppedAt < PLAYBACK_BLIP_MS) return "blip"
  return "start"
}

// Which player the popup controls, as the key of one entry, or "".
//
// entries: one per player, in bus order —
//   { key, proxy, hasMetadata, playing, startSerial, hasTrack, controllable }
// preferredKey: the player picked by clicking its row, or "".
//
// In order:
//   1. A player you clicked, whether or not it is playing. Clicking a paused
//      player has to switch to it: requiring it to be playing let any other
//      playing player overrule the click, so the switcher looked dead. A pick
//      lasts until a different player starts, which the widget handles by
//      clearing preferredKey.
//   2. The playing player started most recently (highest startSerial).
//   3. A player with a track loaded, then one that can be controlled.
// Proxies such as playerctld are skipped: they mirror a real player.
function choosePlayer(entries, preferredKey) {
  var list = entries || []
  var newest = null, newestSerial = -Infinity
  var withTrack = null, controllable = null

  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    if (!e || e.proxy) continue
    if (preferredKey && e.key === preferredKey && e.hasMetadata) return e.key
  }

  for (var j = 0; j < list.length; j++) {
    var p = list[j]
    if (!p || p.proxy) continue
    if (p.playing) {
      var serial = typeof p.startSerial === "number" ? p.startSerial : -1
      if (serial > newestSerial) { newest = p; newestSerial = serial }
    } else if (p.hasTrack && !withTrack) {
      withTrack = p
    } else if (p.controllable && !controllable) {
      controllable = p
    }
  }

  var chosen = newest || withTrack || controllable
  return chosen ? chosen.key : ""
}

// m:ss, or h:mm:ss past an hour; --:-- for anything that is not a time,
// including a sentinel length that only looks like one.
function formatTime(seconds) {
  if (typeof seconds !== "number" || !isFinite(seconds) || seconds < 0) return "--:--"
  if (seconds >= UNBOUNDED_SECONDS) return "--:--"
  var total = Math.floor(seconds)
  var h = Math.floor(total / 3600)
  var m = Math.floor((total % 3600) / 60)
  var s = total % 60
  var mm = h > 0 && m < 10 ? "0" + m : String(m)
  var ss = s < 10 ? "0" + s : String(s)
  return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss
}

// ------------------------------------------------------------ end of track

// How close to the end a stopped track counts as finished. mpv with
// keep-open parks a quarter of a second short of the length as reported.
var TRACK_END_TOLERANCE_SECONDS = 1

// Whether a paused player has run off the end of its track, so that Play
// should start it over rather than resume nothing. Never on a live stream,
// whose live edge sits right at its length.
function isAtTrackEnd(position, length, live) {
  if (live) return false
  if (typeof position !== "number" || typeof length !== "number") return false
  if (!isFinite(position) || !isFinite(length) || length <= 0 || isUnboundedLength(length)) return false
  return position >= length - TRACK_END_TOLERANCE_SECONDS
}

// ---------------------------------------------------------------- metadata

// The line under the artist: the album, then whatever else the player sent
// — the album artist when it differs from the track artist (a compilation),
// the year, and the track number — joined with middle dots. Every field is
// optional; players vary widely in what they tag.
function albumDetails(fields) {
  var f = fields || {}
  var parts = []

  var album = firstText(f.album)
  if (album) parts.push(album)

  var albumArtist = firstText(f.albumArtist)
  var artist = firstText(f.artist)
  if (albumArtist && albumArtist.toLowerCase() !== artist.toLowerCase()) parts.push(albumArtist)

  var year = yearOf(f.date)
  if (year) parts.push(year)

  var track = Number(f.trackNumber)
  if (isFinite(track) && track >= 1 && track < 10000 && Math.floor(track) === track)
    parts.push("Track " + track)

  return parts.join(" · ")
}

// MPRIS sends artist lists as arrays; a single string is taken as-is.
function firstText(value) {
  if (Array.isArray(value)) value = value.length > 0 ? value[0] : ""
  if (value === undefined || value === null) return ""
  return String(value).trim()
}

// xesam:contentCreated is an ISO 8601 date, though players send anything
// from a bare year to a full timestamp.
function yearOf(date) {
  var m = /^\s*(\d{4})/.exec(firstText(date))
  return m ? m[1] : ""
}

// ------------------------------------------------------------------ volume

// Chromium-based browsers publish a Volume property but hard-code it at 1.0
// and silently ignore changes, while Quickshell keeps whatever was last sent —
// so a volume slider on Brave moved, did nothing, and then showed a value the
// browser never had. They are recognised by Chromium's own naming: the bus
// name org.mpris.MediaPlayer2.chromium.instanceN (brave.instanceN in Brave)
// and track IDs under /org/chromium/ (/com/brave/ in Brave).
function isChromiumPlayer(busName, trackId) {
  if (/^org\.mpris\.MediaPlayer2\.(chromium|brave)\.instance\d+$/.test(String(busName || ""))) return true
  return /^\/(org\/chromium|com\/brave)\/MediaPlayer2\/TrackList\//.test(firstText(trackId))
}

// A double as busctl prints it: `d 0.61`. Returns -1 for anything else.
function parseBusctlDouble(line) {
  var m = /^\s*d\s+(\d+(?:\.\d+)?(?:e-?\d+)?)\s*$/.exec(String(line || ""))
  if (!m) return -1
  var v = Number(m[1])
  return isFinite(v) ? v : -1
}

var VOLUME_TOLERANCE = 0.02

// Any other player that ignores volume is caught by reading it back after a
// change: a player that took the change reports what was sent.
function volumeWasIgnored(target, reported) {
  if (typeof reported !== "number" || reported < 0) return false
  return Math.abs(reported - target) > VOLUME_TOLERANCE
}

function fixedVolumeMessage(playerName) {
  var name = firstText(playerName)
  return (name || "This player") + " doesn't allow plugins to change volume."
}

// ------------------------------------------------------------------- speed

// Speeding up is the common case (podcasts, lectures); slowing down is rare
// enough that normal speed is the floor. Five steps, matching the transport row.
var SPEED_STEPS = [1, 1.25, 1.5, 2, 3]
var RATE_EPSILON = 0.001
var MIN_COMMAND_RATE = 0.25
var MAX_COMMAND_RATE = 4

// Browsers and Spotify report a range of exactly 1 to 1: nothing to change.
function canChangeRate(minRate, maxRate) {
  return typeof minRate === "number" && typeof maxRate === "number"
    && isFinite(minRate) && isFinite(maxRate) && maxRate - minRate > RATE_EPSILON
}

// Shown over the speed row when the player won't take a rate, naming it so
// the limit reads as the player's rather than the plugin's.
function fixedRateMessage(playerName) {
  var name = firstText(playerName)
  return (name || "This player") + " doesn't allow plugins to change playback speed."
}

// How fast the position advances between reads. Chromium reports 0 while
// paused and the page's own rate while playing, including one set in the
// page, even though it will not take a rate from outside. Anything that
// is not a sane positive rate counts as normal speed.
function effectiveRate(rate) {
  return typeof rate === "number" && isFinite(rate) && rate > 0 && rate <= 100 ? rate : 1
}

function rateInRange(rate, minRate, maxRate) {
  return canChangeRate(minRate, maxRate)
    && rate >= minRate - RATE_EPSILON && rate <= maxRate + RATE_EPSILON
}

function sameRate(a, b) {
  return typeof a === "number" && typeof b === "number" && Math.abs(a - b) < RATE_EPSILON
}

function formatRate(rate) {
  if (typeof rate !== "number" || !isFinite(rate)) return ""
  return String(Math.round(rate * 100) / 100) + "×"
}

// The next step up (direction 1) or down (-1) from the current rate that the
// player allows, or -1 when there is none. A rate between steps moves to the
// nearest step in that direction.
function stepRate(current, direction, minRate, maxRate) {
  if (!canChangeRate(minRate, maxRate)) return -1
  if (direction > 0) {
    for (var i = 0; i < SPEED_STEPS.length; i++) {
      var up = SPEED_STEPS[i]
      if (up > current + RATE_EPSILON && rateInRange(up, minRate, maxRate)) return up
    }
  } else if (direction < 0) {
    for (var j = SPEED_STEPS.length - 1; j >= 0; j--) {
      var down = SPEED_STEPS[j]
      if (down < current - RATE_EPSILON && rateInRange(down, minRate, maxRate)) return down
    }
  }
  return -1
}

// ---------------------------------------------------------------- commands
//
// Arguments to the IPC commands arrive as strings from any process that can
// reach the shell, so each is parsed strictly and bounded.

// "+10" and "-5" are relative, "40" is absolute. Anything else is null.
function parseAdjustment(text) {
  var m = /^([+-])?(\d{1,6}(?:\.\d{1,3})?)$/.exec(String(text === undefined || text === null ? "" : text).trim())
  if (!m) return null
  var value = Number(m[2])
  if (m[1] === "-") value = -value
  return { relative: m[1] !== undefined && m[1] !== "", value: value }
}

// Where a seek command lands, in seconds, clamped to the track; -1 if the
// argument is not an adjustment. A length of 0 means unknown, so only the
// start is enforced.
function seekTarget(position, length, text) {
  var adj = parseAdjustment(text)
  if (!adj) return -1
  var target = adj.relative ? position + adj.value : adj.value
  target = Math.max(0, target)
  if (length > 0) target = Math.min(target, length)
  return target
}

// A volume command in percent: "+5", "-5" or "40". Returns 0-1, or -1.
function volumeTarget(volume, text) {
  var adj = parseAdjustment(text)
  if (!adj) return -1
  var percent = adj.relative ? volume * 100 + adj.value : adj.value
  return Math.max(0, Math.min(100, percent)) / 100
}

// A speed command: "faster", "slower", or a rate such as "1.5", which must
// be one the player allows. Returns the rate to set, or -1.
function rateTarget(current, text, minRate, maxRate) {
  var t = String(text === undefined || text === null ? "" : text).trim().toLowerCase()
  if (t === "faster" || t === "up") return stepRate(current, 1, minRate, maxRate)
  if (t === "slower" || t === "down") return stepRate(current, -1, minRate, maxRate)
  var adj = parseAdjustment(t)
  if (!adj || adj.relative || !rateInRange(adj.value, minRate, maxRate)) return -1
  // mpv allows 0.01 to 100; past these, playback is noise rather than speech.
  if (adj.value < MIN_COMMAND_RATE || adj.value > MAX_COMMAND_RATE) return -1
  return adj.value
}

// ---------------------------------------------------------------- keyboard

var KEY_SEEK_SECONDS = 5
var KEY_VOLUME_PERCENT = 5

// The popup's keyboard shortcuts. `key` is a name the widget derives from the
// Qt key code ("space", "left", "right", "up", "down", "escape", "media-*")
// or, for printable keys, the typed character.
function keyAction(key) {
  switch (String(key || "")) {
  case "space": case "k": case "media-play": return "playPause"
  case "left": return "seekBack"
  case "right": return "seekForward"
  case "up": return "volumeUp"
  case "down": return "volumeDown"
  case "m": return "mute"
  case "n": case "media-next": return "next"
  case "p": case "media-previous": return "previous"
  case "s": return "shuffle"
  case "r": return "repeat"
  case "[": return "slower"
  case "]": return "faster"
  case "l": return "goLive"
  case "escape": return "close"
  }
  return ""
}
