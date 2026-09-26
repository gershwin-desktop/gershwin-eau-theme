# Eau Theme

"Eau" is French for "Aqua". This is the default theme for the Gershwin Desktop Experience.

The repository builds two bundles:

- `Eau.theme` (repository root): how things look - drawing, metrics, images.
- `GershwinBehaviors.bundle` (`Behaviors/`): how things behave under any
  theme - keyboard handling, sheets and modality, focus, menu tracking and
  the Menu.app global menu bar. See [Behaviors/README.md](Behaviors/README.md)
  for its contents, settings and the `GSAppKitUserBundles` default that loads
  it (Eau loads it itself when that default is missing).

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
4. The theme will be installed to `$(GNUSTEP_LIBRARY)/Themes/Eau.theme` and
   the behavior bundle to `$(GNUSTEP_LIBRARY)/Bundles/GershwinBehaviors.bundle`

## Build Requirements

- GNUstep development environment
- Objective-C compiler (clang/gcc)
- GNUstep Make (gnustep-make)

## References

- [Original rik.theme](https://github.com/mclarenlabs/rik.theme)
- [Alessandro Sangiuliano's rik.theme fork](https://github.com/AlessandroSangiuliano/rik.theme)

## Developers

### Method Swizzling Pattern

Both bundles use **method swizzling** to augment existing GNUstep classes without completely replacing their implementations. This ensures that original behavior is preserved while adding theme-specific enhancements.

#### Why Method Swizzling?

Direct category overrides (using `@implementation ClassName (Category)`) replace the original method entirely, which can break inheritance chains and skip important superclass logic. Method swizzling allows you to "wrap" the original implementation with custom logic while ensuring the original code still runs.

#### Example: Behaviors/NSButton+GB.m

In `Behaviors/NSButton+GB.m`, we need to handle keyboard events (spacebar and Enter/Return) for button activation while preserving the original `NSButton` behavior for other keys.

**Incorrect Approach (Direct Override):**
```objective-c
@implementation NSButton (GBKeyboardHandling)

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

@implementation NSButton (GBKeyboardHandling)

+ (void) load
{
  Class cls = [NSButton class];
  SEL origSelector = @selector(keyDown:);
  SEL swizSelector = @selector(gb_keyDown:);

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
}

- (void) gb_keyDown: (NSEvent*)theEvent
{
  // Custom logic for spacebar/Enter handling...

  // Call the original implementation (now points to gb_keyDown)
  [self gb_keyDown: theEvent];
}

@end
```

#### Key Benefits:

1. **Preserves Original Behavior**: The original `NSButton`'s `keyDown:` logic is preserved under a new name (`gb_keyDown:`)
2. **Avoids Superclass Conflicts**: Calling `[self gb_keyDown: theEvent]` invokes the original `NSButton` implementation, not skipping to `NSControl`
3. **Predictable Load Order**: Using `+load` ensures swizzling happens as soon as the bundle loads
4. **Safe for Inheritance**: The `class_addMethod` check handles cases where `NSButton` inherits `keyDown:` from its parent

#### When to Use Swizzling vs. Theme Engine Hooks

- **Use Swizzling**: For standard AppKit classes like `NSButton` where the GSTheme engine doesn't provide override hooks
- **Use Theme Engine**: For classes like `NSPopUpButton` that provide built-in override mechanisms (e.g., `_overrideNSPopUpButtonMethod_mouseDown:`)

#### Best Practices

- `+load` runs once per category, so no `dispatch_once` is needed
- Give each added selector a name no other category on the same class uses
- Swizzle a selector in only one place across both bundles
- Include the `class_addMethod` check for inheritance safety
- Document which methods are swizzled and why
- Test thoroughly to ensure original behavior is preserved
