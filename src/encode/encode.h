// SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: GPL-3.0-or-later

#ifndef ENCODE_H
#define ENCODE_H

#include <stddef.h>
#include <stdint.h>

typedef size_t (*base64_encode_fn)(const uint8_t *src, size_t src_len, char *dst);

typedef struct {
    const char        *name;
    int              (*supported)(void);
    base64_encode_fn   encode;
} base64_encoder_t;

// Each encoder unit implements these two symbols:
//   int   <name>_supported(void);
//   size_t <name>_encode(const uint8_t *src, size_t src_len, char *dst);

// Portable fallback — always available.
int    generic_supported(void);
size_t generic_encode(const uint8_t *src, size_t src_len, char *dst);

// x86-64 SSSE3 encoder.
int    x86_ssse3_supported(void);
size_t x86_ssse3_encode(const uint8_t *src, size_t src_len, char *dst);

// AArch64 NEON encoder.
int    arm_neon_supported(void);
size_t arm_neon_encode(const uint8_t *src, size_t src_len, char *dst);

// ARM32 NEON encoder.
int    arm32_neon_supported(void);
size_t arm32_neon_encode(const uint8_t *src, size_t src_len, char *dst);

#endif
