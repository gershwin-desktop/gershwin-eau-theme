#import <AppKit/AppKit.h>
#import "EauGrowBoxView.h"
#import "EauGrowBoxCell.h"
#import "AppearanceMetrics.h"

// Tag to identify our grow box view
static const NSInteger EauGrowBoxViewTag = 0xEA0B0;

@implementation EauGrowBoxView

/* The grow box follows its superview only.  It used to observe the frame
 * changes of every view in the process (object nil): a view that is not in
 * any window, such as a matrix being sized before it is added to a panel,
 * then ran through the handler, whose ARC bookkeeping on the foreign
 * notification object released it once too often. */
- (void)_stopObserving
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_startObservingSuperview
{
  NSView *parent = [self superview];

  [self _stopObserving];
  // A grow box outside a window has nothing to stay on top of or to follow
  if (parent == nil || [self window] == nil)
    return;

  // Stay on top when views are added to the content view
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_contentViewDidAddSubview:)
                                               name:@"NSViewDidAddSubviewNotification"
                                             object:parent];
  // Reposition on resize
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_contentViewFrameDidChange:)
                                               name:NSViewFrameDidChangeNotification
                                             object:parent];
}

- (void)viewDidMoveToSuperview
{
  [super viewDidMoveToSuperview];
  [self _startObservingSuperview];
}

- (void)viewDidMoveToWindow
{
  [super viewDidMoveToWindow];
  [self _startObservingSuperview];
}

- (void)dealloc
{
  [self _stopObserving];
}

// Called when any view adds a subview - check if it's our parent and re-raise
- (void)_contentViewDidAddSubview:(NSNotification *)notification
{
  NSView *parentView = [self superview];

  // Registered for our superview only; a notification that arrives while
  // the box is being moved away is stale
  if (parentView != nil)
    {
      // Get the subview that was added
      NSView *addedView = [[notification userInfo] objectForKey:@"NSView"];

      // Don't re-raise if we're the one being added
      if (addedView != self)
        {
          // Re-add ourselves on top
          EauGrowBoxView *strongSelf = self;
          [strongSelf removeFromSuperview];
          [parentView addSubview:strongSelf positioned:NSWindowAbove relativeTo:nil];
          [self setNeedsDisplay:YES];
        }
    }
}

// Called when superview's frame changes - reposition to stay in bottom-right
- (void)_contentViewFrameDidChange:(NSNotification *)notification
{
  NSView *contentView = [self superview];

  // Registered for our superview only; a notification that arrives while
  // the box is being moved away is stale
  if (contentView != nil)
    {
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
  // Drawn nothing (see -drawRect:), what is behind it must show through
  return [[self window] showsResizeIndicator];
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
  // A window that says it shows no resize indicator (full screen) has none
  if ([[self window] showsResizeIndicator] == NO)
    {
      return;
    }

  EauGrowBoxCell *cell = [[EauGrowBoxCell alloc] init];
  [cell drawWithFrame:[self bounds] inView:self];
}

+ (void)addToWindow:(NSWindow *)window
{
  [self addToWindow: window pixelSized: NO];
}

+ (void)addToSettledWindow:(NSWindow *)window
{
  [self addToWindow: window pixelSized: YES];
}

+ (void)addToWindow:(NSWindow *)window pixelSized:(BOOL)pixelSized
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
      NSView *strongGrowBox = existingGrowBox;
      [strongGrowBox removeFromSuperview];
      [contentView addSubview:strongGrowBox positioned:NSWindowAbove relativeTo:nil];
      return;
    }

  // Use fixed size to avoid theme queries during activation
  // (NSScroller scrollerWidth queries theme, causing issues during GSThemeDidActivateNotification)
  CGFloat size = METRICS_GROW_BOX_SIZE;

  /* Whole device pixels, as autoresizing leaves the box once the window
   * frame settles: a box created on an already settled window (a panel
   * shown again after being a sheet) would otherwise draw over fractional
   * pixels under a scale factor and look different.  Only there: a window
   * shown for the first time keeps the plain size, which autoresizing
   * snaps only if the frame still moves - rounding it here as well made
   * every grip of a window that is already whole pixels one pixel larger. */
  if (pixelSized)
    {
      NSSize px = [contentView convertSize: NSMakeSize(size, size) toView: nil];
      px.width = ceil(fabs(px.width) - 0.001);
      px.height = ceil(fabs(px.height) - 0.001);
      size = fabs([contentView convertSize: px fromView: nil].width);
    }

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
      NSView *strongGrowBox = growBox;
      [strongGrowBox removeFromSuperview];
      [contentView addSubview:strongGrowBox positioned:NSWindowAbove relativeTo:nil];
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
