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
| `GBWindowModalSheets` | BOOL | YES | NO restores libs-gui's blocking, app-modal sheets |
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
| `GBThemeHooks+DefaultButton.h` | `-gbDefaultButtonCellChanged:forWindow:` | nothing (no pulsing) |
| `GBThemeHooks+FocusRing.h` | `-gbKeyboardFocusVisibilityChanged:inWindow:` | nothing |
| `GBThemeHooks+GWDialog.h` | `-gbLayoutGWDialog:` | GWDialog's own layout |
| `GBThemeHooks+Sheet.h` | `-sheetAnimationDurationForWindow:`, `-drawSheetBorderInRect:forWindow:` | no animation, dark gray frame |
| `GBThemeHooks+Window.h` | `-gbWindowWillOrderFront:` | nothing |

`+[GBBehaviors playSystemSound:]` is available to themes that trigger a
sound from drawing code (Eau's progress-bar completion sound); look it up
with `NSClassFromString(@"GBBehaviors")`.

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
`Test/SheetTest` is a scripted GUI test for sheets (see its GNUmakefile).

## Known gaps

- Without the bundle nothing here happens; only Eau loads it as a fallback.
- The progress-bar completion sound is only triggered by Eau.
- A finished NSAlert panel is kept until the alert is released, because
  releasing it right after its modal session crashes libs-back.
- libs-gui has no `-[NSWindow setStyleMask:]`: a sheet gets a new
  decoration view while attached and its old one back afterwards.
- Alert-panel keyboard handling (Esc, arrow and Tab focus) is still in
  Eau's `EauAlertPanel`, so other themes get libs-gui's.

## Conventions

Same as Eau (see `../AGENTS.md`): swizzle in `+load`, always chain to the
original, `gb_` prefix for added selectors, `+GB` suffix for categories.
Each swizzled selector has exactly one owner across Eau and this bundle, and
each added selector name is unique per class (two categories defining the
same `gb_` selector silently cancel each other's swizzle). Add the method to
the target class first when it only inherits it (`class_addMethod`), or the
swizzle lands on the superclass.
