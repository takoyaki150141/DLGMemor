//
//  mem_utils.c
//  mem
//
//  Re-implemented for theos / iOS 16+ deployment.
//  Substring-like scan with type-aware comparison.
//

#include "mem_utils.h"
#include "search_result_def.h"
#include <stddef.h>
#include <stdint.h>

// Forward declaration to keep this TU self-contained even if
// search_result.c isn't linked in (the host app already has its
// own copy otherwise).
int compare_value(void *value1, int size1,
                  void *value2, int size2,
                  int type);

// Walk `len` bytes of `b`, comparing each `vlen`-byte window
// against `v` with type-aware semantics. Returns a pointer into
// `b` on match (or NULL).
//
// `comparison` is one of SearchResultComparisonLT/LE/EQ/GE/GT:
// only windows for which compare_value(...) compares in that
// direction are returned. EQ is the common case.
void *search_mem_value(const void *b, size_t len,
                       void *v, size_t vlen,
                       int type, int comparison) {
    if (b == NULL || v == NULL || len < vlen) return NULL;

    const uint8_t *buf = (const uint8_t *)b;
    for (size_t i = 0; i + vlen <= len; ++i) {
        int c = compare_value((void *)(buf + i), (int)vlen,
                              v, (int)vlen, type);
        switch (comparison) {
            case SearchResultComparisonLT: if (c <  0) return (void *)(buf + i); break;
            case SearchResultComparisonLE: if (c <= 0) return (void *)(buf + i); break;
            case SearchResultComparisonEQ: if (c == 0) return (void *)(buf + i); break;
            case SearchResultComparisonGE: if (c >= 0) return (void *)(buf + i); break;
            case SearchResultComparisonGT: if (c >  0) return (void *)(buf + i); break;
            default:                       if (c == 0) return (void *)(buf + i); break;
        }
    }
    return NULL;
}