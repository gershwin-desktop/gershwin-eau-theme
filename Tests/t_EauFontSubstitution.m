/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* ObjectTesting coverage for NSFont+Eau: a font asked for by a name this
 * system does not have is replaced by an available family, and the
 * replacement keeps the size that was asked for. Applications that let
 * users pick sizes (titles in a video editor, a text editor's font panel)
 * otherwise get 13 pt text whatever they choose. Needs an X display. */

#import <AppKit/AppKit.h>
#import "Testing.h"

int main(void)
{
  @autoreleasepool
    {
      /* The installed theme would swizzle NSFont a second time; test only
       * the category linked into this tool. */
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      NSMutableDictionary *arguments = [[defaults
        volatileDomainForName: NSArgumentDomain] mutableCopy];
      arguments[@"GSTheme"] = @"GNUstep";
      [defaults removeVolatileDomainForName: NSArgumentDomain];
      [defaults setVolatileDomain: arguments forName: NSArgumentDomain];
      [NSApplication sharedApplication];

      NSFont *big = [NSFont fontWithName: @"NoSuchFamilyAnywhere" size: 96];
      PASS(big != nil, "a missing font name still yields a font");
      PASS([big pointSize] == 96,
           "the replacement has the requested size (got %.1f)",
           [big pointSize]);

      NSFont *small = [NSFont fontWithName: @"NoSuchFamilyAnywhere" size: 9];
      PASS([small pointSize] == 9,
           "another size gets its own replacement (got %.1f)",
           [small pointSize]);
    }
  return 0;
}
