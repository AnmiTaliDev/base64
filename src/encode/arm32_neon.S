// SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// ARM32 NEON base64 encoder (GNU Assembler, unified syntax).
//
// Uses vld3 to load 24 input bytes de-interleaved into three 8-lane
// d-registers (uint8x8_t).  Extracts four 6-bit index vectors, translates
// them to ASCII with arithmetic offsets, then stores 32 output bytes with
// vst4.  Per-iteration throughput: 24 in → 32 out.
//
// Index → ASCII offsets (identical method to x86_ssse3 and arm_neon):
//   base 65;  > 25: +6;  > 51: -75;  > 61: -15;  > 62: +3
//
// Exported symbol:
//   size_t arm32_neon_encode(const uint8_t *src, size_t src_len, char *dst)
// arm32_neon_supported() lives in arm32_neon.c.

#if defined(__arm__) && !defined(__aarch64__)

    .arch   armv7-a
    .fpu    neon
    .syntax unified
    .arm

    .text

// ASCII_XLAT reg
//   Translates one d-register (uint8x8_t) of 6-bit indices to ASCII in-place.
//   Clobbers d0 (offset accumulator) and d1 (comparison temp).
//   Constants d16–d23 must be preloaded before the SIMD loop.
.macro  ASCII_XLAT  reg
    vmov.i8  d0,  #65
    vcgt.u8  d1,  \reg, d16         @ index > 25?
    vand     d1,  d1,   d17
    vadd.i8  d0,  d0,   d1
    vcgt.u8  d1,  \reg, d18         @ index > 51?
    vand     d1,  d1,   d19
    vsub.i8  d0,  d0,   d1
    vcgt.u8  d1,  \reg, d20         @ index > 61?
    vand     d1,  d1,   d21
    vsub.i8  d0,  d0,   d1
    vcgt.u8  d1,  \reg, d22         @ index > 62?
    vand     d1,  d1,   d23
    vadd.i8  d0,  d0,   d1
    vadd.i8  \reg, \reg, d0
.endm

// size_t arm32_neon_encode(const uint8_t *src, size_t src_len, char *dst)
//
// APCS-GNU calling convention:
//   r0 = src, r1 = src_len, r2 = dst
//   returns r0 = bytes written (no null terminator)
//
// GPR usage:
//   r4  = src pointer (advances)       r5  = src_end (src + src_len, const)
//   r6  = dst base (const)             r7  = j (output byte count)
//   r8  = remaining bytes (per iter)   r9  = current write pointer (scalar)
//   r10 = LUT pointer (scalar)         r11 = byte temp (scalar)
//
// NEON: d0-d7 (caller-saved) used for data; d16-d25 (caller-saved) for constants.
// d8-d15 (callee-saved) are not touched.
    .global arm32_neon_encode
    .type   arm32_neon_encode, %function
arm32_neon_encode:
    push    {r4, r5, r6, r7, r8, r9, r10, r11, lr}

    mov     r4,  r0             @ src pointer
    add     r5,  r0, r1         @ src_end = src + src_len
    mov     r6,  r2             @ dst base
    mov     r7,  #0             @ j = 0

    vmov.i8  d16, #25
    vmov.i8  d17, #6
    vmov.i8  d18, #51
    vmov.i8  d19, #75
    vmov.i8  d20, #61
    vmov.i8  d21, #15
    vmov.i8  d22, #62
    vmov.i8  d23, #3
    vmov.i8  d24, #15           @ 0x0F
    vmov.i8  d25, #63           @ 0x3F

.Lsimd_loop:
    sub     r8, r5, r4          @ remaining = src_end - src_ptr
    cmp     r8, #24
    blt     .Lscalar_entry

    // vld3: load 24 bytes, de-interleave into d0=a, d1=b, d2=c; advance r4.
    vld3.8  {d0, d1, d2}, [r4]!

    // idx0 (d3) = a >> 2
    vshr.u8  d3, d0, #2

    // idx1 (d4) = (a & 0x03) << 4 | (b >> 4)
    vshr.u8  d4, d1, #4
    vand     d7, d0, d23         @ a & 0x03  (d23 = {3})
    vshl.i8  d7, d7, #4
    vorr     d4, d4, d7

    // idx2 (d5) = (b & 0x0F) << 2 | (c >> 6)
    vshr.u8  d5, d2, #6
    vand     d7, d1, d24         @ b & 0x0F
    vshl.i8  d7, d7, #2
    vorr     d5, d5, d7

    // idx3 (d6) = c & 0x3F
    vand     d6, d2, d25

    // a/b/c (d0-d2) are consumed; ASCII_XLAT clobbers d0 and d1.
    ASCII_XLAT d3
    ASCII_XLAT d4
    ASCII_XLAT d5
    ASCII_XLAT d6

    // vst4: interleave d3-d6 into 32 output bytes.
    // d3-d6 are consecutive — required by vst4.
    add     r8, r6, r7
    vst4.8  {d3, d4, d5, d6}, [r8]
    add     r7, r7, #32
    b       .Lsimd_loop

.Lscalar_entry:
    sub     r8, r5, r4          @ remaining bytes
    add     r9, r6, r7          @ r9 = current write pointer

    adr     r10, .Lenc_lut

.Lscalar_loop:
    cmp     r8, #0
    beq     .Ldone
    cmp     r8, #3
    bge     .Ls3
    cmp     r8, #2
    beq     .Ls2

    // 1 remaining byte
    ldrb    r0, [r4]

    lsr     r1, r0, #2
    ldrb    r1, [r10, r1]
    strb    r1, [r9], #1

    and     r1, r0, #0x03
    lsl     r1, r1, #4
    ldrb    r1, [r10, r1]
    strb    r1, [r9], #1

    mov     r1, #'='
    strb    r1, [r9], #1
    strb    r1, [r9], #1
    b       .Ldone

.Ls2:
    ldrb    r0, [r4], #1
    ldrb    r3, [r4], #1

    lsr     r1, r0, #2
    ldrb    r1, [r10, r1]
    strb    r1, [r9], #1

    and     r1, r0, #0x03
    lsl     r1, r1, #4
    lsr     r2, r3, #4
    orr     r1, r1, r2
    ldrb    r1, [r10, r1]
    strb    r1, [r9], #1

    and     r1, r3, #0x0F
    lsl     r1, r1, #2
    ldrb    r1, [r10, r1]
    strb    r1, [r9], #1

    mov     r1, #'='
    strb    r1, [r9], #1
    b       .Ldone

.Ls3:
    ldrb    r0,  [r4], #1
    ldrb    r3,  [r4], #1
    ldrb    r11, [r4], #1
    sub     r8,  r8,   #3

    lsr     r1, r0, #2
    ldrb    r1, [r10, r1]
    strb    r1, [r9], #1

    and     r1, r0, #0x03
    lsl     r1, r1, #4
    lsr     r2, r3, #4
    orr     r1, r1, r2
    ldrb    r1, [r10, r1]
    strb    r1, [r9], #1

    and     r1, r3, #0x0F
    lsl     r1, r1, #2
    lsr     r2, r11, #6
    orr     r1, r1, r2
    ldrb    r1, [r10, r1]
    strb    r1, [r9], #1

    and     r1, r11, #0x3F
    ldrb    r1, [r10, r1]
    strb    r1, [r9], #1

    b       .Lscalar_loop

.Ldone:
    mov     r0, #0
    strb    r0, [r9]            @ null-terminate
    sub     r0, r9, r6          @ return j = write_ptr - dst_base

    pop     {r4, r5, r6, r7, r8, r9, r10, r11, pc}
    .size   arm32_neon_encode, . - arm32_neon_encode


    .section .rodata
    .balign 64
.Lenc_lut:
    .ascii  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

#else
    .text
#endif

    .section .note.GNU-stack, "", @progbits
