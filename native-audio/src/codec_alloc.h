// SPDX-License-Identifier: AGPL-3.0-only
// Compile-prefix only for unchanged Xiph translation units. Include libc first,
// so allocation macros never rewrite system declarations. Every Xiph heap block
// belongs to the active serial decoder and is tracked for bounded abort cleanup.
#ifndef ZGTA_RADIO_CODEC_ALLOC_H
#define ZGTA_RADIO_CODEC_ALLOC_H
#include <stdlib.h>
#include <stdint.h>
#include <alloca.h>
void *zgta_radio_codec_malloc(size_t);
void *zgta_radio_codec_calloc(size_t,size_t);
void *zgta_radio_codec_realloc(void *,size_t);
void zgta_radio_codec_free(void *);
size_t zgta_radio_codec_stack(size_t);
#define malloc zgta_radio_codec_malloc
#define calloc zgta_radio_codec_calloc
#define realloc zgta_radio_codec_realloc
#define free zgta_radio_codec_free
#undef alloca
#define alloca(n) __builtin_alloca(zgta_radio_codec_stack(n))
#endif
