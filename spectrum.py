#!/usr/bin/env python3
"""Winamp's classic spectrum analyser, fed from the default sink's monitor.

This mirrors the analyser in Winamp 2.x/5.x as reconstructed by Webamp
(packages/webamp/js/components/VisPainter.ts), whose authors worked it out from
the Winamp 2.63 and 5.666 executables, and uses the Nullsoft FFT from WACUP's
vis_classic (via Webamp's FFTNullsoft.ts). Settings are those of a fresh Winamp
install: thick bands, peaks on, "moderate" bar falloff, "slow" peak falloff.

What makes it look like Winamp rather than a generic FFT:

  * 19 bars — 75 columns grouped in fours, three lit and one gap.
  * A 1024-sample Hann-windowed FFT with Nullsoft's log-shaped equalisation,
    mapped to columns on a scale that is 91% logarithmic and 9% linear.
  * Bars rise instantly and fall linearly, 12/16 of a level per frame.
  * Peaks jump to the bar, then fall with acceleration: velocity starts at 3
    (in 1/256ths of a level) and grows by 1.1x each frame.
  * Everything is quantised to 16 integer levels, which is the stepped look.

Winamp's falloff constants are per frame and Webamp runs them at 60 fps, so the
analyser advances one frame per 1/60 s of audio (a 735-sample hop over a
1024-sample sliding window) to fall at the same speed.

Output is one line per frame: 19 bar levels, a bar, then 19 peak levels, each
0.0-1.0, with -1 for a peak that has fallen out of sight:

    0.533,0.4,...|0.6,-1,...

Exits cleanly on SIGTERM/SIGINT/broken pipe so the QML Process that owns it can
start and stop it on demand without leaking recorder subprocesses.
"""
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

FALLOFF = 12        # "moderate", Winamp's default
PEAK_FALLOFF = 1.1  # "slow", Winamp's default
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


def start_recorder():
    monitor = get_monitor_target()
    cmd = ["parec", "--format=s16le", f"--rate={RATE}", "--channels=1", "--latency-msec=20"]
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


def main():
    global recorder
    signal.signal(signal.SIGINT, cleanup)
    signal.signal(signal.SIGTERM, cleanup)

    analyser = Analyser()
    window = np.zeros(FFT_SIZE, dtype=np.float64)
    hop_bytes = HOP * 2
    pending = bytearray()

    recorder = start_recorder()

    while True:
        if recorder.poll() is not None:
            stop_recorder()
            recorder = start_recorder()
            pending = bytearray()

        ready, _, _ = select.select([recorder.stdout], [], [], 1.0)
        if not ready:
            continue

        data = recorder.stdout.read(hop_bytes * 4)
        if not data:
            continue
        pending += data

        # Advance one analyser frame per hop, so falloff speed tracks audio
        # time rather than how often the pipe happens to deliver.
        while len(pending) >= hop_bytes:
            hop = np.frombuffer(bytes(pending[:hop_bytes]), dtype=np.int16).astype(np.float64) / 32768.0
            del pending[:hop_bytes]

            window = np.roll(window, -HOP)
            window[-HOP:] = hop

            bars, peaks = analyser.step(columns_from(nullsoft_spectrum(window * INPUT_GAIN)))

            try:
                sys.stdout.write(format_frame(bars, peaks) + "\n")
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
