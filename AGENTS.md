# AGENTS.md

Two bundles for the Gershwin Desktop, both GNUstep (not Darwin/AppKit), targeting GNUstep on Linux/FreeBSD/OpenBSD:
- **Eau** (repo root): the default Aqua-style theme, principal class `Eau` (a `GSTheme` subclass). Visuals only: drawing, metrics, images.
- **GershwinBehaviors.bundle** (`Behaviors/`, principal class `GBBehaviors`): theme-independent behavior (keyboard, modality/sheets, focus, menu tracking, Menu.app client). Loaded via the `GSAppKitUserBundles` default; Eau loads it as a fallback (`Eau+Behaviors.m`). See `Behaviors/README.md`.
- Rule of thumb: still wanted under another theme -> `Behaviors/`. Draws/sizes -> Eau. `Behaviors/` must not import Eau headers or `AppearanceMetrics.h`; it asks the theme for visuals through optional hooks (`GBThemeIfResponds()`, `Behaviors/GBThemeHooks+*.h`), which Eau implements in `Eau+<Topic>.m`.

## Build & install
- Use `gmake`, never `make`.
- Build: `gmake` (repo root) -> `Eau.theme/`, and recurses into `Behaviors/` -> `Behaviors/GershwinBehaviors.bundle/`. Both makefiles use `$(wildcard *.m)`.
- `GNUmakefile` already sets `GNUSTEP_INSTALLATION_DOMAIN = SYSTEM`. Always install to SYSTEM only, never LOCAL. Verify after install that nothing landed in `/Local`.
- Compiled with `-fobjc-arc -fobjc-arc-exceptions`, links `-lX11` (see `GNUmakefile`). Fix every build warning. `Tests/` builds `NSAlert+Eau.m` without ARC.
- No `GNUmakefile.in`; edit `GNUmakefile` directly (still check for a `.in` sibling first).
- Local GNUstep lives at `/System` (source `/System/Library/Makefiles/GNUstep.sh`); the Gershwin dev stack is at `/Developer`. CI (`.github/workflows/build.yml`) builds against gershwin-developer's `make corelibs` + `make eau-theme` on FreeBSD/OpenBSD/Arch/Debian - not standalone.

## Customization: two mechanisms
- Most work is method swizzling in `+load` of categories (`+Eau` in Eau, `+GB` in `Behaviors/` with `gb_` selectors). Two variants:
  - `class_addMethod` + `method_exchangeImplementations` with a new `eau_`/`gb_` selector (e.g. `NSAlert+Eau.m`, `NSProgressIndicator+Eau.m`, `Behaviors/NSButton+GB.m`, `Behaviors/NSSearchField+GB.m`).
  - `method_setImplementation` with C-function IMPs (`NSMenuView+Eau.m`, `GSStandardDecorationView+Eau.m`, `Behaviors/NSMenu+GB.m`, `Behaviors/NSTextView+GB.m`). libobjc here has no `imp_implementationWithBlock`.
- When touching a swizzle, always add a new swizzled selector and chain to the original - never fully replace a method body. Each swizzled selector has exactly one owner across both bundles.
- Add the method to the target class first when it only inherits it (otherwise the swizzle hits the superclass, e.g. `keyDown:` lives only on `NSResponder`), and keep added selector names unique per class (two categories defining the same `gb_` selector cancel each other).
- GCD: `dispatch_once` only in `+load` (`Eau+TitleBarButtons.m`); existing main-queue dispatch in `Behaviors/GBMenuClient.m` and `Behaviors/NSAlert+GB.m`. Do not add GCD-based async paths.
- The theme engine also has hooks: some methods are overridden directly on `Eau` (e.g. `keyForKeyEquivalent:`) or via `_overrideNSPopUpButtonMethod_mouseDown:` style selectors (`NSPopUpButton+Eau.m`).
- GNUstep bug workarounds stay as shims (no patches against GNUstep) with a `TODO: Upstream to GNUstep - <what should change>` comment.

## Switching to another theme and back
This applies to Eau's visual code only. `Behaviors/` is theme-independent by design: its
swizzles stay on under any theme, take no `EauThemeIsActive()` guard (they must not import
Eau headers), and reach Eau only through the optional hooks, which answer only while Eau
is the active theme. Where Eau typography used to be switched off with the theme inside
a behavior (e.g. the 14 pt menu font and enforced system font weights in
`Behaviors/NSFont+GB.m`), it is now a hook (`Behaviors/GBThemeHooks+Font.h`, `Eau+Font.m`).
The Eau bundle cannot be unloaded, so every Eau swizzle stays installed for the life of
the process and must be switched on and off with the theme itself:
- **Any new Eau swizzle starts with `if (!EauThemeIsActive())` and chains to the
  implementation it replaced.** `EauThemeIsActive()` (declared in `Eau.h`, defined in
  `EauActivation.m`, set in `-[Eau activate]` and cleared in `-deactivate`) is the one
  switch; without that guard the look leaks into whatever theme the user picks
  next. A `Tests/` tool that links the guarded category must link `EauActivation.m`
  with it, since the theme class is not in the tool. Theme methods on `Eau` itself
  (`drawButton:...`, `standardWindowButton:...`, `GBThemeHooks` methods) need no guard -
  they are only called on the active theme - and neither do the
  `_override<Class>Method_<sel>` methods, which GSTheme installs and removes with the
  activation.
- Anything Eau *hands to* a live object (the resize grip, the title bar buttons, the
  hosted `EauProgressView`, the focus overlay) survives the switch and has to be taken
  out and put back by `EauThemeSwitchWatcher` in `EauThemeSwitch.m`, which runs on every
  `GSThemeDidActivateNotification`, whichever theme activated.
- `EauThemeSwitch.m` also snapshots the implementations GSTheme's override mechanism
  replaces, because GSTheme records those while a theme instance is built and builds a
  fresh instance on every switch - so an instance built while Eau was already active
  (the Themes preference pane does that) would record Eau's own as the ones to restore.
- The Menu.app IPC is behavior, not theme: it lives in `Behaviors/GBMenuClient.m` and
  `Behaviors/GSTheme+GBMenu.m` and stays connected under any theme, so `-[Eau activate]` /
  `-deactivate` neither start nor stop it (this supersedes the earlier rule that the IPC
  belongs to Eau's `-activate` / `-deactivate`).
- Switching needs two fixes outside this repo, both committed on `dev` of their
  repositories: `Library/Patches/libs-gui/theme-follows-default-change.patch` (an
  application that started with the default theme never watched the GSTheme default) and
  the Themes preference pane posting `GSThemePreferenceDidChangeNotification` so the
  change is picked up at once instead of within half a minute.

## Architecture notes
- `GSAppKitUserBundles` load in `-[NSApplication _init]`, before the display server and the theme: `Behaviors/` `+load` code must not need `NSApp`, a theme or a display.
- Menu bar is served by a separate Menu.app over Distributed Objects: `Behaviors/GBMenuClient.m` registers `MenuClient.<pid>` and connects to `org.gnustep.Gershwin.MenuServer`; `Behaviors/GSTheme+GBMenu.m` hides the in-app menu bar when Menu.app is available (`modifyRect:forMenu:isHorizontal:` returns `NSZeroRect`). Menu code must assume this split; `GBMenuRelaunchManager` / `GBMenuScrollManager` support it.
- Default cell behaviors are set by swizzling `init`/`initWithCoder:` (e.g. `NSTextFieldCell` forces `bezeled:NO`). When changing a default, keep the same per-instance pattern.
- Sizing/spacing constants for Eau controls live in `AppearanceMetrics.h` (spacing, orbs, margins, etc.) - reuse these rather than hardcoding.
- `EauAlertPanel` (`NSAlert+Eau.m`) handles Return, Escape and Cmd-C itself in `-sendEvent:` and `-performKeyEquivalent:`, which run before the focused control sees the key. Never add keys there that belong to the focused control (Space once went to the default button that way); let them reach the first responder, and let the panel's `-keyDown:` handle only what no control consumed.

## Conventions
- Sources are not ASCII-only: Unicode menu-key symbols (`⌃⌥⌘⇧`) in `Eau.m` are intentional. Use a plain hyphen `-`, never an em dash, in new code and comments. Put WHY in comments, not WHAT.
- Format per `.clang-format` (2-space indent, Stroustrup braces, 100 columns).

## Verification
- Unit tests (gnustep-make TestFramework): `Tests/` (Eau code) and `Behaviors/Tests/` (behavior code) - `gmake -C <dir>`, run `./obj/t_*`; some need an X display, and `t_ButtonSpaceKey` also `-GSTheme <abs path>/Eau.theme`. Manual tools under `Test/` (`alerttest`, `dialogtest`, `guiDrawing` GORM sample, `EauTest` showcase) linking `-lgnustep-gui`; scripted sheet test in `Behaviors/Test/SheetTest` (headless: Xvfb + xdotool). Real verification is running the installed theme against system apps (e.g. `/System/Applications/LoginWindow.app`), not hand-written smoke tests.
- Before finishing: clean build with no warnings (root, `Tests/`, `Behaviors/Tests/`), then review `git diff`.

## Git
- Work on the `dev` branch. Never commit/push to `main`/`master`.
- Commit only when the user explicitly asks ("commit"); push only when explicitly asked.