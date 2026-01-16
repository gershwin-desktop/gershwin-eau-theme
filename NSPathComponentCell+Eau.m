#import "AppearanceMetrics.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@implementation NSPathComponentCell (Eau)

+ (void) load
{
}

- (id) eau_initTextCell: (NSString *)string
{
  self = [self eau_initTextCell: string];
  if (self)
    {
      [self setFont: METRICS_FONT_SYSTEM_REGULAR_13];
    }
  return self;
}

@end
