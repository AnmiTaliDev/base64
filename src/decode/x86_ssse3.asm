; SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
; SPDX-License-Identifier: GPL-3.0-or-later
;
; x86-64 SSSE3 base64 decoder.
; Processes 16 base64 input bytes -> 12 output bytes per SIMD iteration.
; Scalar tail handles the final block (may carry '=' padding).
;
; Validation + translation: parallel table-lookup (Muła 2018).
;   hi_lut[src>>4]  gives the per-row addend to convert ASCII -> 6-bit index.
;   Validation uses lo_lut[src&0xF] ANDed with hi_nibble_mask[src>>4]:
;   a zero result in any lane means the character is invalid.
;
; '+' and '/' share high nibble 2 but need different addends (+19 vs +16).
; We use the base addend 16 for the whole row, then detect '+' specifically
; via (hi==2 AND lo==0xB) and add +3 only to those lanes.
;
; Packing 16 x 6-bit -> 12 x 8-bit (Muła 2018):
;   For each group of 4 indices [i0,i1,i2,i3]:
;     pair_hi = i0*64 + i1    (via pmaddubsw with {64,1,64,1,...})
;     pair_lo = i2*64 + i3    (second 16-bit word from same pmaddubsw call)
;   Then pmaddwd([pair_hi, pair_lo], {4096, 1}):
;     dword = pair_hi*4096 + pair_lo
;           = i0<<18 | i1<<12 | i2<<6 | i3   (the 24-bit decoded value)
;   Extract bytes [2,1,0] of each dword with pshufb -> 12 output bytes.
;
; Exported symbols:
;   int    x86_ssse3_dec_supported(void)
;   size_t x86_ssse3_dec_decode(const char *src, size_t src_len, uint8_t *dst)

global x86_ssse3_dec_supported
global x86_ssse3_dec_decode

section .rodata

; lo_lut[lo_nibble] -> validity bitmask matched against hi_nibble_mask[hi_nibble].
; lo_lut[lo] = OR of hi_nibble_mask[hi] for all valid base64 chars with that lo nibble.
align 16
lo_lut:
    db 0x2A, 0x3E, 0x3E, 0x3E, 0x3E, 0x3E, 0x3E, 0x3E
    db 0x3E, 0x3E, 0x3C, 0x15, 0x14, 0x14, 0x14, 0x15

; hi_nibble_mask[hi_nibble] -> unique bit assigned to this hi nibble row.
; hi=2 -> 0x01, hi=3 -> 0x02, hi=4 -> 0x04, hi=5 -> 0x08, hi=6 -> 0x10, hi=7 -> 0x20.
align 16
hi_nibble_mask:
    db 0x00, 0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

; hi_delta[hi_nibble]: addend (mod 256) to map ASCII -> 6-bit index.
;   hi=2: +16  ('/' 0x2F+16=63; '+' gets an extra +3 below)
;   hi=3: +4   ('0'-'9' -> 52-61)
;   hi=4: -65  ('A'-'O' -> 0-14)   mod 256 = 191 = 0xBF
;   hi=5: -65  ('P'-'Z' -> 15-25)
;   hi=6: -71  ('a'-'o' -> 26-40)  mod 256 = 185 = 0xB9
;   hi=7: -71  ('p'-'z' -> 41-51)
align 16
hi_delta:
    db    0,    0,   16,    4,  191,  191,  185,  185
    db    0,    0,    0,    0,    0,    0,    0,    0

align 16
nibble_mask_vec: times 16 db 0x0F

; '+' correction: hi==2 AND lo==0xB needs +3 extra.
align 16
hi2_vec:  times 16 db 0x02
align 16
lob_vec:  times 16 db 0x0B
align 16
plus3_vec: times 16 db 0x03

; pmaddubsw constant: produces pair_hi=i0*64+i1 and pair_lo=i2*64+i3.
; Bytes alternate {64, 1} so that adjacent byte pairs are multiplied and summed.
align 16
maddubs_lut: times 8 db 64, 1

; pmaddwd constant: {4096, 1} per 16-bit word pair.
; Computes pair_hi*4096 + pair_lo = decoded 24-bit value per dword.
align 16
madd_lut: times 4 dw 4096, 1

; out_shuf: extract bytes [2,1,0] from each of the 4 dwords (32-bit slots)
; and pack them to positions [0..11]. Bytes at position 3 of each dword are 0 and discarded.
; dword 0 occupies bytes  0- 3, want bytes [2,1,0] -> output positions 0,1,2
; dword 1 occupies bytes  4- 7, want bytes [6,5,4] -> output positions 3,4,5
; dword 2 occupies bytes  8-11, want bytes [10,9,8] -> output positions 6,7,8
; dword 3 occupies bytes 12-15, want bytes [14,13,12] -> output positions 9,10,11
align 16
out_shuf:
    db  2,  1,  0,  6,  5,  4, 10,  9,  8, 14, 13, 12, -1, -1, -1, -1

section .text

x86_ssse3_dec_supported:
    push    rbx
    mov     eax, 1
    cpuid
    xor     eax, eax
    bt      ecx, 9
    adc     eax, 0
    pop     rbx
    ret

; size_t x86_ssse3_dec_decode(const char *src, size_t src_len, uint8_t *dst)
;   rdi = src, rsi = src_len, rdx = dst
;   returns rax = bytes written, or (size_t)-1 on invalid input
;
; Caller guarantees: src_len % 4 == 0.
; The last 4-byte block is always handled by the scalar path (may have padding).
x86_ssse3_dec_decode:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi
    mov     r13, rsi
    mov     r14, rdx
    xor     r15, r15
    mov     rbx, r13

    ; Preload constant vectors into caller-saved XMM registers.
    movdqa  xmm8,  [rel lo_lut]
    movdqa  xmm9,  [rel hi_nibble_mask]
    movdqa  xmm10, [rel hi_delta]
    movdqa  xmm11, [rel nibble_mask_vec]

.simd_loop:
    ; Leave the last block for scalar (may carry '=' padding).
    cmp     rbx, 20
    jl      .scalar

    movdqu  xmm0, [r12]        ; load 16 input bytes

    ; Split nibbles.
    movdqa  xmm1, xmm0
    psrlw   xmm1, 4
    pand    xmm1, xmm11        ; hi nibbles
    movdqa  xmm2, xmm0
    pand    xmm2, xmm11        ; lo nibbles

    ; Validate: lo_lut[lo] & hi_nibble_mask[hi] must be non-zero for every lane.
    movdqa  xmm3, xmm8
    pshufb  xmm3, xmm2         ; lo_bits per lane
    movdqa  xmm4, xmm9
    pshufb  xmm4, xmm1         ; hi_bits per lane
    pand    xmm3, xmm4         ; 0 where invalid
    pxor    xmm5, xmm5
    pcmpeqb xmm3, xmm5         ; 0xFF where invalid
    pmovmskb eax, xmm3
    test    eax, eax
    jnz     .invalid

    ; Translate: add hi_delta[hi] to each byte.
    movdqa  xmm5, xmm10
    pshufb  xmm5, xmm1         ; per-lane addend
    paddb   xmm0, xmm5

    ; Extra +3 for '+' (hi==2 AND lo==0xB).
    movdqa  xmm5, [rel hi2_vec]
    pcmpeqb xmm5, xmm1         ; 0xFF where hi==2
    movdqa  xmm6, [rel lob_vec]
    pcmpeqb xmm6, xmm2         ; 0xFF where lo==0xB
    pand    xmm5, xmm6          ; 0xFF only at '+'
    pand    xmm5, [rel plus3_vec]
    paddb   xmm0, xmm5          ; xmm0 = correct 6-bit indices

    ; Pack 16 x 6-bit -> 12 output bytes.
    ; pmaddubsw: [i0,i1,i2,i3,...] * {64,1,64,1,...} -> [i0*64+i1, i2*64+i3, ...] as 8 int16
    pmaddubsw xmm0, [rel maddubs_lut]

    ; pmaddwd: [pair_hi, pair_lo, ...] * {4096,1,...} -> [pair_hi*4096+pair_lo, ...] as 4 int32
    pmaddwd xmm0, [rel madd_lut]

    ; pshufb to extract bytes [2,1,0] from each dword, compacted to positions 0-11.
    pshufb  xmm0, [rel out_shuf]

    ; Store 12 bytes: movq writes 8, then movd writes 4.
    movq    qword [r14 + r15], xmm0
    psrldq  xmm0, 8
    movd    dword [r14 + r15 + 8], xmm0

    add     r12, 16
    add     r15, 12
    sub     rbx, 16
    jmp     .simd_loop

.scalar:
    lea     r8, [rel dec_table]

.scalar_loop:
    test    rbx, rbx
    jz      .done

    movzx   eax, byte [r12]
    movzx   ecx, byte [r12 + 1]
    movzx   edx, byte [r12 + 2]
    movzx   r9d, byte [r12 + 3]

    movzx   eax, byte [r8 + rax]
    movzx   ecx, byte [r8 + rcx]
    movzx   edx, byte [r8 + rdx]
    movzx   r9d, byte [r8 + r9]

    cmp     al,  0xFF
    je      .invalid
    cmp     cl,  0xFF
    je      .invalid
    cmp     cl,  0x40
    je      .invalid

    xor     r10d, r10d
    cmp     dl, 0xFF
    je      .invalid
    cmp     dl, 0x40
    jne     .c_not_pad
    mov     r10d, 1
    xor     edx, edx
.c_not_pad:

    xor     r11d, r11d
    cmp     r9b, 0xFF
    je      .invalid
    cmp     r9b, 0x40
    jne     .d_not_pad
    mov     r11d, 1
    xor     r9d, r9d
.d_not_pad:

    ; "=X" is never valid.
    test    r10d, r10d
    jz      .pad_ok
    test    r11d, r11d
    jz      .invalid
.pad_ok:

    ; Padding only allowed in the last block.
    cmp     rbx, 4
    je      .assemble
    test    r10d, r10d
    jnz     .invalid
    test    r11d, r11d
    jnz     .invalid

.assemble:
    shl     eax, 18
    shl     ecx, 12
    shl     edx, 6
    or      eax, ecx
    or      eax, edx
    or      eax, r9d

    mov     ecx, eax
    shr     ecx, 16
    mov     [r14 + r15], cl
    inc     r15

    test    r10d, r10d
    jnz     .skip_b2
    mov     ecx, eax
    shr     ecx, 8
    mov     [r14 + r15], cl
    inc     r15
.skip_b2:

    test    r11d, r11d
    jnz     .skip_b3
    mov     [r14 + r15], al
    inc     r15
.skip_b3:

    add     r12, 4
    sub     rbx, 4
    jmp     .scalar_loop

.done:
    mov     rax, r15
    jmp     .ret

.invalid:
    mov     rax, -1

.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

section .rodata

dec_table:
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF  ; 00-07
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF  ; 08-0F
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF  ; 10-17
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF  ; 18-1F
    db 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF  ; 20-27
    db 0xFF,0xFF,0xFF,0x3E,0xFF,0xFF,0xFF,0x3F  ; 28-2F  (+ and /)
    db 0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x3B ; 30-37  (0-7)
    db 0x3C,0x3D,0xFF,0xFF,0xFF,0x40,0xFF,0xFF  ; 38-3F  (8-9 and =)
    db 0xFF,0x00,0x01,0x02,0x03,0x04,0x05,0x06  ; 40-47  (A-G)
    db 0x07,0x08,0x09,0x0A,0x0B,0x0C,0x0D,0x0E  ; 48-4F  (H-O)
    db 0x0F,0x10,0x11,0x12,0x13,0x14,0x15,0x16  ; 50-57  (P-W)
    db 0x17,0x18,0x19,0xFF,0xFF,0xFF,0xFF,0xFF  ; 58-5F  (X-Z)
    db 0xFF,0x1A,0x1B,0x1C,0x1D,0x1E,0x1F,0x20  ; 60-67  (a-g)
    db 0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28  ; 68-6F  (h-o)
    db 0x29,0x2A,0x2B,0x2C,0x2D,0x2E,0x2F,0x30  ; 70-77  (p-w)
    db 0x31,0x32,0x33,0xFF,0xFF,0xFF,0xFF,0xFF  ; 78-7F  (x-z)
    times 128 db 0xFF                            ; 80-FF

section .note.GNU-stack noalloc noexec nowrite progbits
