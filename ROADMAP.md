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

## Decided: side panels for list-shaped features

The library established the pattern for anything that is a list to browse
alongside the player: a button in the popup toggles a second column on the
right, the same width as the player column, divided from it by a line, with a
section header, a subline for context, header actions on the right, the list
filling the popup's height, and a footer for actions on a selection. The
TrackList queue (#16) and synced lyrics (#14) are to reuse it rather than
invent their own layouts.

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
  own play/pause per row; and an opt-in switch to pause the others.
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

## 2.0 — second release

Everything after 1.0, released together. Work was cut as 1.1 and 1.2 along
the way, but neither was published: 2.0 is the next release after 1.0. The
first table is what was cut as 1.1, the second as 1.2, the third what came
after.

| # | Feature | Status | Source | Notes |
| --- | --- | --- | --- | --- |
| 20 | Recognise Apple Music radio as live on first tune-in | **Done** | Measured on Apple Music 1 and Chill | A new track in a Chromium player is checked for where playback started: a station starts about 48 s behind the end of what it has loaded (112 of 160 s on Apple Music 1, 32 of 80 s on Chill), a song near zero. LIVE shows at once, provisionally, and growth confirms it as before |
| 10 | Winamp's oscilloscope and mirrored bars | **Done** | Winamp's analyzer and scope; a voice-recorder style asked for directly | Clicking the visualiser cycles analyser, mirrored bars, VU meter, oscilloscope. The oscilloscope is Webamp's WavePaintHandler in its default "lines" style: 576 samples, one every seventh for 75 columns, on the analyser's sixteen rows. The mirrored bars reuse the analyser's nineteen bands at its bar thickness, centre-out with band 0 in the middle, growing both ways from the centre line. Remembered in the plugin's state folder. Omaramp's VU and ASCII styles are not planned |
| 17 | Stereo VU meter | **Done** | Winamp 5 Modern skin, WACUP, Omaramp Stereo VU | The third visualisation in the click cycle, before the oscilloscope. spectrum.py --vu captures in stereo and reports each channel's RMS level (+3 dB, so a full-scale sine reads 0 dB) on a -40 dB to 0 dB scale, with meter ballistics: instant rise, a 1 dB fall per frame, and a peak held for half a second before falling with the analyser's acceleration. Measured through spectrum.py rather than PipeWire's node peaks, which reuses the capture the other visualisations already run |
| 11 | Bitrate / kHz / stereo chips | **Done** | Winamp's kbps · kHz · stereo | Square chips under the album line, aligned with the track text. A local file (a `file://` track URL) is read once per track with `ffprobe` while the popup is open, for all three; anything else, such as a browser tab, falls back to the sample rate and channel count of the PipeWire playback stream matched to the player by application name and track title. MPRIS itself carries none of it |
| 21 | Eject: browse and play music | **Done** | Winamp's eject | An eject cell in the transport row opens the library as a second column on the right of the popup, the same width as the player column and divided from it by a line, so the list gets the popup's full height. Rooted at `xdg-user-dir MUSIC` and never leaving it: folders first, then audio and playlists, an Up row, the folder as a subline under LIBRARY, Play all, and a bordered play button per folder. Winamp-style selection: click selects, shift-click selects a run, double-click plays one; a footer plays the selection in pick order or clears it. One track goes to the active player over MPRIS OpenUri when it accepts files (mpv); several go as an M3U written to the private state folder; otherwise the desktop's default audio app starts with `gtk-launch`. Nothing is played by the plugin itself |
| 22 | Close a player from PLAYERS | **Done** | Asked for directly: an mpv left open had no way to close without a terminal | A small bordered close button on each PLAYERS row, shown only when the player reports CanQuit (mpv does; Chromium browsers do not), calling MPRIS Quit |

Also in 1.1:

- **Every setting lives in the popup.** 1.0's config settings (analyser
  on/off, title width, hide when idle, pause others) moved into it, and carry
  over from a 1.0 install on 2.0's first run (#40).
- **Live streams read just LIVE**, with a pulsing dot and no elapsed counter:
  YouTube TV's reported position is a 0-30 s sawtooth.
- **Volume on Chromium browsers** is disabled with a note naming the player,
  since Chromium ignores volume changes over MPRIS.


| # | Feature | Status | Source | Notes |
| --- | --- | --- | --- | --- |
| 16 | Playlist via MPRIS TrackList | **Done** | Winamp playlist, Omaramp queue | For players that publish TrackList (archamp does), read with `busctl` since Quickshell has none: a PLAYLIST bar above the art with the song's place and time through the list, and the playlist in the side column, click to jump. Editing it came later (#34). Browsers, Spotify and mpv publish no TrackList, so their bar has no list |
| 14 | Synced lyrics | **Done** | Omaramp; `crmne.lyrics` does it as its own plugin | A lyrics cell in the transport row opens the side column. A `.lrc` beside a local file first, else LRCLIB (`/api/get` with the track's length, `/api/search` without), sent artist, title, album and length only, and only while the column is open. Answers are cached in the state folder (sixty, misses retried after a week). Synced lyrics light the line being sung and keep it a third of the way down, pausing after a manual scroll; a click on a line seeks to it. Plain lyrics show as text. Live streams have none |
| 23 | Setting: default local music player | **Done** | Asked for directly | Which app the library starts when the active player cannot take a pick. Today it is whatever the desktop opens `audio/mpeg` with (`xdg-mime`), falling back to `xdg-open`. Must be chosen in the popup, not in config: likely a settings side panel listing installed apps that handle audio |
| 24 | Setting: default local music location | **Done** | Asked for directly | The library's root folder. Today it is `xdg-user-dir MUSIC`, else `~/Music`. Chosen in the popup, e.g. "Use this folder" from the library itself, remembered in `preferences.json`; the browser still never leaves the chosen root |
| 25 | Setting: allow online lyrics | **Done** | Asked for directly | An on/off switch for asking LRCLIB. Off means lyrics come only from a `.lrc` beside a local file, and nothing leaves the machine. Chosen in the popup and remembered in `preferences.json`; the lyrics column's subline should say when online lookup is off, so an empty column is never a mystery |
| 26 | Settings panel | **Done** | Needed to hold #23-#32 | A gear button opens SETTINGS as a side column, per the side-panel pattern: sections with switches, choices and buttons, everything remembered in `preferences.json`. Pause others may move here from the PLAYERS header. The popup stays the only place settings are made; nothing is config-only |
| 27 | Setting: hide when nothing is playing | **Done** | Returns from 1.0's `hideWhenIdle`, now in the popup | Off by default. Hiding the widget also hides the way into the popup, so it must come back on its own as soon as a player has a track, and the IPC `toggle` command still opens the popup regardless |
| 28 | Setting: load cover art from the web | **Done** | Suggested alongside #25 | On by default. Off shows the placeholder for `https://` art instead of fetching from the host the player chose; local and embedded art are unaffected. With #25 off as well, the plugin makes no network requests at all |
| 29 | Setting: remember live stations, and Forget stations | **Done** | Suggested | On by default. `live-streams.json` is a small listening history; off stops writing it (stations then read as LIVE only after their length grows, or via the tune-in check), and Forget stations empties it |
| 30 | Clear lyrics cache | **Done** | Suggested | A button in settings that empties `lyrics-cache.json`, so every song is looked up afresh |
| 31 | Setting: keyboard step sizes | **Done** | Suggested | How far the popup's ← → seek (5 s today) and ↑ ↓ change volume (5 % today), and so the `seekBack`/`seekForward` and volume keys. A few chips each, e.g. 5 / 10 / 30 s and 2 / 5 / 10 % |
| 32 | Setting: default visualisation | **Done** | Asked for directly | Which of analyser, mirrored bars, VU meter and oscilloscope the popup shows. Today clicking the visualiser cycles and the last one sticks; the setting picks it directly, from the same stored value, so the two stay in step |
| 15 | Live video preview | **Done** | Asked for directly | For browsers and known video players (mpv, VLC, Celluloid, Haruna, GNOME Videos), a ScreencopyView of the player's window replaces the album art across the popup, the track's details beneath. The window is found through Hyprland: those of the process owning the MPRIS name (GetConnectionUnixProcessID), then the one whose title names the track, or for a browser its one ordinary window, web apps aside. Captures the whole window (a tab previews with the browser around it); only while the popup is open. Not offered to audio players, whose window would be their skin |

Also:

- **Settings panel** beside the player, holding every setting (#23-#32), with
  snapshot tiles for the visualisations.
- **PLAYLIST bar** for every player, its shuffle, repeat and playlist buttons
  dimmed with an explanation when a player can't do them, headed with the
  playlist's name when the player shares one.
- **Winamp's dot matrix** behind the visualisations, which now take the
  header's full height.
- **Players with no activity** (Brave's player for a Discord web app) stay out
  of the popup.
- **Playback controls** read lyrics, previous, play/pause, next, eject, with
  play/pause the wide one.

After 1.2 was cut:

| # | Feature | Status | Source | Notes |
| --- | --- | --- | --- | --- |
| 33 | Saved playlists: build, save and load | **Done** | Asked for directly | M3U files in `Playlists` inside the music folder (#38), so they belong to no one player. The player's playlist column has Open and New at the top and Add, Save and Save as at the bottom. Open lists them in the same column: play, rename, delete (to the trash), and move and remove tracks, each change written at once. Save keeps the player's queue; a queue played from a saved playlist stays linked to that file, keeps its name (marked edited once changed), saves back with Save, and follows a rename. Editing a saved playlist that is playing makes the same change in the player. Names are cleaned (no slashes, no leading dots); writes stay in the playlist folder. The playlist buttons were first in the library and moved here |
| 34 | Edit the playing list | **Done** | Asked for directly | Add (a music-folder browser in the column, MPRIS `AddTrack`), remove (`RemoveTrack`) and move up or down on each song, for players that allow it. MPRIS has no move, so moving uses archamp's own `org.archamp.TrackList.MoveTrack` where the player offers `CanMoveTracks` |
| 35 | Skip back and forward buttons | **Done** | Asked for directly | Between the times under the seek bar, by the Settings seek step (now 5, 10, 15 or 30 s), each glyph showing its step. Tried in the transport row first |
| 36 | Winamp5 and Off visualisations | **Done** | Winamp5 Classified's analyser; Winamp's own click cycle | Winamp5 follows the analyser in the cycle: the same bars striped a row lit and a row empty on whole-pixel rows, every stripe and gap the same height. Off ends the cycle as in Winamp: an empty corner, and the capture stops |
| 37 | Visualiser colours | **Done** | Asked for directly, after classic popup themes were rejected | One choice for all: Gradient (the theme's accent from dark to near white, default), Solid (the accent) or Winamp (base-2.91's VISCOLOR.TXT spectrum, peaks and scope shades; plain white for Winamp5). A gradient between the theme's accent and urgent colours was tried first and was invisible on single-hue themes |
| 38 | Setting: playlist folder | **Done** | Asked for directly | Beside the library folder setting, with the same Change… and Default |
| 39 | Setting: bar title width and scrolling | **Done** | Returns from 1.0's config `maxLabelWidth` | 160, 260 (default) or Full, and whether a title too long for it scrolls whenever a track is loaded (on) |
| 42 | Update notices | **Done** | Omarchy has no update notice for plugins: `omarchy plugin update` is run by hand | Once a day while the popup is open (a switch in Settings), GitHub's latest release is compared with the installed manifest's version. A newer one shows *Update available* above Now Playing, with a pulsing dot like LIVE's; it opens the release notes (Markdown, images and HTML removed) in the side column, the exact command Update runs, copyable, and Update and Dismiss (for that version). Settings has an UPDATES section: versions, last check, Check now, View update. Updating reloads the plugin mid-run, so the attempt is written to update.json first and read back by the reloaded widget, which reports *Updated to …* with Restart shell and Done, or that it didn't finish. Only 2.0 and later can tell their users; 1.0 users update by hand once |
| 41 | Library search | **Done** | Asked for directly | A search box at the top of the library column, and of the Add browser. It covers the whole music folder by words of the artist, album and file name (apostrophes ignored), from one `find` listing taken when a search starts; results show artist and album beneath, and select, play and add like browsed tracks, up to 500 shown. Tags aren't read: folders named Artist/Album carry the same words without opening thousands of files |
| 40 | Carry over 1.0's config settings | **Done** | Semantic versioning: keeping the upgrade non-breaking | On 2.0's first run, settings a 1.0 user had set in the shell's config move into the popup's: hide when idle and pause others as they were, the title width to the nearest choice (Full standing in for 1.0's 600), and the analyser switched off to Off. Only values actually set, and only once |

## Later

| # | Feature | Status | Source | Notes |
| --- | --- | --- | --- | --- |

## Rejected

| Feature | Why |
| --- | --- |
| Live stream DVR: behind-live readout and rewind buttons (was #19) | Measured on YouTube TV in Brave, none of it can be built on what MPRIS carries. A relative Seek of −30 s moved a few seconds, not thirty: Brave turns it into its own fixed step. The reported position is not a position at all — it counts from 0 to 30 s and restarts, every thirty seconds, while the video plays on — so there is nothing to seek against or to measure a rewind by. And a programme ending sends no signal: title, length and counter carried on unchanged. The panel could never know how far behind live you are. Go Live, which asks for a position far past the end, does work and stays |
| Playlist / queue manager *through Quickshell* | Quickshell's MPRIS service does not expose the TrackList interface, and its QML services are a fixed set with no generic D-Bus module, so QML alone cannot reach it. Patching Quickshell would mean maintaining a build against a packaged `quickshell` that every Omarchy update replaces. A helper process is the way in instead — see #16 |
| 10-band EQ, loudness normaliser, 3D widener | These are PipeWire filter chains, not media control. The `equalizer` plugin already does it |
| YouTube search, direct streaming, Spotify import | That is being a player: it means bundling mpv and yt-dlp and giving up "control what you already run". Note this is about *sourcing* media — controlling a YouTube or Spotify tab already works |
| Winamp's analyser options: falloff speeds, peaks, thin bands (was #18) | Built as click-to-cycle presets and taken out: the original analyser was judged right as it is, and every option was only reachable from the terminal or a preset nobody asked for |
| Cropping the video preview to the video | Built as a motion crop (compare small snapshots, crop to what moves) and taken out: it found YouTube TV's picture, but pages present video too differently (moving ads and chat, still scenes, layout changes) for a guessed crop to be trusted. The preview shows the whole window. Picture-in-Picture would give a clean capture but floats on screen, and fullscreen covers it, which defeats glancing at the game from the popup |
| Skins | Winamp's soul, but it fights Omarchy's theme tokens, which are the reason this widget looks native |
| Classic popup themes (was #34 in a draft) | Built as colours only: Winamp 2.91, Winamp3 Classified and Winamp5 Classified, read from each skin's GENEX.BMP, PLEDIT.TXT and VISCOLOR.TXT, later with a display above the controls and chrome below. Taken out: a popup in several colours looked worse than one following the Omarchy theme. The skins' visualiser colours stayed, as #37 |
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
