// SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Non-AArch64 stub for the ARM NEON encoder.
// On AArch64 the real implementation lives in arm_neon.S.

#include "encode.h"

#ifndef __aarch64__

int arm_neon_supported(void)
{
    return 0;
}

size_t arm_neon_encode(const uint8_t *src, size_t src_len, char *dst)
{
    (void)src;
    (void)src_len;
    (void)dst;
    return (size_t)-1;
}

#endif
