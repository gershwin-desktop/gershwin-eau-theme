# Eau Theme

"Eau" is French for "Aqua". This is the default theme for the Gershwin Desktop Experience.

## Installation

1. Ensure you have GNUstep installed and configured on your system
2. Build the theme bundle:
   ```bash
   cd gershwin-eau-theme
   gmake
   ```
3. Install the theme:
   ```bash
   gmake install
   ```
4. The theme will be installed to `$(GNUSTEP_LIBRARY)/Themes/Eau.theme`

## Build Requirements

- GNUstep development environment
- Objective-C compiler (clang/gcc)
- GNUstep Make (gnustep-make)

## References

- [Original rik.theme](https://github.com/mclarenlabs/rik.theme)
- [Alessandro Sangiuliano's rik.theme fork](https://github.com/AlessandroSangiuliano/rik.theme)

## Sheets and the window manager

libs-gui shows a sheet (`-beginSheet:modalForWindow:...`, `NSAlert`
`-beginSheetModalForWindow:...`, `NSSavePanel` as a sheet) as an ordinary
window that only carries `WM_TRANSIENT_FOR`, which dialogs, drawers and child
windows carry too. So that the Gershwin window manager can hang the sheet from
its parent's titlebar, slide it in and out and keep it attached, the theme
marks it:

- `_GERSHWIN_SHEET` (`CARDINAL`, 32 bit) = `1` is put on the window every time
  it is ordered in while it is its parent's `attachedSheet`, and deleted when
  the same window is ordered in as anything else (a panel reused as an
  ordinary dialog).
- It is set in the swizzled `XGServer -orderwindow:::`
  (`GSDisplayServer+Eau.m`), the first point at which even a deferred sheet
  has an X window, and before the window is mapped, as the window manager
  reads it at the map request.
- `WM_TRANSIENT_FOR` (set by libs-back) names the parent; the window manager
  needs both.

The window manager's side of the contract is described in `SHEETS.md` of
gershwin-windowmanager. The showcase (`Test/`, Window > Showcase, "Sheets &
Alerts") opens an alert sheet and a save panel sheet.

## Developers

### Method Swizzling Pattern

The Eau theme uses **method swizzling** to augment existing GNUstep classes without completely replacing their implementations. This ensures that original behavior is preserved while adding theme-specific enhancements.

#### Why Method Swizzling?

Direct category overrides (using `@implementation ClassName (Category)`) replace the original method entirely, which can break inheritance chains and skip important superclass logic. Method swizzling allows you to "wrap" the original implementation with custom logic while ensuring the original code still runs.

#### Example: NSButton+Eau.m

In `NSButton+Eau.m`, we need to handle keyboard events (spacebar and Enter/Return) for button activation while preserving the original `NSButton` behavior for other keys.

**Incorrect Approach (Direct Override):**
```objective-c
@implementation NSButton (EauKeyboardHandling)

- (void) keyDown: (NSEvent*)theEvent
{
  // Custom logic...
  [super keyDown: theEvent];  // This skips NSButton's logic!
}

@end
```

**Correct Approach (Method Swizzling):**
```objective-c
#import <objc/runtime.h>

@implementation NSButton (EauKeyboardHandling)

+ (void) load
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Class cls = [NSButton class];
    SEL origSelector = @selector(keyDown:);
    SEL swizSelector = @selector(eau_keyDown:);

    Method origMethod = class_getInstanceMethod(cls, origSelector);
    Method swizMethod = class_getInstanceMethod(cls, swizSelector);

    // Attempt to add the method first in case NSButton doesn't implement it directly
    BOOL didAddMethod = class_addMethod(cls,
                                        origSelector,
                                        method_getImplementation(swizMethod),
                                        method_getTypeEncoding(swizMethod));

    if (didAddMethod)
      {
        class_replaceMethod(cls,
                            swizSelector,
                            method_getImplementation(origMethod),
                            method_getTypeEncoding(origMethod));
      }
    else
      {
        method_exchangeImplementations(origMethod, swizMethod);
      }
  });
}

- (void) eau_keyDown: (NSEvent*)theEvent
{
  // Custom logic for spacebar/Enter handling...

  // Call the original implementation (now points to eau_keyDown)
  [self eau_keyDown: theEvent];
}

@end
```

#### Key Benefits:

1. **Preserves Original Behavior**: The original `NSButton`'s `keyDown:` logic is preserved under a new name (`eau_keyDown:`)
2. **Avoids Superclass Conflicts**: Calling `[self eau_keyDown: theEvent]` invokes the original `NSButton` implementation, not skipping to `NSControl`
3. **Predictable Load Order**: Using `+load` ensures swizzling happens as soon as the theme bundle loads
4. **Safe for Inheritance**: The `class_addMethod` check handles cases where `NSButton` inherits `keyDown:` from its parent

#### When to Use Swizzling vs. Theme Engine Hooks

- **Use Swizzling**: For standard AppKit classes like `NSButton` where the GSTheme engine doesn't provide override hooks
- **Use Theme Engine**: For classes like `NSPopUpButton` that provide built-in override mechanisms (e.g., `_overrideNSPopUpButtonMethod_mouseDown:`)

#### Best Practices

- Always use `dispatch_once` in `+load` for thread safety
- Include the `class_addMethod` check for inheritance safety
- Document which methods are swizzled and why
- Test thoroughly to ensure original behavior is preserved
