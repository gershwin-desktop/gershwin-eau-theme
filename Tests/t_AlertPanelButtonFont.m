/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

/* t_AlertPanelButtonFont.m - the buttons of an Eau alert panel all use the
 * regular 13 pt metrics font, whatever font size defaults the application
 * carries.  Many apps' domains held NSUserFontSize = 3, and the non-default
 * buttons, which asked for the default size, came out at 3 pt while the
 * default button stayed at 13 pt. */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "Testing.h"
#import "NSAlert+Eau.h"
#import "AppearanceMetrics.h"

static NSButton *panelButton(EauAlertPanel *panel, const char *name)
{
  Ivar ivar = class_getInstanceVariable([panel class], name);
  return (ivar == NULL) ? nil : object_getIvar(panel, ivar);
}

int main(void)
{
  @autoreleasepool {
    [NSApplication sharedApplication];

    /* Tiny default sizes, as found in the user's app domains; volatile so
     * the test never writes them to disk. */
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeVolatileDomainForName: NSArgumentDomain];
    [defaults setVolatileDomain:
                [NSDictionary dictionaryWithObjectsAndKeys:
                  [NSNumber numberWithFloat: 3], @"NSUserFontSize",
                  [NSNumber numberWithFloat: 3], @"NSFontSize", nil]
                        forName: NSArgumentDomain];

    EauAlertPanel *panel = [[[EauAlertPanel alloc] init] autorelease];
    [panel setTitleBar: @"" icon: nil title: @"Beenden"
               message: @"Sie haben ungespeicherte Dokumente"];
    NSMutableArray *buttons = [NSMutableArray array];
    NSArray *titles = [NSArray arrayWithObjects:
                         @"Ansehen", @"Dennoch beenden", @"Abbrechen", nil];
    for (NSString *title in titles)
      {
        NSButton *button = [[[NSButton alloc] init] autorelease];
        [button setTitle: title];
        [buttons addObject: button];
      }
    [panel setButtons: buttons];

    CGFloat expected = [METRICS_FONT_SYSTEM_REGULAR_13 pointSize];
    const char *names[3] = { "defButton", "altButton", "othButton" };
    for (int i = 0; i < 3; i++)
      {
        NSFont *font = [[panelButton(panel, names[i]) cell] font];
        PASS(font != nil && [font pointSize] == expected,
             "%s uses the %.0f pt metrics font (got %.1f pt)",
             names[i], expected, [font pointSize]);
      }
  }
  return 0;
}
