import QtQuick
import QtTest
import "../Logic.js" as Logic

// Tests for Logic.js, the pure functions BarWidget.qml runs.
//
//   QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_logic.qml
//
// Most of this guards input from other applications: anything that registers
// an MPRIS player chooses its art URL and bus name.
TestCase {
  name: "Logic"

  // ------------------------------------------------------------ safeArtUrl

  function test_art_accepts_absolute_file_urls() {
    compare(Logic.safeArtUrl("file:///tmp/cover.png"), "file:///tmp/cover.png")
    compare(Logic.safeArtUrl("file:///home/me/.cache/art/a%20b.jpg"), "file:///home/me/.cache/art/a%20b.jpg")
  }

  function test_art_accepts_https() {
    compare(Logic.safeArtUrl("https://i.scdn.co/image/ab67616d"), "https://i.scdn.co/image/ab67616d")
    compare(Logic.safeArtUrl("https://i.ytimg.com/vi/x/hqdefault.jpg?sqp=1"), "https://i.ytimg.com/vi/x/hqdefault.jpg?sqp=1")
  }

  function test_art_accepts_embedded_images() {
    // How mpv-mpris publishes a file's own embedded cover.
    var jpeg = "data:image/jpeg;base64,/9j/4AAQSkZJRgABAgAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgK"
    compare(Logic.safeArtUrl(jpeg), jpeg)
    compare(Logic.safeArtUrl("data:image/png;base64,iVBORw0KGgo="), "data:image/png;base64,iVBORw0KGgo=")
    compare(Logic.safeArtUrl("data:image/webp;base64,UklGRg=="), "data:image/webp;base64,UklGRg==")
  }

  function test_art_accepts_a_realistically_large_embedded_cover() {
    // ~78 KB, the size mpv sent for a real track. The URL length cap must not
    // apply to inline data.
    var big = "data:image/jpeg;base64," + new Array(78001).join("A")
    compare(Logic.safeArtUrl(big), big)
  }

  function test_art_rejects_data_that_is_not_a_base64_raster_image() {
    var rejected = [
      "data:text/html;base64,PHNjcmlwdD4=",
      "data:image/svg+xml;base64,PHN2Zz4=",
      "data:image/png,rawbytes",
      "data:image/png;base64,not base64!",
      "data:image/png;base64,",
      "data:;base64,AAAA",
      "data:image/png;base64,AAAA\nAAAA",
    ]
    for (var i = 0; i < rejected.length; i++)
      compare(Logic.safeArtUrl(rejected[i]), "", rejected[i])
  }

  function test_art_rejects_oversized_embedded_art() {
    var huge = "data:image/jpeg;base64," + new Array(Logic.MAX_DATA_ART_LENGTH + 1).join("A")
    compare(Logic.safeArtUrl(huge), "")
  }

  function test_art_rejects_cleartext_and_internal_schemes() {
    var rejected = [
      "http://example.com/cover.png",
      "image://icon/audio-x-generic",
      "qrc:/shell/secret.png",
      "ftp://example.com/cover.png",
      "javascript:alert(1)",
      "file://relative/path.png",
      "file:relative.png",
      "/tmp/cover.png",
      "https://",
      "https:///no-host",
    ]
    for (var i = 0; i < rejected.length; i++)
      compare(Logic.safeArtUrl(rejected[i]), "", rejected[i])
  }

  function test_art_rejects_credentials_in_the_authority() {
    // An @ before the host is how user:pass@ smuggles a different host past
    // a quick glance.
    compare(Logic.safeArtUrl("https://user:pass@evil.example/c.png"), "")
  }

  function test_art_rejects_whitespace_and_control_characters() {
    compare(Logic.safeArtUrl("https://example.com/a b.png"), "")
    compare(Logic.safeArtUrl("https://example.com/a\nb.png"), "")
    compare(Logic.safeArtUrl("file:///tmp/a\u0000.png"), "")
  }

  function test_art_rejects_oversized_urls() {
    var huge = "https://example.com/" + new Array(3000).join("a")
    compare(Logic.safeArtUrl(huge), "")
  }

  function test_art_handles_missing_values() {
    compare(Logic.safeArtUrl(undefined), "")
    compare(Logic.safeArtUrl(null), "")
    compare(Logic.safeArtUrl(""), "")
  }

  // --------------------------------------------------------- isMprisBusName

  function test_bus_name_accepts_real_players() {
    verify(Logic.isMprisBusName("org.mpris.MediaPlayer2.mpv"))
    verify(Logic.isMprisBusName("org.mpris.MediaPlayer2.spotify"))
    verify(Logic.isMprisBusName("org.mpris.MediaPlayer2.chromium.instance12345"))
    verify(Logic.isMprisBusName("org.mpris.MediaPlayer2.firefox.instance_1_42"))
    verify(Logic.isMprisBusName("org.mpris.MediaPlayer2.brave-origin"))
  }

  function test_bus_name_rejects_everything_else() {
    var rejected = [
      "",
      "org.mpris.MediaPlayer2",
      "org.mpris.MediaPlayer2.",
      "org.freedesktop.Notifications",
      ":1.42",
      "org.mpris.MediaPlayer2.mpv; rm -rf ~",
      "org.mpris.MediaPlayer2.mpv --user",
      "org.mpris.MediaPlayer2..double",
      "org.mpris.MediaPlayer2.mpv/../x",
      "-org.mpris.MediaPlayer2.mpv",
    ]
    for (var i = 0; i < rejected.length; i++)
      verify(!Logic.isMprisBusName(rejected[i]), rejected[i])
  }

  function test_bus_name_respects_the_dbus_length_cap() {
    var base = "org.mpris.MediaPlayer2."
    verify(Logic.isMprisBusName(base + new Array(255 - base.length + 1).join("a")))
    verify(!Logic.isMprisBusName(base + new Array(256 - base.length + 1).join("a")))
  }

  // ---------------------------------------------------- parseBusctlPosition

  function test_position_parses_microseconds_to_seconds() {
    compare(Logic.parseBusctlPosition("x 8882398"), 8.882398)
    compare(Logic.parseBusctlPosition("x 0"), 0)
    compare(Logic.parseBusctlPosition("  x 1000000  "), 1)
  }

  function test_position_rejects_anything_that_is_not_a_clean_int64() {
    var rejected = [
      "",
      "x",
      "x -5",
      "s \"8882398\"",
      "d 8.88",
      "Failed to get property Position: Unknown object",
      "x 12 extra",
      "8882398",
    ]
    for (var i = 0; i < rejected.length; i++)
      compare(Logic.parseBusctlPosition(rejected[i]), -1, rejected[i])
    compare(Logic.parseBusctlPosition(undefined), -1)
  }

  // -------------------------------------------------------------- scope

  function test_scope_frames_parse() {
    var cols = Logic.parseScopeFrame("o|7:9:9,8:8:8")
    compare(cols.length, 2)
    compare(cols[0], { top: 7, bottom: 9, row: 9 })
  }

  function test_scope_frames_are_bounded_and_clamped() {
    var many = []
    for (var i = 0; i < 200; i++) many.push("7:7:7")
    compare(Logic.parseScopeFrame("o|" + many.join(",")).length, 75)
    compare(Logic.parseScopeFrame("o|-4:99:40")[0], { top: 0, bottom: 15, row: 15 })
    compare(Logic.parseScopeFrame("o|9:3:5")[0], { top: 9, bottom: 9, row: 5 })
    compare(Logic.parseScopeFrame("o|x:1:2,1:2")[0], null)
    compare(Logic.parseScopeFrame("o|x:1:2,1:2")[1], null)
    compare(Logic.parseScopeFrame("0.5,0.2|0.6"), [])
    compare(Logic.parseScopeFrame(undefined), [])
  }

  function test_scope_is_brightest_in_the_middle() {
    verify(Logic.scopeBrightness(7) > Logic.scopeBrightness(12))
    verify(Logic.scopeBrightness(7) > Logic.scopeBrightness(1))
    compare(Logic.scopeBrightness(6), 1)
  }

  function test_visualisations_cycle_through_four() {
    compare(Logic.nextVisualisation("analyser"), "winamp5")
    compare(Logic.nextVisualisation("winamp5"), "mirror")
    compare(Logic.nextVisualisation("mirror"), "vu")
    compare(Logic.nextVisualisation("vu"), "oscilloscope")
    compare(Logic.nextVisualisation("oscilloscope"), "off")
    compare(Logic.nextVisualisation("off"), "analyser")
    compare(Logic.nextVisualisation("junk"), "winamp5")
  }

  function test_old_settings_carry_over() {
    var d = Logic.parsePreferences("")
    compare(d.titleWidth, 260)
    compare(d.scrollTitle, true)
    compare(Logic.parsePreferences('{"version":1,"scrollTitle":false}').scrollTitle, false)
    compare(d.settingsMigrated, false)
    var m = Logic.migrateSettings(d, { hideWhenIdle: true, pauseOthers: true, maxLabelWidth: 200, visualizerEnabled: false })
    compare(m.hideWhenIdle, true)
    compare(m.pauseOthers, true)
    compare(m.titleWidth, 160)
    compare(m.visualisation, "off")
    compare(Logic.migrateSettings(d, { visualizerEnabled: true }).visualisation, "analyser")
    compare(m.settingsMigrated, true)
    var none = Logic.migrateSettings(Object.assign({}, d, { pauseOthers: true }), {})
    compare(none.pauseOthers, true)
    compare(none.titleWidth, 260)
    compare(Logic.migrateSettings(d, { maxLabelWidth: 80 }).titleWidth, 160)
    compare(Logic.migrateSettings(d, { maxLabelWidth: 600 }).titleWidth, 0)
    compare(Logic.migrateSettings(d, { maxLabelWidth: 430 }).titleWidth, 0)
    compare(Logic.migrateSettings(d, { maxLabelWidth: 420 }).titleWidth, 260)
    compare(Logic.migrateSettings(d, { maxLabelWidth: "junk" }).titleWidth, 260)
    compare(Logic.migrateSettings(d, null).settingsMigrated, true)
    compare(Logic.parsePreferences('{"version":1,"titleWidth":0,"settingsMigrated":true}').titleWidth, 0)
    compare(Logic.parsePreferences('{"version":1,"titleWidth":300}').titleWidth, 260)
    compare(Logic.parsePreferences('{"version":1,"titleWidth":480}').titleWidth, 260)
    compare(JSON.parse(Logic.serializePreferences({ titleWidth: 160, settingsMigrated: true })).titleWidth, 160)
  }

  function test_visualiser_colours() {
    compare(Logic.visColour("winamp"), "winamp")
    compare(Logic.visColour("white"), "gradient")
    compare(Logic.visColour(undefined), "gradient")
    compare(Logic.VIS_COLOURS, ["gradient", "solid", "winamp"])
    compare(Logic.mixHex("#000000", "#FFFFFF", 0.5), "#808080")
    var grad = Logic.spectrumColors("gradient", "#00FF00")
    compare(grad[0], "#B3FFB3")
    compare(grad[15], "#006600")
    compare(Logic.spectrumColors("solid", "#123456")[7], "#123456")
    compare(Logic.spectrumColors("winamp", "#123456")[0], "#EF3110")
    compare(Logic.spectrumColorAt(grad, 0), "#006600")
    compare(Logic.spectrumColorAt(grad, 1), "#B3FFB3")
    compare(Logic.vuSegmentColor(grad, 0), "#006600")
    compare(Logic.vuSegmentColor(grad, 18), "#B3FFB3")
    compare(Logic.scopeColor("winamp", grad, 7), "#FFFFFF")
    compare(Logic.scopeColor("gradient", grad, 3), grad[3])
    compare(Logic.scopeColor("solid", grad, 3), null)
    verify(Logic.winamp5RowLit(0))
    verify(!Logic.winamp5RowLit(1))
    compare(Logic.parsePreferences('{"version":1}').visColour, "gradient")
    compare(Logic.parsePreferences('{"version":1,"visColour":"solid"}').visColour, "solid")
    compare(JSON.parse(Logic.serializePreferences({ visColour: "winamp" })).visColour, "winamp")
  }

  function test_mirrored_bars_put_the_lowest_band_in_the_middle() {
    compare(Logic.MIRROR_BARS, 19)
    compare(Logic.mirrorBand(9), 0)
    compare(Logic.mirrorBand(8), 1)
    compare(Logic.mirrorBand(10), 2)
    compare(Logic.mirrorBand(0), 17)
    compare(Logic.mirrorBand(18), 18)
    // Every band appears exactly once.
    var seen = []
    for (var i = 0; i < 19; i++) seen.push(Logic.mirrorBand(i))
    seen.sort(function(a, b) { return a - b })
    compare(seen, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18])
  }

  function test_pause_others_is_off_unless_saved_on() {
    var both = Logic.parsePreferences(Logic.serializePreferences({ visualisation: "mirror", pauseOthers: true }))
    compare(both.visualisation, "mirror")
    compare(both.pauseOthers, true)
    compare(Logic.parsePreferences('{"version":1,"pauseOthers":"yes"}').pauseOthers, false)
    compare(Logic.parsePreferences('{"version":1}').pauseOthers, false)
    compare(Logic.parsePreferences("junk").pauseOthers, false)
  }

  function test_vu_frames_parse_and_clamp() {
    compare(Logic.parseVuFrame("v|0.720,0.655|0.810,0.790"), { levels: [0.72, 0.655], peaks: [0.81, 0.79] })
    compare(Logic.parseVuFrame("v|2,-1|x,0.5"), { levels: [1, 0], peaks: [0, 0.5] })
    compare(Logic.parseVuFrame("v|0.5"), { levels: [0.5, 0], peaks: [0, 0] })
    compare(Logic.parseVuFrame("0.5,0.2|0.6"), { levels: [0, 0], peaks: [0, 0] })
    compare(Logic.parseVuFrame(undefined), { levels: [0, 0], peaks: [0, 0] })
  }

  function test_visualiser_gain_undoes_player_volume() {
    compare(Logic.visualiserGain(0.32, false), 1 / 0.32)
    compare(Logic.visualiserGain(0.5, true), 8)
    compare(Logic.visualiserGain(1, false), 1)
    compare(Logic.visualiserGain(0, false), 1)
    compare(Logic.visualiserGain(0.001, false), Logic.MAX_VISUALISER_GAIN)
    compare(Logic.visualiserGain(undefined, true), 1)
    verify(Logic.volumeIsCubic("org.mpris.MediaPlayer2.mpv"))
    verify(Logic.volumeIsCubic("org.mpris.MediaPlayer2.mpv.instance-ab12"))
    verify(!Logic.volumeIsCubic("org.mpris.MediaPlayer2.archamp"))
    verify(!Logic.volumeIsCubic("org.mpris.MediaPlayer2.mpvx"))
  }

  function test_preview_frames_are_on_the_grid() {
    compare(Logic.PREVIEW_BARS.length, 19)
    compare(Logic.PREVIEW_PEAKS.length, 19)
    for (var i = 0; i < 19; i++) verify(Logic.PREVIEW_PEAKS[i] >= Logic.PREVIEW_BARS[i])
    var scope = Logic.previewScope()
    compare(scope.length, 75)
    for (var j = 0; j < scope.length; j++) verify(scope[j].top >= 0 && scope[j].top <= scope[j].bottom && scope[j].bottom <= 15)
  }

  function test_vu_segments() {
    compare(Logic.vuLit(0), 0)
    compare(Logic.vuLit(1), 19)
    compare(Logic.vuLit(0.5), 10)
    compare(Logic.vuPeakSegment(0.8, 0.5), 14)
    compare(Logic.vuPeakSegment(0.2, 0.5), 9)
    compare(Logic.vuPeakSegment(0, 0), -1)
  }

  function test_preferences_have_safe_defaults() {
    var d = Logic.parsePreferences("junk")
    compare(d.onlineLyrics, true)
    compare(d.webArt, true)
    compare(d.rememberStations, true)
    compare(d.hideWhenIdle, false)
    compare(d.seekStep, 5)
    compare(d.volumeStep, 5)
    compare(d.musicFolder, "")
    compare(d.playlistFolder, "")
    compare(d.musicPlayer, "")
  }

  function test_preferences_round_trip_and_reject_junk_values() {
    var saved = Logic.parsePreferences(Logic.serializePreferences({
      onlineLyrics: false, webArt: false, rememberStations: false, hideWhenIdle: true,
      seekStep: 30, volumeStep: 2, musicFolder: "/data/Tunes", musicPlayer: "mpv.desktop",
    }))
    compare(saved.onlineLyrics, false)
    compare(saved.webArt, false)
    compare(saved.rememberStations, false)
    compare(saved.hideWhenIdle, true)
    compare(saved.seekStep, 30)
    compare(saved.volumeStep, 2)
    compare(saved.musicFolder, "/data/Tunes")
    compare(Logic.parsePreferences('{"version":1,"playlistFolder":"/data/Lists"}').playlistFolder, "/data/Lists")
    compare(Logic.parsePreferences('{"version":1,"playlistFolder":"lists/../x"}').playlistFolder, "")
    compare(saved.musicPlayer, "mpv.desktop")
    compare(Logic.parsePreferences('{"version":1,"seekStep":15}').seekStep, 15)
    var bad = Logic.parsePreferences('{"version":1,"seekStep":7,"volumeStep":"5","musicPlayer":"../evil.desktop","musicFolder":"/a/../b","onlineLyrics":"no"}')
    compare(bad.seekStep, 5)
    compare(bad.volumeStep, 5)
    compare(bad.musicPlayer, "")
    compare(bad.musicFolder, "")
    compare(bad.onlineLyrics, true)
  }

  function test_gio_mime_recommended_apps() {
    var out = "Default application for \u201caudio/mpeg\u201d: mpv-headless-audio.desktop\n"
      + "Registered applications:\n\tmpv.desktop\n\tmpv-headless-audio.desktop\n\torg.kde.kdenlive.desktop\n"
      + "Recommended applications:\n\tmpv.desktop\n\tmpv-headless-audio.desktop\n\tbad name.desktop\n"
    compare(Logic.parseGioMime(out), ["mpv.desktop", "mpv-headless-audio.desktop"])
    compare(Logic.parseGioMime(""), [])
  }

  function test_desktop_names() {
    compare(Logic.desktopEntryName("[Desktop Entry]\nName=mpv (background audio)\nExec=mpv\n[Desktop Action x]\nName=Other"), "mpv (background audio)")
    compare(Logic.desktopEntryName("[Other]\nName=Nope"), "")
    compare(Logic.desktopIdLabel("org.kde.kdenlive.desktop"), "kdenlive")
    compare(Logic.desktopIdLabel("mpv.desktop"), "mpv")
    compare(Logic.parseChosenFolder("/home/me/Tunes\n"), "/home/me/Tunes")
    compare(Logic.parseChosenFolder(""), "")
  }

  function test_preferences_default_to_the_analyser() {
    compare(Logic.parsePreferences(Logic.serializePreferences({ visualisation: "mirror" })).visualisation, "mirror")
    compare(Logic.parsePreferences(Logic.serializePreferences({ visualisation: "oscilloscope" })).visualisation, "oscilloscope")
    compare(Logic.parsePreferences(Logic.serializePreferences({ visualisation: "nonsense" })).visualisation, "analyser")
    compare(Logic.parsePreferences("not json").visualisation, "analyser")
    compare(Logic.parsePreferences('{"version":2,"visualisation":"oscilloscope"}').visualisation, "analyser")
    compare(Logic.parsePreferences(undefined).visualisation, "analyser")
  }

  // ------------------------------------------------------ parseSpectrumFrame

  function test_frame_parses_bars_and_peaks() {
    var frame = Logic.parseSpectrumFrame("0.5,0.25,1.000|0.6,-1,1.000")
    compare(frame.bars, [0.5, 0.25, 1])
    compare(frame.peaks, [0.6, -1, 1])
  }

  function test_frame_clamps_levels_into_range() {
    var frame = Logic.parseSpectrumFrame("1.7,-0.3,nope|2,-4,x")
    compare(frame.bars, [1, 0, 0])
    compare(frame.peaks, [1, -1, -1])
  }

  function test_frame_is_bounded_to_the_bar_count() {
    var many = new Array(501).join("0.5,") + "0.5"
    var frame = Logic.parseSpectrumFrame(many + "|" + many)
    compare(frame.bars.length, Logic.BAR_COUNT)
    compare(frame.peaks.length, Logic.BAR_COUNT)
  }

  function test_frame_without_peaks_or_input() {
    compare(Logic.parseSpectrumFrame("0.1,0.2").peaks, [])
    var empty = Logic.parseSpectrumFrame("")
    compare(empty.bars, [])
    compare(empty.peaks, [])
    compare(Logic.parseSpectrumFrame(undefined).bars, [])
  }

  // --------------------------------------------------------------- formatTime

  function test_format_minutes_and_seconds() {
    compare(Logic.formatTime(0), "0:00")
    compare(Logic.formatTime(9.9), "0:09")
    compare(Logic.formatTime(221.28), "3:41")
    compare(Logic.formatTime(3599), "59:59")
  }

  function test_format_hours() {
    compare(Logic.formatTime(3600), "1:00:00")
    compare(Logic.formatTime(3725), "1:02:05")
  }

  // ------------------------------------------------------- isUnboundedLength

  function test_live_stream_sentinel_is_unbounded() {
    // Exactly what Chromium reported for a live YouTube TV stream: INT64_MAX
    // microseconds, shown as 2562047788:00:54 before this existed.
    verify(Logic.isUnboundedLength(9223372036854.775807))
    verify(Logic.isUnboundedLength(2562047788 * 3600 + 54))
    verify(Logic.isUnboundedLength(Logic.UNBOUNDED_SECONDS))
  }

  function test_real_durations_are_bounded() {
    verify(!Logic.isUnboundedLength(221.28))           // a song
    verify(!Logic.isUnboundedLength(3 * 3600))         // a film
    verify(!Logic.isUnboundedLength(24 * 3600))        // a day-long stream VOD
    verify(!Logic.isUnboundedLength(30 * 24 * 3600))   // a month
  }

  function test_missing_lengths_are_not_live() {
    // No length is "no timeline", a different case from "never ends".
    verify(!Logic.isUnboundedLength(0))
    verify(!Logic.isUnboundedLength(-1))
    verify(!Logic.isUnboundedLength(NaN))
    verify(!Logic.isUnboundedLength(Infinity))
    verify(!Logic.isUnboundedLength(undefined))
  }

  // ------------------------------------------------------------- live edge

  function test_live_edge_position_is_past_any_rewind_window() {
    // YouTube's longest DVR windows run to about twelve hours.
    verify(Logic.LIVE_EDGE_POSITION_SECONDS > 12 * 3600)
  }

  function test_live_edge_position_is_never_mistaken_for_a_live_length() {
    verify(!Logic.isUnboundedLength(Logic.LIVE_EDGE_POSITION_SECONDS))
  }

  function test_apple_music_radio_growth_is_detected() {
    // The measured steps on Apple Music 1.
    verify(Logic.isGrowingLength(160.149, 176.2))
    verify(Logic.isGrowingLength(176.2, 192.2))
  }

  function test_a_real_song_does_not_grow() {
    verify(!Logic.isGrowingLength(221.28, 221.28))
    // Tiny revisions are metadata settling, not a live stream.
    verify(!Logic.isGrowingLength(221.28, 221.9))
    verify(!Logic.isGrowingLength(221.28, 200))
  }

  function test_apple_radio_tune_ins_are_recognised() {
    // Measured in Brave on Apple Music 1, Hits and Country.
    verify(Logic.looksLikeRadioTuneIn(112.5, 160.2))
    verify(Logic.looksLikeRadioTuneIn(112.179, 160.149))
    verify(Logic.looksLikeRadioTuneIn(113.128, 160.149))
    verify(Logic.looksLikeRadioTuneIn(32.112, 80))       // Apple Music Chill
  }

  function test_songs_starting_or_resuming_are_not_tune_ins() {
    verify(!Logic.looksLikeRadioTuneIn(0.2, 200))       // a song starting
    verify(!Logic.looksLikeRadioTuneIn(150, 160))       // near its end
    verify(!Logic.looksLikeRadioTuneIn(10, 58))         // too early to tell
    verify(!Logic.looksLikeRadioTuneIn(92.4, 8899.8))   // a podcast resumed
    verify(!Logic.looksLikeRadioTuneIn(5.7, 15.9))      // Spotify's placeholder
    verify(!Logic.looksLikeRadioTuneIn(NaN, 160))
    verify(!Logic.looksLikeRadioTuneIn(100, 9223372036854.775807))
  }

  function test_a_remembered_station_is_only_judged_while_playing() {
    verify(Logic.provisionalExpiryRuns(true, true))
    verify(!Logic.provisionalExpiryRuns(false, true))
    verify(Logic.provisionalExpiryRuns(false, false))
    verify(Logic.provisionalExpiryRuns(true, false))
  }

  function test_only_a_confirmed_live_stream_carries_over() {
    verify(Logic.carriesLive(true, false))
    verify(!Logic.carriesLive(true, true))
    verify(!Logic.carriesLive(false, false))
  }

  function test_a_late_real_length_is_not_growth() {
    // Spotify's web player: a placeholder until playback, then the episode.
    verify(!Logic.isGrowingLength(15.949002, 8899.806))
    verify(!Logic.isGrowingLength(30, 200))
  }

  function test_the_first_real_length_is_not_growth() {
    // Players often report 0 before the real length arrives.
    verify(!Logic.isGrowingLength(0, 221.28))
    verify(!Logic.isGrowingLength(-1, 221.28))
    verify(!Logic.isGrowingLength(undefined, 221.28))
    verify(!Logic.isGrowingLength(NaN, 221.28))
  }

  function test_a_player_re_registering_on_a_station_switch_is_the_same_player() {
    // Brave was gone for one to two seconds on each Apple Music switch.
    var name = "org.mpris.MediaPlayer2.brave.instance1497160"
    verify(Logic.isReturningLivePlayer(name, name, 100000, 101000))
    verify(Logic.isReturningLivePlayer(name, name, 100000, 102000))
    verify(Logic.isReturningLivePlayer(name, name, 100000, 100000 + Logic.LIVE_PLAYER_RETURN_MS))
  }

  function test_a_player_gone_too_long_or_a_different_one_is_not_returning() {
    var name = "org.mpris.MediaPlayer2.brave.instance1497160"
    verify(!Logic.isReturningLivePlayer(name, name, 100000, 100000 + Logic.LIVE_PLAYER_RETURN_MS + 1))
    verify(!Logic.isReturningLivePlayer("org.mpris.MediaPlayer2.mpv", name, 100000, 101000))
    verify(!Logic.isReturningLivePlayer("", "", 100000, 101000))
    verify(!Logic.isReturningLivePlayer(name, name, 101000, 100000))
    verify(!Logic.isReturningLivePlayer(name, name, undefined, 100000))
  }

  function test_provisional_live_outlasts_a_measured_segment() {
    // Apple Music 1 grew every 16 s; a real stream must confirm in time.
    verify(Logic.PROVISIONAL_LIVE_MS > 16000)
    verify(!Logic.provisionalLiveExpired(0, 16000))
  }

  function test_provisional_live_expires_when_nothing_grows() {
    verify(Logic.provisionalLiveExpired(0, Logic.PROVISIONAL_LIVE_MS))
    verify(Logic.provisionalLiveExpired(1000, 1000 + Logic.PROVISIONAL_LIVE_MS + 1))
    verify(Logic.provisionalLiveExpired(undefined, 5000))
  }

  // --------------------------------------------------- remembered live streams

  function test_store_round_trips() {
    var list = Logic.rememberLiveStream([], "Brave Origin | Apple Music 1", 1789)
    var read = Logic.parseLiveStreamStore(Logic.serializeLiveStreamStore(list))
    compare(read.length, 1)
    compare(read[0].key, "Brave Origin | Apple Music 1")
    compare(read[0].seen, 1789)
    verify(Logic.isKnownLiveStream(read, "Brave Origin | Apple Music 1"))
    verify(!Logic.isKnownLiveStream(read, "Brave Origin | Apple Music Hits"))
  }

  function test_remembering_moves_a_station_to_the_front_without_duplicating() {
    var list = Logic.rememberLiveStream([], "a", 1)
    list = Logic.rememberLiveStream(list, "b", 2)
    list = Logic.rememberLiveStream(list, "a", 3)
    compare(list.length, 2)
    compare(list[0].key, "a")
    compare(list[0].seen, 3)
    compare(list[1].key, "b")
  }

  function test_the_store_is_capped() {
    var list = []
    for (var i = 0; i < Logic.MAX_LIVE_STREAMS + 25; i++) list = Logic.rememberLiveStream(list, "station " + i, i)
    compare(list.length, Logic.MAX_LIVE_STREAMS)
    compare(list[0].key, "station " + (Logic.MAX_LIVE_STREAMS + 24))
  }

  function test_forgetting_removes_only_that_station() {
    var list = Logic.rememberLiveStream(Logic.rememberLiveStream([], "a", 1), "b", 2)
    list = Logic.forgetLiveStream(list, "a")
    compare(list.length, 1)
    compare(list[0].key, "b")
  }

  function test_a_damaged_store_reads_as_empty_or_partial() {
    compare(Logic.parseLiveStreamStore("").length, 0)
    compare(Logic.parseLiveStreamStore("not json").length, 0)
    compare(Logic.parseLiveStreamStore("[]").length, 0)
    compare(Logic.parseLiveStreamStore("{\"streams\": \"nope\"}").length, 0)
    var mixed = Logic.parseLiveStreamStore(JSON.stringify({ streams: [
      { key: "good", seen: 1 }, { key: 42 }, null, { key: "" }, { key: "good", seen: 2 },
      { key: new Array(600).join("x") }, { key: "no seen" },
    ]}))
    compare(mixed.length, 2)
    compare(mixed[0].key, "good")
    compare(mixed[1].key, "no seen")
    compare(mixed[1].seen, 0)
  }

  function test_the_store_refuses_unreadable_keys() {
    compare(Logic.rememberLiveStream([], "", 1).length, 0)
    compare(Logic.rememberLiveStream([], new Array(600).join("x"), 1).length, 0)
  }

  function test_go_live_on_an_unbounded_stream_goes_a_year_ahead() {
    compare(Logic.liveEdgeTarget(9223372036854.775807, true), Logic.LIVE_EDGE_POSITION_SECONDS)
  }

  function test_a_growing_stream_has_no_go_live() {
    // Apple Music radio already plays at live; jumping to its end stalled it.
    compare(Logic.liveEdgeTarget(192.2, false), -1)
    compare(Logic.liveEdgeTarget(0, false), -1)
  }

  function test_seek_settle_covers_the_measured_update_delay() {
    // Brave reported the new position 58 ms after a seek.
    verify(Logic.SEEK_SETTLE_MS > 58)
    verify(Logic.SEEK_SETTLE_MS <= 2000)
  }

  // --------------------------------------------------- classifyPlaybackStart

  function test_players_reporting_in_at_load_are_initial() {
    var loaded = 100000
    compare(Logic.classifyPlaybackStart(loaded + 10, loaded, undefined, false), "initial")
    compare(Logic.classifyPlaybackStart(loaded + Logic.PLAYER_STARTUP_GRACE_MS - 1, loaded, undefined, false), "initial")
  }

  function test_a_fresh_player_after_load_is_a_start() {
    var loaded = 100000
    compare(Logic.classifyPlaybackStart(loaded + 60000, loaded, undefined, false), "start")
  }

  function test_a_loop_restart_or_buffering_flicker_is_a_blip() {
    // mpv looping a file, YouTube buffering: out of Playing for an instant.
    var loaded = 100000, stopped = loaded + 60000
    compare(Logic.classifyPlaybackStart(stopped + 300, loaded, stopped, true), "blip")
    compare(Logic.classifyPlaybackStart(stopped + Logic.PLAYBACK_BLIP_MS - 1, loaded, stopped, true), "blip")
  }

  function test_resuming_after_a_real_pause_is_a_start() {
    var loaded = 100000, stopped = loaded + 60000
    compare(Logic.classifyPlaybackStart(stopped + Logic.PLAYBACK_BLIP_MS, loaded, stopped, true), "start")
    compare(Logic.classifyPlaybackStart(stopped + 30000, loaded, stopped, true), "start")
  }

  function test_a_quick_restart_of_an_unranked_player_is_still_a_start() {
    // Nothing to keep if it was never ranked.
    var loaded = 100000, stopped = loaded + 60000
    compare(Logic.classifyPlaybackStart(stopped + 300, loaded, stopped, false), "start")
  }

  // ------------------------------------------------------------ choosePlayer

  function player(key, overrides) {
    var p = { key: key, proxy: false, hasMetadata: true, playing: false,
              startSerial: -1, hasTrack: true, controllable: true }
    for (var k in overrides) p[k] = overrides[k]
    return p
  }

  function test_a_player_with_no_activity_is_left_out() {
    // Brave's player for a Discord web app: registered, stopped, no track.
    verify(!Logic.isActivePlayer(false, false))
    verify(Logic.isActivePlayer(true, false))
    verify(Logic.isActivePlayer(false, true))
    var idle = player("brave", { hasMetadata: false, hasTrack: false, playing: false })
    compare(Logic.choosePlayer([idle], ""), "")
    compare(Logic.choosePlayer([idle, player("archamp", {})], ""), "archamp")
    compare(Logic.choosePlayer([idle], "brave"), "")
  }

  function test_clicking_a_paused_player_switches_to_it() {
    // The bug: Spotify playing, mpv paused, click mpv — nothing happened.
    var entries = [
      player("spotify", { playing: true, startSerial: 4 }),
      player("mpv", { playing: false }),
    ]
    compare(Logic.choosePlayer(entries, "mpv"), "mpv")
  }

  function test_the_most_recently_started_player_wins() {
    var entries = [
      player("forgotten", { playing: true, startSerial: 1 }),
      player("new", { playing: true, startSerial: 7 }),
      player("older", { playing: true, startSerial: 3 }),
    ]
    compare(Logic.choosePlayer(entries, ""), "new")
  }

  function test_a_playing_player_beats_a_paused_one_with_a_track() {
    var entries = [
      player("paused", { playing: false }),
      player("playing", { playing: true, startSerial: 0 }),
    ]
    compare(Logic.choosePlayer(entries, ""), "playing")
  }

  function test_with_nothing_playing_a_loaded_track_wins() {
    var entries = [
      player("idle", { hasTrack: false }),
      player("loaded", { hasTrack: true }),
    ]
    compare(Logic.choosePlayer(entries, ""), "loaded")
  }

  function test_a_pick_of_a_player_that_is_gone_falls_back() {
    var entries = [player("spotify", { playing: true, startSerial: 2 })]
    compare(Logic.choosePlayer(entries, "closed-player"), "spotify")
  }

  function test_proxies_are_never_chosen() {
    var entries = [
      player("playerctld", { proxy: true, playing: true, startSerial: 9 }),
      player("mpv", { playing: true, startSerial: 1 }),
    ]
    compare(Logic.choosePlayer(entries, "playerctld"), "mpv")
    compare(Logic.choosePlayer(entries, ""), "mpv")
  }

  function test_no_players_chooses_nothing() {
    compare(Logic.choosePlayer([], ""), "")
    compare(Logic.choosePlayer(undefined, "mpv"), "")
  }

  function test_format_refuses_a_sentinel_length() {
    compare(Logic.formatTime(9223372036854.775807), "--:--")
  }

  function test_format_placeholders() {
    compare(Logic.formatTime(-1), "--:--")
    compare(Logic.formatTime(NaN), "--:--")
    compare(Logic.formatTime(Infinity), "--:--")
    compare(Logic.formatTime(undefined), "--:--")
    compare(Logic.formatTime("12"), "--:--")
  }

  // --------------------------------------------------------- end of track

  function test_a_finished_track_is_at_its_end() {
    verify(Logic.isAtTrackEnd(221.048, 221.28, false))
    verify(Logic.isAtTrackEnd(230, 221.28, false))
    verify(!Logic.isAtTrackEnd(200, 221.28, false))
  }

  function test_live_and_unknown_lengths_never_end() {
    verify(!Logic.isAtTrackEnd(176, 176.2, true))
    verify(!Logic.isAtTrackEnd(5, 9223372036854.775807, false))
    verify(!Logic.isAtTrackEnd(0, 0, false))
    verify(!Logic.isAtTrackEnd(NaN, 200, false))
    verify(!Logic.isAtTrackEnd(undefined, 200, false))
  }

  // -------------------------------------------------------------- library

  function test_library_root_comes_from_xdg_or_home() {
    compare(Logic.libraryRoot("/home/me/Music\n", "/home/me"), "/home/me/Music")
    compare(Logic.libraryRoot("/data/Tunes", "/home/me"), "/data/Tunes")
    // xdg-user-dir answers $HOME when no music folder is configured.
    compare(Logic.libraryRoot("/home/me", "/home/me"), "/home/me/Music")
    compare(Logic.libraryRoot("", "/home/me"), "/home/me/Music")
    compare(Logic.libraryRoot("relative/path", "/home/me"), "/home/me/Music")
  }

  function test_paths_are_cleaned() {
    compare(Logic.cleanPath("/home/me/Music/"), "/home/me/Music")
    compare(Logic.cleanPath("/home/me/../etc"), "")
    compare(Logic.cleanPath("/home/./me"), "")
    compare(Logic.cleanPath("home/me"), "")
    compare(Logic.cleanPath("/a\u0007b"), "")
    compare(Logic.cleanPath(undefined), "")
  }

  function test_the_browser_stays_inside_the_library() {
    var root = "/home/me/Music"
    verify(Logic.isInside(root, "/home/me/Music/Journey"))
    verify(Logic.isInside(root, root))
    verify(!Logic.isInside(root, "/home/me/MusicVideos"))
    verify(!Logic.isInside(root, "/home/me"))
    compare(Logic.libraryFolder(root, "/etc"), root)
    compare(Logic.libraryFolder(root, "/home/me/Music/../.."), root)
    compare(Logic.parentFolder(root, "/home/me/Music/Journey/Greatest Hits 2"), "/home/me/Music/Journey")
    compare(Logic.parentFolder(root, root), root)
    compare(Logic.libraryCrumb(root, "/home/me/Music/Journey/Greatest Hits 2"), "Music / Journey / Greatest Hits 2")
    compare(Logic.libraryCrumb(root, root), "Music")
  }

  // ---------------------------------------------------------------- video

  function test_video_players() {
    verify(Logic.isVideoPlayer("org.mpris.MediaPlayer2.brave.instance1", "Brave Origin", "", true))
    verify(Logic.isVideoPlayer("org.mpris.MediaPlayer2.mpv", "mpv", "", false))
    verify(Logic.isVideoPlayer("org.mpris.MediaPlayer2.vlc", "VLC media player", "vlc", false))
    verify(Logic.isVideoPlayer("org.mpris.MediaPlayer2.Celluloid", "Celluloid", "io.github.celluloid_player.Celluloid", false))
    verify(!Logic.isVideoPlayer("org.mpris.MediaPlayer2.archamp", "archamp", "", false))
    verify(!Logic.isVideoPlayer("org.mpris.MediaPlayer2.spotify", "Spotify", "spotify", false))
  }

  function test_the_players_window_is_found() {
    var windows = [
      { pid: 2128699, title: "Discord | General | Deep-Space" },
      { pid: 2128699, title: "Never Gonna Give You Up - YouTube - Brave" },
      { pid: 555, title: "mpv - clip.mkv" },
    ]
    compare(Logic.chooseVideoWindow(windows, 2128699, "Never Gonna Give You Up", true), 1)
    // A browser's only window naming something else is not the video...
    var discord = { pid: 2128699, title: "Discord | General | Deep-Space", windowClass: "brave-discord.com__channels_@me-Default" }
    compare(Logic.chooseVideoWindow([discord], 2128699, "Never Gonna Give You Up", true), -1)
    // ...but its one ordinary window is, even when the page title doesn't name
    // the track (YouTube TV playing FOX News).
    var tv = { pid: 2128699, title: "Home - YouTube TV - Brave Origin", windowClass: "brave-origin" }
    compare(Logic.chooseVideoWindow([discord, tv], 2128699, "FOX News", true), 1)
    var tv2 = { pid: 2128699, title: "Inbox - Brave Origin", windowClass: "brave-origin" }
    compare(Logic.chooseVideoWindow([discord, tv, tv2], 2128699, "FOX News", true), -1)
    compare(Logic.chooseVideoWindow(windows, 555, "clip", false), 2)
    compare(Logic.chooseVideoWindow(windows, 555, "Different title", false), 2)
    compare(Logic.chooseVideoWindow(windows, 999, "x", false), -1)
    compare(Logic.chooseVideoWindow(windows, 0, "x", false), -1)
  }

  function test_video_aspect_is_bounded() {
    compare(Logic.videoAspect(1920, 1080), 0.5625)
    compare(Logic.videoAspect(490, 827), 1)
    compare(Logic.videoAspect(3000, 600), 0.4)
    compare(Logic.videoAspect(0, 0), 9 / 16)
    compare(Logic.parseBusctlUint("u 2128699\n"), 2128699)
    compare(Logic.parseBusctlUint("s nope"), 0)
  }

  function test_video_feed_loss() {
    verify(Logic.sameFrame([1, 2, 3], [1, 2, 3]))
    verify(!Logic.sameFrame([1, 2, 3], [1, 2, 4]))
    verify(!Logic.sameFrame(null, [1]))
    verify(!Logic.sameFrame([], []))
    var n = 0
    for (var i = 0; i < Logic.FEED_STALL_SAMPLES; i++) n = Logic.nextStallCount(n, true, true)
    verify(Logic.feedLost(true, n))
    verify(!Logic.feedLost(true, n - 1))
    compare(Logic.nextStallCount(n, false, true), 0)
    compare(Logic.nextStallCount(n, true, false), 0)
    verify(Logic.feedLost(false, 0))
  }

  // ------------------------------------------------------------- playlist

  function test_track_ids_are_object_paths() {
    compare(Logic.parseTrackIds('{"type":"ao","data":["/org/archamp/track/0","/org/archamp/track/1"]}'),
      ["/org/archamp/track/0", "/org/archamp/track/1"])
    compare(Logic.parseTrackIds('{"type":"ao","data":["/ok","bad path","/x/../y","/org/mpris/MediaPlayer2/TrackList/NoTrack"]}'),
      ["/ok", "/org/mpris/MediaPlayer2/TrackList/NoTrack"])
    compare(Logic.parseTrackIds('{"type":"as","data":["/a"]}'), [])
    compare(Logic.parseTrackIds("junk"), [])
    verify(!Logic.isObjectPath("/a/"))
    verify(!Logic.isObjectPath("/a;rm"))
  }

  function test_wrapped_track_ids_read_as_paths() {
    compare(Logic.objectPathText('QVariant(QDBusObjectPath, QDBusObjectPath("/org/archamp/track/13"))'), "/org/archamp/track/13")
    compare(Logic.objectPathText("/org/archamp/track/13"), "/org/archamp/track/13")
    compare(Logic.objectPathText('QDBusObjectPath("not a path")'), "")
    compare(Logic.objectPathText(undefined), "")
  }

  function test_tracks_metadata_parses() {
    var json = '{"type":"aa{sv}","data":[[{"mpris:trackid":{"type":"o","data":"/org/archamp/track/0"},'
      + '"xesam:title":{"type":"s","data":"Eat the Elephant"},"xesam:artist":{"type":"as","data":["A Perfect Circle"]},'
      + '"mpris:length":{"type":"x","data":313701587},"xesam:url":{"type":"s","data":"file:///m/Eat%20the%20Elephant.m4a"}},'
      + '{"mpris:trackid":{"type":"o","data":"not a path"}}]]}'
    var meta = Logic.parseTracksMetadata(json)
    compare(Object.keys(meta), ["/org/archamp/track/0"])
    compare(meta["/org/archamp/track/0"].title, "Eat the Elephant")
    compare(meta["/org/archamp/track/0"].artist, "A Perfect Circle")
    compare(meta["/org/archamp/track/0"].length, 313.701587)
    compare(meta["/org/archamp/track/0"].path, "/m/Eat the Elephant.m4a")
    compare(Logic.parseTracksMetadata("junk"), {})
  }

  function test_active_playlist_name() {
    compare(Logic.activePlaylistName('{"type":"(b(oss))","data":[true,["/org/x/1","Road Trip Mix",""]]}'), "Road Trip Mix")
    compare(Logic.activePlaylistName('{"type":"(b(oss))","data":[false,["/","",""]]}'), "")
    compare(Logic.activePlaylistName('{"type":"s","data":"Nope"}'), "")
    compare(Logic.activePlaylistName("junk"), "")
    compare(Logic.playlistHeading("Road Trip Mix"), "ROAD TRIP MIX")
    compare(Logic.playlistHeading(""), "PLAYLIST")
  }

  function test_track_numbers_are_padded() {
    compare(Logic.trackNumber(1, 12), "01")
    compare(Logic.trackNumber(12, 12), "12")
    compare(Logic.trackNumber(7, 150), "007")
    compare(Logic.trackNumber(3, 5), "03")
  }

  function test_playlist_progress() {
    var ids = ["/t/0", "/t/1", "/t/2"]
    var meta = { "/t/0": { length: 300 }, "/t/1": { length: 200 }, "/t/2": { length: 100 } }
    compare(Logic.playlistProgress(ids, meta, "/t/1", 50), { index: 2, count: 3, elapsed: 350, total: 600 })
    compare(Logic.playlistProgress(ids, meta, "/t/1", 999), { index: 2, count: 3, elapsed: 500, total: 600 })
    compare(Logic.playlistProgress(ids, meta, "/elsewhere", 50), { index: 0, count: 3, elapsed: 0, total: 600 })
    compare(Logic.playlistProgress([], {}, "/t/0", 5), { index: 0, count: 0, elapsed: 0, total: 0 })
  }

  // --------------------------------------------------------------- lyrics

  function test_lrc_parses_times_and_skips_tags() {
    var lrc = "[ar:Journey]\n[ti:Of a Lifetime]\n[00:12.50]First line\n[00:05.00]Earlier line\n[01:02]Minute line\n\n"
    var parsed = Logic.parseLrc(lrc)
    verify(parsed.synced)
    compare(parsed.lines.length, 3)
    compare(parsed.lines[0], { time: 5, text: "Earlier line" })
    compare(parsed.lines[1], { time: 12.5, text: "First line" })
    compare(parsed.lines[2].time, 62)
  }

  function test_lrc_repeated_stamps_and_offset() {
    var parsed = Logic.parseLrc("[offset:+500]\n[00:10.00][00:40.00]Chorus")
    compare(parsed.lines.length, 2)
    compare(parsed.lines[0], { time: 9.5, text: "Chorus" })
    compare(parsed.lines[1].time, 39.5)
  }

  function test_plain_lyrics_have_no_times() {
    var parsed = Logic.parseLrc("Line one\r\nLine two\n")
    verify(!parsed.synced)
    compare(parsed.lines, [{ time: -1, text: "Line one" }, { time: -1, text: "Line two" }])
    compare(Logic.parseLrc(undefined).lines, [])
  }

  function test_lrc_text_is_cleaned_and_bounded() {
    var parsed = Logic.parseLrc("[00:01.00]bad\u0007bell")
    compare(parsed.lines[0].text, "badbell")
    var long = "[00:01.00]" + new Array(2000).join("x")
    compare(Logic.parseLrc(long).lines[0].text.length, Logic.MAX_LYRIC_LINE_LENGTH)
  }

  function test_active_line_follows_the_position() {
    var lines = [{ time: 5, text: "a" }, { time: 12.5, text: "b" }, { time: 62, text: "c" }]
    compare(Logic.activeLyricIndex(lines, 0), -1)
    compare(Logic.activeLyricIndex(lines, 4.8), 0)
    compare(Logic.activeLyricIndex(lines, 30), 1)
    compare(Logic.activeLyricIndex(lines, 500), 2)
    compare(Logic.activeLyricIndex(lines, NaN), -1)
  }

  function test_lrc_sits_beside_the_track() {
    compare(Logic.lrcPathFor("/m/Journey/01 - Of a Lifetime.mp3"), "/m/Journey/01 - Of a Lifetime.lrc")
    compare(Logic.lrcPathFor("/m/v1.2/track"), "/m/v1.2/track.lrc")
    compare(Logic.lrcPathFor("relative.mp3"), "")
  }

  function test_lrclib_urls() {
    compare(Logic.lrclibUrl("Journey", "Of a Lifetime", "Journey", 410.6),
      "https://lrclib.net/api/get?artist_name=Journey&track_name=Of%20a%20Lifetime&album_name=Journey&duration=411")
    compare(Logic.lrclibUrl("A&B", "Q?", "", 0), "https://lrclib.net/api/search?artist_name=A%26B&track_name=Q%3F")
    compare(Logic.lrclibUrl("", "Title", "", 200), "")
    compare(Logic.lrclibUrl("Artist", "", "", 200), "")
  }

  function test_lrclib_responses() {
    var synced = Logic.parseLrclib('{"syncedLyrics":"[00:01.00]Hi","plainLyrics":"Hi"}')
    verify(synced.found && synced.lyrics.synced)
    var plain = Logic.parseLrclib('{"syncedLyrics":null,"plainLyrics":"Hi\\nThere"}')
    verify(plain.found && !plain.lyrics.synced)
    compare(plain.lyrics.lines.length, 2)
    verify(Logic.parseLrclib('{"instrumental":true}').instrumental)
    var search = Logic.parseLrclib('[{"plainLyrics":"p"},{"syncedLyrics":"[00:02.00]s"}]')
    verify(search.lyrics.synced)
    verify(!Logic.parseLrclib('{"code":404,"message":"Failed to find"}').found)
    verify(!Logic.parseLrclib("nope").found)
  }

  function test_lyrics_cache_remembers_and_retries_misses() {
    var key = Logic.lyricsKey("Journey", "Of a Lifetime", "Journey", 411)
    var cache = Logic.rememberLyrics([], { key: key, at: 1000, found: true, instrumental: false, text: "[00:01.00]Hi" })
    cache = Logic.rememberLyrics(cache, { key: "miss", at: 1000, found: false, instrumental: false, text: "" })
    compare(Logic.cachedLyrics(cache, key, 2000).text, "[00:01.00]Hi")
    verify(Logic.cachedLyrics(cache, "miss", 2000) !== null)
    compare(Logic.cachedLyrics(cache, "miss", 1000 + Logic.LYRICS_MISS_RETRY_MS + 1), null)
    var round = Logic.parseLyricsCache(Logic.serializeLyricsCache(cache))
    compare(round.length, 2)
    compare(round[0].key, "miss")
    compare(Logic.parseLyricsCache("junk"), [])
  }

  function test_skip_icons_follow_the_step() {
    compare(Logic.skipIcon(10, true), String.fromCodePoint(0xF0D71))
    compare(Logic.skipIcon(5, false), "\u{F11F9}")
    compare(Logic.skipIcon(30, false), "\u{F0D96}")
    compare(Logic.skipIcon(15, true), String.fromCodePoint(0xF193A))
    compare(Logic.skipIcon(7, true), "\u{F0211}")
  }

  function test_updates() {
    compare(Logic.parseVersion("v2.10.3"), [2, 10, 3])
    compare(Logic.parseVersion("2.0"), null)
    compare(Logic.parseVersion("2.0.0-beta"), null)
    verify(Logic.isNewerVersion("2.1.0", "2.0.0"))
    verify(Logic.isNewerVersion("v2.0.10", "2.0.9"))
    verify(!Logic.isNewerVersion("2.0.0", "2.0.0"))
    verify(!Logic.isNewerVersion("1.9.9", "2.0.0"))
    verify(!Logic.isNewerVersion("junk", "2.0.0"))
    var r = Logic.parseLatestRelease(JSON.stringify({ tag_name: "v2.1.0", published_at: "2026-10-01T12:00:00Z",
      body: "Hello\r\n\r\n\r\n![shot](https://x/y.png)\n<img src=x>**New**", draft: false, prerelease: false }))
    compare(r.version, "2.1.0")
    compare(r.tag, "v2.1.0")
    compare(r.published, "2026-10-01")
    compare(r.url, "https://github.com/lancefaul/omarchy-omedia-controls/releases/tag/v2.1.0")
    compare(r.notes, "Hello\n\n**New**")
    compare(Logic.releaseNotesText("## New\n\n### Playlists\n- one"), "## New\n\n**Playlists**\n- one")
    var sections = Logic.releaseNoteSections("Intro line\n\n## New\n- one\n\n---\n\nLoose end\n\n# Fixed\n- two")
    compare(sections.length, 4)
    compare(sections[0], { title: "", body: "Intro line" })
    compare(sections[1], { title: "NEW", body: "- one" })
    compare(sections[2], { title: "", body: "Loose end" })
    compare(sections[3], { title: "FIXED", body: "- two" })
    compare(Logic.releaseNoteSections(""), [])
    compare(Logic.parseLatestRelease(JSON.stringify({ tag_name: "v2.1.0", prerelease: true })), null)
    compare(Logic.parseLatestRelease(JSON.stringify({ tag_name: "nightly" })), null)
    compare(Logic.parseLatestRelease("junk"), null)
    verify(Logic.updateCheckDue(0, 1000))
    verify(!Logic.updateCheckDue(1000, 1000 + 60000))
    verify(Logic.updateCheckDue(1000, 1000 + Logic.UPDATE_CHECK_INTERVAL_MS))
    verify(Logic.updateCheckDue(5000, 1000))
    compare(Logic.UPDATE_COMMAND, ["omarchy", "plugin", "update", "lancefaul.omedia-controls", "--yes"])
    var c = Logic.parseUpdateCache(JSON.stringify({ checkedAt: 99, release: { version: "2.1.0", url: "https://evil.example/", notes: "x" } }))
    compare(c.checkedAt, 99)
    compare(c.release.url, "https://github.com/lancefaul/omarchy-omedia-controls/releases/")
    compare(Logic.parseUpdateCache("junk"), { checkedAt: 0, release: null, attempt: null })
    compare(Logic.parseUpdateCache(JSON.stringify({ attempt: { version: "2.1.0", at: 5 } })).attempt, { version: "2.1.0", at: 5 })
    compare(Logic.parseUpdateCache(JSON.stringify({ attempt: { version: "x" } })).attempt, null)
    compare(Logic.updateAttemptState({ version: "2.1.0", at: 1000 }, "2.1.0", 2000), "applied")
    compare(Logic.updateAttemptState({ version: "2.1.0", at: 1000 }, "2.2.0", 2000), "applied")
    compare(Logic.updateAttemptState({ version: "2.1.0", at: 1000 }, "2.0.0", 2000), "")
    compare(Logic.updateAttemptState({ version: "2.1.0", at: 1000 }, "2.0.0", 1000 + Logic.UPDATE_ATTEMPT_TIMEOUT_MS), "failed")
    compare(Logic.updateAttemptState(null, "2.0.0", 2000), "")
    compare(Logic.RESTART_COMMAND, ["omarchy", "restart", "shell"])
    compare(Logic.parsePreferences('{"version":1,"updateDismissed":"2.1.0"}').updateDismissed, "2.1.0")
    compare(Logic.parsePreferences('{"version":1,"updateDismissed":"x"}').updateDismissed, "")
    compare(Logic.parsePreferences('{"version":1}').updateCheck, true)
  }

  function test_library_search() {
    var cmd = Logic.libraryFindCommand("/m/Music")
    compare(cmd.slice(0, 5), ["find", "/m/Music", "-type", "f", "("])
    compare(cmd.slice(-4), [")", "-not", "-path", "*/.*"])
    compare(Logic.libraryFindCommand("relative"), [])
    var paths = Logic.parseFileList("/m/Music/Avenged Sevenfold/Hail to the King/07 Heretic.m4a\n"
      + "/m/Music/Journey/Escape/01 Don't Stop Believin'.m4a\n/etc/passwd\n/m/Music/a/../b.mp3\n\n"
      + "/m/Music/Journey/Escape/10 Open Arms.m4a\n", "/m/Music")
    compare(paths.length, 3)
    var hit = Logic.searchLibrary(paths, "/m/Music", "hail heretic")
    compare(hit.total, 1)
    compare(hit.results[0], { path: "/m/Music/Avenged Sevenfold/Hail to the King/07 Heretic.m4a",
      title: "07 Heretic", album: "Hail to the King", artist: "Avenged Sevenfold" })
    compare(Logic.searchLibrary(paths, "/m/Music", "dont stop").total, 1)
    compare(Logic.searchLibrary(paths, "/m/Music", "JOURNEY").results.map(function(r) { return r.title }),
      ["01 Don't Stop Believin'", "10 Open Arms"])
    compare(Logic.searchLibrary(paths, "/m/Music", "m4a").total, 0)
    compare(Logic.searchLibrary(paths, "/m/Music", "a").total, 0)
    compare(Logic.searchLibrary(paths, "/m/Music", "journey", 1).results.length, 1)
    compare(Logic.searchLibrary(paths, "/m/Music", "journey", 1).total, 2)
    compare(Logic.searchText("Don’t  Stop!"), "dont stop")
    compare(Logic.searchCountText({ results: [1], total: 1 }), "1 result")
    compare(Logic.searchCountText({ results: [1, 2], total: 9 }), "Showing 2 of 9")
  }

  function test_playlist_names() {
    compare(Logic.playlistsFolder("/home/me/Music"), "/home/me/Music/Playlists")
    compare(Logic.playlistsFolder("relative"), "")
    compare(Logic.playlistFileName("  Road  trip "), "Road trip.m3u")
    compare(Logic.playlistFileName("../../etc/passwd"), "etc passwd.m3u")
    compare(Logic.playlistFileName("a/b\\c"), "a b c.m3u")
    compare(Logic.playlistFileName("...hidden"), "hidden.m3u")
    compare(Logic.playlistFileName("Mix.M3U"), "Mix.m3u")
    compare(Logic.playlistFileName("   "), "")
    compare(Logic.playlistFileName("x".repeat(200)).length, 80 + 4)
    compare(Logic.playlistDisplayName("/m/Playlists/Road trip.m3u8"), "Road trip")
    verify(Logic.playlistNameTaken(["Road Trip.m3u"], "road trip.m3u", ""))
    verify(!Logic.playlistNameTaken(["Road Trip.m3u"], "road trip.m3u", "Road Trip.m3u"))
    verify(!Logic.playlistNameTaken(["Other.m3u"], "road trip.m3u", ""))
  }

  function test_m3u_round_trip() {
    var text = "﻿#EXTM3U\n#EXTINF:123,Artist - Song\n/m/a.mp3\n# note\nsub/b.flac\n"
      + "file:///m/c%20d.m4a\nhttps://radio.example/stream\n../up.mp3\n\n#EXTINF:1,orphan\n"
    var e = Logic.parseM3u(text, "/m/Playlists")
    compare(e.length, 4)
    compare(e[0].location, "/m/a.mp3")
    compare(e[0].info, "#EXTINF:123,Artist - Song")
    compare(e[1].location, "/m/Playlists/sub/b.flac")
    compare(e[1].info, "")
    compare(e[2].location, "/m/c d.m4a")
    compare(e[3].location, "https://radio.example/stream")
    compare(Logic.serializeM3u(e),
      "#EXTM3U\n#EXTINF:123,Artist - Song\n/m/a.mp3\n/m/Playlists/sub/b.flac\n/m/c d.m4a\nhttps://radio.example/stream\n")
    compare(Logic.serializeM3u([{ location: "/m/x\ny.mp3" }, { location: "/m/ok.mp3", info: "not extinf" }]),
      "#EXTM3U\n/m/ok.mp3\n")
  }

  function test_add_track_commands_keep_order() {
    var cmds = Logic.addTrackCommands("org.mpris.MediaPlayer2.archamp", ["/m/a b.mp3", "bad", "/m/c.mp3"], "/org/archamp/track/4")
    compare(cmds.length, 2)
    compare(cmds[0].slice(-3), ["file:///m/c.mp3", "/org/archamp/track/4", "false"])
    compare(cmds[1][cmds[1].length - 3], "file:///m/a%20b.mp3")
    compare(Logic.addTrackCommands("x", ["/m/a.mp3"], "")[0][9], "/org/mpris/MediaPlayer2/TrackList/NoTrack")
  }

  function test_playlist_link_state() {
    var file = ["/m/a.m4a", "/m/b.m4a", "/m/c.m4a"]
    compare(Logic.playlistLinkState(["/m/a.m4a", "/m/b.m4a", "/m/c.m4a"], file), "same")
    compare(Logic.playlistLinkState(["/m/b.m4a", "/m/a.m4a", "/m/c.m4a"], file), "edited")
    compare(Logic.playlistLinkState(["/m/a.m4a"], file), "edited")
    compare(Logic.playlistLinkState(["/m/x.m4a", "/m/y.m4a"], file), "unrelated")
    compare(Logic.playlistLinkState([], file), "same")
    var kept = Logic.entriesWithInfo(["/m/b.m4a", "/m/new.m4a"], [{ location: "/m/b.m4a", info: "#EXTINF:1,B" }])
    compare(kept, [{ location: "/m/b.m4a", info: "#EXTINF:1,B" }, { location: "/m/new.m4a", info: "" }])
  }

  function test_queue_matches_saved_playlist() {
    var saved = { "Nightmare.m3u": ["/m/a.m4a", "/m/b.m4a"], "Other.m3u": ["/m/a.m4a"] }
    compare(Logic.matchingPlaylistName(["/m/a.m4a", "/m/b.m4a"], saved), "Nightmare")
    compare(Logic.matchingPlaylistName(["/m/b.m4a", "/m/a.m4a"], saved), "")
    compare(Logic.matchingPlaylistName(["/m/a.m4a"], saved), "Other")
    compare(Logic.matchingPlaylistName([], saved), "")
    compare(Logic.matchingPlaylistName(["/m/a.m4a"], null), "")
    compare(Logic.matchingPlaylistFile(["/m/a.m4a", "/m/b.m4a"], saved), "Nightmare.m3u")
  }

  function test_playlist_editing() {
    var e = Logic.entriesFromPaths(["/m/a.mp3", "bad", "/m/b.mp3"])
    compare(e.length, 2)
    e = Logic.appendEntries(e, ["/m/c.mp3", "/m/a.mp3"])
    compare(e.map(function(x) { return x.location }), ["/m/a.mp3", "/m/b.mp3", "/m/c.mp3", "/m/a.mp3"])
    compare(Logic.moveEntry(e, 0, 1)[1].location, "/m/a.mp3")
    compare(Logic.moveEntry(e, 0, -1), e)
    compare(Logic.moveEntry(e, 3, 1), e)
    compare(Logic.removeEntry(e, 1).length, 3)
    compare(Logic.removeEntry(e, 9).length, 4)
    var label = Logic.playlistEntryLabel({ location: "/m/Album/01 Song.m4a", info: "" })
    compare(label.title, "01 Song")
    compare(label.folder, "Album")
    compare(Logic.playlistEntryLabel({ location: "/m/x.mp3", info: "#EXTINF:5,Named" }).title, "Named")
    compare(Logic.playlistEntryLabel({ location: "https://r.example/s" }).folder, "")
  }

  function test_selection_elsewhere_is_counted() {
    compare(Logic.selectedElsewhere(["/m/a.mp3", "/n/b.mp3"], ["/m/a.mp3", "/m/c.mp3"]), 1)
    compare(Logic.selectedElsewhere(["/m/a.mp3"], ["/m/a.mp3"]), 0)
    compare(Logic.selectedElsewhere(["/n/b.mp3"], []), 1)
    compare(Logic.selectedElsewhere(null, ["/m/a.mp3"]), 0)
  }

  function test_selection_toggles_in_pick_order() {
    var sel = Logic.toggleSelection([], "/m/b.mp3")
    sel = Logic.toggleSelection(sel, "/m/a.mp3")
    compare(sel, ["/m/b.mp3", "/m/a.mp3"])
    compare(Logic.toggleSelection(sel, "/m/b.mp3"), ["/m/a.mp3"])
    compare(Logic.toggleSelection(sel, "/m/../x"), sel)
  }

  function test_shift_click_selects_a_run() {
    var folder = ["/m/1.mp3", "/m/2.mp3", "/m/3.mp3", "/m/4.mp3"]
    compare(Logic.selectRange(["/m/1.mp3"], folder, "/m/1.mp3", "/m/3.mp3"), ["/m/1.mp3", "/m/2.mp3", "/m/3.mp3"])
    compare(Logic.selectRange([], folder, "/m/4.mp3", "/m/2.mp3"), ["/m/2.mp3", "/m/3.mp3", "/m/4.mp3"])
    compare(Logic.selectRange([], folder, "/elsewhere.mp3", "/m/2.mp3"), ["/m/2.mp3"])
  }

  function test_playlists_hold_only_clean_paths() {
    compare(Logic.playlistText(["/m/a b.mp3", "/m/../etc/passwd", "/m/c\nd.mp3", "/m/e.m4a"]),
      "#EXTM3U\n/m/a b.mp3\n/m/e.m4a\n")
  }

  function test_paths_become_file_uris() {
    compare(Logic.pathToFileUri("/home/me/Music/04 - The Party's Over #1.mp3"),
      "file:///home/me/Music/04%20-%20The%20Party's%20Over%20%231.mp3")
    compare(Logic.pathToFileUri("relative.mp3"), "")
  }

  function test_preferences_remember_a_clean_library_folder() {
    compare(Logic.parsePreferences(Logic.serializePreferences({ libraryDir: "/home/me/Music/Journey" })).libraryDir, "/home/me/Music/Journey")
    compare(Logic.parsePreferences('{"version":1,"libraryDir":"/home/me/../etc"}').libraryDir, "")
  }

  // --------------------------------------------------------- format chips

  function test_file_urls_become_safe_paths() {
    compare(Logic.fileUrlToPath("file:///home/me/Music/Journey/04%20-%20The%20Party's%20Over.mp3"),
      "/home/me/Music/Journey/04 - The Party's Over.mp3")
    compare(Logic.fileUrlToPath("https://example.com/a.mp3"), "")
    compare(Logic.fileUrlToPath("file://host/a.mp3"), "")
    compare(Logic.fileUrlToPath("file:///a%0Ab.mp3"), "")
    compare(Logic.fileUrlToPath("file:///a%ZZ.mp3"), "")
    compare(Logic.fileUrlToPath(["file:///x.flac"]), "/x.flac")
    compare(Logic.fileUrlToPath(undefined), "")
  }

  function test_ffprobe_output_parses() {
    var mp3 = '{"streams":[{"codec_name":"mp3","sample_rate":"44100","channels":2,"bit_rate":"292938"}],"format":{"bit_rate":"295401"}}'
    compare(Logic.parseFfprobe(mp3), { bitrate: 292938, sampleRate: 44100, channels: 2 })
    var noStreamRate = '{"streams":[{"sample_rate":"48000","channels":1}],"format":{"bit_rate":"128000"}}'
    compare(Logic.parseFfprobe(noStreamRate), { bitrate: 128000, sampleRate: 48000, channels: 1 })
    compare(Logic.parseFfprobe("nope"), { bitrate: 0, sampleRate: 0, channels: 0 })
    compare(Logic.parseFfprobe('{"streams":[{"bit_rate":"-5","sample_rate":"x"}]}'), { bitrate: 0, sampleRate: 0, channels: 0 })
  }

  function test_chips_read_like_winamp() {
    compare(Logic.formatChips({ bitrate: 292938, sampleRate: 44100, channels: 2 }), ["293 kbps", "44 kHz", "stereo"])
    compare(Logic.formatChips({ sampleRate: 48000, channels: 1 }), ["48 kHz", "mono"])
    compare(Logic.formatChips({ channels: 6 }), ["5.1"])
    compare(Logic.formatChips({}), [])
    compare(Logic.formatChips(null), [])
    compare(Logic.nodeRate("1/44100"), 44100)
    compare(Logic.nodeRate("1/7"), 0)
    compare(Logic.nodeRate("48000"), 0)
  }

  function test_streams_match_players() {
    var mpvA = { "application.name": "mpv", "media.name": "Rebirthing - mpv" }
    var brave = { "application.name": "Brave", "media.name": "Playback" }
    compare(Logic.streamScore(mpvA, "mpv", "Rebirthing"), 2)
    compare(Logic.streamScore(mpvA, "mpv", "Of a Lifetime"), 1)
    compare(Logic.streamScore(brave, "Brave Origin", "Apple Music 1"), 1)
    compare(Logic.streamScore(brave, "mpv", "x"), 0)
    compare(Logic.streamScore({}, "mpv", "x"), 0)
    compare(Logic.streamScore(null, "mpv", "x"), 0)
  }

  // ------------------------------------------------------------- metadata

  function test_album_details_joins_what_is_there() {
    compare(Logic.albumDetails({ album: "Greatest Hits 2", artist: ["Journey"], albumArtist: ["Journey"],
      date: "2011-01-01T00:00:00", trackNumber: 4 }), "Greatest Hits 2 \u00b7 2011 \u00b7 Track 4")
  }

  function test_album_details_names_a_different_album_artist() {
    compare(Logic.albumDetails({ album: "Now 45", artist: "Dua Lipa", albumArtist: ["Various Artists"] }),
      "Now 45 \u00b7 Various Artists")
    compare(Logic.albumDetails({ album: "X", artist: "journey", albumArtist: "Journey" }), "X")
  }

  function test_album_details_skips_junk() {
    compare(Logic.albumDetails({}), "")
    compare(Logic.albumDetails(undefined), "")
    compare(Logic.albumDetails({ album: "  ", date: "unknown", trackNumber: 0 }), "")
    compare(Logic.albumDetails({ trackNumber: 2.5 }), "")
    compare(Logic.albumDetails({ trackNumber: "7" }), "Track 7")
    compare(Logic.albumDetails({ date: "1999" }), "1999")
  }

  // --------------------------------------------------------------- volume

  function test_chromium_players_are_recognised() {
    verify(Logic.isChromiumPlayer("org.mpris.MediaPlayer2.brave.instance1801091", ""))
    verify(Logic.isChromiumPlayer("org.mpris.MediaPlayer2.chromium.instance42", ""))
    verify(Logic.isChromiumPlayer("", "/com/brave/MediaPlayer2/TrackList/Track0E71C7E7"))
    verify(Logic.isChromiumPlayer("", "/org/chromium/MediaPlayer2/TrackList/TrackAB12"))
    // As Quickshell hands it over.
    verify(Logic.isChromiumPlayer("", 'QVariant(QDBusObjectPath, QDBusObjectPath("/org/chromium/MediaPlayer2/TrackList/TrackAB12"))'))
    verify(!Logic.isChromiumPlayer("org.mpris.MediaPlayer2.mpv", "/0"))
    verify(!Logic.isChromiumPlayer("org.mpris.MediaPlayer2.spotify", "/com/spotify/track/4uLU6hMCjMI75M1A2tKUQC"))
    verify(!Logic.isChromiumPlayer("org.mpris.MediaPlayer2.brave.instance1.evil", ""))
    verify(!Logic.isChromiumPlayer(undefined, undefined))
  }

  function test_busctl_doubles_parse_strictly() {
    compare(Logic.parseBusctlDouble("d 1"), 1)
    compare(Logic.parseBusctlDouble("d 0.61\n"), 0.61)
    compare(Logic.parseBusctlDouble("x 5"), -1)
    compare(Logic.parseBusctlDouble("d -1"), -1)
    compare(Logic.parseBusctlDouble("garbage"), -1)
  }

  function test_an_ignored_volume_change_is_noticed() {
    verify(Logic.volumeWasIgnored(0.61, 1))
    verify(!Logic.volumeWasIgnored(0.61, 0.61))
    verify(!Logic.volumeWasIgnored(0.61, 0.62))
    verify(!Logic.volumeWasIgnored(0.61, -1))
  }

  function test_fixed_volume_message() {
    compare(Logic.fixedVolumeMessage("Brave Origin"), "Brave Origin doesn't allow plugins to change volume.")
    compare(Logic.fixedVolumeMessage(""), "This player doesn't allow plugins to change volume.")
  }

  // ---------------------------------------------------------------- speed

  function test_a_fixed_rate_cannot_change() {
    verify(!Logic.canChangeRate(1, 1))
    verify(!Logic.canChangeRate(undefined, 2))
    verify(!Logic.canChangeRate(NaN, 2))
    verify(Logic.canChangeRate(0.01, 100))
  }

  function test_rate_steps_respect_the_range() {
    compare(Logic.stepRate(1, 1, 0.01, 100), 1.25)
    compare(Logic.stepRate(1.25, -1, 0.01, 100), 1)
    compare(Logic.stepRate(2, 1, 0.01, 100), 3)
    compare(Logic.stepRate(3, 1, 0.01, 100), -1)
    compare(Logic.stepRate(1, -1, 0.01, 100), -1)
    compare(Logic.stepRate(0.5, 1, 0.01, 100), 1)
    compare(Logic.stepRate(1.1, 1, 0.01, 100), 1.25)
    compare(Logic.stepRate(1.1, -1, 0.01, 100), 1)
    compare(Logic.stepRate(1, 1, 1, 1.5), 1.25)
    compare(Logic.stepRate(1.5, 1, 1, 1.5), -1)
    compare(Logic.stepRate(1, 1, 1, 1), -1)
  }

  function test_fixed_rate_message_names_the_player() {
    compare(Logic.fixedRateMessage("Brave"), "Brave doesn't allow plugins to change playback speed.")
    compare(Logic.fixedRateMessage(""), "This player doesn't allow plugins to change playback speed.")
    compare(Logic.fixedRateMessage(undefined), "This player doesn't allow plugins to change playback speed.")
  }

  function test_effective_rate() {
    compare(Logic.effectiveRate(1.5), 1.5)
    compare(Logic.effectiveRate(0), 1)
    compare(Logic.effectiveRate(-2), 1)
    compare(Logic.effectiveRate(NaN), 1)
    compare(Logic.effectiveRate(undefined), 1)
    compare(Logic.effectiveRate(1e9), 1)
  }

  function test_format_rate() {
    compare(Logic.formatRate(1), "1\u00d7")
    compare(Logic.formatRate(0.75), "0.75\u00d7")
    compare(Logic.formatRate(NaN), "")
  }

  // ------------------------------------------------------------- commands

  function test_adjustments_parse_strictly() {
    compare(Logic.parseAdjustment("+10"), { relative: true, value: 10 })
    compare(Logic.parseAdjustment("-2.5"), { relative: true, value: -2.5 })
    compare(Logic.parseAdjustment(" 40 "), { relative: false, value: 40 })
    compare(Logic.parseAdjustment(""), null)
    compare(Logic.parseAdjustment("1e9"), null)
    compare(Logic.parseAdjustment("--5"), null)
    compare(Logic.parseAdjustment("5; rm"), null)
    compare(Logic.parseAdjustment("1234567"), null)
    compare(Logic.parseAdjustment(undefined), null)
  }

  function test_seek_target_clamps_to_the_track() {
    compare(Logic.seekTarget(30, 200, "+10"), 40)
    compare(Logic.seekTarget(5, 200, "-10"), 0)
    compare(Logic.seekTarget(195, 200, "+10"), 200)
    compare(Logic.seekTarget(30, 200, "90"), 90)
    compare(Logic.seekTarget(30, 0, "+10"), 40)
    compare(Logic.seekTarget(30, 200, "soon"), -1)
  }

  function test_volume_target_is_in_percent() {
    compare(Logic.volumeTarget(0.5, "+5"), 0.55)
    compare(Logic.volumeTarget(0.02, "-5"), 0)
    compare(Logic.volumeTarget(0.98, "+5"), 1)
    compare(Logic.volumeTarget(0.5, "40"), 0.4)
    compare(Logic.volumeTarget(0.5, "400"), 1)
    compare(Logic.volumeTarget(0.5, "loud"), -1)
  }

  function test_rate_target() {
    compare(Logic.rateTarget(1, "faster", 0.01, 100), 1.25)
    compare(Logic.rateTarget(1.5, "slower", 0.01, 100), 1.25)
    compare(Logic.rateTarget(1, "slower", 0.01, 100), -1)
    compare(Logic.rateTarget(1, "1.5", 0.01, 100), 1.5)
    compare(Logic.rateTarget(1, "1.5", 1, 1), -1)
    compare(Logic.rateTarget(1, "+1", 0.01, 100), -1)
    compare(Logic.rateTarget(1, "500", 0.01, 100), -1)
    compare(Logic.rateTarget(1, "7", 0.01, 100), -1)
    compare(Logic.rateTarget(1, "0.1", 0.01, 100), -1)
    compare(Logic.rateTarget(1, "4", 0.01, 100), 4)
    compare(Logic.rateTarget(1, "fast", 0.01, 100), -1)
  }

  function test_key_actions() {
    compare(Logic.keyAction("space"), "playPause")
    compare(Logic.keyAction("left"), "seekBack")
    compare(Logic.keyAction("up"), "volumeUp")
    compare(Logic.keyAction("m"), "mute")
    compare(Logic.keyAction("]"), "faster")
    compare(Logic.keyAction("escape"), "close")
    compare(Logic.keyAction("x"), "")
    compare(Logic.keyAction(undefined), "")
  }
}
