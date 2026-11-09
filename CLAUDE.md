# OMedia Controls: notes for Claude

A native-styled MPRIS controller for the Omarchy bar (`lancefaul.omedia-controls`), listed on the
plugin marketplace. It is a controller, not a player. `README.md` documents it; `ROADMAP.md` is fully
worked through, so **don't start feature work unasked**. Plugin-wide lessons (reloading, settings,
testing a shell plugin) are in the user-level `omarchy-plugin-dev` skill.

**This file can end up in the public tree** (a release copies the development tree): keep it free of
personal details.

## Rules

- **It is live from this checkout** (the plugin folder is a symlink to this repo). Work in a worktree;
  QML needs `omarchy-restart-shell`.
- **Two repos.** Development happens in the private repo (`origin`). A release copies the tree onto
  the public repo as a normal commit — never this repo's history (its commit messages describe the
  owner's hardware) — with `.github/workflows/` left out (the marketplace's security baseline flags
  its package installs). Force-pushes are blocked here: hand the owner a `! git push --force` line if
  one is ever truly needed.
- **A public push is a release**: `omarchy plugin update` installs the public HEAD, and the widget's
  update notice reads GitHub's latest release. The marketplace listing is updated by editing the
  existing "[Verify]" issue's target commit, not by opening a second one.
- **Everything settable is settable in the widget's own UI**, never only in a config file.
- **Testing pauses his music**: "Pause others" is on, so starting a test player pauses what he is
  playing. Avoid it, or resume what was playing.
- **Screenshots and `preview.png`**: never a full-screen capture. Temporary IPC (marked `SHOTS-TEMP`,
  reverted after) gives the popup's exact rects for `grim -g`; open the popup on the monitor the
  pointer is not on, since grim draws the cursor in.
- Tests: `python3 -m unittest discover -s tests` and
  `env -u QT_QPA_PLATFORMTHEME QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/tst_logic.qml`
  (with the session's `gtk3` platform theme the runner prints nothing; check for a `Totals:` line).
  The Python suite includes a one-`id`-per-object check: nothing can load BarWidget.qml outside the shell.
- **The popup's keyboard**: a focused control gets each key before the catcher. Buttons are `PanelButton`
  (Omarchy's `Button` with `focusable` on and a name), never bare `Button`; a new clickable needs
  `activeFocusOnTab`, `activate()`, Return/Space, a `FocusRing` and `Accessible.role`/`name`. Focus a click gives
  a control goes back to the catcher (`keepPointerFocus`), or Space would press the last-clicked button again
  instead of play/pause; only Tab keeps focus on a control. The catcher never sees a Tab a focused control
  takes, so every focusable thing sets `root.tabbing` in its own `Keys.onPressed` (EqSlider through `tabbed()`);
  a new one that doesn't sends focus back to the catcher on every Tab.
- **Never capture from the default source** (2026-10 audit, #5): `spectrum.py` must not start `parec` without a
  monitor target, or it records the microphone.
- **The visualiser hears one player, at full level** (2026-11-08, the bars barely moved for an app embedding
  archamp): a stream is matched by its app name against the player's identity *or its bus name's player
  part* (`Logic.busPlayer`: identity "MyApp", bus `...archamp.myapp`, stream "archamp"); the gain undoes the
  player's volume (the widget's `gain`) **and** the stream's own PipeWire volume (`stream_level`, re-read each
  second), unless the two are one control (within 2 %); `parec` on a stream gets `node.dont-reconnect` and
  `dont-fallback`, or it is moved on when the stream ends instead of exiting (checked on a scratch stream).
- **Motion and keys** (#2, #3): every popup action needs a key or a focusable button (Omarchy's `Ui/Button` isn't
  focusable by default), and every endless animation a setting in the widget. Surfaces and audits:
  `.claude/SCREENS.md`.

## Review

Before merging or shipping: the user-level `pre-merge-review` skill — `/code-review` on the
diff in a fresh context, `/security-review` when it touches the update and install flow or `spectrum.py`'s audio capture, findings as Important / Nit / Pre-existing with file and line, every
finding answered, at most three rounds.

**Always needs the owner's eyes:** anything copied to the public repo (a release), the update and install flow, MPRIS actions that reach other players, `spectrum.py`.

**How to undo:** `git revert` on `main`. A public release can't be unpublished: undo with a new release.

## Skills learn

Plugin-wide lessons go in `omarchy-plugin-dev`; this plugin's own go in this file, in the same
commit. Never general advice, and never anything personal.

## Audits

**Audits:** untangle not yet (counted from 2026-11-07); state-machine-audit not yet (counted from 2026-11-07). Update with the area and date after each run (`untangle-codebase`, `state-machine-audit`); the monthly `audit-due` check reads this line.
