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

// Winamp's oscilloscope, from spectrum.py --oscilloscope: "o|top:bottom:row,..."
// for 75 columns on a sixteen-row grid. Bounded to 75 columns, every value an
// integer clamped to the grid, and top kept at or above bottom; a malformed
// column is left empty rather than drawn wrong.
var SCOPE_COLUMNS = 75
var SCOPE_ROWS = 16

function parseScopeFrame(line) {
  var text = String(line === undefined || line === null ? "" : line)
  if (text.indexOf("o|") !== 0) return []
  var parts = text.slice(2).split(",")
  var columns = []
  for (var i = 0; i < parts.length && i < SCOPE_COLUMNS; i++) {
    var f = parts[i].split(":")
    var top = parseInt(f[0], 10), bottom = parseInt(f[1], 10), row = parseInt(f[2], 10)
    if (f.length !== 3 || !isFinite(top) || !isFinite(bottom) || !isFinite(row)) {
      columns.push(null)
      continue
    }
    top = Math.max(0, Math.min(SCOPE_ROWS - 1, top))
    bottom = Math.max(top, Math.min(SCOPE_ROWS - 1, bottom))
    row = Math.max(0, Math.min(SCOPE_ROWS - 1, row))
    columns.push({ top: top, bottom: bottom, row: row })
  }
  return columns
}

// How bright a column is, by the row the wave sits on: brightest around the
// middle, dimmer toward the edges, as Winamp's default skin colours the scope.
function scopeBrightness(row) {
  var step = row >= 14 ? 4 : row >= 12 ? 3 : row >= 10 ? 2 : row >= 8 ? 1
    : row >= 6 ? 0 : row >= 4 ? 1 : row >= 2 ? 2 : 3
  return 1 - step * 0.12
}

// Which visualisation the header shows, kept in the plugin's own state file.
// Clicking the visualiser steps to the next, as clicking Winamp's does.
// Read back defensively: anything unexpected is the analyser.
// Off last, as in Winamp, whose visualiser click cycle ends with nothing.
var VISUALISATIONS = ["analyser", "winamp5", "mirror", "vu", "oscilloscope", "off"]
var VISUALISATION_NAMES = { analyser: "Analyser", winamp5: "Winamp5", oscilloscope: "Oscilloscope", mirror: "Mirrored bars", vu: "VU meter", off: "Off" }

// ----------------------------------------------------------- visualiser colours
//
// One choice of colours for every visualisation: a gradient of the Omarchy
// theme's accent (the default), the accent alone, or Winamp's own. For the
// Winamp5 analyser (bars striped a row lit, a row empty, as Winamp5
// Classified draws them) Winamp's own is plain white.
var VIS_COLOURS = ["gradient", "solid", "winamp"]
var VIS_COLOUR_NAMES = { gradient: "Gradient", solid: "Solid", winamp: "Winamp" }

function visColour(value) {
  return VIS_COLOURS.indexOf(value) !== -1 ? value : "gradient"
}

// Winamp's spectrum, from base-2.91.wsz's VISCOLOR.TXT (colours 2 to 17, top
// row first), its scope shades (18 to 22) and its peak dots (23).
var WINAMP_SPECTRUM = ["#EF3110", "#CE2910", "#D65A00", "#D66600", "#D67300", "#C67B08", "#DEA518", "#D6B521",
  "#BDDE29", "#94DE21", "#29CE10", "#32BE10", "#39B510", "#319C08", "#299400", "#188408"]
var WINAMP_SCOPE = ["#FFFFFF", "#D6D6DE", "#B5BDBD", "#A0AAAF", "#949CA5"]
var WINAMP_PEAK = "#969696"

function hexChannel(hex, i) {
  return parseInt(String(hex).slice(1 + i * 2, 3 + i * 2), 16)
}

// "#rrggbb" between a (t = 0) and b (t = 1).
function mixHex(a, b, t) {
  var out = "#"
  for (var i = 0; i < 3; i++) {
    var v = Math.round(hexChannel(a, i) + (hexChannel(b, i) - hexChannel(a, i)) * t)
    out += (v < 16 ? "0" : "") + Math.max(0, Math.min(255, v)).toString(16).toUpperCase()
  }
  return out
}

// The colour of each of the sixteen rows, top first. The gradient is the
// accent itself, from dark at the bottom through the accent to near white at
// the top, the way Winamp's climbs from green to red: a single-hue Omarchy
// theme has no second colour far enough from its accent to show, but every
// accent has a light and a dark. accent is "#rrggbb".
function spectrumColors(mode, accent) {
  if (mode === "winamp") return WINAMP_SPECTRUM
  var out = []
  for (var i = 0; i < 16; i++) {
    var up = 1 - i / 15
    out.push(mode !== "gradient" ? accent
      : up >= 0.5 ? mixHex(accent, "#FFFFFF", (up - 0.5) * 2 * 0.7)
      : mixHex(accent, "#000000", (0.5 - up) * 2 * 0.6))
  }
  return out
}

// The colour for a bar lit to this level (0 to 1): the row at its top.
function spectrumColorAt(colors, level) {
  var rows = Math.max(1, Math.min(16, Math.round(Number(level) * 15) + 1))
  return colors[16 - rows]
}

// A VU segment's colour, left to right along the spectrum from its bottom.
function vuSegmentColor(colors, index) {
  return colors[15 - Math.round(Math.max(0, Math.min(VU_SEGMENTS - 1, index)) * 15 / (VU_SEGMENTS - 1))]
}

// The oscilloscope's colour for a row: Winamp's scope shades, dimmer away
// from the middle; a gradient's colour for that row; or null for the accent
// dimmed by scopeBrightness.
function scopeColor(mode, colors, row) {
  if (mode === "winamp") {
    var step = Math.round((1 - scopeBrightness(row)) / 0.12)
    return WINAMP_SCOPE[Math.max(0, Math.min(4, step))]
  }
  if (mode === "gradient") return colors[Math.max(0, Math.min(15, row))]
  return null
}

// The Winamp5 analyser's rows: the bottom one lit, then every other one, so
// every lit stripe and every gap is one row tall.
function winamp5RowLit(rowFromBottom) {
  return rowFromBottom % 2 === 0
}

// Winamp's dot matrix behind the visualisations, on a whole-pixel grid so the
// dots stay evenly spaced at any scale: dots of `size` every `pitch` pixels
// both ways, the grid centred in the area. Draws onto a Canvas 2D context.
function drawDotMatrix(ctx, width, height, pitch, size, color) {
  var p = Math.max(2, Math.round(pitch))
  var d = Math.max(1, Math.min(p - 1, Math.round(size)))
  var cols = Math.floor((width - d) / p) + 1
  var rows = Math.floor((height - d) / p) + 1
  if (cols < 1 || rows < 1) return
  var x0 = Math.floor((width - ((cols - 1) * p + d)) / 2)
  var y0 = Math.floor((height - ((rows - 1) * p + d)) / 2)
  ctx.fillStyle = color
  for (var r = 0; r < rows; r++)
    for (var c = 0; c < cols; c++)
      ctx.fillRect(x0 + c * p, y0 + r * p, d, d)
}

// How much to scale the captured audio back up so the visualisers don't follow
// the player's own volume, as Winamp's don't. The capture is after that
// volume; the widget knows it over MPRIS, but players apply it differently:
// mpv's volume is cubic (50 % plays at an eighth of the level), most others
// (archamp's Webamp among them) linear. Capped at +40 dB; at 0 there is
// nothing to recover and 1 is sent.
var MAX_VISUALISER_GAIN = 100

function volumeIsCubic(busName) {
  return /^org\.mpris\.MediaPlayer2\.mpv(\.|$)/.test(String(busName || ""))
}

function visualiserGain(volume, cubic) {
  var v = Number(volume)
  if (!isFinite(v) || v <= 0 || v >= 1) return 1
  var level = cubic ? v * v * v : v
  return Math.min(MAX_VISUALISER_GAIN, 1 / level)
}

// Fixed frames for the snapshots on the settings column's visualisation
// picker: what each one looks like mid-song, without running the analyser.
var PREVIEW_BARS = [0.8, 0.93, 0.87, 0.73, 0.8, 0.6, 0.67, 0.53, 0.6, 0.47, 0.4, 0.47, 0.33, 0.4, 0.27, 0.2, 0.27, 0.13, 0.07]
var PREVIEW_PEAKS = [0.93, 1, 0.93, 0.87, 0.87, 0.73, 0.73, 0.67, 0.67, 0.6, 0.53, 0.53, 0.47, 0.47, 0.33, 0.33, 0.33, 0.2, 0.13]

// The oscilloscope's columns for a made-up wave, drawn exactly as
// spectrum.py's scope_columns does: each sample to a row, joined to the last.
function previewScope() {
  var columns = []
  var last = 0
  for (var x = 0; x < 75; x++) {
    var v = 0.55 * Math.sin(x * 0.42) + 0.25 * Math.sin(x * 1.3 + 1) + 0.1 * Math.sin(x * 3.1)
    var b = Math.max(0, Math.min(255, Math.floor(128 * (1 + v))))
    var y = Math.max(0, Math.min(15, Math.floor(b / 16 * 2 + 0.5) - 9))
    if (x === 0) last = y
    var top = y, bottom = last
    last = y
    if (bottom < top) { var t = top; top = bottom; bottom = t; top += 1 }
    columns.push({ top: top, bottom: bottom, row: y })
  }
  return columns
}

// The VU meter, from spectrum.py --vu: "v|left,right|left peak,right peak",
// each 0-1. Anything missing or malformed reads as silence.
var VU_SEGMENTS = 19

function parseVuFrame(line) {
  var frame = { levels: [0, 0], peaks: [0, 0] }
  var text = String(line === undefined || line === null ? "" : line)
  if (text.indexOf("v|") !== 0) return frame
  var halves = text.slice(2).split("|")
  function read(part, into) {
    var values = String(part || "").split(",")
    for (var i = 0; i < 2; i++) {
      var v = parseFloat(values[i])
      into[i] = isFinite(v) ? Math.max(0, Math.min(1, v)) : 0
    }
  }
  read(halves[0], frame.levels)
  read(halves[1], frame.peaks)
  return frame
}

// How many of a meter's segments are lit, and which one shows the peak (-1 for
// none). The peak segment is the last one it reaches, never below the level.
function vuLit(level) {
  return Math.round(Math.max(0, Math.min(1, level)) * VU_SEGMENTS)
}

function vuPeakSegment(peak, level) {
  var p = Math.max(vuLit(peak), vuLit(level))
  return p > 0 ? p - 1 : -1
}

function visualisation(value) {
  return VISUALISATIONS.indexOf(value) !== -1 ? value : "analyser"
}

function nextVisualisation(value) {
  return VISUALISATIONS[(VISUALISATIONS.indexOf(visualisation(value)) + 1) % VISUALISATIONS.length]
}

// Every choice the plugin offers, made in the popup (the settings column,
// the visualiser, PLAYERS, the library) and kept in preferences.json; none
// lives only in the shell's config. Read back defensively: anything missing
// or unexpected is its default.
var SEEK_STEPS = [5, 10, 15, 30]

// The skip buttons' glyphs, each showing its step: Material Design's rewind
// and fast-forward 5, 10, 15 and 30. Any other step gets the plain ones.
function skipIcon(step, forward) {
  var icons = forward
    ? { 5: "\u{F11F8}", 10: "\u{F0D71}", 15: "\u{F193A}", 30: "\u{F0D06}" }
    : { 5: "\u{F11F9}", 10: "\u{F0D2A}", 15: "\u{F1946}", 30: "\u{F0D96}" }
  return icons[step] || (forward ? "\u{F0211}" : "\u{F045F}")
}
var VOLUME_STEPS = [2, 5, 10]

function preferenceDefaults() {
  return {
    visualisation: "analyser",
    visColour: "gradient",
    pauseOthers: false,
    libraryDir: "",
    musicFolder: "",       // "" is the desktop's music folder
    playlistFolder: "",    // "" is Playlists inside the music folder
    musicPlayer: "",       // a desktop file id, or "" for the desktop's default
    onlineLyrics: true,
    webArt: true,
    rememberStations: true,
    hideWhenIdle: false,
    titleWidth: 260,       // the bar title's widest, in px; 0 is its full length
    scrollTitle: true,     // a bar title too long for its width scrolls
    updateCheck: true,     // ask GitHub for a newer release once a day
    updateDismissed: "",   // the release whose notice was dismissed
    settingsMigrated: false,
    seekStep: 5,
    volumeStep: 5,
  }
}

// How wide the bar's title may grow: a few widths, or its full length (0).
var TITLE_WIDTHS = [160, 260, 0]

// 1.0 kept four settings in the shell's config (Omarchy's plugin settings);
// 2.0 keeps every setting in the popup. On 2.0's first run, the ones a user
// had set carry over: hide when idle and pause others as they were, the
// title width to the nearest width offered (Full standing in for 1.0's
// widest, 600, which was as good as the whole title), and the analyser
// switched off to the Off visualisation. settings is the widget's config object; only values
// actually present count, so defaults never overwrite a choice.
function migrateSettings(prefs, settings) {
  var out = Object.assign({}, prefs)
  var s = settings && typeof settings === "object" ? settings : {}
  if (typeof s.hideWhenIdle === "boolean") out.hideWhenIdle = s.hideWhenIdle
  if (typeof s.pauseOthers === "boolean") out.pauseOthers = s.pauseOthers
  if (s.visualizerEnabled === false) out.visualisation = "off"
  var width = Number(s.maxLabelWidth)
  if (s.maxLabelWidth !== undefined && s.maxLabelWidth !== null && isFinite(width)) {
    var nearest = TITLE_WIDTHS.reduce(function(best, w) {
      var d = Math.abs((w > 0 ? w : 600) - width), bestD = Math.abs((best > 0 ? best : 600) - width)
      return d < bestD || (d === bestD && w === 0) ? w : best
    })
    out.titleWidth = nearest
  }
  out.settingsMigrated = true
  return out
}

function isDesktopId(value) {
  return typeof value === "string" && value.length <= 255 && /^[A-Za-z0-9._-]+\.desktop$/.test(value)
}

function parsePreferences(text) {
  var prefs = preferenceDefaults()
  if (typeof text !== "string" || text.length > 16384) return prefs
  var data
  try { data = JSON.parse(text) } catch (e) { return prefs }
  if (!data || data.version !== 1) return prefs
  prefs.visualisation = visualisation(data.visualisation)
  prefs.visColour = visColour(data.visColour)
  prefs.pauseOthers = data.pauseOthers === true
  prefs.libraryDir = cleanPath(data.libraryDir)
  prefs.musicFolder = cleanPath(data.musicFolder)
  prefs.playlistFolder = cleanPath(data.playlistFolder)
  prefs.musicPlayer = isDesktopId(data.musicPlayer) ? data.musicPlayer : ""
  prefs.onlineLyrics = data.onlineLyrics !== false
  prefs.webArt = data.webArt !== false
  prefs.rememberStations = data.rememberStations !== false
  prefs.hideWhenIdle = data.hideWhenIdle === true
  prefs.seekStep = SEEK_STEPS.indexOf(data.seekStep) !== -1 ? data.seekStep : 5
  prefs.volumeStep = VOLUME_STEPS.indexOf(data.volumeStep) !== -1 ? data.volumeStep : 5
  prefs.titleWidth = TITLE_WIDTHS.indexOf(data.titleWidth) !== -1 ? data.titleWidth : 260
  prefs.scrollTitle = data.scrollTitle !== false
  prefs.updateCheck = data.updateCheck !== false
  prefs.updateDismissed = parseVersion(data.updateDismissed) ? String(data.updateDismissed) : ""
  prefs.settingsMigrated = data.settingsMigrated === true
  return prefs
}

function serializePreferences(prefs) {
  // Through the parser, so only valid values are ever written.
  var clean = parsePreferences(JSON.stringify(Object.assign({ version: 1 }, prefs || {})))
  return JSON.stringify(Object.assign({ version: 1 }, clean), null, 2) + "\n"
}

// The applications `gio mime audio/mpeg` recommends, as desktop file ids.
function parseGioMime(text) {
  var ids = []
  if (typeof text !== "string" || text.length > 65536) return ids
  var lines = text.split(/\r?\n/)
  var inRecommended = false
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (/^Recommended applications:/.test(line)) { inRecommended = true; continue }
    if (/^\S/.test(line)) { inRecommended = false; continue }
    var id = line.trim()
    if (inRecommended && isDesktopId(id) && ids.indexOf(id) === -1) ids.push(id)
  }
  return ids.slice(0, 20)
}

// A desktop file's Name, from its [Desktop Entry] group; "" if there is none.
function desktopEntryName(text) {
  if (typeof text !== "string" || text.length > 262144) return ""
  var group = ""
  var lines = text.split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var g = /^\[(.+)\]\s*$/.exec(lines[i])
    if (g) { group = g[1]; continue }
    var m = /^Name\s*=\s*(.+)$/.exec(lines[i])
    if (m && group === "Desktop Entry") return m[1].replace(/[\u0000-\u001f\u007f]/g, "").trim().slice(0, 100)
  }
  return ""
}

// A name for a desktop id when its file can't be read: "org.kde.kdenlive" -> "kdenlive".
function desktopIdLabel(id) {
  var base = String(id || "").replace(/\.desktop$/, "")
  var parts = base.split(".")
  return parts[parts.length - 1] || base
}

// The path zenity prints for a chosen folder, or "".
function parseChosenFolder(text) {
  return cleanPath(String(text || "").replace(/\r?\n$/, ""))
}

// ----------------------------------------------------------------- library
//
// The music browser opened by the eject button, as in Winamp. It starts in
// the user's music folder and never leaves it.

// An absolute path with no control characters, no "." or ".." segments and
// no trailing slash, or "".
function cleanPath(value) {
  var p = firstText(value)
  if (!p || p.charAt(0) !== "/" || p.length > MAX_PATH_LENGTH) return ""
  if (/[\u0000-\u001f\u007f]/.test(p)) return ""
  var parts = p.split("/")
  for (var i = 1; i < parts.length; i++) {
    if (parts[i] === "." || parts[i] === "..") return ""
  }
  if (p.length > 1 && p.charAt(p.length - 1) === "/") p = p.slice(0, -1)
  return p
}

// The music folder: what xdg-user-dir reports, else ~/Music.
function libraryRoot(xdgMusicDir, home) {
  var reported = cleanPath(xdgMusicDir)
  var h = cleanPath(home)
  // xdg-user-dir falls back to $HOME itself when no music folder is set.
  if (reported && reported !== h) return reported
  return h ? (h === "/" ? "/Music" : h + "/Music") : ""
}

function isInside(root, path) {
  var r = cleanPath(root), p = cleanPath(path)
  if (!r || !p) return false
  return p === r || p.indexOf(r === "/" ? "/" : r + "/") === 0
}

// Where a remembered or navigated folder may be: inside the library, else the
// library itself.
function libraryFolder(root, path) {
  return isInside(root, path) ? cleanPath(path) : cleanPath(root)
}

function parentFolder(root, path) {
  var p = libraryFolder(root, path)
  if (p === cleanPath(root)) return p
  var up = p.slice(0, p.lastIndexOf("/")) || "/"
  return libraryFolder(root, up)
}

// "Music / Journey / Greatest Hits 2": the folder, named from the library's
// own name down.
function libraryCrumb(root, path) {
  var r = cleanPath(root), p = libraryFolder(root, path)
  if (!r) return ""
  var rootName = r.slice(r.lastIndexOf("/") + 1) || "/"
  var rest = p.slice(r.length).split("/").filter(function(s) { return s !== "" })
  return [rootName].concat(rest).join(" / ")
}

// A path as a file:// URI, each segment percent-encoded, for MPRIS OpenUri.
function pathToFileUri(path) {
  var p = cleanPath(path)
  if (!p) return ""
  return "file://" + p.split("/").map(function(s) { return encodeURIComponent(s) }).join("/")
}

// Selecting tracks, Winamp style: a click toggles one, a shift-click adds the
// run between the last click and this one. The selection keeps the order the
// tracks were picked in, across folders, and that is the order they play.
var MAX_SELECTION = 1000

function toggleSelection(selection, path) {
  var list = Array.isArray(selection) ? selection.slice() : []
  var p = cleanPath(path)
  if (!p) return list
  var i = list.indexOf(p)
  if (i !== -1) list.splice(i, 1)
  else if (list.length < MAX_SELECTION) list.push(p)
  return list
}

// How many selected tracks are not in the folder being shown, so a selection
// carried over from other folders is never invisible.
function selectedElsewhere(selection, folderPaths) {
  var list = Array.isArray(selection) ? selection : []
  var paths = (Array.isArray(folderPaths) ? folderPaths : []).map(cleanPath)
  return list.filter(function(p) { return paths.indexOf(p) === -1 }).length
}

// folderPaths is the current folder's tracks in the order shown.
function selectRange(selection, folderPaths, anchor, path) {
  var list = Array.isArray(selection) ? selection.slice() : []
  var paths = Array.isArray(folderPaths) ? folderPaths : []
  var a = paths.indexOf(anchor), b = paths.indexOf(path)
  if (a === -1 || b === -1) return toggleSelection(list, path)
  var from = Math.min(a, b), to = Math.max(a, b)
  for (var i = from; i <= to && list.length < MAX_SELECTION; i++) {
    var p = cleanPath(paths[i])
    if (p && list.indexOf(p) === -1) list.push(p)
  }
  return list
}

// An M3U playlist of the selection, for a player that takes one item at a
// time over MPRIS. Paths are cleaned; a line break would start a new entry,
// so anything unclean is dropped.
function playlistText(paths) {
  var lines = ["#EXTM3U"]
  var list = Array.isArray(paths) ? paths : []
  for (var i = 0; i < list.length && i < MAX_SELECTION; i++) {
    var p = cleanPath(list[i])
    if (p) lines.push(p)
  }
  return lines.join("\n") + "\n"
}

// ---------------------------------------------------------------- playlists
//
// Saved playlists are M3U files in "Playlists" inside the music folder (or a
// folder chosen in Settings), so
// they belong to no one player: mpv and archamp both play them. An entry
// keeps where the track is and, when the file gave one, its #EXTINF line, so
// editing someone else's playlist doesn't lose its titles.
var PLAYLISTS_FOLDER = "Playlists"
var PLAYLIST_NAME_FILTERS = ["*.m3u", "*.m3u8"]
var MAX_PLAYLIST_ENTRIES = 5000
var MAX_PLAYLIST_NAME = 80

function playlistsFolder(root) {
  var r = cleanPath(root)
  return r ? (r === "/" ? "" : r) + "/" + PLAYLISTS_FOLDER : ""
}

// The file name for a typed name: no slashes, control characters or leading
// dots, spaces collapsed, at most MAX_PLAYLIST_NAME characters. "" when
// nothing usable is left.
function playlistFileName(name) {
  var n = String(name === undefined || name === null ? "" : name)
    .replace(/[\u0000-\u001f\u007f\/\\]/g, " ")
    .replace(/\s+/g, " ")
    .replace(/^[.\s]+/, "")
    .trim()
  if (/\.m3u8?$/i.test(n)) n = n.replace(/\.m3u8?$/i, "").trim()
  if (n.length > MAX_PLAYLIST_NAME) n = n.slice(0, MAX_PLAYLIST_NAME).trim()
  return n ? n + ".m3u" : ""
}

// A playlist file's name as shown.
function playlistDisplayName(fileName) {
  var f = firstText(fileName)
  f = f.slice(f.lastIndexOf("/") + 1)
  return f.replace(/\.m3u8?$/i, "")
}

// Whether a name is taken by another file in the folder, ignoring case, as
// the file names differ only by case would confuse anyone.
function playlistNameTaken(fileNames, fileName, except) {
  var want = String(fileName || "").toLowerCase()
  var skip = String(except || "").toLowerCase()
  if (!want) return false
  return (Array.isArray(fileNames) ? fileNames : []).some(function(f) {
    var name = String(f || "").toLowerCase()
    return name === want && name !== skip
  })
}

// An M3U's entries: [{ location, info }]. Relative paths are resolved against
// the playlist's folder, file:// URLs become paths, and anything else (a
// stream URL) is kept as written. Comments other than #EXTINF are dropped.
function parseM3u(text, folder) {
  var out = []
  if (typeof text !== "string" || text.length > 4000000) return out
  var base = cleanPath(folder)
  var info = ""
  var lines = text.replace(/^﻿/, "").split(/\r?\n/)
  for (var i = 0; i < lines.length && out.length < MAX_PLAYLIST_ENTRIES; i++) {
    var line = lines[i].trim()
    if (!line) continue
    if (line.charAt(0) === "#") {
      if (/^#EXTINF:/i.test(line) && line.length <= 2000) info = line
      continue
    }
    var location = ""
    if (/^file:\/\//i.test(line)) location = fileUrlToPath(line)
    else if (line.charAt(0) === "/") location = cleanPath(line)
    else if (/^[a-z][a-z0-9+.-]*:\/\//i.test(line)) location = /[\u0000-\u001f\u007f]/.test(line) ? "" : line
    else if (base) location = cleanPath(base + "/" + line)
    if (location) out.push({ location: location, info: info })
    info = ""
  }
  return out
}

function serializeM3u(entries) {
  var lines = ["#EXTM3U"]
  var list = Array.isArray(entries) ? entries : []
  for (var i = 0; i < list.length && i < MAX_PLAYLIST_ENTRIES; i++) {
    var e = list[i] || {}
    var location = String(e.location || "")
    if (!location || /[\u0000-\u001f\u007f]/.test(location)) continue
    var info = String(e.info || "")
    if (/^#EXTINF:/i.test(info) && !/[\u0000-\u001f\u007f]/.test(info)) lines.push(info)
    lines.push(location)
  }
  return lines.join("\n") + "\n"
}

function entriesFromPaths(paths) {
  return (Array.isArray(paths) ? paths : [])
    .map(function(p) { return { location: cleanPath(p), info: "" } })
    .filter(function(e) { return e.location !== "" })
}

// How an entry reads in the list: the #EXTINF title when there is one, else
// the file name without its extension; the folder it's in beneath.
function playlistEntryLabel(entry) {
  var e = entry || {}
  var location = String(e.location || "")
  var m = /^#EXTINF:[^,]*,(.*)$/i.exec(String(e.info || ""))
  var file = location.slice(location.lastIndexOf("/") + 1)
  var title = m && m[1].trim() ? m[1].trim() : file.replace(/\.[^.]{1,5}$/, "")
  var folder = ""
  if (location.charAt(0) === "/") {
    var dir = location.slice(0, location.lastIndexOf("/"))
    folder = dir.slice(dir.lastIndexOf("/") + 1)
  }
  return { title: title || location, folder: folder }
}

// The saved playlist a player's queue is, when it matches one track for
// track: saved is { fileName: [paths] }. Players without the MPRIS Playlists
// interface can't name what they're playing, but a queue that is exactly a
// saved playlist is that playlist. "" when none matches.
function matchingPlaylistName(queuePaths, saved) {
  return playlistDisplayName(matchingPlaylistFile(queuePaths, saved))
}

// The file name of that playlist, or "".
function matchingPlaylistFile(queuePaths, saved) {
  var q = Array.isArray(queuePaths) ? queuePaths : []
  if (q.length === 0 || !saved) return ""
  var names = Object.keys(saved).sort()
  for (var i = 0; i < names.length; i++) {
    var paths = saved[names[i]]
    if (!Array.isArray(paths) || paths.length !== q.length) continue
    var same = true
    for (var j = 0; j < q.length && same; j++) same = paths[j] === q[j]
    if (same) return names[i]
  }
  return ""
}

// How a player's queue stands against the saved playlist it was loaded from:
// "same" track for track, "edited" when it differs but shares tracks, or
// "unrelated" when it shares none (the player has loaded something else). An
// empty queue is still loading, so it reads "same" rather than breaking the
// link.
function playlistLinkState(queuePaths, fileLocations) {
  var q = Array.isArray(queuePaths) ? queuePaths : []
  var f = Array.isArray(fileLocations) ? fileLocations : []
  if (q.length === 0) return "same"
  if (q.length === f.length && q.every(function(p, i) { return p === f[i] })) return "same"
  return q.some(function(p) { return f.indexOf(p) !== -1 }) ? "edited" : "unrelated"
}

// Entries for saving tracks back over a playlist file, keeping the #EXTINF
// line the file had for each track.
function entriesWithInfo(paths, oldEntries) {
  var info = {}
  ;(Array.isArray(oldEntries) ? oldEntries : []).forEach(function(e) {
    if (e && e.location && e.info && !(e.location in info)) info[e.location] = e.info
  })
  return entriesFromPaths(paths).map(function(e) {
    return { location: e.location, info: info[e.location] || "" }
  })
}

// busctl arguments for adding tracks to a player's TrackList, in order, at
// the end: each is added right after the list's last track, so they go in
// last first. afterId is that last track, or NoTrack for an empty list.
var NO_TRACK = "/org/mpris/MediaPlayer2/TrackList/NoTrack"

function addTrackCommands(busName, paths, afterId) {
  var name = String(busName || "")
  var after = isObjectPath(afterId) ? afterId : NO_TRACK
  var out = []
  var list = Array.isArray(paths) ? paths : []
  for (var i = Math.min(list.length, MAX_SELECTION) - 1; i >= 0; i--) {
    var uri = pathToFileUri(list[i])
    if (!uri) continue
    out.push(["busctl", "--user", "call", name, "/org/mpris/MediaPlayer2",
      "org.mpris.MediaPlayer2.TrackList", "AddTrack", "sob", uri, after, "false"])
  }
  return out
}

function appendEntries(entries, paths) {
  var list = Array.isArray(entries) ? entries.slice() : []
  var more = entriesFromPaths(paths)
  return list.concat(more).slice(0, MAX_PLAYLIST_ENTRIES)
}

function removeEntry(entries, index) {
  var list = Array.isArray(entries) ? entries.slice() : []
  if (index >= 0 && index < list.length) list.splice(index, 1)
  return list
}

function moveEntry(entries, index, delta) {
  var list = Array.isArray(entries) ? entries.slice() : []
  var to = index + delta
  if (index < 0 || index >= list.length || to < 0 || to >= list.length) return list
  var item = list.splice(index, 1)[0]
  list.splice(to, 0, item)
  return list
}

// ------------------------------------------------------------------- video
//
// A live preview of the player's window in place of the album art, for
// players that show video. MPRIS says nothing about video, and an audio
// player's window (archamp's Winamp skin) would make a poor cover, so it is
// offered only to browsers and known video players.
function isVideoPlayer(busName, identity, desktopEntry, chromium) {
  if (chromium) return true
  if (/^org\.mpris\.MediaPlayer2\.(mpv|vlc)(\.|$)/.test(String(busName || ""))) return true
  return /\b(vlc|celluloid|haruna|totem|videos|smplayer|mpv)\b/i.test(String(identity || "") + " " + String(desktopEntry || ""))
}

// Whether a window is an installed web app rather than the browser itself:
// Chromium names those by site and profile, "brave-discord.com__channels_@me-Default".
function isWebAppWindow(windowClass) {
  return String(windowClass || "").indexOf("__") !== -1
}

// Which of the windows is the player's: those of the process that owns its
// MPRIS name, and, where one process has many windows (a browser) or the
// caller asks for it, the one whose title names the track. A page's title
// doesn't always (YouTube TV's reads "Home - YouTube TV" while it reports the
// channel), so a browser with exactly one ordinary window, web apps aside,
// uses that. windows is [{ pid, title, windowClass }]; returns an index, or -1.
function chooseVideoWindow(windows, pid, trackTitle, requireTitle) {
  var list = Array.isArray(windows) ? windows : []
  var p = Number(pid)
  if (!isFinite(p) || p <= 0) return -1
  var mine = []
  for (var i = 0; i < list.length; i++) if (list[i] && Number(list[i].pid) === p) mine.push(i)
  if (mine.length === 0) return -1
  var t = firstText(trackTitle).toLowerCase()
  if (t) {
    for (var j = 0; j < mine.length; j++) {
      if (firstText(list[mine[j]].title).toLowerCase().indexOf(t) !== -1) return mine[j]
    }
  }
  if (!requireTitle) return mine.length === 1 ? mine[0] : -1
  var ordinary = mine.filter(function(k) { return !isWebAppWindow(list[k].windowClass) })
  return ordinary.length === 1 ? ordinary[0] : -1
}

// The preview's height as a share of its width: the window's own shape,
// kept between a letterbox and a square so an odd window can't take over
// the popup.
function videoAspect(width, height) {
  var w = Number(width), h = Number(height)
  if (!isFinite(w) || !isFinite(h) || w <= 0 || h <= 0) return 9 / 16
  return Math.max(0.4, Math.min(1, h / w))
}

// A lost feed: an app can stop drawing a window it thinks nobody sees (a
// browser on another workspace), and the preview then holds a still frame.
// The preview is sampled every two seconds; while the player says it is
// playing, this many samples in a row that match to the pixel mean the feed
// has stopped. Live video, even a still-looking shot, is never pixel-identical
// for that long.
var FEED_STALL_SAMPLES = 4

// Whether two samples (flat pixel arrays) are the same frame.
function sameFrame(a, b) {
  if (!a || !b || a.length !== b.length || a.length === 0) return false
  for (var i = 0; i < a.length; i++)
    if (a[i] !== b[i]) return false
  return true
}

// The run of identical samples after one more: back to zero on any change,
// and while paused, when a still frame is expected.
function nextStallCount(count, same, playing) {
  return playing && same ? count + 1 : 0
}

function feedLost(hasContent, stallCount) {
  return !hasContent || stallCount >= FEED_STALL_SAMPLES
}

// busctl ... GetConnectionUnixProcessID: "u 2128699"
function parseBusctlUint(line) {
  var m = /^\s*u\s+(\d{1,10})\s*$/.exec(String(line || ""))
  return m ? Number(m[1]) : 0
}

// ---------------------------------------------------------------- playlist
//
// A player's playlist, from the MPRIS TrackList interface, which Quickshell
// does not expose: read with busctl --json=short. Track IDs are D-Bus object
// paths chosen by the player, so each is checked before it is passed back.

var MAX_PLAYLIST_TRACKS = 5000

function isObjectPath(value) {
  var p = String(value === undefined || value === null ? "" : value)
  return p.length > 0 && p.length <= 512 && /^\/([A-Za-z0-9_]+(\/[A-Za-z0-9_]+)*)?$/.test(p)
}

// A track ID as a plain path. Quickshell hands mpris:trackid over as a wrapped
// D-Bus object path, which reads as
// QVariant(QDBusObjectPath, QDBusObjectPath("/org/archamp/track/13")) when
// turned into text. "" for anything that is not a valid object path.
function objectPathText(value) {
  if (isObjectPath(value)) return String(value)
  var m = /QDBusObjectPath\("([^"]{1,512})"\)/.exec(String(value === undefined || value === null ? "" : value))
  return m && isObjectPath(m[1]) ? m[1] : ""
}

// busctl --json=short get-property ... Tracks: {"type":"ao","data":[...]}
function parseTrackIds(text) {
  if (typeof text !== "string" || text.length > 2000000) return []
  try {
    var data = JSON.parse(text)
    if (!data || data.type !== "ao" || !Array.isArray(data.data)) return []
    return data.data.filter(isObjectPath).slice(0, MAX_PLAYLIST_TRACKS)
  } catch (e) {
    return []
  }
}

// busctl --json=short call ... GetTracksMetadata: {"type":"aa{sv}","data":[[{...},...]]}
// Each entry keyed by its mpris:trackid, with title, artist and length (s).
function parseTracksMetadata(text) {
  var out = {}
  if (typeof text !== "string" || text.length > 8000000) return out
  var data
  try { data = JSON.parse(text) } catch (e) { return out }
  var list = data && Array.isArray(data.data) && Array.isArray(data.data[0]) ? data.data[0] : []
  function value(entry, key) { return entry && entry[key] ? entry[key].data : undefined }
  for (var i = 0; i < list.length && i < MAX_PLAYLIST_TRACKS; i++) {
    var e = list[i]
    var id = value(e, "mpris:trackid")
    if (!isObjectPath(id)) continue
    var length = Number(value(e, "mpris:length"))
    out[id] = {
      title: firstText(value(e, "xesam:title")).slice(0, 500),
      artist: firstText(value(e, "xesam:artist")).slice(0, 500),
      length: isFinite(length) && length > 0 && length < 1e14 ? length / 1e6 : 0,
      path: fileUrlToPath(firstText(value(e, "xesam:url"))),
    }
  }
  return out
}

// A playlist position as shown: at least two digits, and as many as the
// list's longest number, so the column lines up.
function trackNumber(n, count) {
  var width = Math.max(2, String(Math.max(0, Math.floor(Number(count) || 0))).length)
  var text = String(Math.max(0, Math.floor(Number(n) || 0)))
  while (text.length < width) text = "0" + text
  return text
}

// The active playlist's name, from the MPRIS Playlists interface, which a
// player may implement alongside TrackList: ActivePlaylist is (b(oss)), a
// valid flag and (id, name, icon). busctl --json=short gives
// {"type":"(b(oss))","data":[true,["/id","Name",""]]}. "" when there is none,
// so the bar falls back to PLAYLIST.
function activePlaylistName(text) {
  if (typeof text !== "string" || text.length > 65536) return ""
  try {
    var data = JSON.parse(text)
    if (!data || data.type !== "(b(oss))" || !Array.isArray(data.data) || data.data[0] !== true) return ""
    var playlist = data.data[1]
    if (!Array.isArray(playlist) || typeof playlist[1] !== "string") return ""
    return playlist[1].replace(/[\u0000-\u001f\u007f]/g, "").trim().slice(0, 200)
  } catch (e) {
    return ""
  }
}

// The heading for the playlist bar: the playlist's name in capitals, else
// PLAYLIST.
function playlistHeading(name) {
  var n = firstText(name)
  return n ? n.toUpperCase() : "PLAYLIST"
}

// Where playback stands in the playlist: the current track's place (1-based),
// how many there are, the time played through the list so far (earlier
// tracks in full, plus the position in this one) and the list's total. Tracks
// with no length count as zero. index is 0 when the current track is not in
// the list.
function playlistProgress(ids, meta, currentId, positionSeconds) {
  var list = Array.isArray(ids) ? ids : []
  var m = meta || {}
  var index = list.indexOf(currentId)
  var total = 0, before = 0
  for (var i = 0; i < list.length; i++) {
    var len = m[list[i]] ? m[list[i]].length : 0
    total += len
    if (index !== -1 && i < index) before += len
  }
  var pos = typeof positionSeconds === "number" && isFinite(positionSeconds) && positionSeconds > 0 ? positionSeconds : 0
  var currentLen = index !== -1 && m[currentId] ? m[currentId].length : 0
  if (currentLen > 0) pos = Math.min(pos, currentLen)
  return {
    index: index + 1,
    count: list.length,
    elapsed: index === -1 ? 0 : before + pos,
    total: total,
  }
}

// ------------------------------------------------------------------ lyrics
//
// Synced lyrics in LRC form ("[01:23.45]A line"), from a .lrc beside a local
// file or from LRCLIB. Everything read here comes from a file or a web
// service, so it is bounded and only ever shown as plain text.

var MAX_LYRIC_LINES = 2000
var MAX_LYRIC_LINE_LENGTH = 500
var MAX_LYRICS_TEXT = 256000

// Lines with times, sorted, or, for lyrics with no timestamps, the plain lines
// with a time of -1. Metadata tags such as [ar:] are skipped; [offset:] shifts
// every time, as the format defines (positive plays lines earlier).
function parseLrc(text) {
  var result = { synced: false, lines: [] }
  if (typeof text !== "string" || text.length === 0) return result
  var source = text.length > MAX_LYRICS_TEXT ? text.slice(0, MAX_LYRICS_TEXT) : text
  var raw = source.split(/\r?\n/)
  var offset = 0
  var timed = [], plain = []
  var stamp = /\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g
  for (var i = 0; i < raw.length && timed.length + plain.length < MAX_LYRIC_LINES; i++) {
    var line = raw[i]
    var off = /^\s*\[offset:\s*([+-]?\d{1,6})\s*\]\s*$/i.exec(line)
    if (off) { offset = Number(off[1]) / 1000; continue }
    if (/^\s*\[[a-z]{2,}:[^\]]*\]\s*$/i.test(line)) continue
    var times = []
    stamp.lastIndex = 0
    var m, last = 0
    while ((m = stamp.exec(line)) !== null && m.index === last) {
      var frac = m[3] ? Number("0." + m[3]) : 0
      times.push(Number(m[1]) * 60 + Number(m[2]) + frac)
      last = stamp.lastIndex
    }
    var words = line.slice(last).replace(/[\u0000-\u001f\u007f]/g, "").trim()
    if (words.length > MAX_LYRIC_LINE_LENGTH) words = words.slice(0, MAX_LYRIC_LINE_LENGTH)
    if (times.length > 0) {
      for (var t = 0; t < times.length; t++) timed.push({ time: Math.max(0, times[t] - offset), text: words })
    } else if (words !== "") {
      plain.push({ time: -1, text: words })
    }
  }
  if (timed.length > 0) {
    timed.sort(function(a, b) { return a.time - b.time })
    result.synced = true
    result.lines = timed.slice(0, MAX_LYRIC_LINES)
  } else {
    result.lines = plain
  }
  return result
}

// The line being sung at a position: the last one that has started. -1 before
// the first. A small lead shows each line just as it begins rather than late.
var LYRIC_LEAD_SECONDS = 0.25

function activeLyricIndex(lines, position) {
  if (!Array.isArray(lines) || typeof position !== "number" || !isFinite(position)) return -1
  var t = position + LYRIC_LEAD_SECONDS
  var lo = 0, hi = lines.length - 1, found = -1
  while (lo <= hi) {
    var mid = (lo + hi) >> 1
    if (lines[mid].time <= t) { found = mid; lo = mid + 1 } else hi = mid - 1
  }
  return found
}

// The .lrc a local track would have beside it: same name, .lrc extension.
function lrcPathFor(audioPath) {
  var p = cleanPath(audioPath)
  if (!p) return ""
  var slash = p.lastIndexOf("/"), dot = p.lastIndexOf(".")
  var base = dot > slash + 1 ? p.slice(0, dot) : p
  return base + ".lrc"
}

var LRCLIB_BASE = "https://lrclib.net/api/"

// LRCLIB's exact lookup, when the track's length is known (it matches within
// two seconds), else its search. "" when there is not enough to ask about.
function lrclibUrl(artist, title, album, lengthSeconds) {
  var a = firstText(artist), t = firstText(title), al = firstText(album)
  if (!a || !t || a.length > 300 || t.length > 300) return ""
  var q = "artist_name=" + encodeURIComponent(a) + "&track_name=" + encodeURIComponent(t)
  var len = Math.round(Number(lengthSeconds))
  if (isFinite(len) && len > 0 && len < 7200) {
    return LRCLIB_BASE + "get?" + q + (al && al.length <= 300 ? "&album_name=" + encodeURIComponent(al) : "") + "&duration=" + len
  }
  return LRCLIB_BASE + "search?" + q
}

// A /get response is one record; /search returns a list, of which the first
// with synced lyrics wins, else the first with plain ones.
function parseLrclib(text) {
  var none = { found: false, instrumental: false, lyrics: { synced: false, lines: [] } }
  if (typeof text !== "string" || text.length === 0 || text.length > 2000000) return none
  var data
  try { data = JSON.parse(text) } catch (e) { return none }
  var record = data
  if (Array.isArray(data)) {
    record = null
    for (var i = 0; i < data.length && i < 50; i++) {
      if (data[i] && typeof data[i].syncedLyrics === "string" && data[i].syncedLyrics) { record = data[i]; break }
    }
    if (!record) {
      for (var j = 0; j < data.length && j < 50; j++) {
        if (data[j] && (data[j].instrumental === true || (typeof data[j].plainLyrics === "string" && data[j].plainLyrics))) { record = data[j]; break }
      }
    }
  }
  if (!record || typeof record !== "object") return none
  if (record.instrumental === true) return { found: true, instrumental: true, lyrics: { synced: false, lines: [] } }
  var synced = typeof record.syncedLyrics === "string" ? parseLrc(record.syncedLyrics) : { synced: false, lines: [] }
  if (synced.synced && synced.lines.length > 0) return { found: true, instrumental: false, lyrics: synced }
  var plain = typeof record.plainLyrics === "string" ? parseLrc(record.plainLyrics) : { synced: false, lines: [] }
  if (plain.lines.length > 0) return { found: true, instrumental: false, lyrics: plain }
  return none
}

// What the plugin keeps between sessions so a song is looked up once: a
// bounded list of lookups, found or not, newest first. A miss is retried
// after a week, in case someone has added the lyrics since.
var MAX_LYRICS_CACHE = 60
var LYRICS_MISS_RETRY_MS = 7 * 24 * 60 * 60 * 1000

function lyricsKey(artist, title, album, lengthSeconds) {
  var len = Math.round(Number(lengthSeconds))
  return [firstText(artist), firstText(title), firstText(album), isFinite(len) && len > 0 ? len : 0].join("\u001f").toLowerCase()
}

function parseLyricsCache(text) {
  if (typeof text !== "string" || text.length > 8000000) return []
  try {
    var data = JSON.parse(text)
    if (!data || data.version !== 1 || !Array.isArray(data.entries)) return []
    var out = []
    for (var i = 0; i < data.entries.length && out.length < MAX_LYRICS_CACHE; i++) {
      var e = data.entries[i]
      if (!e || typeof e.key !== "string" || e.key.length > 1400 || typeof e.at !== "number") continue
      out.push({ key: e.key, at: e.at, found: e.found === true, instrumental: e.instrumental === true,
        text: typeof e.text === "string" && e.text.length <= MAX_LYRICS_TEXT ? e.text : "" })
    }
    return out
  } catch (err) {
    return []
  }
}

function cachedLyrics(cache, key, nowMs) {
  if (!Array.isArray(cache)) return null
  for (var i = 0; i < cache.length; i++) {
    var e = cache[i]
    if (e.key !== key) continue
    if (!e.found && nowMs - e.at > LYRICS_MISS_RETRY_MS) return null
    return e
  }
  return null
}

function rememberLyrics(cache, entry) {
  var list = Array.isArray(cache) ? cache.filter(function(e) { return e.key !== entry.key }) : []
  list.unshift(entry)
  return list.slice(0, MAX_LYRICS_CACHE)
}

function serializeLyricsCache(cache) {
  return JSON.stringify({ version: 1, entries: Array.isArray(cache) ? cache.slice(0, MAX_LYRICS_CACHE) : [] }) + "\n"
}

// What the browser lists besides folders: audio, and playlists mpv reads.
var LIBRARY_NAME_FILTERS = ["*.mp3", "*.m4a", "*.flac", "*.ogg", "*.oga", "*.opus", "*.wav",
  "*.aif", "*.aiff", "*.aac", "*.wma", "*.alac", "*.ape", "*.wv", "*.mka",
  "*.m3u", "*.m3u8", "*.pls", "*.cue"]

// ------------------------------------------------------------------ updates
//
// A newer release is found by asking GitHub for the latest release of the
// public repository, at most once a day while the popup is open (and when
// asked from Settings). Updating runs Omarchy's own plugin update, which
// fetches, validates, rolls back a failed update and reloads the plugin.
var PLUGIN_ID = "lancefaul.omedia-controls"
var RELEASES_API = "https://api.github.com/repos/lancefaul/omarchy-omedia-controls/releases/latest"
var RELEASES_PAGE = "https://github.com/lancefaul/omarchy-omedia-controls/releases/"
var UPDATE_COMMAND = ["omarchy", "plugin", "update", PLUGIN_ID, "--yes"]
var UPDATE_CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000
var RESTART_COMMAND = ["omarchy", "restart", "shell"]
// An update reloads the plugin, which takes this widget with it, so an
// attempt is written down before it runs and read back by whatever loads
// next. An attempt older than this was abandoned.
var UPDATE_ATTEMPT_TIMEOUT_MS = 5 * 60 * 1000
var MAX_RELEASE_NOTES = 30000

// "2.1.0" or "v2.1.0" as [2, 1, 0]; null for anything else.
function parseVersion(text) {
  var m = /^v?(\d{1,4})\.(\d{1,4})\.(\d{1,6})$/.exec(String(text || "").trim())
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null
}

// Whether version a is newer than b; false when either can't be read.
function isNewerVersion(a, b) {
  var x = parseVersion(a), y = parseVersion(b)
  if (!x || !y) return false
  for (var i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] > y[i]
  return false
}

// GitHub's latest-release answer, kept to what the popup shows:
// { version, tag, notes, url, published } or null.
function parseLatestRelease(text) {
  if (typeof text !== "string" || text.length > 2000000) return null
  var data
  try { data = JSON.parse(text) } catch (e) { return null }
  if (!data || typeof data !== "object" || data.draft || data.prerelease) return null
  var v = parseVersion(data.tag_name)
  if (!v) return null
  var tag = String(data.tag_name).trim()
  return {
    version: v.join("."),
    tag: tag,
    notes: releaseNotesText(data.body),
    url: RELEASES_PAGE + "tag/" + encodeURIComponent(tag),
    published: /^\d{4}-\d{2}-\d{2}T/.test(String(data.published_at || "")) ? String(data.published_at).slice(0, 10) : "",
  }
}

// Release notes as Markdown for the popup, without images or HTML: nothing
// in them is fetched or run, only shown. Headings below a section's stay,
// as bold at the popup's text size.
function releaseNotesText(body) {
  return String(body || "")
    .replace(/!\[[^\]]*\]\([^)]*\)/g, "")
    .replace(/<[^>]*>/g, "")
    .replace(/\r\n/g, "\n")
    .replace(/^#{3,6}[ \t]+(.+?)[ \t#]*$/gm, "**$1**")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
    .slice(0, MAX_RELEASE_NOTES)
}

// The notes as the popup lays them out: a section per heading (# or ##) or
// horizontal rule, each with a header and a dividing line of its own, as the
// rest of the popup has. Text before the first heading is the opening
// section, with no header.
function releaseNoteSections(notes) {
  var out = []
  var current = { title: "", body: [] }
  var lines = String(notes || "").split("\n")
  function push() {
    var body = current.body.join("\n").replace(/\n{3,}/g, "\n\n").trim()
    if (current.title || body) out.push({ title: current.title, body: body })
  }
  for (var i = 0; i < lines.length; i++) {
    var heading = /^#{1,2}[ \t]+(.+?)[ \t#]*$/.exec(lines[i])
    var rule = /^\s*([-*_])(\s*\1){2,}\s*$/.test(lines[i])
    if (heading || rule) {
      push()
      current = { title: heading ? heading[1].trim().toUpperCase() : "", body: [] }
      continue
    }
    current.body.push(lines[i])
  }
  push()
  return out
}

function updateCheckDue(lastChecked, now) {
  var last = Number(lastChecked)
  return !isFinite(last) || last <= 0 || now - last >= UPDATE_CHECK_INTERVAL_MS || now < last
}

// How an update attempt ended, once the plugin has loaded again: "applied"
// when the installed version reached what was being installed, "failed" when
// the attempt is old enough to have finished, else "" while it may still run.
function updateAttemptState(attempt, installed, now) {
  if (!attempt || !parseVersion(attempt.version)) return ""
  if (parseVersion(installed) && !isNewerVersion(attempt.version, installed)) return "applied"
  var at = Number(attempt.at)
  if (!isFinite(at) || now - at >= UPDATE_ATTEMPT_TIMEOUT_MS || now < at) return "failed"
  return ""
}

function parseUpdateCache(text) {
  var data
  try { data = JSON.parse(String(text || "")) } catch (e) { return { checkedAt: 0, release: null, attempt: null } }
  var release = data && data.release && parseVersion(data.release.version) ? {
    version: String(data.release.version),
    tag: String(data.release.tag || ""),
    notes: releaseNotesText(data.release.notes),
    url: String(data.release.url || "").indexOf(RELEASES_PAGE) === 0 ? String(data.release.url) : RELEASES_PAGE,
    published: String(data.release.published || "").slice(0, 10),
  } : null
  var checkedAt = Number(data && data.checkedAt)
  var a = data && data.attempt
  var attempt = a && parseVersion(a.version) ? { version: String(a.version), at: Number(a.at) || 0 } : null
  return {
    checkedAt: isFinite(checkedAt) && checkedAt > 0 ? checkedAt : 0,
    release: release,
    attempt: attempt,
  }
}

// ------------------------------------------------------------ library search
//
// Search covers the whole music folder by file and folder names: music kept
// as Artist/Album/01 Title is found by any mix of those words. The file list
// comes from one `find` when a search starts, and filtering it is instant.
var LIBRARY_SEARCH_MIN = 2
var LIBRARY_SEARCH_LIMIT = 500
var LIBRARY_INDEX_MAX = 50000

// The find command for every file the library would show, in and below the
// music folder, skipping hidden files and folders and never following links.
function libraryFindCommand(root) {
  var r = cleanPath(root)
  if (!r) return []
  var names = []
  LIBRARY_NAME_FILTERS.forEach(function(f, i) {
    if (i > 0) names.push("-o")
    names.push("-iname", f)
  })
  return ["find", r, "-type", "f", "(" ].concat(names, [")", "-not", "-path", "*/.*"])
}

function parseFileList(text, root) {
  var out = []
  if (typeof text !== "string") return out
  var lines = text.split("\n")
  for (var i = 0; i < lines.length && out.length < LIBRARY_INDEX_MAX; i++) {
    var p = cleanPath(lines[i])
    if (p && p !== cleanPath(root) && isInside(root, p)) out.push(p)
  }
  return out
}

// Lower case, apostrophes dropped (so "dont" finds "Don't"), anything else
// that isn't a letter or digit a space.
function searchText(text) {
  return String(text || "").toLowerCase().replace(/['\u2019`]/g, "").replace(/[^0-9a-z\u00c0-\uffff]+/g, " ").trim()
}

// Tracks whose path below the music folder has every word of the query, in
// path order: [{ path, title, album, artist }] and how many matched in all.
function searchLibrary(paths, root, query, limit) {
  var r = cleanPath(root)
  var words = searchText(query).split(" ").filter(function(w) { return w !== "" })
  var max = limit || LIBRARY_SEARCH_LIMIT
  var result = { results: [], total: 0 }
  if (!r || searchText(query).length < LIBRARY_SEARCH_MIN || words.length === 0) return result
  var matches = []
  ;(Array.isArray(paths) ? paths : []).forEach(function(p) {
    var rel = p.slice(r.length + 1)
    var hay = " " + searchText(rel.replace(/\.[^./]{1,5}$/, "")) + " "
    if (words.every(function(w) { return hay.indexOf(w) !== -1 })) matches.push(rel)
  })
  matches.sort(function(a, b) { return a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" }) })
  result.total = matches.length
  result.results = matches.slice(0, max).map(function(rel) {
    var parts = rel.split("/")
    var file = parts[parts.length - 1]
    return {
      path: r + "/" + rel,
      title: file.replace(/\.[^.]{1,5}$/, ""),
      album: parts.length >= 2 ? parts[parts.length - 2] : "",
      artist: parts.length >= 3 ? parts[parts.length - 3] : "",
    }
  })
  return result
}

// The library's subline while searching: "3 results", or "Showing 500 of 812"
// when there are more than can be shown.
function searchCountText(result) {
  var r = result || { results: [], total: 0 }
  if (r.total > r.results.length) return "Showing " + r.results.length + " of " + r.total
  return r.total + (r.total === 1 ? " result" : " results")
}

// The mirrored bars: the analyser's nineteen bands, as thick as its bars and
// laid out from the middle. Band 0 is the centre bar; each step outward takes
// the next two bands, the lower on the left and the higher on the right, so the
// loudest (usually the bass) stands tallest in the middle, the edges taper,
// and every band is still shown.
var MIRROR_BARS = 19

function mirrorBand(index) {
  var centre = (MIRROR_BARS - 1) / 2
  var d = Math.abs(index - centre)
  if (d === 0) return 0
  return index < centre ? 2 * d - 1 : 2 * d
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

// Whether a new track looks like Apple Music radio tuning in, before its
// length has had a chance to grow.
//
// A station starts playing well back from the end of what it has loaded — that
// gap is its buffer — while a song starts at or near zero. Measured in Brave:
// Apple Music 1 at 112.5 of 160.2 s, 112.2 of 160.1 s and 113.1 of 160.1 s,
// and Apple Music Chill at 32.1 of 80 s. The length varies by station; the
// gap does not — about 48 s every time. Used only to show LIVE provisionally; growth still has to
// confirm it within the usual window, so a song resumed at just the wrong
// point shows LIVE for a few seconds at worst.
var TUNE_IN_MAX_LENGTH_SECONDS = 300
var TUNE_IN_MIN_POSITION_SECONDS = 20
var TUNE_IN_MIN_BEHIND_SECONDS = 30
var TUNE_IN_MAX_BEHIND_SECONDS = 70

function looksLikeRadioTuneIn(positionSeconds, lengthSeconds) {
  if (typeof positionSeconds !== "number" || typeof lengthSeconds !== "number") return false
  if (!isFinite(positionSeconds) || !isFinite(lengthSeconds)) return false
  if (lengthSeconds <= 0 || lengthSeconds > TUNE_IN_MAX_LENGTH_SECONDS) return false
  if (positionSeconds < TUNE_IN_MIN_POSITION_SECONDS) return false
  var behind = lengthSeconds - positionSeconds
  return behind >= TUNE_IN_MIN_BEHIND_SECONDS && behind <= TUNE_IN_MAX_BEHIND_SECONDS
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
// Proxies such as playerctld are skipped: they mirror a real player. So is a
// player with no activity — nothing playing and no track loaded — such as the
// one Brave registers for every window, a Discord web app included, before
// anything plays in it (see isActivePlayer).
// Whether a player has anything to show or control: a track loaded, or
// playing. A name alone does not count.
function isActivePlayer(hasTrack, playing) {
  return !!hasTrack || !!playing
}

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
    if (!p || p.proxy || !p.hasMetadata) continue
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

// ------------------------------------------------------------ format chips
//
// Winamp's kbps · kHz · stereo readout. A local file is read with ffprobe,
// which gives all three; anything else (a browser tab, a stream) only has what
// PipeWire knows about the audio it is sending, so no bitrate.

var MAX_PATH_LENGTH = 4096

// The local path behind a file:// track URL, or "" when there is none. The URL
// comes from the player, so the path must be absolute, decode cleanly, and
// carry no control characters before it is handed to ffprobe as an argument.
function fileUrlToPath(url) {
  var text = firstText(url)
  if (text.indexOf("file:///") !== 0 || text.length > MAX_PATH_LENGTH * 3) return ""
  var path
  try {
    path = decodeURIComponent(text.slice("file://".length))
  } catch (e) {
    return ""
  }
  if (path.charAt(0) !== "/" || path.length > MAX_PATH_LENGTH) return ""
  if (/[\u0000-\u001f\u007f]/.test(path)) return ""
  return path
}

function positiveInt(value) {
  var n = Math.round(Number(value))
  return isFinite(n) && n > 0 ? n : 0
}

// ffprobe -of json, first audio stream: bitrate in bits per second (the
// stream's, else the container's), sample rate, channels.
function parseFfprobe(text) {
  var info = { bitrate: 0, sampleRate: 0, channels: 0 }
  if (typeof text !== "string" || text.length > 65536) return info
  var data
  try {
    data = JSON.parse(text)
  } catch (e) {
    return info
  }
  var stream = data && Array.isArray(data.streams) && data.streams.length > 0 ? data.streams[0] : {}
  var format = data && data.format ? data.format : {}
  info.bitrate = positiveInt(stream.bit_rate) || positiveInt(format.bit_rate)
  info.sampleRate = positiveInt(stream.sample_rate)
  info.channels = positiveInt(stream.channels)
  return info
}

// PipeWire's node.rate is a fraction of a second: "1/44100".
function nodeRate(value) {
  var m = /^1\/(\d{4,6})$/.exec(firstText(value))
  return m ? Number(m[1]) : 0
}

function channelsLabel(channels) {
  if (channels === 1) return "mono"
  if (channels === 2) return "stereo"
  if (channels === 6) return "5.1"
  if (channels === 8) return "7.1"
  return channels > 0 && channels < 64 ? channels + " ch" : ""
}

// The chips, as Winamp words them: whole kilobits, whole kilohertz.
function formatChips(info) {
  var chips = []
  if (!info) return chips
  var kbps = Math.round(positiveInt(info.bitrate) / 1000)
  if (kbps > 0 && kbps < 100000) chips.push(kbps + " kbps")
  var khz = Math.floor(positiveInt(info.sampleRate) / 1000)
  if (khz > 0 && khz < 1000) chips.push(khz + " kHz")
  var ch = channelsLabel(positiveInt(info.channels))
  if (ch) chips.push(ch)
  return chips
}

// How well a PipeWire playback stream matches a player: the app first, by
// application name against the player's identity ("mpv" and "mpv", "Brave" and
// "Brave Origin"), then the track title in the stream's name, which tells two
// streams from the same app apart. 0 means no match.
function streamScore(props, identity, title) {
  if (!props) return 0
  var app = firstText(props["application.name"]).toLowerCase()
  var ident = firstText(identity).toLowerCase()
  if (!app || !ident) return 0
  var appMatch = app === ident || ident.indexOf(app) === 0 || app.indexOf(ident) === 0
  if (!appMatch) return 0
  var name = firstText(props["media.name"]).toLowerCase()
  var t = firstText(title).toLowerCase()
  return t && name.indexOf(t) !== -1 ? 2 : 1
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
  return /^\/(org\/chromium|com\/brave)\/MediaPlayer2\/TrackList\//.test(objectPathText(trackId))
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
