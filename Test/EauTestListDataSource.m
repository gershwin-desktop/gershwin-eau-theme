/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauTestListDataSource.h"

@implementation EauTestListDataSource
{
  NSArray *_rows;
  NSDictionary *_children;
}

- (instancetype)init
{
  if ((self = [super init]) != nil)
    {
      _rows = @[
        @{ @"name": @"Applications", @"kind": @"Folder" },
        @{ @"name": @"Documents", @"kind": @"Folder" },
        @{ @"name": @"Readme.txt", @"kind": @"Plain Text" },
        @{ @"name": @"Picture.png", @"kind": @"PNG Image" },
        @{ @"name": @"Archive.tar", @"kind": @"Archive" },
        @{ @"name": @"Notes.rtf", @"kind": @"Rich Text" },
      ];
      _children = @{
        @"Applications": @[ @"Calculator", @"Stickies", @"Terminal" ],
        @"Documents": @[ @"Letter.rtf", @"Budget.csv" ],
      };
    }
  return self;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
  return (NSInteger)[_rows count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  return [[_rows objectAtIndex: (NSUInteger)row] objectForKey: [column identifier]];
}

- (NSArray *)browserItemsForColumn:(NSInteger)column browser:(NSBrowser *)browser
{
  if (column == 0)
    return [_children allKeys];
  NSString *parent = [[browser selectedCellInColumn: column - 1] stringValue];
  return [_children objectForKey: parent];
}

- (NSInteger)browser:(NSBrowser *)browser numberOfRowsInColumn:(NSInteger)column
{
  return (NSInteger)[[self browserItemsForColumn: column browser: browser] count];
}

- (void)browser:(NSBrowser *)browser
    willDisplayCell:(id)cell
              atRow:(NSInteger)row
             column:(NSInteger)column
{
  NSArray *items = [self browserItemsForColumn: column browser: browser];
  NSString *title = [items objectAtIndex: (NSUInteger)row];
  [cell setStringValue: title];
  [cell setLeaf: (column > 0)];
}

@end
