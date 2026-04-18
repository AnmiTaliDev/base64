# base64

Low-level Base64 encoder and decoder written in C with assembly
optimization. Conforms to [RFC 4648].

[RFC 4648]: https://datatracker.ietf.org/doc/html/rfc4648

## Features

- Standard Base64 alphabet (`+` and `/`), with `=` padding
- x86-64 v2 SSSE3-accelerated encoder: processes 12 input bytes per SIMD
  iteration using the Klomp/Muła multiply-shift technique
- Portable C fallback selected automatically at runtime if SSSE3 is unavailable
- Pluggable optimizer architecture: drop a new file into `src/encode/` to
  register an additional backend
- Strict decoder: rejects invalid characters, bad padding position, and
  non-multiple-of-4 input lengths

## Requirements

| Tool   | Version  |
|--------|----------|
| GCC    | >= 7     |
| NASM   | >= 2.14  |
| GNU Make | any    |
| CPU    | x86-64 v2 (SSE4.2, SSSE3) for the optimized path; any x86-64 for the fallback |

## Building

```sh
make        # builds build/base64 (CLI) and build/libbase64.a
make lib    # builds only the static library
make test   # builds and runs the test suite
make clean  # removes the build/ directory
```

## API

Include `base64.h`:

```c
#include "base64.h"
```

### Encoding

```c
// Returns the number of bytes required to hold the encoded output,
// including the null terminator.
size_t base64_encoded_size(size_t input_len);

// Encodes src of length src_len into dst.
// dst must be at least base64_encoded_size(src_len) bytes.
// Returns the number of bytes written, excluding the null terminator.
size_t base64_encode(const uint8_t *src, size_t src_len, char *dst);
```

### Decoding

```c
// Returns the maximum number of bytes the decoded output can occupy.
size_t base64_decoded_max_size(size_t encoded_len);

// Decodes the Base64 string src of length src_len into dst.
// dst must be at least base64_decoded_max_size(src_len) bytes.
// Returns the number of bytes written, or (size_t)-1 on invalid input.
size_t base64_decode(const char *src, size_t src_len, uint8_t *dst);
```

### Example

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "base64.h"

int main(void)
{
    const char *msg = "Hello, World!";
    size_t msg_len  = strlen(msg);

    // Encode
    char *enc = malloc(base64_encoded_size(msg_len));
    base64_encode((const uint8_t *)msg, msg_len, enc);
    printf("encoded: %s\n", enc);  // SGVsbG8sIFdvcmxkIQ==

    // Decode
    uint8_t *dec = malloc(base64_decoded_max_size(strlen(enc)) + 1);
    size_t dec_len = base64_decode(enc, strlen(enc), dec);
    dec[dec_len] = '\0';
    printf("decoded: %s\n", (char *)dec);  // Hello, World!

    free(enc);
    free(dec);
    return 0;
}
```

## CLI

```sh
./build/base64 "Hello, World!"       # encode
./build/base64 -d "SGVsbG8sIFdvcmxkIQ=="  # decode
```

## Project structure

```
include/
  base64.h              public API
src/
  base64.c              size helpers and decoder
  main.c                CLI entry point
  encode/
    encode.h            internal encoder interface and registry declarations
    dispatch.c          runtime backend selection table
    generic.c           portable C encoder (always available)
    x86_ssse3.asm       SSSE3 x86-64 v2 optimized encoder
tests/
  test_base64.c         RFC 4648 test vectors, binary roundtrip, error cases
Makefile
LICENSE
```

## Adding a new optimizer

1. Create `src/encode/<name>.asm` (or `.c`) implementing two symbols:

   ```c
   int    <name>_supported(void);   // return 1 if the CPU supports this backend
   size_t <name>_encode(const uint8_t *src, size_t src_len, char *dst);
   ```

2. Declare both symbols in `src/encode/encode.h`.

3. Add one entry to the `encoders[]` table in `src/encode/dispatch.c`,
   above the backends it should take priority over:

   ```c
   { "<name>", <name>_supported, <name>_encode },
   ```

The Makefile automatically picks up all `*.c` and `*.asm` files in
`src/encode/`, so no build changes are needed.

## License

GNU General Public License v3.0 or later. See [LICENSE](LICENSE).
