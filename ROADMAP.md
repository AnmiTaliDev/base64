# Roadmap

Items within each milestone are in priority order. Milestones are not time-boxed;
they describe the next logical chunk of work.

## v0.1.0 — Released 2026-04-18

- [x] Public API: `base64_encode`, `base64_decode`, `base64_encoded_size`,
      `base64_decoded_max_size`
- [x] x86-64 SSSE3 encoder (`src/encode/x86_ssse3.asm`, NASM): 12 bytes/iter
- [x] AArch64 NEON encoder (`src/encode/arm_neon.S`, GAS): 48 bytes/iter
- [x] Portable C fallback (`src/encode/generic.c`)
- [x] Pluggable backend dispatch with runtime CPU detection
- [x] Strict RFC 4648 decoder
- [x] CLI tool, static library, test suite

## v0.2.0 — Decoder optimization and ARM32

- [x] ARM32 NEON encoder (`src/encode/arm32_neon.S`): same `vld3`/`vst4`
      algorithm with 8-lane d-registers (24 bytes/iter); runtime detection via
      `getauxval(AT_HWCAP) & HWCAP_NEON`
- [ ] SSSE3-accelerated decoder: batch-validate and translate 16 output bytes
      at a time using a parallel table-lookup approach (Muła 2018)

## v0.3.0 — AVX2 encoder

- [ ] x86-64 AVX2 encoder (`src/encode/x86_avx2.c`): process 24 input bytes
      per iteration in 256-bit `ymm` registers using the same multiply-shift
      index extraction and arithmetic offset translation
- [ ] Runtime detection: `CPUID.7:EBX[5]` (AVX2 feature flag)
- [ ] Register in the dispatch table above `x86_ssse3`

## v0.4.0 — Alphabet variants

- [ ] URL-safe Base64 (RFC 4648 §5): replace `+`/`/` with `-`/`_`, no padding
- [ ] No-padding mode: suppress `=` output, tolerate missing `=` on decode
- [ ] Extend the public API with a `base64_options_t` flags parameter on both
      encode and decode; keep the current functions as zero-option wrappers

## v0.5.0 — Streaming API

- [ ] `base64_encoder_t` / `base64_decoder_t` context structs for incremental
      encode/decode without knowing the total input size upfront
- [ ] File-to-file helpers: `base64_encode_file` / `base64_decode_file` that
      process input in 4 KiB chunks using the streaming contexts

## v0.6.0 — RISC-V Vector

- [ ] RISC-V V extension encoder (`src/encode/riscv_zvkb.c`) using `vlseg3e8`
      (segmented load with de-interleave) and `vsseg4e8` for the store, targeting
      RVV 1.0 with VLEN >= 128
- [ ] Runtime detection via `getauxval(AT_HWCAP) & COMPAT_HWCAP_ISA_V`

## v1.0.0 — Stability and tooling

- [ ] CMake build system alongside the existing Makefile
- [ ] `pkg-config` file (`base64.pc`) installed with `make install`
- [ ] libFuzzer harness (`tests/fuzz_base64.c`) covering encode/decode roundtrips
      and deliberate invalid inputs
- [ ] Benchmark suite (`tests/bench_base64.c`) reporting throughput in MB/s for
      each available backend on the current host
- [ ] SECURITY.md with a vulnerability disclosure policy
