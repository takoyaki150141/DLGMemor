//
//  mem.c
//  mem
//
//  Re-implemented for theos / iOS 16+ deployment.
//
//  DeviLeo originally targeted both jailed and jailbroken iOS;
//  the task_for_pid / sysctl / posix_spawn paths here only run on
//  a jailbroken device.  When this dylib is loaded into a LiveContainer-
//  injected target, mach_task_self() already *is* the target process,
//  so the `task` argument is honored but never used to cross a process
//  boundary.
//

#include "mem.h"
#include "mem_utils.h"
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach/vm_map.h>
#include <mach/vm_region.h>
#include <mach-o/dyld.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

// Cap on results returned by a single scan to keep memory usage
// bounded when the user searches for a common value like 0.
#define SEARCH_RESULT_LIMIT 100000

// ---------------------------------------------------------------
// Jailbreak-only helpers (kept for source compatibility; safe
// no-ops when entitlements / task_for_pid aren't available).
// ---------------------------------------------------------------

void all_processes(int uid) {
    (void)uid;
    // Intentionally empty: enumerate-proc-by-uid requires
    // jailbreak.  Without it, scanning is per-process via the
    // dylib host (LiveContainer).
}

mach_port_t get_task(int pid) {
    mach_port_t task = MACH_PORT_NULL;
    // task_for_pid returns KERN_FAILURE on a non-jailbroken device;
    // we deliberately swallow the error and return MACH_PORT_NULL so
    // callers fall back to mach_task_self().
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    if (kr != KERN_SUCCESS) task = MACH_PORT_NULL;
    return task;
}

vm_map_offset_t get_base_address(mach_port_t task) {
    mach_port_t use_task = (task == MACH_PORT_NULL) ? mach_task_self() : task;
    vm_map_offset_t base = 0;
    // _dyld_get_image_vmaddr_slide + first image load command is the
    // canonical way to find the ASLR slide on Apple's toolchains.
    // We expose it here as "the base" for tooling that expects one.
    uint32_t count = _dyld_image_count();
    if (count > 0) {
        const struct mach_header *hdr = _dyld_get_image_header(0);
        if (hdr != NULL) {
            base = (vm_map_offset_t)hdr;
        }
    }
    (void)use_task;
    return base;
}

// ---------------------------------------------------------------
// Raw read / write helpers (operate on the supplied task; for
// LiveContainer this *is* the host process).
// ---------------------------------------------------------------

static int read_bytes(mach_port_t task, mach_vm_address_t addr,
                      void *out, mach_vm_size_t size) {
    if (task == MACH_PORT_NULL) task = mach_task_self();
    mach_vm_offset_t data = 0;
    mach_msg_type_number_t data_size = 0;
    kern_return_t kr = vm_read(task, addr, size, &data, &data_size);
    if (kr != KERN_SUCCESS || data_size != size) {
        if (data != 0) vm_deallocate(task, data, data_size);
        return 0;
    }
    memcpy(out, (void *)data, size);
    vm_deallocate(task, data, data_size);
    return 1;
}

static int write_bytes(mach_port_t task, mach_vm_address_t addr,
                       const void *src, mach_vm_size_t size) {
    if (task == MACH_PORT_NULL) task = mach_task_self();

    // Try the direct write first; fall back to relaxing the page
    // protection if the region is read-only.
    kern_return_t kr = vm_write(task, addr,
                                (vm_offset_t)src, (mach_msg_type_number_t)size);
    if (kr == KERN_SUCCESS) return 1;

    vm_address_t page = addr & ~(vm_address_t)(PAGE_SIZE - 1);
    vm_prot_t original = VM_PROT_READ | VM_PROT_WRITE;
    if (vm_protect(task, page, PAGE_SIZE, FALSE,
                   VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) {
        return 0;
    }
    kr = vm_write(task, addr, (vm_offset_t)src, (mach_msg_type_number_t)size);
    (void)vm_protect(task, page, PAGE_SIZE, FALSE, original);
    return (kr == KERN_SUCCESS) ? 1 : 0;
}

void read_mem(mach_port_t task) {
    if (task == MACH_PORT_NULL) task = mach_task_self();

    vm_address_t addr = 0;
    vm_size_t size = 0;
    uint32_t depth = 0;
    int region_index = 0;
    while (1) {
        struct vm_region_submap_info_data_64 info;
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
        kern_return_t kr = vm_region_recurse_64(task, &addr, &size, &depth,
                                               (vm_region_recurse_info_t)&info, &count);
        if (kr != KERN_SUCCESS) break;
        if (info.is_submap) { depth++; continue; }

        printf("[region %d] start=0x%llx end=0x%llx size=0x%llx prot=R:%dW:%dX:%d\n",
               region_index++,
               (unsigned long long)addr,
               (unsigned long long)(addr + size),
               (unsigned long long)size,
               (info.protection & VM_PROT_READ)  != 0,
               (info.protection & VM_PROT_WRITE) != 0,
               (info.protection & VM_PROT_EXECUTE) != 0);
        addr += size;
    }
}

void *read_range_mem(mach_port_t task,
                     mach_vm_address_t address,
                     int forward,
                     int backward,
                     mach_vm_address_t *ret_address,
                     mach_vm_size_t *ret_data_size) {
    if (task == MACH_PORT_NULL) task = mach_task_self();
    if (ret_address != NULL) *ret_address = 0;
    if (ret_data_size != NULL) *ret_data_size = 0;

    if (forward <= 0)  forward = 0;
    if (backward < 0)  backward = 0;

    // Align the read window to a 4-byte boundary so neighbouring
    // types render cleanly in the on-screen hex view.
    mach_vm_address_t start = address - backward;
    mach_vm_address_t aligned_start = start & ~(mach_vm_address_t)0x3;
    mach_vm_size_t total = (mach_vm_size_t)(forward + backward +
                                            ((address - aligned_start) & 0x3));
    if (total == 0) total = 1;

    void *buf = malloc(total);
    if (buf == NULL) return NULL;
    memset(buf, 0, total);

    if (!read_bytes(task, aligned_start, buf, total)) {
        free(buf);
        return NULL;
    }

    if (ret_address != NULL) *ret_address = aligned_start;
    if (ret_data_size != NULL) *ret_data_size = total;
    return buf;
}

int write_mem(mach_port_t task, mach_vm_address_t address,
              void *value, int size) {
    return write_bytes(task, address, value, (mach_vm_size_t)size);
}

void print_mem(void *data, mach_vm_size_t data_size) {
    if (data == NULL || data_size == 0) {
        printf("(null)\n");
        return;
    }
    unsigned char *bytes = (unsigned char *)data;
    for (mach_vm_size_t i = 0; i < data_size; ++i) {
        printf("%02X ", bytes[i]);
        if ((i + 1) % 16 == 0) printf("\n");
    }
    if (data_size % 16 != 0) printf("\n");
}

// ---------------------------------------------------------------
// Refresh every value in a result chain in-place.
// ---------------------------------------------------------------

void review_mem_in_chain(mach_port_t task, search_result_chain_t chain) {
    if (chain == NULL) return;
    search_result_chain_t c = chain;
    while (c != NULL && c->result != NULL) {
        search_result_t r = c->result;
        if (r->value != NULL) free(r->value);
        r->value = malloc(r->size);
        if (r->value != NULL) {
            if (!read_bytes(task, r->address, r->value, r->size)) {
                memset(r->value, 0, r->size);
            }
        }
        c = c->next;
    }
}

// ---------------------------------------------------------------
// Core scan.  When `chain` is NULL we walk every writable readable
// region of the task and add matches.  When `chain` is non-NULL we
// re-read each saved address and keep only matches against the new
// `value` using the supplied `comparison`.
// ---------------------------------------------------------------

search_result_chain_t search_mem(mach_port_t task,
                                 void *value, int size, int type,
                                 int comparison,
                                 search_result_chain_t chain,
                                 int *length) {
    if (task == MACH_PORT_NULL) task = mach_task_self();
    if (length != NULL) *length = 0;

    search_result_chain_t result_head = NULL;
    search_result_chain_t result_tail = NULL;

    if (chain != NULL) {
        // Re-scan mode: walk the existing chain.
        search_result_chain_t c = chain;
        while (c != NULL && c->result != NULL) {
            search_result_t r = c->result;
            void *current = malloc(r->size);
            if (current != NULL && read_bytes(task, r->address, current, r->size)) {
                int c2 = compare_value(current, r->size,
                                       value, size, type);
                int keep = 0;
                switch (comparison) {
                    case SearchResultComparisonLT: keep = (c2 <  0); break;
                    case SearchResultComparisonLE: keep = (c2 <= 0); break;
                    case SearchResultComparisonEQ: keep = (c2 == 0); break;
                    case SearchResultComparisonGE: keep = (c2 >= 0); break;
                    case SearchResultComparisonGT: keep = (c2 >  0); break;
                    default:                       keep = (c2 == 0); break;
                }
                if (keep) {
                    // Refresh the cached value with what we just read.
                    if (r->value != NULL) free(r->value);
                    r->value = current;
                    current = NULL;
                    search_result_chain_t node = create_search_result_chain(
                        r->address, r->value, r->size, r->type, r->protection);
                    if (node != NULL) {
                        if (result_head == NULL) result_head = node;
                        else                     result_tail->next = node;
                        result_tail = node;
                        if (length != NULL) (*length)++;
                    }
                }
            }
            if (current != NULL) free(current);
            c = c->next;
        }
        return result_head;
    }

    // First scan: walk every readable+writable region that isn't
    // marked executable.  Skipping exec regions avoids wasting time
    // on code blobs and stops us from triggering W^X violations.
    vm_address_t addr = 0;
    vm_size_t size_of_region = 0;
    uint32_t depth = 0;
    while (1) {
        struct vm_region_submap_info_data_64 info;
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
        kern_return_t kr = vm_region_recurse_64(task, &addr, &size_of_region, &depth,
                                               (vm_region_recurse_info_t)&info, &count);
        if (kr != KERN_SUCCESS) break;
        if (info.is_submap) { depth++; continue; }

        int prot = info.protection;
        int readable_writable = ((prot & VM_PROT_READ) != 0) &&
                                ((prot & VM_PROT_WRITE) != 0) &&
                                ((prot & VM_PROT_EXECUTE) == 0);

        if (readable_writable && size_of_region > 0) {
            mach_vm_address_t region_addr = addr;
            mach_vm_size_t region_size = size_of_region;

            // Read the entire region in one shot so we can search
            // it locally without crossing the mach boundary on
            // every byte.
            vm_offset_t data = 0;
            mach_msg_type_number_t data_count = 0;
            kern_return_t r2 = vm_read(task, region_addr, region_size,
                                       &data, &data_count);
            if (r2 == KERN_SUCCESS && data_count > 0) {
                const uint8_t *buf = (const uint8_t *)data;
                mach_vm_size_t end = (mach_vm_size_t)data_count;
                for (mach_vm_size_t off = 0; off + (mach_vm_size_t)size <= end; ++off) {
                    const void *window = buf + off;
                    int c2 = compare_value((void *)window, size,
                                           value, size, type);
                    int match = 0;
                    switch (comparison) {
                        case SearchResultComparisonLT: match = (c2 <  0); break;
                        case SearchResultComparisonLE: match = (c2 <= 0); break;
                        case SearchResultComparisonEQ: match = (c2 == 0); break;
                        case SearchResultComparisonGE: match = (c2 >= 0); break;
                        case SearchResultComparisonGT: match = (c2 >  0); break;
                        default:                       match = (c2 == 0); break;
                    }
                    if (!match) continue;

                    search_result_chain_t node = create_search_result_chain(
                        region_addr + off, (void *)window, size, type,
                        (int)info.protection);
                    if (node == NULL) break;
                    if (result_head == NULL) result_head = node;
                    else                     result_tail->next = node;
                    result_tail = node;
                    if (length != NULL) (*length)++;

                    if (length != NULL && *length >= SEARCH_RESULT_LIMIT) {
                        break;
                    }
                }
                vm_deallocate(task, data, data_count);
            }
        }

        addr += size_of_region;
        if (length != NULL && *length >= SEARCH_RESULT_LIMIT) break;
    }

    return result_head;
}