//
//  DLGMem.h
//  memui
//
//  Created by Liu Junqi on 4/23/18.
//  Copyright © 2018 DeviLeo. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "search_result_def.h"

@interface DLGMem : NSObject

- (void)launchDLGMem;

// Point-scan / pin: add or remove an address from the pinned
// chain. Pinned addresses keep a live-updating cached value that's
// refreshed from memory by the background timer in DLGMemEntry.
- (void)pinAddress:(mach_vm_address_t)address type:(DLGMemValueType)type;
- (void)unpinAddress:(mach_vm_address_t)address;
- (BOOL)isPinned:(mach_vm_address_t)address;

// Snapshot of the pinned chain (caller must destroy_search_result_chain_t
// when done).  Always returns a copy so the UI thread can iterate
// without holding the internal lock.
- (search_result_chain_t)copyPinnedChain;
- (NSInteger)pinnedCount;

// Re-read every pinned address from memory and update its cached
// value.  Safe to call from any thread.
- (void)refreshPinned;

@end
