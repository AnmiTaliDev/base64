// SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: GPL-3.0-or-later

#include "encode.h"
#include <stdint.h>
#include <stddef.h>

static const uint8_t lut[64] = {
    'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
    'Q','R','S','T','U','V','W','X','Y','Z','a','b','c','d','e','f',
    'g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v',
    'w','x','y','z','0','1','2','3','4','5','6','7','8','9','+','/'
};

int generic_supported(void)
{
    return 1;
}

size_t generic_encode(const uint8_t *src, size_t src_len, char *dst)
{
    size_t i = 0;
    size_t j = 0;

    while (i + 2 < src_len) {
        uint32_t t = ((uint32_t)src[i] << 16)
                   | ((uint32_t)src[i + 1] << 8)
                   |  (uint32_t)src[i + 2];
        dst[j++] = (char)lut[(t >> 18) & 0x3F];
        dst[j++] = (char)lut[(t >> 12) & 0x3F];
        dst[j++] = (char)lut[(t >>  6) & 0x3F];
        dst[j++] = (char)lut[ t        & 0x3F];
        i += 3;
    }

    if (i + 1 == src_len) {
        uint32_t t = (uint32_t)src[i] << 16;
        dst[j++] = (char)lut[(t >> 18) & 0x3F];
        dst[j++] = (char)lut[(t >> 12) & 0x3F];
        dst[j++] = '=';
        dst[j++] = '=';
    } else if (i + 2 == src_len) {
        uint32_t t = ((uint32_t)src[i] << 16) | ((uint32_t)src[i + 1] << 8);
        dst[j++] = (char)lut[(t >> 18) & 0x3F];
        dst[j++] = (char)lut[(t >> 12) & 0x3F];
        dst[j++] = (char)lut[(t >>  6) & 0x3F];
        dst[j++] = '=';
    }

    dst[j] = '\0';
    return j;
}
