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

## Loading

libs-gui loads every bundle path listed in the `GSAppKitUserBundles` default
from `-[NSApplication _init]`, before the display server and the theme.
Register it system-wide, for example in a `GlobalDefaults.plist` next to the
system `GNUstep.conf`:

    { GSAppKitUserBundles = ("/System/Library/Bundles/GershwinBehaviors.bundle"); }

As a fallback Eau loads the bundle itself when it finds it missing, so the
Gershwin desktop keeps its behavior even without the default.

## Building

    gmake && sudo gmake install

Installing Eau (`gmake install` at the repository root) also builds and
installs this bundle.

## Conventions

Same as Eau (see `../AGENTS.md`): swizzle in `+load`, always chain to the
original, `gb_` prefix for added selectors, `+GB` suffix for categories.
Each swizzled selector has exactly one owner across Eau and this bundle.
