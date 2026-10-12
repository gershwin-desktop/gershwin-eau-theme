# GershwinBehaviors.bundle

Theme-independent behavior for the Gershwin Desktop: keyboard handling,
modality and sheets, focus policy, menu tracking and Menu.app integration.
Themes such as Eau only draw; anything you would still want after switching
to another theme lives here.

## Rule of thumb

| Layer | Owns |
|---|---|
| libs-gui / libs-back | Generic bugs - fix upstream, shim here meanwhile |
| GershwinBehaviors.bundle | What happens and when |
| Theme (Eau) | How it looks: drawing, metrics, images |

When a behavior needs visuals it calls an optional `GSTheme` hook through
`GBThemeIfResponds()` (`GBTheme.h`) and falls back to a plain default.
Workarounds for GNUstep bugs carry a `TODO: Upstream to GNUstep` comment
saying what should change there.

## What it contains

| Area | Files |
|---|---|
| Menu.app global menu bar (DO client `MenuClient.<pid>`, relaunch, window filter) | `GBMenuClient`, `GBMenuRelaunchManager`, `GBMenuWindowFilter`, `GSTheme+GBMenu.m` |
| Menu tracking: keyboard navigation, scroll wheel and edge scrolling of tall menus, screen clamping, submenu placement | `NSMenu+GB.m`, `NSMenuView+GB.m`, `GBMenuScrollManager`, `GBMenuTracking.h` |
| Submenu safe triangle | `GBMenuSafeTriangle*` |
| Popup menu X11 window type | `GSDisplayServer+GB.m` |
| Window-modal sheets (NSApp/NSWindow/NSAlert/NSSavePanel/NSDocument) | `GBSheet*`, `*+GBSheet.m` |
| Synchronous dialogs (NSRunAlertPanel, `runModal`) shown as sheets | `GBAutoSheet.m` |
| NSAlert runModal (main thread, focus, empty-alert guard, deferred panel teardown) | `NSAlert+GB.m` |
| Default button (Return), button Space/Return keys | `NSWindow+GBDefaultButton.m`, `NSButton+GB`, `NSButtonCell+GB` |
| Focus-ring visibility policy (show after Tab, hide after a click) | `NSWindow+GBFocusRing.m` |
| Window ordering hooks and dialog diagnostics | `NSWindow+GBOrdering.m` |
| Workspace `GWDialog` keyboard handling | `GWDialog+GB.m` |
| Text editing keys (Cmd-A/C/V/X/Z, Tab in field editors), Esc clears a search field | `NSTextView+GB.m`, `NSSearchField+GB.m` |
| Alert sound for `NSBeep`, system sound playback | `NSBeep+GB.m`, `GBSound` |
| Quit when the last window closes | `NSApplication+GB.m` |
| Single-item combo boxes select their item | `NSComboBox+GB.m` |
| Font resolution fallbacks (missing family, wrong weight) | `NSFont+GB.m` |

## Settings

User defaults (any domain, e.g. `defaults write NSGlobalDomain ...`):

| Default | Type | Default value | Effect |
|---|---|---|---|
| `GBWindowModalSheets` | BOOL | YES | NO restores libs-gui's blocking, app-modal sheets (and turns `GBAutoSheets` off) |
| `GBAutoSheets` | BOOL | YES | NO keeps every synchronous dialog an app-modal, centered panel |
| `GBMenuSafeTriangleDelay` | seconds | 0.3 | How long the pointer may rest in the triangle toward an open submenu; 0 turns the triangle off |

Files and environment:

- `~/.config/gershwin/sound-defaults.plist`: `alertSound` (name of the
  sound `NSBeep` plays) and `alertVolume` (0-1), written by the Sound
  preference pane.
- Any environment value containing `appmenu` forces the external (Menu.app)
  menu mode.

## Theme hooks

Optional methods a theme may implement on its `GSTheme` subclass. Each is
declared in its own header; without it the bundle uses the fallback shown.

| Header | Method | Fallback |
|---|---|---|
| `GBThemeHooks+Alert.h` | `-runModalForAlertPanel:result:` | `runModalForWindow:` on the panel |
| `GBThemeHooks+Alert.h` | `-gbIsAlertPanel:` | only GSAlertPanel and NSAlert's panels count as alerts |
| `GBThemeHooks+DefaultButton.h` | `-gbDefaultButtonCellChanged:forWindow:` | nothing (no pulsing) |
| `GBThemeHooks+FocusRing.h` | `-gbKeyboardFocusVisibilityChanged:inWindow:` | nothing |
| `GBThemeHooks+GWDialog.h` | `-gbLayoutGWDialog:` | GWDialog's own layout |
| `GBThemeHooks+Sheet.h` | `-sheetAnimationDurationForWindow:`, `-drawSheetBorderInRect:forWindow:`, `-sheetDidEndForWindow:` | no animation, dark gray frame, nothing |
| `GBThemeHooks+Window.h` | `-gbWindowWillOrderFront:` | nothing |

`+[GBBehaviors playSystemSound:]` is available to themes that trigger a
sound from drawing code (Eau's progress-bar completion sound); look it up
with `NSClassFromString(@"GBBehaviors")`.  So is
`+[GBBehaviors willRunModalWindowAsSheet:]`: a theme whose alert panel
centers and raises itself before `-runModalForWindow:` (Eau's
`EauAlertPanel`) skips that when it answers YES, or the dialog would first
flash up in the middle of the screen.

## Synchronous dialogs as sheets

Most GNUstep applications ask their questions with a blocking call and
continue on the next line: `NSRunAlertPanel` from `-windowShouldClose:`,
`-[NSAlert runModal]`, `-[NSSavePanel runModal]`.  `GBAutoSheet.m` shows
such a dialog as a sheet on the window it is about, without source changes.
It hooks the modal session itself (`-beginModalSessionForWindow:` /
`-endModalSession:`): the dialog is attached through the same code as the
asynchronous sheets (placement, borderless style, window-manager hints,
slide, parent state) before the session starts, and restored when it ends,
so the call still blocks and returns the same code.

- Dialogs: alert panels (GSAlertPanel, NSAlert's panel, or a theme's
  panel recognised by `-gbIsAlertPanel:`), NSSavePanel but not NSOpenPanel
  (the HIG keeps Open app-modal), NSPageLayout and NSPrintPanel.  Other
  modal panels are unchanged.
- Parent, in order: the `docWindow` of `-runModalForWindow:relativeToWindow:`;
  the window whose close is in progress (`-performClose:`, which covers the
  close button, the WM close and Command-W, or `-[NSDocument
  canCloseDocument]`); else the key window; else, with no key window, the
  main window.  It must be visible, on screen, not miniaturized, titled, not
  an NSPanel, at the normal level, without a sheet, and not the dialog.
- While `-terminate:` runs, only a closing window or a window the
  application itself made key (`-makeKeyAndOrderFront:`, as when reviewing
  unsaved documents one by one) is a parent: an application-wide question
  ("You have unsaved documents") stays centered.
- No sheet when another modal session runs, the application is inactive,
  no parent qualifies (launch-time alerts), or the dialog belongs to
  libs-gui's blocking `-beginSheet:` (kill switch).
- Caveat: the session stays app-modal while the sheet is up.  Running it
  window-modal would re-enter the application's event handling underneath
  a call that expects nothing to change until it returns, so other windows
  of the application wait, as they did before; only the look is a sheet.

## Window manager requirements for sheets

A sheet is a borderless window placed under the parent's titlebar. The WM
has to honour, on a window whose hints change after it was created
(`GBSheetX11.m` writes them with Xlib):

- `WM_TRANSIENT_FOR` the parent: stack and move with it;
- `_NET_WM_STATE_MODAL`: the parent is blocked;
- `_MOTIF_WM_HINTS` without decorations: do not frame the sheet.

With another backend, or a WM that ignores these, sheets still work but may
be framed or stack apart from the parent.

## Loading

libs-gui loads every bundle path listed in the `GSAppKitUserBundles` default
from `-[NSApplication _init]`, before the display server and the theme.
Register it system-wide, for example in a `GlobalDefaults.plist` next to the
system `GNUstep.conf`:

    { GSAppKitUserBundles = ("/System/Library/Bundles/GershwinBehaviors.bundle"); }

As a fallback Eau loads the bundle itself when it finds it missing (logging
a warning), so the Gershwin desktop keeps its behavior even without the
default. That happens when the theme initialises, later than the default
would, and other themes have no such fallback.

## Building

    gmake && sudo gmake install

Installing Eau (`gmake install` at the repository root) also builds and
installs this bundle. `Tests/` holds unit tests (build with `gmake -C Tests`,
run the tools in `Tests/obj/`; the window-filter test needs an X display);
`Test/SheetTest` is a scripted GUI test for sheets, synchronous dialogs
included (see its GNUmakefile; `-autosheets YES` runs only those).

## Known gaps

- Without the bundle nothing here happens; only Eau loads it as a fallback.
- The progress-bar completion sound is only triggered by Eau.
- A finished NSAlert panel is kept until the alert is released, because
  releasing it right after its modal session crashes libs-back.
- libs-gui has no `-[NSWindow setStyleMask:]`: a sheet gets a new
  decoration view while attached and its old one back afterwards.
- Alert-panel keyboard handling (Esc, arrow and Tab focus) is still in
  Eau's `EauAlertPanel`, so other themes get libs-gui's.
- A synchronous dialog shown as a sheet still blocks the whole application
  (see "Synchronous dialogs as sheets").

## Conventions

Same as Eau (see `../AGENTS.md`): swizzle in `+load`, always chain to the
original, `gb_` prefix for added selectors, `+GB` suffix for categories.
Each swizzled selector has exactly one owner across Eau and this bundle, and
each added selector name is unique per class (two categories defining the
same `gb_` selector silently cancel each other's swizzle). Add the method to
the target class first when it only inherits it (`class_addMethod`), or the
swizzle lands on the superclass.
