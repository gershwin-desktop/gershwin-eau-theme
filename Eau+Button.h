#import "Eau.h"
#include <AppKit/NSAnimation.h>

@interface Eau(EauButton)
{
}
- (NSColor*) buttonColorInCell:(NSCell*) cell forState: (GSThemeControlState) state;
@end


@interface NSButtonCell(EauDefaultButtonAnimation)
  @property (nonatomic, copy) NSNumber* isDefaultButton;
  @property (nonatomic, copy) NSNumber* pulseProgress;
@end
