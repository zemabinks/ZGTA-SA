// SPDX-License-Identifier: AGPL-3.0-only
#ifndef ZGTASA_NATIVE_AUDIO_H
#define ZGTASA_NATIVE_AUDIO_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
#define ZGTA_RADIO_ABI_VERSION 1
#define ZGTA_RADIO_HEADER_BYTES 8068u
#define ZGTA_RADIO_MAX_PAYLOAD_BYTES (64u*1024u*1024u)
#define ZGTA_RADIO_MAX_WINDOW_FRAMES 8000u
#define ZGTA_RADIO_MAX_HEAP_BYTES (16u*1024u*1024u)
typedef struct zgta_radio_decoder zgta_radio_decoder;
typedef enum zgta_radio_status {
 ZGTA_RADIO_OK=0, ZGTA_RADIO_ARGUMENT=1, ZGTA_RADIO_RANGE=2,
 ZGTA_RADIO_SOURCE=3, ZGTA_RADIO_CHANGED=4, ZGTA_RADIO_OGG=5,
 ZGTA_RADIO_FORMAT=6, ZGTA_RADIO_CODEC=7, ZGTA_RADIO_CANCELLED=8,
 ZGTA_RADIO_MEMORY=9, ZGTA_RADIO_NONFINITE=10, ZGTA_RADIO_STATE=11,
 ZGTA_RADIO_LIMIT=12, ZGTA_RADIO_IO=13
} zgta_radio_status;
typedef struct zgta_radio_info {
 uint32_t abi_version, sample_rate, source_channels, output_channels;
 uint64_t frames, payload_bytes;
} zgta_radio_info;
typedef struct zgta_radio_stats {
 uint64_t bytes_read, read_calls, maximum_read_bytes;
 uint64_t current_heap_bytes, peak_heap_bytes, allocation_calls;
} zgta_radio_stats;
/* create duplicates a readable regular FD, never changes its seek position and
 * never owns/closes the caller FD. The bounded record includes its8068B header.
 * No catalogue/path lookup or source authentication is performed by this ABI. */
zgta_radio_status zgta_radio_create(int fd, uint64_t record_offset,
                                   uint64_t record_bytes, zgta_radio_decoder **out);
/* All operations on one handle except cancel have ONE serial owner. prepare
 * validates the entire bounded Ogg record (CRC, packet/page/format/EOS limits)
 * before opening the reference decoder. No audio device is used. */
zgta_radio_status zgta_radio_prepare(zgta_radio_decoder *, zgta_radio_info *);
/* Exact sample window; stereo interleaved finite float32 at32000Hz. Capacity is
 * floats, not bytes. EOF may return fewer frames. Errors set written=0; discard
 * output after an error. Invalid arguments do not poison a prepared handle. */
zgta_radio_status zgta_radio_read(zgta_radio_decoder *, uint64_t first_frame,
                                 uint32_t frames, float *stereo,
                                 size_t capacity_floats, uint32_t *written);
/* Cancellation is sticky and thread-safe. It may overlap prepare/read; caller
 * must join that serial owner BEFORE destroy. destroy itself may not overlap
 * any call, including cancel. It releases all codec allocations and the DUP fd. */
void zgta_radio_cancel(zgta_radio_decoder *);
void zgta_radio_destroy(zgta_radio_decoder *);
zgta_radio_status zgta_radio_get_stats(const zgta_radio_decoder *, zgta_radio_stats *);
const char *zgta_radio_source_stamp(void);
const char *zgta_radio_status_name(zgta_radio_status);
#ifdef __cplusplus
}
#endif
#endif
