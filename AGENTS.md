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
- GCD: `dispatch_once` only in `+load` (`Eau+TitleBarButtons.m`, `Behaviors/GSDisplayServer+GB.m`); existing main-queue dispatch in `Behaviors/GBMenuClient.m` and `Behaviors/NSAlert+GB.m`. Do not add GCD-based async paths.
- The theme engine also has hooks: some methods are overridden directly on `Eau` (e.g. `keyForKeyEquivalent:`) or via `_overrideNSPopUpButtonMethod_mouseDown:` style selectors (`NSPopUpButton+Eau.m`).
- GNUstep bug workarounds stay as shims (no patches against GNUstep) with a `TODO: Upstream to GNUstep - <what should change>` comment.

## Architecture notes
- `GSAppKitUserBundles` load in `-[NSApplication _init]`, before the display server and the theme: `Behaviors/` `+load` code must not need `NSApp`, a theme or a display.
- Menu bar is served by a separate Menu.app over Distributed Objects: `Behaviors/GBMenuClient.m` registers `MenuClient.<pid>` and connects to `org.gnustep.Gershwin.MenuServer`; `Behaviors/GSTheme+GBMenu.m` hides the in-app menu bar when Menu.app is available (`modifyRect:forMenu:isHorizontal:` returns `NSZeroRect`). Menu code must assume this split; `GBMenuRelaunchManager` / `GBMenuScrollManager` support it.
- Default cell behaviors are set by swizzling `init`/`initWithCoder:` (e.g. `NSTextFieldCell` forces `bezeled:NO`). When changing a default, keep the same per-instance pattern.
- Sizing/spacing constants for Eau controls live in `AppearanceMetrics.h` (spacing, orbs, margins, etc.) - reuse these rather than hardcoding.

## Conventions
- Sources are not ASCII-only: Unicode menu-key symbols (`⌃⌥⌘⇧`) in `Eau.m` are intentional. Use a plain hyphen `-`, never an em dash, in new code and comments. Put WHY in comments, not WHAT.
- Format per `.clang-format` (2-space indent, Stroustrup braces, 100 columns).

## Verification
- Unit tests (gnustep-make TestFramework): `Tests/` and `Behaviors/Tests/` (`gmake -C <dir>`, run the tools in `obj/`, some need an X display). Manual tools under `Test/` (`alerttest`, `dialogtest`, `guiDrawing` GORM sample); scripted sheet test in `Behaviors/Test/SheetTest` (headless: Xvfb + xdotool). Real verification is running the installed theme against system apps (e.g. `/System/Applications/LoginWindow.app`), not hand-written smoke tests.
- Before finishing: clean build with no warnings (root, `Tests/`, `Behaviors/Tests/`), then review `git diff`.

## Git
- Work on the `dev` branch. Never commit/push to `main`/`master`.
- Commit only when the user explicitly asks ("commit"); push only when explicitly asked.