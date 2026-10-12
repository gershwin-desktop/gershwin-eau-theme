/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* t_GBMenuPIDScanMemory.m - looking for the running Menu process must not
 * leave memory behind in the caller's autorelease pool.
 *
 * Every application does this scan when GBMenuClient starts up, which
 * happens before the application's run loop has drained a pool even once;
 * whatever the scan autoreleases stays for the life of the process.  It used
 * to copy the whole Unicode digit bitmap (139 KB) once per /proc entry,
 * which kept about 40 MB in the window manager and in Workspace.
 *
 * Headless.  On a system without /proc the scan does nothing and the test
 * passes trivially.
 */
#import <Foundation/Foundation.h>
#import <sys/resource.h>
#import "Testing.h"
#import "GBMenuRelaunchManager.h"

static long PeakResidentKilobytes(void)
{
  struct rusage usage;

  getrusage(RUSAGE_SELF, &usage);
  return usage.ru_maxrss;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  GBMenuRelaunchManager *manager = [GBMenuRelaunchManager sharedManager];
  long before, grown;

  /* The first scan also loads what every later one shares (the character
     set data, the file manager); only the cost of a scan itself is asked
     about.  Deliberately inside the one outer pool, as at menu client start-up. */
  [manager captureMenuProcessSnapshotIfAvailable];
  before = PeakResidentKilobytes();
  [manager captureMenuProcessSnapshotIfAvailable];
  grown = PeakResidentKilobytes() - before;

  PASS(grown < 1024,
       "scanning /proc for Menu keeps less than 1 MB alive (grew %ld KB)",
       grown);

  [arp release];
  return 0;
}
