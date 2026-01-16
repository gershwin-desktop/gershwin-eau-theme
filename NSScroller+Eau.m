#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@implementation NSScroller (Eau)

+ (void) load
{
  // Intentionally do not swizzle NSScroller initWithFrame.
  // Some builds alias NSLevelIndicator to NSScroller and swizzling
  // causes recursion and crashes.
}

- (id) eau_initWithFrame: (NSRect)frameRect
{
  self = [self eau_initWithFrame: frameRect];
  return self;
}

@end
