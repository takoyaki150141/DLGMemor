//
//  DLGMem.m
//  memui
//
//  Created by Liu Junqi on 4/23/18.
//  Copyright © 2018 DeviLeo. All rights reserved.
//

#import "DLGMem.h"
#import "views/DLGMemUI.h"
#import "views/DLGMemUIView.h"
#include "mem.h"

@interface DLGMem () <DLGMemUIViewDelegate> {
    mach_port_t g_task;
    search_result_chain_t g_chain;
    int g_type;
    search_result_chain_t g_pinned_chain;
}

@property (nonatomic, weak) DLGMemUIView *memView;

@end

@implementation DLGMem

- (instancetype)init {
    self = [super init];
    if (self) {
        [self initVars];
    }
    return self;
}

- (void)dealloc {
    NSLog(@"%@ dealloc", self);
}

- (void)initVars {
    g_task = mach_task_self();
    g_chain = NULL;
    g_type = SearchResultValueTypeUndef;
    g_pinned_chain = NULL;
}

- (void)launchDLGMem {
    [DLGMemUI addDLGMemUIView:self];
}

- (void)searchMem:(const char *)value type:(int)type comparison:(int)comparison {
    int size = 0;
    void *v = value_of_type(value, type, &size);
    int found = 0;
    search_result_chain_t chain = g_chain;
    g_chain = search_mem(g_task, v, size, type, comparison, chain, &found);
    self.memView.chainCount = found;
    self.memView.chain = g_chain;
}

- (void)modifyMem:(mach_vm_address_t)address value:(const char *)value type:(int)type {
    int size = 0;
    void *v = value_of_type(value, type, &size);
    int ret = write_mem(g_task, address, v, size);
    if (ret == 1) { NSLog(@"Modified successfully."); }
    else { NSLog(@"Failed to modify. Error: %d", ret); }
}

#pragma mark - DLGMemUIViewDelegate
- (void)DLGMemUILaunched:(DLGMemUIView *)view {
    self.memView = view;
}

- (void)DLGMemUISearchValue:(NSString *)value type:(DLGMemValueType)type comparison:(DLGMemComparison)comparison {
    const char *v = [value UTF8String];
    int t = [self memTypeFromDLGMemValueType:type];
    int c = [self memComparisonFromDLGMemComparison:comparison];
    [self searchMem:v type:t comparison:c];
}

- (void)DLGMemUIModifyValue:(NSString *)value address:(NSString *)address type:(DLGMemValueType)type {
    mach_vm_address_t a = 0;
    NSScanner *scanner = [NSScanner scannerWithString:address];
    if (![scanner scanHexLongLong:&a]) return;
    const char *v = [value UTF8String];
    int t = [self memTypeFromDLGMemValueType:type];
    [self modifyMem:a value:v type:t];
}

- (void)DLGMemUIRefresh {
    review_mem_in_chain(g_task, g_chain);
    self.memView.chain = g_chain;
}

- (void)DLGMemUIReset {
    destroy_all_search_result_chain(g_chain);
    g_chain = NULL;
    self.memView.chainCount = 0;
    self.memView.chain = g_chain;
}

- (NSString *)DLGMemUIMemory:(NSString *)address size:(NSString *)size {
    mach_vm_address_t a = 0;
    NSScanner *scanner = [NSScanner scannerWithString:address];
    if (![scanner scanHexLongLong:&a]) return nil;
    int s = [size intValue];
    mach_vm_address_t addr = 0;
    mach_vm_size_t data_size = 0;
    void *data = read_range_mem(g_task, a, 0, s, &addr, &data_size);
    if (data == NULL || size == 0) return @"No memory.";
    
    NSMutableString *hex = [NSMutableString stringWithCapacity:data_size * 4];
    NSMutableString *chs = [NSMutableString stringWithCapacity:data_size];
    [hex appendFormat:@"%08llX ", addr];
    for (mach_vm_size_t i = 0; i < data_size; ++i) {
        if (i > 0 && i % 8 == 0) {
            [hex appendFormat:@"%@\n", chs];
            [hex appendFormat:@"%08llX ", addr + i];
            [chs setString:@""];
        }
        uint8_t v = *(((uint8_t *)data) + i);
        [hex appendFormat:@"%02X ", v];
        char c = v;
        if (c < 32 || c > 126) c = '.';
        [chs appendFormat:@"%c", c];
    }
    [hex appendFormat:@"%@\n", chs];
    return hex;
}

#pragma mark - Utils
- (int)memTypeFromDLGMemValueType:(DLGMemValueType)type {
    switch (type) {
        case DLGMemValueTypeUnsignedByte: return SearchResultValueTypeUInt8;
        case DLGMemValueTypeSignedByte: return SearchResultValueTypeSInt8;
        case DLGMemValueTypeUnsignedShort: return SearchResultValueTypeUInt16;
        case DLGMemValueTypeSignedShort: return SearchResultValueTypeSInt16;
        case DLGMemValueTypeUnsignedInt: return SearchResultValueTypeUInt32;
        case DLGMemValueTypeSignedInt: return SearchResultValueTypeSInt32;
        case DLGMemValueTypeUnsignedLong: return SearchResultValueTypeUInt64;
        case DLGMemValueTypeSignedLong: return SearchResultValueTypeSInt64;
        case DLGMemValueTypeFloat: return SearchResultValueTypeFloat;
        case DLGMemValueTypeDouble: return SearchResultValueTypeDouble;
        default: return SearchResultValueTypeUndef;
    }
}

- (int)memComparisonFromDLGMemComparison:(DLGMemComparison)comparison {
    switch (comparison) {
        case DLGMemComparisonLT: return SearchResultComparisonLT;
        case DLGMemComparisonLE: return SearchResultComparisonLE;
        case DLGMemComparisonEQ: return SearchResultComparisonEQ;
        case DLGMemComparisonGE: return SearchResultComparisonGE;
        case DLGMemComparisonGT: return SearchResultComparisonGT;
        default: return SearchResultComparisonEQ;
    }
}

#pragma mark - Point scan (pinned addresses)

- (BOOL)isPinned:(mach_vm_address_t)address {
    search_result_chain_t c = g_pinned_chain;
    while (c != NULL && c->result != NULL) {
        if (c->result->address == address) return YES;
        c = c->next;
    }
    return NO;
}

- (void)pinAddress:(mach_vm_address_t)address type:(DLGMemValueType)type {
    if (address == 0) return;
    if ([self isPinned:address]) return;

    int nativeType = [self memTypeFromDLGMemValueType:type];
    int size = size_of_type(nativeType);
    if (size <= 0) return;

    // Read the current value at the address to seed the pinned entry.
    mach_vm_address_t actualAddr = 0;
    mach_vm_size_t dataSize = 0;
    void *data = read_range_mem(g_task, address, 0, size, &actualAddr, &dataSize);
    if (data == NULL) return;

    search_result_chain_t node = create_search_result_chain(
        address, data, (int)dataSize, nativeType,
        VM_PROT_READ | VM_PROT_WRITE);
    free(data);
    if (node == NULL) return;

    if (g_pinned_chain == NULL) {
        g_pinned_chain = node;
    } else {
        search_result_chain_t tail = g_pinned_chain;
        while (tail->next != NULL) tail = tail->next;
        tail->next = node;
    }

    if (self.memView != nil) {
        self.memView.pinnedCount = [self pinnedCount];
        self.memView.pinnedChain = [self copyPinnedChain];
    }
}

- (void)unpinAddress:(mach_vm_address_t)address {
    search_result_chain_t prev = NULL;
    search_result_chain_t c = g_pinned_chain;
    while (c != NULL && c->result != NULL) {
        if (c->result->address == address) {
            search_result_chain_t next = c->next;
            if (prev == NULL) g_pinned_chain = next;
            else              prev->next = next;
            destroy_search_result_chain(c);
            break;
        }
        prev = c;
        c = c->next;
    }

    if (self.memView != nil) {
        self.memView.pinnedCount = [self pinnedCount];
        self.memView.pinnedChain = [self copyPinnedChain];
    }
}

- (NSInteger)pinnedCount {
    NSInteger n = 0;
    search_result_chain_t c = g_pinned_chain;
    while (c != NULL && c->result != NULL) { n++; c = c->next; }
    return n;
}

- (search_result_chain_t)copyPinnedChain {
    search_result_chain_t head = NULL, tail = NULL;
    search_result_chain_t c = g_pinned_chain;
    while (c != NULL && c->result != NULL) {
        search_result_chain_t node = create_search_result_chain(
            c->result->address,
            c->result->value,
            c->result->size,
            c->result->type,
            c->result->protection);
        if (node == NULL) break;
        if (head == NULL) head = node;
        else              tail->next = node;
        tail = node;
        c = c->next;
    }
    return head;
}

- (void)refreshPinned {
    review_mem_in_chain(g_task, g_pinned_chain);
    if (self.memView != nil && self.memView.pinnedMode) {
        search_result_chain_t snapshot = [self copyPinnedChain];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.memView.pinnedChain = snapshot;
            [self.memView reloadPinnedTable];
        });
    }
}

- (void)DLGMemUIPinAddress:(mach_vm_address_t)address type:(DLGMemValueType)type {
    [self pinAddress:address type:type];
}

- (void)DLGMemUIUnpinAddress:(mach_vm_address_t)address {
    [self unpinAddress:address];
}

- (void)DLGMemUIRefreshPinned {
    [self refreshPinned];
}

@end
