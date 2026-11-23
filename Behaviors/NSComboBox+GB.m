/*
 * NSComboBox+GB.m
 *
 * Auto-selects the only item of a combo box that has exactly one option, so a
 * field that offers no real choice is never left blank: the single option is
 * selected and shown in the text part.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/NSComboBox.h>
#import <objc/runtime.h>

@interface NSComboBox (GBSingleItem)

- (id) gb_initWithCoder: (NSCoder *)aDecoder __attribute__((objc_method_family(init)));
- (void) gb_addItemWithObjectValue: (id)object;
- (void) gb_addItemsWithObjectValues: (NSArray *)objects;
- (void) gb_insertItemWithObjectValue: (id)object atIndex: (NSInteger)index;
- (void) gb_removeItemAtIndex: (NSInteger)index;
- (void) gb_removeItemWithObjectValue: (id)object;
- (void) gb_removeAllItems;
- (void) gb_reloadData;
- (void) gb_noteNumberOfItemsChanged;
- (void) gb_selectOnlyItemIfPresent;

@end

static void GBSwizzle(Class cls, SEL original, SEL swizzled);

@implementation NSComboBox (GBSingleItem)

+ (void) load
{
  Class cls = [NSComboBox class];

  GBSwizzle(cls, @selector(initWithCoder:), @selector(gb_initWithCoder:));
  GBSwizzle(cls, @selector(addItemWithObjectValue:), @selector(gb_addItemWithObjectValue:));
  GBSwizzle(cls, @selector(addItemsWithObjectValues:), @selector(gb_addItemsWithObjectValues:));
  GBSwizzle(cls, @selector(insertItemWithObjectValue:atIndex:), @selector(gb_insertItemWithObjectValue:atIndex:));
  GBSwizzle(cls, @selector(removeItemAtIndex:), @selector(gb_removeItemAtIndex:));
  GBSwizzle(cls, @selector(removeItemWithObjectValue:), @selector(gb_removeItemWithObjectValue:));
  GBSwizzle(cls, @selector(removeAllItems), @selector(gb_removeAllItems));
  GBSwizzle(cls, @selector(reloadData), @selector(gb_reloadData));
  GBSwizzle(cls, @selector(noteNumberOfItemsChanged), @selector(gb_noteNumberOfItemsChanged));
}

static void GBSwizzle(Class cls, SEL original, SEL swizzled)
{
  Method origMethod = class_getInstanceMethod(cls, original);
  Method swizMethod = class_getInstanceMethod(cls, swizzled);
  if (!origMethod || !swizMethod)
    return;

  /* Adding the category implementation under the original selector first
   * overrides inherited methods (initWithCoder: comes from NSControl) on this
   * class only instead of swapping them globally for every control. */
  BOOL didAdd = class_addMethod(cls, original,
                                method_getImplementation(swizMethod),
                                method_getTypeEncoding(swizMethod));
  if (didAdd)
    class_replaceMethod(cls, swizzled,
                        method_getImplementation(origMethod),
                        method_getTypeEncoding(origMethod));
  else
    method_exchangeImplementations(origMethod, swizMethod);
}

- (id) gb_initWithCoder: (NSCoder *)aDecoder
{
  // Call the original implementation, which is now named gb_initWithCoder:.
  self = [self gb_initWithCoder: aDecoder];
  if (self)
    [self gb_selectOnlyItemIfPresent];
  return self;
}

- (void) gb_addItemWithObjectValue: (id)object
{
  [self gb_addItemWithObjectValue: object];
  [self gb_selectOnlyItemIfPresent];
}

- (void) gb_addItemsWithObjectValues: (NSArray *)objects
{
  [self gb_addItemsWithObjectValues: objects];
  [self gb_selectOnlyItemIfPresent];
}

- (void) gb_insertItemWithObjectValue: (id)object atIndex: (NSInteger)index
{
  [self gb_insertItemWithObjectValue: object atIndex: index];
  [self gb_selectOnlyItemIfPresent];
}

- (void) gb_removeItemAtIndex: (NSInteger)index
{
  [self gb_removeItemAtIndex: index];
  [self gb_selectOnlyItemIfPresent];
}

- (void) gb_removeItemWithObjectValue: (id)object
{
  [self gb_removeItemWithObjectValue: object];
  [self gb_selectOnlyItemIfPresent];
}

- (void) gb_removeAllItems
{
  [self gb_removeAllItems];
  [self gb_selectOnlyItemIfPresent];
}

- (void) gb_reloadData
{
  [self gb_reloadData];
  [self gb_selectOnlyItemIfPresent];
}

- (void) gb_noteNumberOfItemsChanged
{
  [self gb_noteNumberOfItemsChanged];
  [self gb_selectOnlyItemIfPresent];
}

// When the combo box ends up with exactly one option there is nothing to
// choose from, so select it and show it in the text part instead of leaving
// the field empty. This runs after any change to the item list.
- (void) gb_selectOnlyItemIfPresent
{
  if ([self numberOfItems] != 1)
    return;

  if ([self indexOfSelectedItem] != 0)
    [self selectItemAtIndex: 0];

  // objectValue works for both the built-in item list and data source mode;
  // itemObjectValueAtIndex: is invalid (returns nil) when usesDataSource is YES.
  id value = [self objectValue];
  NSString *stringValue = nil;
  if ([value isKindOfClass: [NSString class]])
    stringValue = value;
  else if ([value respondsToSelector: @selector(stringValue)])
    stringValue = [value stringValue];

  if (stringValue && ![[self stringValue] isEqualToString: stringValue])
    [self setStringValue: stringValue];
}

@end