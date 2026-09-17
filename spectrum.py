#!/usr/bin/env python3
"""Winamp's classic spectrum analyser, fed from the default sink's monitor.

This mirrors the analyser in Winamp 2.x/5.x as reconstructed by Webamp
(packages/webamp/js/components/VisPainter.ts), whose authors worked it out from
the Winamp 2.63 and 5.666 executables, and uses the Nullsoft FFT from WACUP's
vis_classic (via Webamp's FFTNullsoft.ts). Settings are those of a fresh Winamp
install (thick bands, peaks on), except one step quicker on both falloffs:
"fast" for the bars and "moderate" for the peaks.

What makes it look like Winamp rather than a generic FFT:

  * 19 bars — 75 columns grouped in fours, three lit and one gap.
  * A 1024-sample Hann-windowed FFT with Nullsoft's log-shaped equalisation,
    mapped to columns on a scale that is 91% logarithmic and 9% linear.
  * Bars rise instantly and fall linearly, 16/16 of a level per frame.
  * Peaks jump to the bar, then fall with acceleration: velocity starts at 3
    (in 1/256ths of a level) and grows by 1.2x each frame.
  * Everything is quantised to 16 integer levels, which is the stepped look.

Winamp's falloff constants are per frame and Webamp runs them at 60 fps, so the
analyser advances one frame per 1/60 s of audio (a 735-sample hop over a
1024-sample sliding window) to fall at the same speed.

Output is one line per frame: 19 bar levels, a bar, then 19 peak levels, each
0.0-1.0, with -1 for a peak that has fallen out of sight:

    0.533,0.4,...|0.6,-1,...

With --oscilloscope it is Winamp's other visualisation instead, the
oscilloscope in its default "lines" style (Webamp's WavePaintHandler): 75
columns, each a vertical run of rows on the same sixteen-row grid, top to
bottom, and the row the wave sits on, which sets its brightness:

    o|7:9:9,8:9:8,...

With --vu it is a stereo VU meter: the loudness of each channel and a held
peak for each, 0.0-1.0 on a -30 dB to 0 dB scale:

    v|0.720,0.655|0.810,0.790

Winamp draws from the decoded audio, before its own volume control, so its
visualiser doesn't change with the volume. What is captured here is after the
player's own volume, so the widget sends the inverse of it on stdin, one line
at a time ("gain 3.125"), and the audio is scaled back up before analysis.

It listens to the whole output by default, which mixes in every other app: a
voice call, say, which the gain would then blow up too. So the widget also
names the active player's own playback stream ("stream 23109", PipeWire's
object.serial, which PulseAudio tools call the sink input's index), and only
that stream is recorded. "stream -" goes back to the whole output.

Exits cleanly on SIGTERM/SIGINT/broken pipe so the QML Process that owns it can
start and stop it on demand without leaking recorder subprocesses.
"""
import argparse
import math
import os
import select
import signal
import subprocess
import sys

import numpy as np

RATE = 44100
FFT_SIZE = 1024
SPECTRUM_BINS = FFT_SIZE // 2
HOP = RATE // 60  # one analyser frame per 1/60 s of audio

COLUMNS = 75
BAND_WIDTH = 4  # "thick bands": chunks of four columns
BAR_STARTS = list(range(0, COLUMNS, BAND_WIDTH))  # 0, 4, ..., 72 -> 19 bars
MAX_HEIGHT = 15

# Winamp's falloff settings: bars 3, 6, 12, 16 or 32 sixteenths of a level a
# frame (12 is its default, "moderate"), peaks accelerating by 1.05, 1.1, 1.2,
# 1.4 or 1.6 (1.1, "slow", is its default). One step quicker each here.
FALLOFF = 16        # "fast"
PEAK_FALLOFF = 1.2  # "moderate"
LOG_SCALE = 0.91    # 0 = linear, 1 = logarithmic


def js_round(x):
    """Math.round: half rounds up. Python's round() is banker's rounding."""
    return math.floor(x + 0.5)


# ------------------------------------------------------------- Nullsoft FFT

# Hann window, exactly as FFTNullsoft builds its envelope (power 1.0).
ENVELOPE = (0.5 + 0.5 * np.sin(np.arange(FFT_SIZE) * (2 * math.pi / FFT_SIZE) - math.pi / 2)).astype(np.float64)


def build_equalize():
    """Nullsoft's equalisation curve, a log10 ramp with a decaying bias."""
    eq = np.empty(SPECTRUM_BINS, dtype=np.float64)
    bias = 0.04
    for i in range(SPECTRUM_BINS):
        inv_half_nfreq = (9.0 - bias) / SPECTRUM_BINS
        eq[i] = math.log10(1.0 + bias + (i + 1) * inv_half_nfreq)
        bias /= 1.0025
    return eq


EQUALIZE = build_equalize()


def nullsoft_spectrum(wave):
    """Magnitude spectrum, equalised.

    FFTNullsoft is an in-place radix DFT; its magnitudes are the magnitudes of
    a standard forward FFT of the same windowed input, so numpy does the work.
    """
    spectrum = np.fft.fft(wave * ENVELOPE)[:SPECTRUM_BINS]
    return np.abs(spectrum) * EQUALIZE


# --------------------------------------------------- column frequency mapping

def build_column_map():
    """Where each of the 75 columns samples the spectrum, per VisPainter."""
    max_index = SPECTRUM_BINS
    log_max = math.log10(max_index)
    index1 = np.zeros(COLUMNS, dtype=np.int64)
    index2 = np.zeros(COLUMNS, dtype=np.int64)
    frac2 = np.zeros(COLUMNS, dtype=np.float64)
    for x in range(COLUMNS):
        linear_index = (x / (COLUMNS - 1)) * (max_index - 1)
        log_index = math.pow(10, (log_max * x) / (COLUMNS - 1))
        scaled = (1.0 - LOG_SCALE) * linear_index + LOG_SCALE * log_index
        i1 = min(math.floor(scaled), max_index - 1)
        i2 = min(math.ceil(scaled), max_index - 1)
        index1[x], index2[x] = i1, i2
        frac2[x] = 0.0 if i1 == i2 else scaled - i1
    return index1, index2, frac2


INDEX1, INDEX2, FRAC2 = build_column_map()


def columns_from(spectrum):
    # One spare zero slot: VisPainter's sample array is 76 long, and the last
    # thick band (columns 72-75) reads index 75, which is always 0.
    sample = np.zeros(COLUMNS + 1, dtype=np.float64)
    sample[:COLUMNS] = (1.0 - FRAC2) * spectrum[INDEX1] + FRAC2 * spectrum[INDEX2]
    return sample


# ------------------------------------------------------------- the analyser

class Analyser:
    """Per-bar falloff and peak state. Every column in a thick band gets the
    same input and so the same state, so it is tracked once per bar."""

    def __init__(self):
        n = len(BAR_STARTS)
        self.falloff = [0.0] * n    # saFalloff, levels
        self.peaks = [0] * n        # saPeaks, 1/256ths of a level (Int16Array)
        self.velocity = [0.0] * n   # saData2

    def step(self, sample):
        bars, peaks = [], []
        for b, chunk in enumerate(BAR_STARTS):
            # Thick band: average four columns. saData is an Int16Array, so
            # the average truncates toward zero — part of the stepped look.
            level = int((sample[chunk] + sample[chunk + 1] + sample[chunk + 2] + sample[chunk + 3]) / 4)
            level = min(level, MAX_HEIGHT)

            self.peaks[b] = min(self.peaks[b], MAX_HEIGHT * 256)

            # Bars fall at a constant rate and snap up instantly.
            self.falloff[b] -= FALLOFF / 16.0
            if self.falloff[b] <= level:
                self.falloff[b] = float(level)

            # A peak is reset to the bar whenever the bar catches it...
            if self.peaks[b] <= js_round(self.falloff[b] * 256):
                self.peaks[b] = int(self.falloff[b] * 256)
                self.velocity[b] = 3.0

            peak_level = int(self.peaks[b] / 256)

            # ...and otherwise falls, faster every frame.
            self.peaks[b] -= js_round(self.velocity[b])
            self.velocity[b] *= PEAK_FALLOFF
            if self.peaks[b] <= 0:
                self.peaks[b] = 0

            bar_level = max(0, min(MAX_HEIGHT, js_round(self.falloff[b])))
            bars.append(bar_level / MAX_HEIGHT)
            # Winamp pushes peaks below one level out of view.
            peaks.append(peak_level / MAX_HEIGHT if peak_level >= 1 else -1)
        return bars, peaks


def format_frame(bars, peaks):
    """The line the QML reads: bar levels, a bar, peak levels (-1 = hidden)."""
    return ",".join(f"{v:.3f}" for v in bars) + "|" + ",".join(
        "-1" if p < 0 else f"{p:.3f}" for p in peaks)


# -------------------------------------------------------------- oscilloscope

SCOPE_SAMPLES = 576   # Webamp slices the time-domain buffer to 576 samples
SCOPE_ROWS = 16
SCOPE_SLICE = SCOPE_SAMPLES // COLUMNS  # 7: one sample per column, no averaging


def scope_bytes(wave):
    """getByteTimeDomainData: a sample in [-1, 1] as 128 + 128x, clipped."""
    return np.clip(np.floor(128.0 * (1.0 + wave)), 0, 255).astype(np.int64)


def scope_columns(wave):
    """Winamp's oscilloscope, "lines" style, as (top, bottom, row) per column.

    Rows count down from the top. Each column's row is the sample's byte scaled
    onto sixteen rows and centred; the column is then filled from there to the
    previous column's row, so the wave reads as a connected line. When the
    line descends, the run starts one row lower, as Winamp and WACUP draw it.
    """
    data = scope_bytes(wave[:SCOPE_SAMPLES])
    columns = []
    last = 0
    for x in range(COLUMNS):
        y = js_round((data[SCOPE_SLICE * x] / 16) * 2) - 9
        y = max(0, min(SCOPE_ROWS - 1, y))
        if x == 0:
            last = y
        top, bottom = y, last
        last = y
        if bottom < top:
            top, bottom = bottom, top
            top += 1
        columns.append((top, bottom, y))
    return columns


def format_scope(columns):
    """The oscilloscope line the QML reads: o|top:bottom:row,..."""
    return "o|" + ",".join(f"{t}:{b}:{r}" for t, b, r in columns)


# ----------------------------------------------------------------- VU meter

# The empty end of the meter. Loud modern masters spend most of their time in
# the top ten decibels, which a 40 dB meter barely moved through.
VU_FLOOR_DB = -30.0
VU_FALL_PER_FRAME = 1.0 / 30   # 4/3 dB a frame: a full meter empties in half a second
VU_PEAK_HOLD_FRAMES = 30       # half a second at sixty frames
VU_PEAK_START_VELOCITY = 0.004
VU_PEAK_ACCELERATION = 1.2     # the analyser's peak falloff


def vu_level(samples):
    """A channel's loudness on the meter, 0-1.

    RMS in dBFS, lifted 3 dB so a full-scale sine reads 0 dB as on a peak
    meter, then placed on the -30 dB to 0 dB scale.
    """
    if len(samples) == 0:
        return 0.0
    rms = math.sqrt(float(np.mean(np.square(samples))))
    if rms <= 0:
        return 0.0
    db = 20 * math.log10(rms) + 3.0
    return max(0.0, min(1.0, (db - VU_FLOOR_DB) / -VU_FLOOR_DB))


class VuMeter:
    """Two channels of meter ballistics: instant rise, a steady fall, and a
    peak that holds for half a second before dropping with acceleration."""

    def __init__(self, channels=2):
        self.levels = [0.0] * channels
        self.peaks = [0.0] * channels
        self.hold = [0] * channels
        self.velocity = [VU_PEAK_START_VELOCITY] * channels

    def step(self, channel_samples):
        for c, samples in enumerate(channel_samples):
            target = vu_level(samples)
            self.levels[c] = max(target, self.levels[c] - VU_FALL_PER_FRAME)
            if self.levels[c] >= self.peaks[c]:
                self.peaks[c] = self.levels[c]
                self.hold[c] = VU_PEAK_HOLD_FRAMES
                self.velocity[c] = VU_PEAK_START_VELOCITY
            elif self.hold[c] > 0:
                self.hold[c] -= 1
            else:
                self.peaks[c] = max(self.levels[c], self.peaks[c] - self.velocity[c])
                self.velocity[c] *= VU_PEAK_ACCELERATION
        return list(self.levels), list(self.peaks)


def format_vu(levels, peaks):
    """The VU line the QML reads: v|left,right|left peak,right peak."""
    return "v|" + ",".join(f"{v:.3f}" for v in levels) + "|" + ",".join(f"{p:.3f}" for p in peaks)


# ------------------------------------------------------------ volume undoing

MAX_GAIN = 100.0  # +40 dB: past this, near-silence would be blown up into noise


def parse_stream(line, current):
    """A "stream <index>" line from the widget: a sink input's index, or "-"
    for the whole output (None). Anything else keeps the current stream."""
    parts = line.strip().split()
    if len(parts) != 2 or parts[0] != "stream":
        return current
    if parts[1] == "-":
        return None
    if parts[1].isdigit() and len(parts[1]) <= 10:
        return int(parts[1])
    return current


def parse_gain(line, current):
    """A "gain <factor>" line from the widget; anything else keeps the current
    gain. The factor is clamped to 0..MAX_GAIN."""
    parts = line.strip().split()
    if len(parts) != 2 or parts[0] != "gain":
        return current
    try:
        value = float(parts[1])
    except ValueError:
        return current
    if not math.isfinite(value):
        return current
    return max(0.0, min(MAX_GAIN, value))


# ------------------------------------------------------------------ capture

recorder = None


def cleanup(*_):
    stop_recorder()
    sys.exit(0)


def get_monitor_target():
    try:
        res = subprocess.run(["pactl", "get-default-sink"], capture_output=True, text=True, timeout=1.0)
        sink = res.stdout.strip()
        if sink:
            return sink + ".monitor"
    except Exception:
        pass
    return None


def start_recorder(channels=1, stream=None):
    cmd = ["parec", "--format=s16le", f"--rate={RATE}", f"--channels={channels}", "--latency-msec=20"]
    if stream is not None:
        # One app's playback only, before it is mixed with anything else.
        cmd += [f"--monitor-stream={int(stream)}"]
    else:
        monitor = get_monitor_target()
        if monitor:
            cmd += ["-d", monitor]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    os.set_blocking(proc.stdout.fileno(), False)
    return proc


def stop_recorder():
    global recorder
    if recorder is None:
        return
    try:
        recorder.terminate()
        recorder.wait(timeout=1)
    except Exception:
        try:
            recorder.kill()
        except Exception:
            pass
    recorder = None


# Webamp reads bytes from getByteTimeDomainData, which maps a sample in
# [-1, 1] to 128 + 128x, then feeds (byte - 128) / 24 to the FFT. The same
# gain here keeps the bar heights matching.
INPUT_GAIN = 128.0 / 24.0


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Winamp's classic visualisations")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--oscilloscope", action="store_true",
                      help="draw Winamp's oscilloscope instead of the spectrum analyser")
    mode.add_argument("--vu", action="store_true",
                      help="measure a stereo VU meter instead of the spectrum analyser")
    return parser.parse_args(argv)


def main():
    global recorder
    signal.signal(signal.SIGINT, cleanup)
    signal.signal(signal.SIGTERM, cleanup)

    args = parse_args(sys.argv[1:])
    analyser = Analyser()
    meter = VuMeter()
    window = np.zeros(FFT_SIZE, dtype=np.float64)
    # The VU meter needs both channels; the analyser and scope are mono.
    channels = 2 if args.vu else 1
    hop_bytes = HOP * 2 * channels
    pending = bytearray()

    stream = None
    recorder = start_recorder(channels, stream)
    gain = 1.0
    stdin_open = True
    stdin_buffer = b""
    os.set_blocking(sys.stdin.fileno(), False)

    while True:
        if recorder.poll() is not None:
            stop_recorder()
            # A stream that ended (the player closed it) can't be recorded
            # again; fall back to the whole output until told otherwise.
            stream = None
            recorder = start_recorder(channels, stream)
            pending = bytearray()

        watched = [recorder.stdout] + ([sys.stdin] if stdin_open else [])
        ready, _, _ = select.select(watched, [], [], 1.0)
        if not ready:
            continue

        if sys.stdin in ready:
            chunk = os.read(sys.stdin.fileno(), 4096)
            if not chunk:
                stdin_open = False
            else:
                stdin_buffer = (stdin_buffer + chunk)[-4096:]
                *lines, stdin_buffer = stdin_buffer.split(b"\n")
                wanted = stream
                for raw in lines:
                    text = raw.decode("utf-8", "replace")
                    gain = parse_gain(text, gain)
                    wanted = parse_stream(text, wanted)
                # Read every line first, then switch once.
                if wanted != stream:
                    stream = wanted
                    stop_recorder()
                    recorder = start_recorder(channels, stream)
                    pending = bytearray()
                    continue
        if recorder.stdout not in ready:
            continue

        data = recorder.stdout.read(hop_bytes * 4)
        if not data:
            continue
        pending += data

        # Advance one analyser frame per hop, so falloff speed tracks audio
        # time rather than how often the pipe happens to deliver.
        while len(pending) >= hop_bytes:
            hop = np.frombuffer(bytes(pending[:hop_bytes]), dtype=np.int16).astype(np.float64) / 32768.0 * gain
            del pending[:hop_bytes]

            if args.vu:
                # Interleaved left, right.
                levels, peaks = meter.step([hop[0::2], hop[1::2]])
                line = format_vu(levels, peaks)
                try:
                    sys.stdout.write(line + "\n")
                    sys.stdout.flush()
                except BrokenPipeError:
                    cleanup()
                continue

            window = np.roll(window, -HOP)
            window[-HOP:] = hop

            if args.oscilloscope:
                # The newest audio, unscaled: Webamp's scope reads the raw
                # time-domain bytes rather than the analyser's gained input.
                line = format_scope(scope_columns(window[-SCOPE_SAMPLES:]))
            else:
                bars, peaks = analyser.step(columns_from(nullsoft_spectrum(window * INPUT_GAIN)))
                line = format_frame(bars, peaks)

            try:
                sys.stdout.write(line + "\n")
                sys.stdout.flush()
            except BrokenPipeError:
                cleanup()


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        pass
    finally:
        stop_recorder()
