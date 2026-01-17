#import <AppKit/AppKit.h>
#import "EauGrowBoxView.h"
#import "EauGrowBoxCell.h"
#import "AppearanceMetrics.h"

// Tag to identify our grow box view
static const NSInteger EauGrowBoxViewTag = 0xEA0B0;

@implementation EauGrowBoxView

- (instancetype)initWithFrame:(NSRect)frameRect
{
  self = [super initWithFrame:frameRect];
  if (self)
    {
      // Register for subview notifications to stay on top
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(_contentViewDidAddSubview:)
                                                   name:@"NSViewDidAddSubviewNotification"
                                                 object:nil];
      // Register for frame changes to reposition on resize
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(_contentViewFrameDidChange:)
                                                   name:NSViewFrameDidChangeNotification
                                                 object:nil];
    }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [super dealloc];
}

// Called when any view adds a subview - check if it's our parent and re-raise
- (void)_contentViewDidAddSubview:(NSNotification *)notification
{
  NSView *parentView = [notification object];

  // Only care about our superview (the content view)
  if (parentView == [self superview])
    {
      // Get the subview that was added
      NSView *addedView = [[notification userInfo] objectForKey:@"NSView"];

      // Don't re-raise if we're the one being added
      if (addedView != self)
        {
          // Re-add ourselves on top
          [self retain];
          [self removeFromSuperview];
          [parentView addSubview:self positioned:NSWindowAbove relativeTo:nil];
          [self release];
          [self setNeedsDisplay:YES];
        }
    }
}

// Called when superview's frame changes - reposition to stay in bottom-right
- (void)_contentViewFrameDidChange:(NSNotification *)notification
{
  NSView *changedView = [notification object];

  // Only care about our superview
  if (changedView == [self superview])
    {
      NSView *contentView = [self superview];
      NSRect contentBounds = [contentView bounds];
      CGFloat size = [self frame].size.width;

      CGFloat yPos;
      if ([contentView isFlipped])
        {
          yPos = contentBounds.size.height - size;
        }
      else
        {
          yPos = 0;
        }

      NSRect newFrame = NSMakeRect(
        contentBounds.size.width - size,
        yPos,
        size,
        size
      );

      [self setFrame:newFrame];
      [self setNeedsDisplay:YES];
    }
}

- (NSInteger)tag
{
  return EauGrowBoxViewTag;
}

- (BOOL)isOpaque
{
  return YES;
}

- (BOOL)isFlipped
{
  // Match parent's coordinate system
  return [[self superview] isFlipped];
}

// Allow mouse events to pass through to the window manager's resize handle
- (NSView *)hitTest:(NSPoint)point
{
  return nil;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
  return NO;
}

- (void)drawRect:(NSRect)dirtyRect
{
  EauGrowBoxCell *cell = [[EauGrowBoxCell alloc] init];
  [cell drawWithFrame:[self bounds] inView:self];
  RELEASE(cell);
}

+ (void)addToWindow:(NSWindow *)window
{
  if (!window)
    return;

  // Only add to resizable windows
  if (!([window styleMask] & NSResizableWindowMask))
    return;

  NSView *contentView = [window contentView];
  if (!contentView)
    return;

  // Check if grow box already exists - if so, bring it to front
  NSView *existingGrowBox = [contentView viewWithTag:EauGrowBoxViewTag];
  if (existingGrowBox)
    {
      // Re-add to ensure it's on top of all other subviews
      [existingGrowBox retain];
      [existingGrowBox removeFromSuperview];
      [contentView addSubview:existingGrowBox positioned:NSWindowAbove relativeTo:nil];
      [existingGrowBox release];
      return;
    }

  // Use fixed size to avoid theme queries during activation
  // (NSScroller scrollerWidth queries theme, causing issues during GSThemeDidActivateNotification)
  CGFloat size = METRICS_GROW_BOX_SIZE;

  // Calculate position in bottom-right corner
  // Handle both flipped and non-flipped content views
  NSRect contentBounds = [contentView bounds];
  CGFloat yPos;

  if ([contentView isFlipped])
    {
      // Flipped: y=0 is top, so bottom is at height - size
      yPos = contentBounds.size.height - size;
    }
  else
    {
      // Non-flipped: y=0 is bottom
      yPos = 0;
    }

  NSRect growBoxFrame = NSMakeRect(
    contentBounds.size.width - size,
    yPos,
    size,
    size
  );

  EauGrowBoxView *growBox = [[EauGrowBoxView alloc] initWithFrame:growBoxFrame];

  // Set autoresizing based on coordinate system
  if ([contentView isFlipped])
    {
      // Flipped: stick to right and bottom (which is MaxY in flipped)
      [growBox setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    }
  else
    {
      // Non-flipped: stick to right and bottom (which is MinY)
      [growBox setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
    }

  // Ensure content view posts frame change notifications for resize tracking
  [contentView setPostsFrameChangedNotifications:YES];

  [contentView addSubview:growBox positioned:NSWindowAbove relativeTo:nil];
  RELEASE(growBox);
}

+ (void)raiseInWindow:(NSWindow *)window
{
  if (!window)
    return;

  NSView *contentView = [window contentView];
  if (!contentView)
    return;

  NSView *growBox = [contentView viewWithTag:EauGrowBoxViewTag];
  if (growBox)
    {
      // Re-add to ensure it's on top of all other subviews
      [growBox retain];
      [growBox removeFromSuperview];
      [contentView addSubview:growBox positioned:NSWindowAbove relativeTo:nil];
      [growBox release];
      [growBox setNeedsDisplay:YES];
    }
}

+ (void)removeFromWindow:(NSWindow *)window
{
  if (!window)
    return;

  NSView *contentView = [window contentView];
  if (!contentView)
    return;

  NSView *growBox = [contentView viewWithTag:EauGrowBoxViewTag];
  if (growBox)
    {
      [growBox removeFromSuperview];
    }
}

@end
