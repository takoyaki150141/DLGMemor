//
//  search_result.c
//  mem
//
//  Re-implemented for theos / iOS 16+ deployment.
//  Original DeviLeo headers kept verbatim; this translation unit
//  is what the Xcode project referenced but never committed.
//

#include "search_result.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ---------------------------------------------------------------
// Construction / destruction
// ---------------------------------------------------------------

search_result_chain_t create_search_result_chain(mach_vm_address_t address,
                                                 void *value,
                                                 int size,
                                                 int type,
                                                 int protection) {
    search_result_t r = (search_result_t)malloc(sizeof(struct search_result));
    if (r == NULL) return NULL;
    r->address = address;
    r->size = size;
    r->type = type;
    r->protection = protection;
    r->value = malloc(size);
    if (r->value == NULL) {
        free(r);
        return NULL;
    }
    memcpy(r->value, value, size);

    search_result_chain_t c = (search_result_chain_t)malloc(sizeof(struct search_result_chain));
    if (c == NULL) {
        free(r->value);
        free(r);
        return NULL;
    }
    c->result = r;
    c->next = NULL;
    return c;
}

void destroy_search_result_chain(search_result_chain_t chain) {
    if (chain == NULL) return;
    if (chain->result != NULL) {
        if (chain->result->value != NULL) free(chain->result->value);
        free(chain->result);
    }
    free(chain);
}

void destroy_all_search_result_chain(search_result_chain_t chain) {
    while (chain != NULL) {
        search_result_chain_t next = chain->next;
        destroy_search_result_chain(chain);
        chain = next;
    }
}

void show_search_result_chain(search_result_chain_t chain) {
    search_result_chain_t c = chain;
    int i = 0;
    while (c != NULL && c->result != NULL) {
        printf("[%d] addr=0x%llx size=%d type=%d prot=%d value=",
               i++,
               (unsigned long long)c->result->address,
               c->result->size,
               c->result->type,
               c->result->protection);
        unsigned char *v = (unsigned char *)c->result->value;
        for (int j = 0; j < c->result->size; ++j) printf("%02x ", v[j]);
        printf("\n");
        c = c->next;
    }
}

// ---------------------------------------------------------------
// Type-aware value comparison
// Returns 0 if equal, <0 if v1<v2, >0 if v1>v2.
// `comparison` lets the caller decide which direction "match" is.
// ---------------------------------------------------------------

int compare_value(void *value1, int size1,
                  void *value2, int size2,
                  int type) {
    if (value1 == NULL || value2 == NULL) return -1;
    if (size1 != size2) return (size1 - size2);

    switch (type) {
        case SearchResultValueTypeUInt8: {
            uint8_t a = *(uint8_t *)value1;
            uint8_t b = *(uint8_t *)value2;
            return (a == b) ? 0 : (a < b ? -1 : 1);
        }
        case SearchResultValueTypeSInt8: {
            int8_t a = *(int8_t *)value1;
            int8_t b = *(int8_t *)value2;
            return (a == b) ? 0 : (a < b ? -1 : 1);
        }
        case SearchResultValueTypeUInt16: {
            uint16_t a = *(uint16_t *)value1;
            uint16_t b = *(uint16_t *)value2;
            return (a == b) ? 0 : (a < b ? -1 : 1);
        }
        case SearchResultValueTypeSInt16: {
            int16_t a = *(int16_t *)value1;
            int16_t b = *(int16_t *)value2;
            return (a == b) ? 0 : (a < b ? -1 : 1);
        }
        case SearchResultValueTypeUInt32: {
            uint32_t a = *(uint32_t *)value1;
            uint32_t b = *(uint32_t *)value2;
            return (a == b) ? 0 : (a < b ? -1 : 1);
        }
        case SearchResultValueTypeSInt32: {
            int32_t a = *(int32_t *)value1;
            int32_t b = *(int32_t *)value2;
            return (a == b) ? 0 : (a < b ? -1 : 1);
        }
        case SearchResultValueTypeUInt64: {
            uint64_t a = *(uint64_t *)value1;
            uint64_t b = *(uint64_t *)value2;
            return (a == b) ? 0 : (a < b ? -1 : 1);
        }
        case SearchResultValueTypeSInt64: {
            int64_t a = *(int64_t *)value1;
            int64_t b = *(int64_t *)value2;
            return (a == b) ? 0 : (a < b ? -1 : 1);
        }
        case SearchResultValueTypeFloat: {
            float a = *(float *)value1;
            float b = *(float *)value2;
            // Bit-exact float comparison; the original library
            // didn't special-case NaN and the games this targets
            // rarely store NaN in scan-able fields anyway.
            return (a == b) ? 0 : (a < b ? -1 : 1);
        }
        case SearchResultValueTypeDouble: {
            double a = *(double *)value1;
            double b = *(double *)value2;
            return (a == b) ? 0 : (a < b ? -1 : 1);
        }
        default:
            return memcmp(value1, value2, size1);
    }
}

int size_of_type(int type) {
    switch (type) {
        case SearchResultValueTypeUInt8:
        case SearchResultValueTypeSInt8:  return 1;
        case SearchResultValueTypeUInt16:
        case SearchResultValueTypeSInt16: return 2;
        case SearchResultValueTypeUInt32:
        case SearchResultValueTypeSInt32:
        case SearchResultValueTypeFloat:  return 4;
        case SearchResultValueTypeUInt64:
        case SearchResultValueTypeSInt64:
        case SearchResultValueTypeDouble: return 8;
        default: return 0;
    }
}

// ---------------------------------------------------------------
// Parse a string into a typed value. Allocates a buffer the caller
// must free.
// ---------------------------------------------------------------

void *value_of_type(const char *value_str, int type, int *value_size) {
    if (value_str == NULL || value_size == NULL) return NULL;
    *value_size = size_of_type(type);
    if (*value_size == 0) return NULL;

    void *v = malloc(*value_size);
    if (v == NULL) return NULL;
    memset(v, 0, *value_size);

    switch (type) {
        case SearchResultValueTypeUInt8: {
            unsigned int t = 0; sscanf(value_str, "%u", &t);
            *(uint8_t *)v = (uint8_t)t; break;
        }
        case SearchResultValueTypeSInt8: {
            int t = 0; sscanf(value_str, "%d", &t);
            *(int8_t *)v = (int8_t)t; break;
        }
        case SearchResultValueTypeUInt16: {
            unsigned int t = 0; sscanf(value_str, "%u", &t);
            *(uint16_t *)v = (uint16_t)t; break;
        }
        case SearchResultValueTypeSInt16: {
            int t = 0; sscanf(value_str, "%d", &t);
            *(int16_t *)v = (int16_t)t; break;
        }
        case SearchResultValueTypeUInt32: {
            unsigned long t = 0; sscanf(value_str, "%lu", &t);
            *(uint32_t *)v = (uint32_t)t; break;
        }
        case SearchResultValueTypeSInt32: {
            long t = 0; sscanf(value_str, "%ld", &t);
            *(int32_t *)v = (int32_t)t; break;
        }
        case SearchResultValueTypeUInt64: {
            unsigned long long t = 0; sscanf(value_str, "%llu", &t);
            *(uint64_t *)v = (uint64_t)t; break;
        }
        case SearchResultValueTypeSInt64: {
            long long t = 0; sscanf(value_str, "%lld", &t);
            *(int64_t *)v = (int64_t)t; break;
        }
        case SearchResultValueTypeFloat: {
            float t = 0.0f; sscanf(value_str, "%f", &t);
            *(float *)v = t; break;
        }
        case SearchResultValueTypeDouble: {
            double t = 0.0; sscanf(value_str, "%lf", &t);
            *(double *)v = t; break;
        }
        default:
            free(v);
            v = NULL;
            *value_size = 0;
            break;
    }
    return v;
}