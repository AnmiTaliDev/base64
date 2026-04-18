// SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: GPL-3.0-or-later

#ifndef BASE64_H
#define BASE64_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns bytes needed to hold base64-encoded output, including null terminator.
size_t base64_encoded_size(size_t input_len);

// Returns maximum bytes the decoded output can occupy.
size_t base64_decoded_max_size(size_t encoded_len);

// Encode src of length src_len into dst.
// dst must be at least base64_encoded_size(src_len) bytes.
// Returns number of bytes written, excluding null terminator.
size_t base64_encode(const uint8_t *src, size_t src_len, char *dst);

// Decode base64 string src of length src_len into dst.
// dst must be at least base64_decoded_max_size(src_len) bytes.
// Returns number of bytes written, or (size_t)-1 on invalid input.
size_t base64_decode(const char *src, size_t src_len, uint8_t *dst);

#ifdef __cplusplus
}
#endif

#endif
