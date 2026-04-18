; SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
; SPDX-License-Identifier: GPL-3.0-or-later
;
; x86-64 v2 (SSSE3) base64 encoder.
; Processes 12 input bytes -> 16 output bytes per SIMD iteration.
; Scalar tail handles remaining 1-11 bytes.
;
; Index -> ASCII translation uses the arithmetic offset method:
;   base_offset = 65
;   index > 25: +6   (offset 71  for a-z)
;   index > 51: -75  (offset 252 for 0-9, as uint8)
;   index > 61: -15  (offset 237 for '+')
;   index > 62: +3   (offset 240 for '/')
; Then: output_byte = index + offset  (mod 256)
;
; Exported symbols (match the base64_encoder_t interface in encode.h):
;   int    x86_ssse3_supported(void)
;   size_t x86_ssse3_encode(const uint8_t *src, size_t src_len, char *dst)

global x86_ssse3_supported
global x86_ssse3_encode

section .rodata

align 64
enc_lut: db "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

; pshufb mask: rearrange a 16-byte block (4 groups of 3 bytes each) into
; 4 copies of [b0 b1 b1 b2] so the multiply-shift step extracts all four
; 6-bit indices from each dword.
; Rearranges 12 contiguous source bytes into 4 groups of [b1,b0,b2,b1].
; This layout lets the multiply-shift below extract all four 6-bit indices
; from each dword without any extra shifts outside the SIMD pipeline.
align 16
shuf_src: db 1,0,2,1, 4,3,5,4, 7,6,8,7, 10,9,11,10

; After pshufb each dword holds [b1, b0, b2, b1] (little-endian).
; mask_hi/mult_hi extracts idx3 (b0>>2) into byte 0 and idx1 (low4(b1)<<2 | b2>>6) into byte 2.
; mask_lo/mult_lo extracts idx2 (b1>>4 | low2(b0)<<4) into byte 1 and idx0 (b2&0x3F) into byte 3.
align 16
mask_hi: times 4 dd 0x0FC0FC00
align 16
mask_lo: times 4 dd 0x003F03F0
align 16
mult_hi: times 4 dd 0x04000040
align 16
mult_lo: times 4 dd 0x01000010

; Arithmetic translation constants.
align 16
c_base:  times 16 db 65    ; starting offset ('A')
align 16
c_25:    times 16 db 25    ; threshold: index > 25 → +6
align 16
c_51:    times 16 db 51    ; threshold: index > 51 → -75
align 16
c_61:    times 16 db 61    ; threshold: index > 61 → -15
align 16
c_62:    times 16 db 62    ; threshold: index > 62 → +3
align 16
c_d6:    times 16 db 6
align 16
c_d75:   times 16 db 75
align 16
c_d15:   times 16 db 15
align 16
c_d3:    times 16 db 3

section .text

; int x86_ssse3_supported(void)
; Returns 1 if CPUID reports SSSE3 (CPUID.1:ECX[9]), else 0.
x86_ssse3_supported:
    push    rbx
    mov     eax, 1
    cpuid
    xor     eax, eax
    bt      ecx, 9
    adc     eax, 0
    pop     rbx
    ret

; size_t x86_ssse3_encode(const uint8_t *src, size_t src_len, char *dst)
;
; System V AMD64 ABI:
;   rdi = src, rsi = src_len, rdx = dst
;   rax = bytes written (no null terminator)
x86_ssse3_encode:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi            ; src pointer (advances)
    mov     r13, rsi            ; src_len
    mov     r14, rdx            ; dst
    xor     r15, r15            ; out_pos
    mov     rbx, rsi            ; remaining source bytes

    cmp     rbx, 12
    jl      .scalar

    movdqa  xmm13, [rel shuf_src]
    movdqa  xmm14, [rel mask_hi]
    movdqa  xmm15, [rel mask_lo]

.simd_loop:
    ; Load 16 bytes covering 12 source bytes + 4 lookahead (safe: tail < 12).
    movdqu  xmm0, [r12]

    ; Rearrange into [b0 b1 b1 b2] groups.
    pshufb  xmm0, xmm13

    ; Extract indices 0,2 per group via pmulhuw.
    movdqa  xmm1, xmm0
    pand    xmm1, xmm14
    pmulhuw xmm1, [rel mult_hi]

    ; Extract indices 1,3 per group via pmullw.
    movdqa  xmm2, xmm0
    pand    xmm2, xmm15
    pmullw  xmm2, [rel mult_lo]

    por     xmm1, xmm2          ; xmm1: 16 six-bit indices (one per byte, 0-63)

    ; Translate indices to ASCII using arithmetic offsets.
    ; offset starts at 65.
    movdqa  xmm0, [rel c_base]  ; offset = 65

    ; index > 25: offset += 6
    movdqa  xmm2, xmm1
    pcmpgtb xmm2, [rel c_25]    ; -1 where index > 25
    pand    xmm2, [rel c_d6]
    paddb   xmm0, xmm2

    ; index > 51: offset -= 75
    movdqa  xmm2, xmm1
    pcmpgtb xmm2, [rel c_51]    ; -1 where index > 51
    pand    xmm2, [rel c_d75]
    psubb   xmm0, xmm2

    ; index > 61: offset -= 15
    movdqa  xmm2, xmm1
    pcmpgtb xmm2, [rel c_61]    ; -1 where index > 61
    pand    xmm2, [rel c_d15]
    psubb   xmm0, xmm2

    ; index > 62: offset += 3
    movdqa  xmm2, xmm1
    pcmpgtb xmm2, [rel c_62]    ; -1 where index > 62
    pand    xmm2, [rel c_d3]
    paddb   xmm0, xmm2

    ; output = index + offset
    paddb   xmm1, xmm0

    movdqu  [r14 + r15], xmm1

    add     r12, 12
    add     r15, 16
    sub     rbx, 12
    cmp     rbx, 12
    jge     .simd_loop

.scalar:
    ; rbx = remaining source bytes (0..11)
    lea     r8, [rel enc_lut]

.scalar_loop:
    test    rbx, rbx
    jz      .done

    cmp     rbx, 3
    jge     .s3

    cmp     rbx, 2
    je      .s2

    ; 1 remaining byte
    movzx   eax, byte [r12]

    mov     ecx, eax
    shr     ecx, 2
    movzx   ecx, byte [r8 + rcx]
    mov     [r14 + r15], cl
    inc     r15

    and     eax, 0x03
    shl     eax, 4
    movzx   eax, byte [r8 + rax]
    mov     [r14 + r15], al
    inc     r15

    mov     byte [r14 + r15],     '='
    mov     byte [r14 + r15 + 1], '='
    add     r15, 2
    jmp     .done

.s2:
    ; 2 remaining bytes
    movzx   eax, byte [r12]
    movzx   edx, byte [r12 + 1]

    mov     ecx, eax
    shr     ecx, 2
    movzx   ecx, byte [r8 + rcx]
    mov     [r14 + r15], cl
    inc     r15

    mov     ecx, eax
    and     ecx, 0x03
    shl     ecx, 4
    mov     edi, edx
    shr     edi, 4
    or      ecx, edi
    movzx   ecx, byte [r8 + rcx]
    mov     [r14 + r15], cl
    inc     r15

    and     edx, 0x0F
    shl     edx, 2
    movzx   edx, byte [r8 + rdx]
    mov     [r14 + r15], dl
    inc     r15

    mov     byte [r14 + r15], '='
    inc     r15
    jmp     .done

.s3:
    ; Full group of 3 bytes
    movzx   eax, byte [r12]
    movzx   edx, byte [r12 + 1]
    movzx   ecx, byte [r12 + 2]

    mov     edi, eax
    shr     edi, 2
    movzx   edi, byte [r8 + rdi]
    mov     [r14 + r15], dil
    inc     r15

    mov     edi, eax
    and     edi, 0x03
    shl     edi, 4
    mov     r9d, edx
    shr     r9d, 4
    or      edi, r9d
    movzx   edi, byte [r8 + rdi]
    mov     [r14 + r15], dil
    inc     r15

    mov     edi, edx
    and     edi, 0x0F
    shl     edi, 2
    mov     r9d, ecx
    shr     r9d, 6
    or      edi, r9d
    movzx   edi, byte [r8 + rdi]
    mov     [r14 + r15], dil
    inc     r15

    and     ecx, 0x3F
    movzx   ecx, byte [r8 + rcx]
    mov     [r14 + r15], cl
    inc     r15

    add     r12, 3
    sub     rbx, 3
    jmp     .scalar_loop

.done:
    mov     rax, r15

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
