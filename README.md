# OMedia Controls

Top bar media plugin for Omarchy.

![OMedia Controls in four Omarchy themes: a local track at 1.25x speed, several players at once, a live TV stream, and a live radio station](preview.png)

*Album art is blurred in this preview only. The plugin shows it in full.*

A native-styled MPRIS widget for the [Omarchy](https://omarchy.org) shell: album
art and the track title in the bar, and a popup with the full details, transport
controls, a live spectrum visualiser and a picker for whichever players are
running.

It binds MPRIS directly rather than going through the built-in `omarchy.media`
service, whose service half only runs while that plugin's own bar icon is
enabled — this widget replaces that icon, so it cannot depend on it.

## What it does

- **In the bar:** album art and the track title, capped at a configurable width
  so a long title can't push the bar's other sections around. The full title and
  artist stay in the tooltip.
- **In the popup**, laid out like Omarchy's own panels:
  - a **Now Playing** header with Winamp's classic spectrum analyser beside it
  - album art, title, artist, and album with its year and track number, each
    scrolling if too long to fit; a **seek bar** you can drag or click, and a
    counter that flips between length and time remaining
  - **playback controls**: shuffle, previous, play/pause, next and repeat
  - **speed**: 1×, 1.25×, 1.5×, 2× and 3×, on players that allow it
  - **volume**, with a labelled mute button. Chromium browsers (Brave,
    Chrome) and any player caught ignoring volume changes get a note instead
    of a slider that does nothing
- **Stable shape:** with nothing playing, or on a player that can't do
  something, controls disable rather than disappear.
- **Several players at once:** anything with a track shows up in a list; click
  one to make it the active player. A playing source wins over a paused one.
- **Mouse:** left-click opens the popup, right-click play/pause, middle-click
  next, scroll to change track. Clicking the popup's album art raises the
  player's own window, when the player supports it. Hover a long title in the
  bar to scroll it.
- **Keyboard**, while the popup is open — see below.
- **Commands** for binding hotkeys without opening the popup — see below.

## Keyboard

| Key | Does |
| --- | --- |
| Space or `k` | Play / pause |
| ← / → | Seek back / forward 5 seconds |
| ↑ / ↓ | Volume up / down 5% |
| `n` / `p` | Next / previous |
| `m` | Mute |
| `s` | Shuffle |
| `r` | Repeat: off, all, one |
| `[` / `]` | Slower / faster |
| `l` | Go live |
| Esc | Close |

## Commands

Everything the popup does is also a command, for binding keys in
`~/.config/hypr/bindings.lua`:

```bash
omarchy-shell lancefaul.omedia-controls playPause
omarchy-shell lancefaul.omedia-controls next          # and previous
omarchy-shell lancefaul.omedia-controls seek +10      # -10, or 90 for an exact second
omarchy-shell lancefaul.omedia-controls volume -5     # percent; 40 sets it
omarchy-shell lancefaul.omedia-controls speed faster  # slower, or a rate from 0.25 to 4
omarchy-shell lancefaul.omedia-controls mute          # shuffle, repeat, goLive
omarchy-shell lancefaul.omedia-controls toggle        # open, close
omarchy-shell lancefaul.omedia-controls status        # what is playing, as JSON
```

Each replies `ok`, or `unavailable` when the player can't do it. They act on
the player the popup on the focused monitor is showing.

## The visualiser is Winamp's

`spectrum.py` ports Winamp's classic spectrum analyser as
[Webamp](https://github.com/captbaritone/webamp) reconstructs it from the Winamp
2.63 and 5.666 executables, with the Nullsoft FFT from WACUP's `vis_classic`.
Settings are a fresh Winamp install's: nineteen thick bars, bars that rise
instantly and fall linearly, and peaks that hang before falling with
acceleration, all on sixteen stepped levels.

## Cost while idle

The visualiser's audio capture and the position probe only run while the popup
is open **and** something is playing. Nothing polls in the background, and the
`parec` monitor stream is not held open the rest of the time. While running,
the analyser takes about 1% of a CPU core at 60 frames a second. Titles scroll
only while the popup is open or under the pointer, so an idle bar never
animates.

## Privacy and security

Plugins run unsandboxed inside the Omarchy shell, so here is exactly what this
one does:

- **Reads all system audio while the popup is open on a playing track**, from
  the default output's monitor, to draw the visualiser. It is analysed in
  memory; nothing is stored, and the only thing that leaves `spectrum.py` is
  nineteen bar levels and nineteen peak levels per frame.
- **Makes no network requests of its own.** Cover art is loaded from wherever
  the player says it is, but only as a local `file://`, an `https://` URL, or
  a base64 raster image embedded in the metadata (how mpv sends a file's own
  cover) — any other scheme, plain `http`, SVG, credentials in the URL or
  control characters, and the placeholder is shown instead. The player chooses that URL, so an `https` art
  URL does mean a request to the host the player picked.
- **Runs four programs**, always as argument lists and never through a shell:
  `python3 spectrum.py`, `parec` and `pactl` (inside `spectrum.py`),
  `busctl --user get-property` to read a player's position and volume
  straight from the player, and
  `install -d -m 700` once at load to create its state folder. The player's
  bus name is refused unless it is shaped like an MPRIS name.
- **Treats track metadata as untrusted.** Titles, artists and albums come from
  whichever application registered a player, and are always rendered as plain
  text, including in the bar tooltip.
- **Writes one file**: `~/.local/state/omedia-controls/live-streams.json`, in
  a folder only you can open. It lists the live streams it has detected — the
  app's name and the station's title, such as
  `Brave Origin | Apple Music Country`, and when each was last seen — so a
  station you have heard before shows as LIVE the moment it starts instead of
  after a delay. Nothing else is recorded: no songs, no listening history,
  nothing about normal tracks. It keeps at most 200 stations, drops any whose
  length stops growing, and is read back defensively. Delete the file to clear
  it.
- **Accepts commands** from anything that can reach the shell's IPC
  socket, which is any program running as you. Arguments are parsed strictly
  (`+10`, `-5`, `1.5`) and anything else is refused.
- **Takes the keyboard while the popup is open**, as Omarchy's own panels do,
  and gives it back when it closes.
- **Needs no root** and installs nothing.

## Live streams

Live streams show a full bar in the accent colour and `LIVE` instead of a
duration. On a stream you can rewind, such as YouTube TV, `LIVE` sits on the
right with a counter of how long you have been watching on the left. On one
you cannot, such as Apple Music radio, there is nothing to count against, so
`LIVE` sits alone, centred under the bar. Two kinds are recognised:

- **"Never ends" lengths**, such as YouTube TV in Chromium browsers, which
  report the largest possible length. Recognised immediately.
- **Growing lengths**, such as Apple Music radio, which reports a finite length
  that grows as audio loads. There is no other signal, so a station you have
  never heard shows a normal timeline until its length first grows — about 16
  seconds on Apple Music — and is remembered from then on. Switching from one
  station to another stays `LIVE` throughout.

Hover `LIVE` on a stream that can rewind, such as YouTube TV, and it becomes
**GO LIVE**, which returns you to the live edge. Apple Music radio has no Go
Live: it already plays at live and cannot rewind, and jumping to the end of
what it has loaded only makes it stall while more arrives.

## Tests

```bash
python3 -m unittest discover -s tests -v
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_logic.qml
```

The first pins the analyser's Winamp behaviour; the second covers the pure
logic in `Logic.js`, mostly the checks on input from other applications. Both
run in CI.

## Requirements

- Omarchy Quattro with its Quickshell-based shell
- `python`, `python-numpy`, and `parec` (from `libpulse`, already present on
  Omarchy) for the spectrum visualiser
- Any media player that exposes the standard MPRIS interface

## Install

```bash
omarchy plugin add https://github.com/lancefaul/omarchy-omedia-controls.git --enable
```

For local development, link the checkout into the plugins directory instead, so
edits apply without reinstalling:

```bash
# from the root of your checkout
ln -s "$PWD" ~/.config/omarchy/plugins/lancefaul.omedia-controls
omarchy-shell shell rescanPlugins
omarchy plugin enable lancefaul.omedia-controls right
```

Saving a file under `~/.config/omarchy/plugins/` normally reloads the plugin
automatically — but **the watcher does not follow a symlink out to another
directory**, so edits made through the link above need a reload:

```bash
omarchy restart shell
```

Copy the folder in rather than linking it if you would rather have hot reload
than edit in place.

## Why the position is read over D-Bus directly

Quickshell's `position` is extrapolated from whenever it last heard from the
player, and nothing forces a re-read: emitting `positionChanged()` does not,
and a player restarting a track on repeat sends no `Seeked` signal. Measured on
a ten-second file looped by mpv, Quickshell's position kept climbing —
`28.98` against a length of `10.00` — so a bar clamped to the track length just
sat at full and never reset.

So while the popup is open on a playing track, `Position` is read straight off
the player's own D-Bus property with `busctl` every two seconds and
interpolated between reads. Closed popup, nothing running.

## Units, since MPRIS hides them

D-Bus carries `Position` and `mpris:length` in **microseconds**, but Quickshell
converts both to **seconds** before QML sees them (`position=100.058`,
`length=867.76`). `volume` is 0–1. Worth knowing before dividing by a million
that is not there.

## Settings

| Setting | Default | What it does |
| --- | --- | --- |
| `visualizerEnabled` | `true` | Show the spectrum analyser in the popup header |
| `maxLabelWidth` | `260` | Widest the bar title gets, in logical pixels, before it elides |
| `hideWhenIdle` | `false` | Off by default, so the widget stays a stable click target |
| `pauseOthers` | `false` | Starting one player pauses the rest, like audio focus on a phone |

## Remove

```bash
omarchy plugin remove lancefaul.omedia-controls
```

## Licence

MIT — see [LICENSE](LICENSE).
