"""Tests for spectrum.py, the port of Winamp's classic spectrum analyser.

Run with the standard library alone:

    python3 -m unittest discover -s tests

The behaviour pinned here is the behaviour that makes it look like Winamp, as
reconstructed by Webamp from the Winamp 2.63 and 5.666 executables: nineteen
bars, instant rise, linear fall, and peaks that hang before falling with
acceleration. A change that breaks one of these is a change to how the
visualiser feels, so it should fail loudly.
"""
import importlib.util
import math
import pathlib
import unittest

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("spectrum", ROOT / "spectrum.py")
spectrum = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(spectrum)


def tone(frequency=1000.0, amplitude=0.5):
    t = np.arange(spectrum.FFT_SIZE) / spectrum.RATE
    return amplitude * np.sin(2 * math.pi * frequency * t)


def silence():
    return np.zeros(spectrum.FFT_SIZE)


def analyse(analyser, wave):
    return analyser.step(spectrum.columns_from(spectrum.nullsoft_spectrum(wave * spectrum.INPUT_GAIN)))


def levels(values):
    """0-1 floats back to Winamp's integer levels; -1 stays -1."""
    return [v if v < 0 else round(v * spectrum.MAX_HEIGHT) for v in values]


class LayoutTest(unittest.TestCase):
    def test_nineteen_thick_bars(self):
        # 75 columns in fours: 0, 4, ..., 72.
        self.assertEqual(len(spectrum.BAR_STARTS), 19)
        self.assertEqual(spectrum.BAR_STARTS[0], 0)
        self.assertEqual(spectrum.BAR_STARTS[-1], 72)

    def test_hop_is_one_sixtieth_of_a_second(self):
        # Winamp's falloff constants are per frame at 60 fps.
        self.assertEqual(spectrum.HOP, 735)

    def test_last_thick_band_reads_a_padding_zero(self):
        # Columns 72-75: index 75 must exist and be zero, as in VisPainter.
        sample = spectrum.columns_from(np.ones(spectrum.SPECTRUM_BINS))
        self.assertEqual(len(sample), spectrum.COLUMNS + 1)
        self.assertEqual(sample[spectrum.COLUMNS], 0.0)


class NullsoftFftTest(unittest.TestCase):
    def test_envelope_is_a_hann_window(self):
        env = spectrum.ENVELOPE
        self.assertAlmostEqual(env[0], 0.0, places=6)
        self.assertAlmostEqual(env[spectrum.FFT_SIZE // 2], 1.0, places=6)

    def test_equalisation_rises_monotonically(self):
        eq = spectrum.EQUALIZE
        self.assertEqual(len(eq), spectrum.SPECTRUM_BINS)
        self.assertTrue(np.all(eq > 0))
        self.assertTrue(np.all(np.diff(eq) > 0))

    def test_column_map_stays_inside_the_spectrum(self):
        self.assertTrue(np.all(spectrum.INDEX1 >= 0))
        self.assertTrue(np.all(spectrum.INDEX2 <= spectrum.SPECTRUM_BINS - 1))
        self.assertTrue(np.all((spectrum.FRAC2 >= 0) & (spectrum.FRAC2 < 1)))

    def test_column_map_leans_logarithmic(self):
        # At 91% logarithmic, the middle column sits far below the middle bin.
        middle = spectrum.COLUMNS // 2
        self.assertLess(spectrum.INDEX1[middle], spectrum.SPECTRUM_BINS // 4)

    def test_a_tone_lands_in_one_region(self):
        spec = spectrum.nullsoft_spectrum(tone(1000) * spectrum.INPUT_GAIN)
        peak_bin = int(np.argmax(spec))
        expected = round(1000 / (spectrum.RATE / spectrum.FFT_SIZE))
        self.assertLessEqual(abs(peak_bin - expected), 1)


class BarDynamicsTest(unittest.TestCase):
    def setUp(self):
        self.analyser = spectrum.Analyser()

    def loudest_bar(self, bars):
        return max(range(len(bars)), key=lambda i: bars[i])

    def test_silence_draws_nothing(self):
        bars, peaks = analyse(self.analyser, silence())
        self.assertEqual(levels(bars), [0] * 19)
        self.assertEqual(peaks, [-1] * 19)

    def test_bars_rise_instantly(self):
        bars, _ = analyse(self.analyser, tone())
        self.assertEqual(max(levels(bars)), spectrum.MAX_HEIGHT)

    def test_bars_never_exceed_max_height(self):
        bars, _ = analyse(self.analyser, tone(amplitude=1.0))
        self.assertTrue(all(0 <= b <= 1 for b in bars))

    def test_bars_fall_linearly_one_level_a_frame(self):
        bars, _ = analyse(self.analyser, tone())
        hot = self.loudest_bar(bars)
        heights = []
        for _ in range(21):
            bars, _ = analyse(self.analyser, silence())
            heights.append(levels(bars)[hot])
        # 15 falling one level a frame: zero on frame 15.
        self.assertEqual(heights[0], 14)
        self.assertEqual(heights[14], 0)
        self.assertTrue(all(a >= b for a, b in zip(heights, heights[1:])))
        # Never more than one level per frame.
        self.assertTrue(all(a - b <= 1 for a, b in zip(heights, heights[1:])))


class PeakDynamicsTest(unittest.TestCase):
    def peak_trace(self, frames_of_silence):
        analyser = spectrum.Analyser()
        bars, _ = analyse(analyser, tone())
        hot = max(range(19), key=lambda i: bars[i])
        trace = []
        for _ in range(frames_of_silence):
            _, peaks = analyse(analyser, silence())
            trace.append(levels(peaks)[hot])
        return trace

    def test_peaks_hang_before_falling(self):
        trace = self.peak_trace(60)
        # Velocity starts at 3/256 of a level: well over a dozen frames pass
        # before the peak loses its first whole level.
        self.assertTrue(all(p == trace[0] for p in trace[:15]))

    def test_peaks_fall_with_acceleration(self):
        trace = [p for p in self.peak_trace(60) if p >= 0]
        drops = [a - b for a, b in zip(trace, trace[1:])]
        first_drop = next(i for i, d in enumerate(drops) if d > 0)
        # Once falling, the gaps between whole-level drops shrink.
        later = drops[first_drop:]
        self.assertGreater(sum(later[-5:]), sum(later[:5]))

    def test_fallen_peaks_are_hidden(self):
        trace = self.peak_trace(80)
        self.assertEqual(trace[-1], -1)

    def test_a_peak_never_sits_below_its_bar(self):
        analyser = spectrum.Analyser()
        for frame in range(40):
            wave = tone() if frame % 10 < 3 else silence()
            bars, peaks = analyse(analyser, wave)
            for b, p in zip(levels(bars), levels(peaks)):
                if p >= 0:
                    self.assertGreaterEqual(p, b)


class OscilloscopeTest(unittest.TestCase):
    """Winamp's oscilloscope, "lines" style, as Webamp's WavePaintHandler."""

    def test_silence_is_a_flat_line_just_above_centre(self):
        # A silent byte is 128: round(128 / 16 * 2) - 9 = row 7 of 16.
        columns = spectrum.scope_columns(np.zeros(spectrum.SCOPE_SAMPLES))
        self.assertEqual(len(columns), 75)
        self.assertTrue(all(c == (7, 7, 7) for c in columns))

    def test_one_sample_per_column_every_seventh(self):
        self.assertEqual(spectrum.SCOPE_SLICE, 7)

    def test_rows_stay_on_the_grid(self):
        loud = np.sign(np.sin(np.arange(spectrum.SCOPE_SAMPLES) / 3.0))
        for top, bottom, row in spectrum.scope_columns(loud):
            self.assertTrue(0 <= top <= bottom <= 15)
            self.assertTrue(0 <= row <= 15)

    def test_extremes_reach_the_edges(self):
        high = spectrum.scope_columns(np.full(spectrum.SCOPE_SAMPLES, 1.0))
        low = spectrum.scope_columns(np.full(spectrum.SCOPE_SAMPLES, -1.0))
        self.assertEqual(high[5][2], 15)   # byte 255 -> row 23, clamped
        self.assertEqual(low[5][2], 0)     # byte 0 -> row -9, clamped

    def test_the_line_joins_each_column_to_the_last(self):
        wave = np.zeros(spectrum.SCOPE_SAMPLES)
        wave[spectrum.SCOPE_SLICE * 10] = 0.9   # a spike at column 10
        columns = spectrum.scope_columns(wave)
        # Down from row 7 to 15 (byte 243, clamped): the run starts one row
        # lower, at 8, as Winamp draws a descending line.
        self.assertEqual(columns[10], (8, 15, 15))
        # Back up to 7: the run covers 7 to 15 with no offset.
        self.assertEqual(columns[11], (7, 15, 7))
        self.assertEqual(columns[12], (7, 7, 7))

    def test_scope_line_shape(self):
        line = spectrum.format_scope([(7, 9, 9)] * 75)
        self.assertTrue(line.startswith("o|7:9:9,"))
        self.assertEqual(len(line[2:].split(",")), 75)

    def test_bytes_follow_web_audio(self):
        self.assertEqual(list(spectrum.scope_bytes(np.array([-1.0, 0.0, 0.999, 2.0]))), [0, 128, 255, 255])

    def test_oscilloscope_is_opt_in(self):
        self.assertFalse(spectrum.parse_args([]).oscilloscope)
        self.assertTrue(spectrum.parse_args(["--oscilloscope"]).oscilloscope)


class VuMeterTest(unittest.TestCase):
    def sine(self, amplitude, n=spectrum.HOP):
        return amplitude * np.sin(2 * math.pi * 1000 * np.arange(n) / spectrum.RATE)

    def test_silence_reads_empty(self):
        self.assertEqual(spectrum.vu_level(np.zeros(spectrum.HOP)), 0.0)
        self.assertEqual(spectrum.vu_level(np.array([])), 0.0)

    def test_a_full_scale_sine_reads_full(self):
        self.assertAlmostEqual(spectrum.vu_level(self.sine(1.0)), 1.0, places=2)

    def test_fifteen_db_down_reads_half(self):
        self.assertAlmostEqual(spectrum.vu_level(self.sine(10 ** (-15 / 20))), 0.5, places=2)

    def test_meter_rises_instantly_and_falls_a_db_a_frame(self):
        meter = spectrum.VuMeter()
        levels, _ = meter.step([self.sine(1.0), self.sine(1.0)])
        self.assertGreater(levels[0], 0.99)
        levels, _ = meter.step([np.zeros(spectrum.HOP), np.zeros(spectrum.HOP)])
        self.assertAlmostEqual(levels[0], 1.0 - spectrum.VU_FALL_PER_FRAME, delta=0.01)

    def test_channels_are_measured_separately(self):
        meter = spectrum.VuMeter()
        levels, _ = meter.step([self.sine(1.0), self.sine(0.01)])
        self.assertGreater(levels[0], 0.99)
        self.assertLess(levels[1], 0.1)

    def test_peak_holds_then_falls(self):
        meter = spectrum.VuMeter()
        meter.step([self.sine(1.0), self.sine(1.0)])
        silence = [np.zeros(spectrum.HOP), np.zeros(spectrum.HOP)]
        held = [meter.step(silence)[1][0] for _ in range(spectrum.VU_PEAK_HOLD_FRAMES)]
        self.assertTrue(all(p > 0.99 for p in held))
        falling = [meter.step(silence)[1][0] for _ in range(20)]
        self.assertLess(falling[-1], 0.99)
        drops = [a - b for a, b in zip(falling, falling[1:])]
        self.assertGreater(drops[-1], drops[0])

    def test_peak_never_sits_below_the_level(self):
        meter = spectrum.VuMeter()
        for frame in range(80):
            amp = 1.0 if frame % 20 < 5 else 0.05
            levels, peaks = meter.step([self.sine(amp), self.sine(amp / 2)])
            for l, p in zip(levels, peaks):
                self.assertGreaterEqual(p + 1e-9, l)

    def test_vu_line_shape_and_modes(self):
        self.assertEqual(spectrum.format_vu([0.5, 0.25], [0.75, 0.5]), "v|0.500,0.250|0.750,0.500")
        self.assertTrue(spectrum.parse_args(["--vu"]).vu)
        with self.assertRaises(SystemExit):
            spectrum.parse_args(["--vu", "--oscilloscope"])


class GainTest(unittest.TestCase):
    def test_gain_lines_parse_and_clamp(self):
        self.assertEqual(spectrum.parse_gain("gain 3.125\n", 1.0), 3.125)
        self.assertEqual(spectrum.parse_gain("gain 1e9", 1.0), spectrum.MAX_GAIN)
        self.assertEqual(spectrum.parse_gain("gain -2", 1.0), 0.0)
        self.assertEqual(spectrum.parse_gain("gain nan", 2.0), 2.0)
        self.assertEqual(spectrum.parse_gain("volume 3", 2.0), 2.0)
        self.assertEqual(spectrum.parse_gain("gain", 2.0), 2.0)
        self.assertEqual(spectrum.parse_gain("", 2.0), 2.0)


class StreamTest(unittest.TestCase):
    def test_stream_lines_parse(self):
        self.assertEqual(spectrum.parse_stream("stream 23109\n", None), 23109)
        self.assertIsNone(spectrum.parse_stream("stream -", 23109))
        self.assertEqual(spectrum.parse_stream("stream abc", 5), 5)
        self.assertEqual(spectrum.parse_stream("stream 12345678901", 5), 5)
        self.assertEqual(spectrum.parse_stream("gain 3", 5), 5)


class OutputFormatTest(unittest.TestCase):
    def test_frame_line_shape(self):
        line = spectrum.format_frame([0.5] * 19, [0.6] * 18 + [-1])
        bars, peaks = line.split("|")
        self.assertEqual(len(bars.split(",")), 19)
        self.assertEqual(len(peaks.split(",")), 19)
        self.assertTrue(peaks.endswith(",-1"))
        self.assertNotIn("\n", line)

    def test_js_round_rounds_half_up(self):
        # Math.round, not Python's banker's rounding.
        self.assertEqual(spectrum.js_round(0.5), 1)
        self.assertEqual(spectrum.js_round(2.5), 3)
        self.assertEqual(spectrum.js_round(-0.5), 0)


if __name__ == "__main__":
    unittest.main()
