#import "Eau.h"

void NSRoundRectDraw(NSRect r, float radius);
void NSRoundRectFill(NSRect r, float radius);

@interface Eau(EauDrawings)

- (NSGradient *) _bezelGradientWithColor:(NSColor*) baseColor;
- (NSGradient *) _buttonGradientWithColor:(NSColor*) baseColor;
- (NSGradient *) _windowTitlebarGradient;
- (NSGradient *) _windowTitlebarGradientInactive;
- (NSRect) drawInnerGrayBezel: (NSRect)border withClip: (NSRect)clip;
- (NSBezierPath*) buttonBezierPathWithRect: (NSRect)frame andStyle: (int) style;
@end
