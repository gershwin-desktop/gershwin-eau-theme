/* NSButton+Eau.m - Eau theme button keyboard handling
   Copyright (C) 2026 Free Software Foundation, Inc.

   This file is part of GNUstep.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/> or write to the 
   Free Software Foundation, 51 Franklin Street, Fifth Floor, 
   Boston, MA 02110-1301, USA.
*/

#import "NSButton+Eau.h"
#import "Eau.h"
#import "Eau+Button.h"
#import "NSButtonCell+Eau.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

// Weak proxy to break the retain cycle between NSTimer and NSButtonCell.
// NSTimer retains its target, preventing dealloc. This proxy holds a weak
// reference to the cell, so the cell can be deallocated normally when the
// window is closed. If the cell is gone, the timer is invalidated.
@interface EauPulseProxy : NSObject
@property (nonatomic, weak) NSButtonCell *cell;
@end
@implementation EauPulseProxy
- (void) pulseTick: (NSTimer *)timer
{
  NSButtonCell *cell = self.cell;
  if (!cell) { [timer invalidate]; return; }
  [cell EauPulseTick: timer];
}
@end

@implementation NSButton (EauKeyboardHandling)

+ (void) load
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Class cls = [NSButton class];

    // keyDown: swizzle
    {
      SEL origSelector = @selector(keyDown:);
      SEL swizSelector = @selector(eau_keyDown:);
      Method origMethod = class_getInstanceMethod(cls, origSelector);
      Method swizMethod = class_getInstanceMethod(cls, swizSelector);
      BOOL didAddMethod = class_addMethod(cls, origSelector,
                                          method_getImplementation(swizMethod),
                                          method_getTypeEncoding(swizMethod));
      if (didAddMethod)
        class_replaceMethod(cls, swizSelector,
                            method_getImplementation(origMethod),
                            method_getTypeEncoding(origMethod));
      else
        method_exchangeImplementations(origMethod, swizMethod);
    }

    // setKeyEquivalent: swizzle - when @"\r", start pulse on the cell
    {
      SEL orig = @selector(setKeyEquivalent:);
      SEL swiz = @selector(eau_setKeyEquivalent:);
      Method origM = class_getInstanceMethod(cls, orig);
      Method swizM = class_getInstanceMethod(cls, swiz);
      if (origM && swizM)
        method_exchangeImplementations(origM, swizM);
    }
  });
}

- (void) eau_setKeyEquivalent: (NSString *)key
{
  [self eau_setKeyEquivalent: key];
  if ([key isEqualToString: @"\r"])
    {
      NSButtonCell *cell = [self cell];
      if (cell)
        {
          [cell setIsDefaultButton: @YES];
          // Use a weak proxy as timer target to avoid retain cycle.
          // Timer is stored on self (NSButton), released when button deallocates.
          NSTimer *old = objc_getAssociatedObject(self, @selector(eau_setKeyEquivalent:));
          if (old) [old invalidate];
          EauPulseProxy *proxy = [[EauPulseProxy alloc] init];
          proxy.cell = cell;
          NSTimer *t = [NSTimer timerWithTimeInterval: 1.0/30.0
                                               target: proxy
                                             selector: @selector(pulseTick:)
                                             userInfo: nil
                                              repeats: YES];
          [[NSRunLoop currentRunLoop] addTimer: t forMode: NSDefaultRunLoopMode];
          [[NSRunLoop currentRunLoop] addTimer: t forMode: NSModalPanelRunLoopMode];
          [[NSRunLoop currentRunLoop] addTimer: t forMode: NSEventTrackingRunLoopMode];
          objc_setAssociatedObject(self, @selector(eau_setKeyEquivalent:), t,
                                   OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

/**
 * Swizzled keyDown to ensure spacebar activates buttons with focus ring.
 */
- (void) eau_keyDown: (NSEvent*)theEvent
{
  NSString *characters = [theEvent characters];
  
  if ([self isEnabled] && [characters length] > 0)
    {
      unichar keyChar = [characters characterAtIndex: 0];
      
      // Handle spacebar - critical for focus ring interaction
      if (keyChar == ' ' || keyChar == 0x20)
        {
          [self performClick: self];
          return;
        }
      
      // Handle Enter/Return
      if (keyChar == '\r' || keyChar == '\n' || keyChar == 0x03)
        {
          [self performClick: self];
          return;
        }
    }
  
  // Call the original implementation (which now points to eau_keyDown)
  [self eau_keyDown: theEvent];
}

@end
