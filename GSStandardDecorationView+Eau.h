/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <GNUstepGUI/GSWindowDecorationView.h>

@class NSButton;

/* Declared by GNUstep in the class' own implementation file only. */
@interface GSStandardWindowDecorationView (EauGNUstepPrivate)
- (void) updateRects;
@end

@interface GSStandardWindowDecorationView (EauTheme)
- (void) EAUupdateRects;
- (BOOL) hasZoomButton;
- (void) setHasZoomButton:(BOOL)flag;
- (NSButton *) zoomButton;
- (void) setZoomButton:(NSButton *)button;
- (NSRect) zoomButtonRect;
- (void) EAUzoomButtonClicked:(id)sender;

/* Throw away the title bar buttons and ask the theme that is current right
 * now for fresh ones.  GNUstep builds these once when the window is created
 * and never replaces them, so without this a window keeps the buttons of
 * whichever theme happened to be active when it opened. */
- (void) EAUrebuildTitleBarButtons;
@end
