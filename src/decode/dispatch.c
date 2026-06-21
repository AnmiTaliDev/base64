// SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: GPL-3.0-or-later

#include "decode.h"
#include "../../include/base64.h"
#include <stddef.h>

static const base64_decoder_t decoders[] = {
    { "x86_ssse3", x86_ssse3_dec_supported, x86_ssse3_dec_decode },
    { "generic",   generic_dec_supported,   generic_dec_decode   },
};

#define DECODER_COUNT (sizeof(decoders) / sizeof(decoders[0]))

static base64_decode_fn resolve(void)
{
    for (size_t i = 0; i < DECODER_COUNT; i++) {
        if (decoders[i].supported())
            return decoders[i].decode;
    }
    return generic_dec_decode;
}

size_t base64_decode(const char *src, size_t src_len, uint8_t *dst)
{
    static base64_decode_fn fn = NULL;
    if (!fn)
        fn = resolve();
    return fn(src, src_len, dst);
}
