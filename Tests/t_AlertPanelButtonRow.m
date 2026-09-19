/* t_AlertPanelButtonRow.m - ObjectTesting coverage for the Eau theme's
 * alert-panel button row.
 *
 * The rules proven here (behavioral spec, gershwin-eau-theme):
 *
 *  1. A panel with the usual short buttons keeps the standard width.
 *  2. Every button of a panel stays inside the content view, left of the
 *     right margin and right of the left margin, no matter how long the
 *     button titles are (three long titles are what a build result offers:
 *     "Install and Launch" / "Install" / "OK", and translations are longer).
 *  3. Buttons never overlap each other.
 *
 * The panel is driven the way eau_setupPanel does (setTitleBar:... then
 * setButtons:, which runs sizePanelToFit), so the test covers the real
 * layout wiring independently of swizzle state.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "Testing.h"
#import "NSAlert+Eau.h"
#import "AppearanceMetrics.h"

static id panelIvar(EauAlertPanel *panel, const char *name)
{
  Ivar ivar = class_getInstanceVariable([panel class], name);
  if (ivar == NULL)
    {
      return nil;
    }
  return object_getIvar(panel, ivar);
}

/* Build a themed panel with the given button titles (first one is the
 * default button, as in -setButtons:). */
static EauAlertPanel *panelWithButtonTitles(NSArray *titles)
{
  EauAlertPanel *panel = [[EauAlertPanel alloc] init];
  [panel setTitleBar: @"" icon: nil title: @"Build Succeeded"
             message: @"Hello built successfully."];

  NSMutableArray *buttons = [NSMutableArray array];
  for (NSString *title in titles)
    {
      NSButton *button = [[NSButton alloc] init];
      [button setTitle: title];
      [buttons addObject: button];
      [button release];
    }
  [panel setButtons: buttons];
  return [panel autorelease];
}

/* The buttons of a panel, in layout order, ignoring the ones not in use. */
static NSArray *panelButtons(EauAlertPanel *panel)
{
  NSMutableArray *result = [NSMutableArray array];
  const char *names[3] = { "defButton", "altButton", "othButton" };
  for (int i = 0; i < 3; i++)
    {
      NSButton *button = panelIvar(panel, names[i]);
      if (button != nil && [button superview] != nil)
        {
          [result addObject: button];
        }
    }
  return result;
}

int main(void)
{
  @autoreleasepool {
    [NSApplication sharedApplication];

    /* --- 1. Short buttons keep the standard panel width --- */
    {
      EauAlertPanel *panel = panelWithButtonTitles(
        [NSArray arrayWithObjects: @"OK", @"Cancel", nil]);

      PASS([[panel contentView] frame].size.width == METRICS_WIN_MIN_WIDTH,
        "a panel with short buttons keeps the standard width");
    }

    /* --- 2. and 3. Long buttons all fit, without overlapping --- */
    {
      NSArray *titles = [NSArray arrayWithObjects:
        @"Installieren und starten", @"Installieren", @"OK", nil];
      EauAlertPanel *panel = panelWithButtonTitles(titles);
      NSArray *buttons = panelButtons(panel);
      NSRect content = [[panel contentView] frame];

      PASS([buttons count] == 3, "all three buttons are in the panel");

      BOOL allInside = YES;
      for (NSButton *button in buttons)
        {
          NSRect rect = [button frame];
          if (NSMinX(rect) < METRICS_CONTENT_SIDE_MARGIN
              || NSMaxX(rect) > NSMaxX(content) - METRICS_CONTENT_SIDE_MARGIN)
            {
              allInside = NO;
              NSLog(@"button '%@' at %@ is outside content %@",
                    [button title], NSStringFromRect(rect),
                    NSStringFromRect(content));
            }
        }
      PASS(allInside,
        "every button stays inside the panel's side margins");

      BOOL noOverlap = YES;
      for (NSUInteger i = 0; i < [buttons count]; i++)
        {
          for (NSUInteger j = i + 1; j < [buttons count]; j++)
            {
              if (NSIntersectsRect([[buttons objectAtIndex: i] frame],
                                   [[buttons objectAtIndex: j] frame]))
                {
                  noOverlap = NO;
                }
            }
        }
      PASS(noOverlap, "buttons do not overlap each other");
    }
  }
  return 0;
}
