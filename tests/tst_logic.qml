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
