# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-18

### Added

- Public API: `base64_encode`, `base64_decode`, `base64_encoded_size`,
  `base64_decoded_max_size`
- x86-64 SSSE3 encoder (`src/encode/x86_ssse3.asm`, NASM): Klomp/Muła
  multiply-shift index extraction; 12 input bytes → 16 output bytes per
  SIMD iteration; arithmetic offset ASCII translation via `pcmpgtb`/`paddb`
- AArch64 NEON encoder (`src/encode/arm_neon.S`, GAS): `ld3` de-interleaves
  48 bytes into three 16-byte lanes, four index vectors extracted with shifts
  and masks, `ASCII_XLAT` macro applies arithmetic offsets, `st4` interleaves
  64 output bytes; 4× the throughput of the SSSE3 path
- Portable C encoder (`src/encode/generic.c`) as the unconditional fallback
- Pluggable backend architecture: `src/encode/dispatch.c` walks a priority
  table at first call and caches the winning function pointer; adding a new
  backend requires one new file and one table entry
- Strict RFC 4648 decoder: rejects invalid characters, misplaced or
  mid-stream padding, and non-multiple-of-4 lengths
- CLI tool (`build/base64`) with `-d` flag for decoding
- RFC 4648 test vectors, binary roundtrip test, and invalid-input rejection
  tests
- Static library target (`build/libbase64.a`)
- GAS `.S` build support in the Makefile alongside the existing NASM `.asm`
  rules; `.S` objects receive a `_s` suffix to prevent filename collisions
  with same-named C stubs
