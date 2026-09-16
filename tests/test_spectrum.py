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

    def test_bars_fall_linearly_three_quarters_of_a_level_a_frame(self):
        bars, _ = analyse(self.analyser, tone())
        hot = self.loudest_bar(bars)
        heights = []
        for _ in range(21):
            bars, _ = analyse(self.analyser, silence())
            heights.append(levels(bars)[hot])
        # 15 falling 0.75 a frame, rounded as Winamp rounds: zero on frame 20.
        self.assertEqual(heights[0], 14)
        self.assertEqual(heights[19], 0)
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
