# Roadmap

Everything considered for OMedia Controls, including the things we decided
against and why. Nothing here is a commitment; it is a catalogue so a decision
can be made once rather than re-argued.

Two sources fed this list: the feature set of
[Omaramp](https://github.com/JoeJoeflyn/omaramp) (a Winamp-inspired Omarchy
player) and classic Winamp itself.

**The distinction that decides most of it:** Omaramp *is* a player — it owns
mpv, so it can queue, stream and equalise. OMedia Controls *controls the players
you already run*, over MPRIS. Anything MPRIS exposes is reachable; anything it
does not is either a different plugin's job or a rewrite into a media player.

To be clear, controlling browser media is very much in scope: a YouTube,
YouTube TV or Spotify tab publishes MPRIS like any native app, art and transport
included.

## Decided: this stays a controller

A Winamp-style player is being built as a **separate project**. OMedia Controls
does not grow a playback engine; it controls whatever is playing, that player
included. Two consequences:

- The "that would mean being a player" rejections below stand. Playback, a
  library, streaming and an equaliser belong to the other project.
- Features that depend on a well-behaved player — a TrackList queue above all
  — can be built against one that implements the interface properly, while
  degrading gracefully for players that do not.

## Status key

- **Planned** — agreed, waiting its turn
- **Considering** — catalogued, decide later
- **Rejected** — with the reason, so it does not come back up

---

## 1.0 — first release — **shipped**

The first marketplace release. Everything below the table was planned as
later work and pulled forward because it turned out to be necessary.

| # | Feature | Status | Source | Notes |
| --- | --- | --- | --- | --- |
| 1 | Seek bar with drag-to-seek and click-to-jump | **Done** | Winamp position slider, Omaramp playhead | Built on `PanelSlider`. Position is read over D-Bus while the popup is open, because Quickshell's own value runs past the end of a repeating track. The knob holds the drag target while scrubbing |
| 2 | Time counter `03:41 / 05:12`, click to toggle elapsed ⇄ remaining | **Done** | Winamp | Right-hand figure flips to `-04:22` remaining; both sides read `--:--` with nothing playing |
| 3 | Volume slider and mute | **Done** | Both | Display-only speakers at each end of the slider, and a labelled full-width Mute button beneath it |
| 4 | Shuffle, and repeat off/playlist/track | **Done** | Winamp, Omaramp | Disabled rather than hidden on players that do not support them. Repeat cycles in Winamp's order; both show their state with the selected fill |
| 5 | Stop, distinct from pause | **Removed** | Winamp | Built, then taken out: little practical use next to pause and seek, and a sixth control broke the uniform five-cell transport row |
| 6 | Playback speed 1×–3× | **Done** | Omaramp | A SPEED row of five chips (1, 1.25, 1.5, 2, 3 — slowing down was judged rarely useful), each disabled outside the player's `minRate`/`maxRate`. Browsers and Spotify report a fixed 1–1 range, so the row is disabled there; mpv reports 0.01–100, so commands are capped at 0.25×–4× rather than trusting it |
| 7 | Scrolling title instead of eliding | **Done** | Winamp ticker, Omaramp | Hold, glide, hold, jump back. In the popup, title, artist and album scroll while it is open; in the bar, only under the pointer, so an idle desktop never animates |
| 8 | Keyboard control | **Done** | Omaramp | Unblocked by moving the popup from `PopupCard` to `KeyboardPanel`, the surface Omarchy's own panels use: an xdg-popup only gets keys after a click routes focus through the bar. Space/`k` play-pause, ←/→ seek 5 s, ↑/↓ volume 5%, `n`/`p` next and previous, `m` mute, `s` shuffle, `r` repeat, `[`/`]` speed, `l` go live, Esc closes |
| 9 | Richer metadata: album artist, track number, year | **Done** | Winamp info panel | One line under the artist: album · album artist (only when it differs from the track artist) · year · track number |
| 12 | IPC commands for global hotkeys | **Done** | Omaramp | `omarchy-shell lancefaul.omedia-controls playPause`, and `next`, `previous`, `seek ±s`, `volume ±%`, `speed`, `mute`, `shuffle`, `repeat`, `goLive`, `open`/`close`/`toggle`, `status` (JSON). Routed to the copy of the widget on the focused monitor. The widget also answers `omarchy-shell shell toggle lancefaul.omedia-controls` like a built-in panel |

Also in 1.0:

- **Winamp's classic spectrum analyser**, ported from Webamp's reconstruction
  of the Winamp 2.63 and 5.666 executables, with the Nullsoft FFT from WACUP's
  `vis_classic`: nineteen flat bars, instant rise, linear fall, floating peaks.
  Lives beside the title in the header.
- **Layout from Omarchy's own panels** — `PanelHero`, section headers and
  separators — so the popup follows the theme.
- **Controls stay put when nothing is playing**, disabled instead of vanishing.
- **Several players at once**: the popup follows the most recently started
  one, ignoring playback flickers; a PLAYERS section under the header with its
  own play/pause per row; and an opt-in setting to pause the others.
- **Live streams**: `LIVE` and an elapsed counter for both the "never ends"
  length (YouTube TV) and a length that grows (Apple Music radio), with
  detected stations remembered so they read as live at once. Go Live on
  streams that can rewind; not on Apple radio, where jumping to the end of the
  loaded audio starved its buffer and stalled playback.
- **Hardening of input from other applications**: cover art only as a local
  file, https or an embedded raster image, bus names validated before reaching
  `busctl`, and bounded parsing of helper output and the station store.
- **Tests**: unittest for the analyser, qmltestrunner for the widget logic,
  both in CI.

## 1.1 — next

| # | Feature | Status | Source | Notes |
| --- | --- | --- | --- | --- |
| 16 | Queue via a TrackList helper process | **Planned** | Winamp playlist, Omaramp queue | Supersedes the rejection below. QML cannot reach arbitrary D-Bus, but a helper can — the same pattern `spectrum.py` already uses — talking to `org.mpris.MediaPlayer2.TrackList` and returning JSON. The companion Winamp-style player will implement TrackList, so this has a guaranteed consumer. For everyone else it degrades: browsers and Spotify do not implement it, some desktop players do, so the queue tab should appear only when the active player offers one |
| 19 | Live stream DVR: how far behind live, and rewind controls | **Planned** | YouTube TV's rewind window | 1.0 shows LIVE, an elapsed counter and Go Live, but not where you are in the window. Brave reports the same unbounded length and a position counter reset to zero after every seek, so a rewind of ten minutes and one of one minute look identical. What the panel *can* track: session start (when it first saw the stream, which is the rewind window's start), pauses (the edge moves while the playhead does not), seeks it sends itself, and Go Live resetting to the edge. It can also *detect* a seek made in the page — the counter drops unexpectedly mid-playback — without knowing its size. So: add −10 s / −30 s buttons on live streams to make the panel a DVR remote that always knows its offset; show `LIVE` at the edge, `-10:00` when the offset is known, and `BEHIND LIVE` after a page seek until Go Live resyncs. The window is lost if the shell restarts, since only the panel is tracking it |
| 20 | Recognise Apple Music radio as live on first tune-in | Considering | Measured on Apple Music 1 | A station never heard before shows a timeline for about 16 s, until its length first grows. Tuning in reported a position of about 113 s into a 160 s length, which a song never does at its start; that may identify a station at once. Unproven on other stations |

## 1.2 — character

| # | Feature | Status | Source | Notes |
| --- | --- | --- | --- | --- |
| 10 | More visualiser styles: oscilloscope, VU meter, ASCII | Considering | Omaramp's 37, Winamp's analyzer and scope | Webamp's `VisPainter.ts` also has Winamp's oscilloscope. Render modes, not new capture. Keep the idle cost at zero |
| 18 | Winamp's analyser options | **Planned** | Winamp's visualisation options (right-click the vis) | Plugin settings, not popup controls, all passed to `spectrum.py`, where the constants already live: bar falloff and peak falloff (slowest to fastest, defaults moderate and slow), peaks on or off, and thick (19) or thin (75) bands, plus the refresh rate (full, half, quarter or eighth) to save CPU. Winamp's Fire and Line styles are left out: they colour from the skin and would override the theme |

## Later

| # | Feature | Status | Source | Notes |
| --- | --- | --- | --- | --- |
| 11 | Bitrate / kHz / stereo chips | Considering | Winamp's KBPS·kHz·stereo | MPRIS rarely carries bitrate, but `Quickshell.Services.Pipewire` exposes node `properties` and `channels`, which should carry sample rate and channel count. No helper process needed |
| 15 | Live video preview of the playing window | Considering | Not in Omaramp or Winamp — asked for directly | MPRIS carries no frames, but `Quickshell.Wayland` ships `ScreencopyView`, which `zzwong.stage` already uses for live window previews. Find the player's toplevel via the Hyprland module and capture it. **It captures the whole toplevel** — its only properties are `captureSource`, `paintCursor` and `live`, with no source rectangle — so a normal browser tab previews as a small browser window, chrome included. Picture-in-Picture and fullscreen video are separate toplevels containing only the video, so those preview cleanly. Cropping in QML is possible but guesses at where the video sits and saves nothing, since the whole window is still copied. Opt-in and popup-only: continuous capture costs GPU, and an idle desktop currently costs nothing |
| 17 | VU meter driven by PipeWire peaks | Considering | Winamp VU, Omaramp Stereo VU | `Quickshell.Services.Pipewire` exposes `peak`/`peaks` per node, so a level meter needs no `parec` capture and no Python at all. Cheaper than the FFT path for anything that is not a spectrum |
| 14 | Synced lyrics from lrclib | Considering | Omaramp | Real work, and `crmne.lyrics` already does exactly this as its own plugin. Decide whether to duplicate or defer to it |

## Rejected

| Feature | Why |
| --- | --- |
| Playlist / queue manager *through Quickshell* | Quickshell's MPRIS service does not expose the TrackList interface, and its QML services are a fixed set with no generic D-Bus module, so QML alone cannot reach it. Patching Quickshell would mean maintaining a build against a packaged `quickshell` that every Omarchy update replaces. A helper process is the way in instead — see #16 |
| 10-band EQ, loudness normaliser, 3D widener | These are PipeWire filter chains, not media control. The `equalizer` plugin already does it |
| YouTube search, direct streaming, Spotify import | That is being a player: it means bundling mpv and yt-dlp and giving up "control what you already run". Note this is about *sourcing* media — controlling a YouTube or Spotify tab already works |
| Skins | Winamp's soul, but it fights Omarchy's theme tokens, which are the reason this widget looks native |
| Compact / shade mode (was #13) | Collapsing the bar item to one glyph. Dropped: `maxLabelWidth` already bounds the bar item, and a glyph-only widget loses the title, which is the point of it being in the bar |
| Show and song details for Apple Music radio in the browser | Not available to any MPRIS client. Measured on Apple Music 1 over a show-to-song change: Brave kept reporting only the station name and logo, because Apple's web player never passes the programme or song to the browser's media session. A desktop client such as Cider does report them |

---

## Reference: what MPRIS exposes

Quickshell's `Quickshell.Services.Mpris` surface, which bounds everything above.

**Track:** `trackTitle`, `trackArtist`, `trackArtists`, `trackAlbum`,
`trackAlbumArtist`, `trackArtUrl`, `metadata` (raw map: track number, year,
genre, url, sometimes bitrate)

**Position:** `position`, `length`, `positionSupported`, `canSeek`,
`lengthSupported`

**Playback:** `playbackState`, `isPlaying`, `volume`, `volumeSupported`,
`shuffle`, `shuffleSupported`, `loopState`, `loopSupported`, `rate`, `minRate`,
`maxRate`, `fullscreen`, `canSetFullscreen`

**Methods:** `play`, `pause`, `togglePlaying`, `stop`, `next`, `previous`,
`raise`, `quit`

**Capabilities:** `canControl`, `canPlay`, `canPause`, `canTogglePlaying`,
`canGoNext`, `canGoPrevious`, `canQuit`, `canRaise` — every control has to be
gated on these, because players differ in what they implement

**Identity:** `identity`, `desktopEntry`, `dbusName`, `uniqueId`,
`supportedUriSchemes`, `supportedMimeTypes`

**Not exposed by Quickshell:** the TrackList and Playlists interfaces. Reaching
them means a helper process speaking D-Bus, not a QML change (see #16).

## Reference: what the rest of Quickshell offers us

The QML services are a fixed set — `Mpris`, `Notifications`, `Pipewire`,
`Polkit`, `SystemTray`, `UPower`, `Bluetooth`, `Greetd`, `Pam` — plus
`Quickshell.Wayland`, `Hyprland`, `Io` and `DBusMenu`. There is no generic D-Bus
module, so anything outside that set needs a helper process.

Two of them matter here:

- **`Quickshell.Wayland`** ships `ScreencopyView`, live window capture. This is
  what `zzwong.stage` uses for its workspace previews, and it is the only route
  to anything video (#15).
- **`Quickshell.Services.Pipewire`** exposes nodes with `properties`,
  `channels`, `volume`, `muted`, and `peak`/`peaks`. That covers the format
  chips (#11) and a VU meter (#17) without leaving QML.
