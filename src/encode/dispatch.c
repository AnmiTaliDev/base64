// SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Encoder dispatch: walks the priority table at first call, selects the first
// implementation whose supported() check passes, then caches the function
// pointer for all subsequent calls.
//
// To register a new optimizer:
//   1. Add its two symbols to encode.h.
//   2. Append an entry to the encoders[] table below — higher index = lower priority.

#include "encode.h"
#include "../../include/base64.h"
#include <stddef.h>

// Priority table: first entry with supported() == 1 wins.
// Keep faster/more-specific implementations at the top.
static const base64_encoder_t encoders[] = {
    { "arm_neon",  arm_neon_supported,  arm_neon_encode  },
    { "x86_ssse3", x86_ssse3_supported, x86_ssse3_encode },
    { "generic",   generic_supported,   generic_encode   },
};

#define ENCODER_COUNT (sizeof(encoders) / sizeof(encoders[0]))

static base64_encode_fn resolve(void)
{
    for (size_t i = 0; i < ENCODER_COUNT; i++) {
        if (encoders[i].supported())
            return encoders[i].encode;
    }
    // generic_supported() always returns 1, so this is unreachable.
    return generic_encode;
}

size_t base64_encode(const uint8_t *src, size_t src_len, char *dst)
{
    static base64_encode_fn fn = NULL;
    if (!fn)
        fn = resolve();
    return fn(src, src_len, dst);
}
