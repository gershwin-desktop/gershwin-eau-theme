/* NSButtonCell+GB.h - default-button keyboard wiring for button cells
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/NSButtonCell.h>

@interface NSButtonCell (GBDefaultButton)

/* GNUstep marks the default button by giving its cell the common_ret image.
 * A theme that intercepts that image (Eau hides it) calls this so the button
 * also answers Return, whether or not the application set the key equivalent
 * itself.  Safe to call before the cell has a control view: it then does
 * nothing, and -[NSButton setKeyEquivalent:] catches up later. */
- (void) gb_adoptReturnKeyEquivalent;

@end
