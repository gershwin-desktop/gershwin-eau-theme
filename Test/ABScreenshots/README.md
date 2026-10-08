# ABScreenshots - pixel A/B test for Eau

Compares how the theme renders at a reference revision (A) and in this
working tree (B), pixel for pixel, at any GSScaleFactor.

    ./ab-compare.sh                      # A = origin/dev, scales 1 and 1.4
    ./ab-compare.sh -r main -s "1 1.4 2" -o /tmp/ab
    ./ab-compare.sh -w ~/wm/WindowManager/WindowManager.app/WindowManager \
        -s "1 1.25 1.4 2"                # also under the real window manager
    ./ab-compare.sh -b -o /tmp/ab        # rerun only B against the A runs there

It builds A in a temporary git worktree, builds B and the harness, then runs
`abharness` under Xvfb (1600x1200, 96 dpi) once per side, scale, decoration
mode and capture mode, serially. Each run loads that side's `Eau.theme` and,
when the revision has one, its `Behaviors/GershwinBehaviors.bundle`. The
report is `<out>/RESULTS.md`, with an A | B | diff image in `<out>/diff/` for
every deviation. The exit status is the number of images that differ.

## Decoration modes (`-d`)

- `eau` - no window manager, `-GSBackHandlesWindowDecorations NO`: Eau draws
  the titlebars, and libs-gui loads the behaviors bundle through
  `GSAppKitUserBundles`.
- `bare` - no window manager, `-GSBackHandlesWindowDecorations YES` and no
  `GSAppKitUserBundles`, so Eau loads the bundle itself from
  `Library/Bundles` of the run's private HOME, later in start-up than
  libs-gui would. Windows have no titlebars at all.
- `wm` - the Gershwin desktop: as `bare`, but with the window manager given
  with `-w` (a build of gershwin-windowmanager, `dev` branch) running in the
  same display. `ab-withwm.sh` starts it, waits until it has announced itself
  on the root window (`_NET_SUPPORTING_WM_CHECK`), runs the harness and stops
  it. It runs with the same tree's `Eau.theme` (and, via the same private
  HOME, its behaviors bundle) as the client under test, so a regression in
  how that tree's Eau draws the window manager's own decorations shows up
  too - it is not always A's theme. It runs without compositing (`-dc`):
  its fade-ins and translucent menus are still blending when a capture is
  taken and made two runs of A differ.

The default is `eau bare`, plus `wm` when `-w` is given. Window frames,
fractional content sizes and the start-up order all differ between the
modes, so a mode can deviate alone.

Per-window captures (`*w_*.png`) are of the client window only, so a window
manager's frame never counts; the full-screen captures include it.

## Metrics with and without the window manager

For every full-screen capture the harness also writes `<capture>.metrics`:
the content view size and the frame of every view, the text rect of every
text cell (where its baseline sits) and the field editor frame, in device
pixels inside the content view. With both `bare` and `wm` runs,
`ab-metrics.py` compares them, per side: the window manager places and frames
windows, but must not move anything inside one by more than a device pixel.
It also flags every item whose change under the window manager is not the
same in B as in A. Both go into a second section of `RESULTS.md`.

## What is captured

About 40 screenshots per run (whole screen plus per-window crops): the
classic EauTest window and Tab focus, the menu bar, a dropdown, a submenu, a
90-item overflow menu before and after scrolling, all showcase sections, the
drawer, NSAlert (modal and as a sheet), a save panel as a sheet,
NSRunAlertPanel, NSOpenPanel and NSSavePanel. The `quick` mode skips every
mouse action so the Tab focus ring stays visible on the panels and sheets.

## Determinism

The harness, identically for both sides, quantizes
`+[NSDate timeIntervalSinceReferenceDate]` to 3 s steps (freezing the default
button pulse and progress animations), stops the caret blink, resets
spinners, fixes the date picker's date and fully redraws and syncs every
window before each capture. A is run twice: A vs A must be 0 everywhere, or
the A vs B numbers mean nothing.

## Expected differences

Against a reference without window-modal sheets (anything before the
GershwinBehaviors split), the sheet captures (`22*`, `23*`) differ by design:
the sheet is attached under its parent's titlebar and has no titlebar of its
own. Compare only the sheet interiors there.

## Files

- `abmain.m` - the scripted capture run, wrapped around the EauTest fixture
  (`../EauTest_main.m` and friends)
- `abinput.c` - pointer, click and key input for the harness (XWarpPointer,
  because XTest motion is a no-op on Xvfb)
- `ab-compare.sh` - build, run and compare
- `ab-withwm.sh` - runs the harness under a window manager (the `wm` mode)
- `ab-metrics.py` - the metrics comparison
