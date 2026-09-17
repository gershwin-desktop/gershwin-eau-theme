#import "Eau.h"

@interface Eau(EauButton)
{
}
- (NSColor*) buttonColorInCell:(NSCell*) cell forState: (GSThemeControlState) state;
@end


@interface NSButtonCell(EauDefaultButtonAnimation)
  @property (nonatomic, copy) NSNumber* isDefaultButton;
@end
