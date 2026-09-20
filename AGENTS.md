# AGENTS.md

Eau: default Aqua-style theme bundle for the Gershwin Desktop. It is a GNUstep theme (principal class `Eau`, an `GSTheme` subclass), not a Darwin/AppKit app. Targets GNUstep on Linux/FreeBSD/OpenBSD.

## Build & install
- Use `gmake`, never `make`.
- Build: `gmake` (repo root) -> `Eau.theme/` bundle plus `obj/` artifacts.
- `GNUmakefile` already sets `GNUSTEP_INSTALLATION_DOMAIN = SYSTEM`. Always install to SYSTEM only, never LOCAL. Verify after install that nothing landed in `/Local`.
- Compiled with `-fobjc-arc -fobjc-arc-exceptions`, links `-lX11` (see `GNUmakefile`). Fix every build warning.
- No `GNUmakefile.in`; edit `GNUmakefile` directly (still check for a `.in` sibling first).
- Local GNUstep lives at `/System` (source `/System/Library/Makefiles/GNUstep.sh`); the Gershwin dev stack is at `/Developer`. CI (`.github/workflows/build.yml`) builds against gershwin-developer's `make corelibs` + `make eau-theme` on FreeBSD/OpenBSD/Arch/Debian - not standalone.

## Customization: two mechanisms
- Most UI work is method swizzling in `+load` of `+Eau` categories. Two variants:
  - `class_addMethod` + `method_exchangeImplementations` with a new `eau_`/`swz` selector (e.g. `NSButton+Eau.m`, `NSButtonCell+Eau.m`, `NSWindow+Eau.m`, `GSDisplayServer+Eau.m`, `NSAlert+Eau.m`).
  - `method_setImplementation` with C-function IMPs (`NSMenu+Eau.m`, `NSMenuView+Eau.m`, `NSTextView+Eau.m`, `GSStandardDecorationView+Eau.m`).
- When touching a swizzle, always add a new swizzled selector and chain to the original - never fully replace a method body.
- GCD is limited to `dispatch_once` in `+load` (only `NSButton+Eau.m`, `GSDisplayServer+Eau.m`, `Eau+TitleBarButtons.m` use it; most files swizzle directly). Do not add GCD-based async paths.
- The theme engine also has hooks: some methods are overridden directly on `Eau` (e.g. `keyForKeyEquivalent:`) or via `_overrideNSPopUpButtonMethod_mouseDown:` style selectors (`NSPopUpButton+Eau.m`).

## Switching to another theme and back
The bundle cannot be unloaded, so every swizzle stays installed for the life of the
process and must be switched on and off with the theme itself:
- **Any new swizzle starts with `if (!EauThemeIsActive())` and chains to the
  implementation it replaced.** `EauThemeIsActive()` (`Eau.h`, set in `-[Eau activate]`,
  cleared in `-deactivate`) is the one switch; without that guard the behaviour leaks
  into whatever theme the user picks next. Theme methods on `Eau` itself
  (`drawButton:...`, `standardWindowButton:...`) need no guard - they are only
  called on the active theme - and neither do the `_override<Class>Method_<sel>`
  methods, which GSTheme installs and removes with the activation.
- Anything Eau *hands to* a live object (the resize grip, the title bar buttons, the
  hosted `EauProgressView`, the focus overlay) survives the switch and has to be taken
  out and put back by `EauThemeSwitchWatcher` in `EauThemeSwitch.m`, which runs on every
  `GSThemeDidActivateNotification`, whichever theme activated.
- `EauThemeSwitch.m` also snapshots the implementations GSTheme's override mechanism
  replaces, because GSTheme records those while a theme instance is built and builds a
  fresh instance on every switch - so an instance built while Eau was already active
  (the Themes preference pane does that) would record Eau's own as the ones to restore.
- The Menu.app IPC belongs to `-activate` / `-deactivate`, not to `-initWithBundle:`,
  and it has to be connected *before* `[super activate]`: the main menu asks
  `-proposedVisibility:forMenu:` while it is re-established, so the application's own
  menu bar is mapped on top of the global one if Menu.app is not reachable yet.
  `-deactivate` withdraws this application's windows from Menu.app and hands the menu
  bar back with `-setMain:`.
- Switching needs two fixes outside this repo, both committed on `dev` of their
  repositories: `Library/Patches/libs-gui/theme-follows-default-change.patch` (an
  application that started with the default theme never watched the GSTheme default) and
  the Themes preference pane posting `GSThemePreferenceDidChangeNotification` so the
  change is picked up at once instead of within half a minute.

## Architecture notes
- Menu bar is served by a separate Menu.app over Distributed Objects: Eau registers a menu client (`NSConnection`, name `MenuClient.<pid>`) and connects to `org.gnustep.Gershwin.MenuServer`. When Menu.app is available the in-app menu bar is hidden (`modifyRect:forMenu:isHorizontal:` returns `NSZeroRect`). Menu code must assume this split; `EauMenuRelaunchManager.m` / `EauMenuScrollManager.m` support it.
- Default cell behaviors are set by swizzling `init`/`initWithCoder:` (e.g. `NSTextFieldCell` forces `bezeled:NO`). When changing a default, keep the same per-instance pattern.
- Sizing/spacing constants for ASD controls live in `AppearanceMetrics.h` (spacing, orbs, margins, etc.) - reuse these rather than hardcoding.
- `EauAlertPanel` (`NSAlert+Eau.m`) handles Return, Escape and Cmd-C itself in `-sendEvent:` and `-performKeyEquivalent:`, which run before the focused control sees the key. Never add keys there that belong to the focused control (Space once went to the default button that way); let them reach the first responder, and let the panel's `-keyDown:` handle only what no control consumed.

## Conventions
- Sources are not ASCII-only: Unicode menu-key symbols (`⌃⌥⌘⇧`) in `Eau.m` are intentional. Use a plain hyphen `-`, never an em dash, in new code and comments. Put WHY in comments, not WHAT.
- Format per `.clang-format` (2-space indent, Stroustrup braces, 100 columns).

## Verification
- ObjectTesting tools under `Tests/` (`gmake` there, run `./obj/t_*`; `t_ButtonSpaceKey` needs an X display and `-GSTheme <abs path>/Eau.theme`). Manual tools under `Test/` (`alerttest`, `dialogtest`, `guiDrawing` GORM sample) linking `-lgnustep-gui`. Real verification is running the installed theme against system apps (e.g. `/System/Applications/LoginWindow.app`), not hand-written smoke tests.
- Before finishing: clean build with no warnings, then review `git diff`.

## Git
- Work on the `dev` branch. Never commit/push to `main`/`master`.
- Commit only when the user explicitly asks ("commit"); push only when explicitly asked.