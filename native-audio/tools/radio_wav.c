// SPDX-License-Identifier: AGPL-3.0-only
// Host-only lazy WAV export using the same bounded decoder as native iOS.
#include "zgtasa_native_audio.h"
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef EXPECTED_SOURCE_STAMP
#error Build with the verified native-audio source stamp
#endif

static int number(const char *text, uint64_t *value) {
    if (!*text) return 0;
    for (const char *p = text; *p; p++) if (*p < '0' || *p > '9') return 0;
    errno = 0; char *end; unsigned long long result = strtoull(text, &end, 10);
    if (errno || *end) return 0;
    *value = (uint64_t)result; return 1;
}
static void le16(unsigned char *p, uint16_t value) {
    p[0] = (unsigned char)value; p[1] = (unsigned char)(value >> 8);
}
static void le32(unsigned char *p, uint32_t value) {
    for (int i = 0; i < 4; i++) p[i] = (unsigned char)(value >> (8 * i));
}
static int write_all(int fd, const void *data, size_t bytes) {
    const unsigned char *p = data;
    while (bytes) {
        ssize_t count = write(fd, p, bytes);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return 0;
        p += count; bytes -= (size_t)count;
    }
    return 1;
}
int main(int argc, char **argv) {
    uint64_t offset, bytes;
    if (argc != 5 || !number(argv[2], &offset) || !number(argv[3], &bytes)) {
        fprintf(stderr, "Usage: radio-wav pack-file record-offset record-bytes new-output.wav\n"); return 2;
    }
    if (strcmp(zgta_radio_source_stamp(), EXPECTED_SOURCE_STAMP)) {
        fprintf(stderr, "Native radio decoder source stamp mismatch\n"); return 2;
    }
    int input = open(argv[1], O_RDONLY), output = -1, created = 0;
    zgta_radio_decoder *decoder = NULL; zgta_radio_info info = {0};
    zgta_radio_status status = zgta_radio_create(input, offset, bytes, &decoder);
    if (input >= 0) close(input);
    if (!status) status = zgta_radio_prepare(decoder, &info);
    if (!status && (info.sample_rate != 32000 || info.output_channels != 2 ||
                   !info.frames || info.frames > (UINT32_MAX - 48u) / 8u)) status = ZGTA_RADIO_FORMAT;
    if (!status) {
        output = open(argv[4], O_WRONLY | O_CREAT | O_EXCL, 0600);
        if (output < 0) status = ZGTA_RADIO_IO;
        else created = 1;
    }
    if (!status) {
        unsigned char header[56] = {0}; uint32_t audio_bytes = (uint32_t)(info.frames * 8u);
        memcpy(header, "RIFF", 4); le32(header + 4, audio_bytes + 48u); memcpy(header + 8, "WAVEfmt ", 8);
        le32(header + 16, 16); le16(header + 20, 3); le16(header + 22, 2);
        le32(header + 24, 32000); le32(header + 28, 32000 * 8); le16(header + 32, 8); le16(header + 34, 32);
        memcpy(header + 36, "fact", 4); le32(header + 40, 4); le32(header + 44, (uint32_t)info.frames);
        memcpy(header + 48, "data", 4); le32(header + 52, audio_bytes);
        if (!write_all(output, header, sizeof(header))) status = ZGTA_RADIO_IO;
    }
    float samples[ZGTA_RADIO_MAX_WINDOW_FRAMES * 2];
    unsigned char encoded[ZGTA_RADIO_MAX_WINDOW_FRAMES * 8];
    for (uint64_t first = 0; !status && first < info.frames;) {
        uint32_t requested = info.frames - first < ZGTA_RADIO_MAX_WINDOW_FRAMES ?
            (uint32_t)(info.frames - first) : ZGTA_RADIO_MAX_WINDOW_FRAMES, written = 0;
        status = zgta_radio_read(decoder, first, requested, samples, ZGTA_RADIO_MAX_WINDOW_FRAMES * 2, &written);
        if (!status && written != requested) status = ZGTA_RADIO_CODEC;
        if (status) break;
        for (uint32_t i = 0; i < written * 2; i++) {
            uint32_t bits; memcpy(&bits, &samples[i], sizeof(bits)); le32(encoded + i * 4, bits);
        }
        if (!write_all(output, encoded, (size_t)written * 8)) status = ZGTA_RADIO_IO;
        first += written;
    }
    if (output >= 0 && close(output) && !status) status = ZGTA_RADIO_IO;
    zgta_radio_destroy(decoder);
    if (status) {
        if (created) unlink(argv[4]);
        fprintf(stderr, "Native radio WAV export failed: %s\n", zgta_radio_status_name(status)); return 1;
    }
    printf("{\"frames\":%llu,\"rate\":%u,\"channels\":2,\"format\":\"float32-wav\",\"sourceStamp\":\"%s\"}\n",
           (unsigned long long)info.frames, info.sample_rate, zgta_radio_source_stamp());
    return 0;
}
