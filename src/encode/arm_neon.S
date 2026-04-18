// SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// AArch64 NEON base64 encoder (GNU Assembler, compiled through the C
// preprocessor so that #ifdef __aarch64__ guards work).
//
// Algorithm (48 in → 64 out per iteration):
//   ld3 loads 48 bytes and de-interleaves them into three 16-byte vectors
//   a, b, c.  Four 6-bit index vectors are extracted with shifts and masks,
//   translated to ASCII with arithmetic offsets, then stored with st4.
//
// Index → ASCII arithmetic offsets (same method as x86_ssse3):
//   base 65;  index > 25: +6;  index > 51: -75;  index > 61: -15;  index > 62: +3
//
// Exported symbols:
//   int    arm_neon_supported(void)
//   size_t arm_neon_encode(const uint8_t *src, size_t src_len, char *dst)

#ifdef __aarch64__

    .arch   armv8-a
    .text

// ASCII_XLAT reg
//   Translates one fully-qualified vector register (e.g. "v5.16b") from a
//   6-bit index to an ASCII character in-place.
//   Clobbers v0 (offset accumulator) and v1 (comparison temp).
//   Constants v16–v23 must be preloaded before entering the SIMD loop.
.macro  ASCII_XLAT  reg
    movi    v0.16b, #65
    cmhi    v1.16b, \reg, v16.16b       // index > 25?
    and     v1.16b, v1.16b, v17.16b
    add     v0.16b, v0.16b, v1.16b
    cmhi    v1.16b, \reg, v18.16b       // index > 51?
    and     v1.16b, v1.16b, v19.16b
    sub     v0.16b, v0.16b, v1.16b
    cmhi    v1.16b, \reg, v20.16b       // index > 61?
    and     v1.16b, v1.16b, v21.16b
    sub     v0.16b, v0.16b, v1.16b
    cmhi    v1.16b, \reg, v22.16b       // index > 62?
    and     v1.16b, v1.16b, v23.16b
    add     v0.16b, v0.16b, v1.16b
    add     \reg,   \reg,   v0.16b
.endm

// int arm_neon_supported(void)
// NEON is mandatory on AArch64; always returns 1.
    .global arm_neon_supported
    .type   arm_neon_supported, %function
arm_neon_supported:
    mov     w0, #1
    ret
    .size   arm_neon_supported, . - arm_neon_supported


// size_t arm_neon_encode(const uint8_t *src, size_t src_len, char *dst)
//
// AArch64 calling convention:
//   x0 = src, x1 = src_len, x2 = dst
//   returns x0 = bytes written (no null terminator)
//
// Callee-saved GPRs used: x19–x24.
// NEON registers v0–v7, v16–v27 are caller-saved; v8–v15 are not touched.
    .global arm_neon_encode
    .type   arm_neon_encode, %function
arm_neon_encode:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0             // src (base, does not advance)
    mov     x20, x1             // src_len
    mov     x21, x2             // dst (base)
    mov     x22, xzr            // i  — source byte index
    mov     x23, xzr            // j  — output byte index

    // Translation thresholds and deltas loaded into caller-saved NEON regs.
    movi    v16.16b, #25        // threshold  > 25
    movi    v17.16b, #6         // delta      +6
    movi    v18.16b, #51        // threshold  > 51
    movi    v19.16b, #75        // delta      -75  (mod 256 via psubb)
    movi    v20.16b, #61        // threshold  > 61
    movi    v21.16b, #15        // delta      -15
    movi    v22.16b, #62        // threshold  > 62
    movi    v23.16b, #3         // delta      +3   (also used as mask 0x03)
    movi    v24.16b, #0x0f      // mask 0x0F for (b & 0x0F)
    movi    v25.16b, #0x3f      // mask 0x3F for (c & 0x3F)

.Lsimd_loop:
    sub     x24, x20, x22       // remaining = src_len - i
    cmp     x24, #48
    blt     .Lscalar_entry

    // ld3: load 48 bytes from src+i, de-interleave into:
    //   v0 = a  (bytes 0, 3, 6, …, 45)
    //   v1 = b  (bytes 1, 4, 7, …, 46)
    //   v2 = c  (bytes 2, 5, 8, …, 47)
    add     x0, x19, x22
    ld3     {v0.16b, v1.16b, v2.16b}, [x0]

    // idx0 (v3) = a >> 2
    ushr    v3.16b, v0.16b, #2

    // idx1 (v4) = (a & 0x03) << 4 | (b >> 4)
    ushr    v4.16b, v1.16b,  #4         // b >> 4
    and     v7.16b, v0.16b, v23.16b     // a & 0x03
    shl     v7.16b, v7.16b,  #4
    orr     v4.16b, v4.16b, v7.16b

    // idx2 (v5) = (b & 0x0F) << 2 | (c >> 6)
    ushr    v5.16b, v2.16b,  #6         // c >> 6
    and     v7.16b, v1.16b, v24.16b     // b & 0x0F
    shl     v7.16b, v7.16b,  #2
    orr     v5.16b, v5.16b, v7.16b

    // idx3 (v6) = c & 0x3F
    and     v6.16b, v2.16b, v25.16b

    // Translate each index vector to ASCII.
    // a/b/c (v0-v2) are no longer needed; ASCII_XLAT clobbers v0 and v1.
    ASCII_XLAT v3.16b
    ASCII_XLAT v4.16b
    ASCII_XLAT v5.16b
    ASCII_XLAT v6.16b

    // st4: store 64 bytes interleaved as
    //   [idx0[0], idx1[0], idx2[0], idx3[0], idx0[1], …]
    // v3-v6 are consecutive — required by st4.
    add     x0, x21, x23
    st4     {v3.16b, v4.16b, v5.16b, v6.16b}, [x0]

    add     x22, x22, #48
    add     x23, x23, #64
    b       .Lsimd_loop

.Lscalar_entry:
    // Set up scalar pointers.
    add     x19, x19, x22       // x19 = src + i  (current read pointer)
    sub     x24, x20, x22       // x24 = remaining bytes
    add     x4,  x21, x23       // x4  = dst + j  (current write pointer)

    adrp    x0, enc_lut
    add     x0, x0, :lo12:enc_lut

.Lscalar_loop:
    cbz     x24, .Ldone
    cmp     x24, #3
    bge     .Ls3
    cmp     x24, #2
    beq     .Ls2
    // fall through: 1 remaining byte

    ldrb    w1, [x19]

    lsr     w2, w1, #2
    ldrb    w2, [x0, x2]
    strb    w2, [x4], #1

    and     w2, w1, #0x03
    lsl     w2, w2, #4
    ldrb    w2, [x0, x2]
    strb    w2, [x4], #1

    mov     w2, #'='
    strb    w2, [x4], #1
    strb    w2, [x4], #1
    b       .Ldone

.Ls2:
    ldrb    w1, [x19], #1       // byte 0
    ldrb    w3, [x19], #1       // byte 1

    lsr     w2, w1, #2
    ldrb    w2, [x0, x2]
    strb    w2, [x4], #1

    and     w2, w1, #0x03
    lsl     w2, w2, #4
    lsr     w5, w3, #4
    orr     w2, w2, w5
    ldrb    w2, [x0, x2]
    strb    w2, [x4], #1

    and     w2, w3, #0x0f
    lsl     w2, w2, #2
    ldrb    w2, [x0, x2]
    strb    w2, [x4], #1

    mov     w2, #'='
    strb    w2, [x4], #1
    b       .Ldone

.Ls3:
    ldrb    w1, [x19], #1       // byte 0
    ldrb    w3, [x19], #1       // byte 1
    ldrb    w5, [x19], #1       // byte 2
    sub     x24, x24, #3

    lsr     w2, w1, #2
    ldrb    w2, [x0, x2]
    strb    w2, [x4], #1

    and     w2, w1, #0x03
    lsl     w2, w2, #4
    lsr     w6, w3, #4
    orr     w2, w2, w6
    ldrb    w2, [x0, x2]
    strb    w2, [x4], #1

    and     w2, w3, #0x0f
    lsl     w2, w2, #2
    lsr     w6, w5, #6
    orr     w2, w2, w6
    ldrb    w2, [x0, x2]
    strb    w2, [x4], #1

    and     w2, w5, #0x3f
    ldrb    w2, [x0, x2]
    strb    w2, [x4], #1

    b       .Lscalar_loop

.Ldone:
    // null-terminate
    strb    wzr, [x4]
    // j = current write pointer - dst base
    sub     x0, x4, x21

    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
    .size   arm_neon_encode, . - arm_neon_encode


    .section .rodata
    .balign 64
enc_lut:
    .ascii  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

#else
    // Non-AArch64: symbols provided by arm_neon.c stub.
    .text
#endif

    .section .note.GNU-stack, "", @progbits
