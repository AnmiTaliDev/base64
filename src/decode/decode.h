// SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: GPL-3.0-or-later

#ifndef DECODE_H
#define DECODE_H

#include <stddef.h>
#include <stdint.h>

typedef size_t (*base64_decode_fn)(const char *src, size_t src_len, uint8_t *dst);

typedef struct {
    const char        *name;
    int              (*supported)(void);
    base64_decode_fn   decode;
} base64_decoder_t;

int    generic_dec_supported(void);
size_t generic_dec_decode(const char *src, size_t src_len, uint8_t *dst);

int    x86_ssse3_dec_supported(void);
size_t x86_ssse3_dec_decode(const char *src, size_t src_len, uint8_t *dst);

#endif
