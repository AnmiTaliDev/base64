// SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Runtime NEON detection for ARM32.
// The actual encoder lives in arm32_neon.S; this file provides only
// arm32_neon_supported() and, on non-ARM32 targets, stub symbols so the
// linker stays happy regardless of which architecture is being built.

#include "encode.h"

#if defined(__arm__) && !defined(__aarch64__)

#ifdef __linux__
#include <sys/auxv.h>
#ifndef HWCAP_NEON
#define HWCAP_NEON (1 << 12)
#endif

int arm32_neon_supported(void)
{
    return (getauxval(AT_HWCAP) & HWCAP_NEON) != 0;
}
#else
// Non-Linux ARM32: conservatively report no NEON.
int arm32_neon_supported(void)
{
    return 0;
}
#endif

#else

// Non-ARM32 stubs — the .S file is empty on these targets.
int arm32_neon_supported(void)
{
    return 0;
}

size_t arm32_neon_encode(const uint8_t *src, size_t src_len, char *dst)
{
    (void)src;
    (void)src_len;
    (void)dst;
    return (size_t)-1;
}

#endif
