// SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: GPL-3.0-or-later

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "base64.h"

static int failures = 0;

static void check_encode(const char *input, const char *expected)
{
    size_t in_len = strlen(input);
    char buf[256];
    size_t n = base64_encode((const uint8_t *)input, in_len, buf);
    if (strcmp(buf, expected) != 0) {
        fprintf(stderr, "FAIL encode(%s): got '%s', want '%s'\n",
                input, buf, expected);
        failures++;
    } else {
        printf("PASS encode(%s) = %s  [%zu bytes]\n", input, buf, n);
    }
}

static void check_decode(const char *input, const char *expected, size_t exp_len)
{
    uint8_t buf[256];
    size_t n = base64_decode(input, strlen(input), buf);
    if (n == (size_t)-1 || n != exp_len || memcmp(buf, expected, exp_len) != 0) {
        fprintf(stderr, "FAIL decode(%s): got n=%zu\n", input, n);
        failures++;
    } else {
        printf("PASS decode(%s) -> %zu bytes\n", input, n);
    }
}

static void check_decode_invalid(const char *input)
{
    uint8_t buf[256];
    size_t n = base64_decode(input, strlen(input), buf);
    if (n != (size_t)-1) {
        fprintf(stderr, "FAIL decode_invalid(%s): expected error, got %zu\n", input, n);
        failures++;
    } else {
        printf("PASS decode_invalid(%s) correctly rejected\n", input);
    }
}

int main(void)
{
    // RFC 4648 test vectors
    check_encode("",       "");
    check_encode("f",      "Zg==");
    check_encode("fo",     "Zm8=");
    check_encode("foo",    "Zm9v");
    check_encode("foob",   "Zm9vYg==");
    check_encode("fooba",  "Zm9vYmE=");
    check_encode("foobar", "Zm9vYmFy");

    check_decode("",         "", 0);
    check_decode("Zg==",     "f", 1);
    check_decode("Zm8=",     "fo", 2);
    check_decode("Zm9v",     "foo", 3);
    check_decode("Zm9vYg==", "foob", 4);
    check_decode("Zm9vYmE=", "fooba", 5);
    check_decode("Zm9vYmFy", "foobar", 6);

    // Roundtrip with binary data
    uint8_t bin[] = {0x00, 0xFF, 0x80, 0x7F, 0x01, 0xFE, 0xAB, 0xCD};
    char enc[64];
    uint8_t dec[64];
    size_t enc_len = base64_encode(bin, sizeof(bin), enc);
    size_t dec_len = base64_decode(enc, enc_len, dec);
    if (dec_len != sizeof(bin) || memcmp(dec, bin, sizeof(bin)) != 0) {
        fprintf(stderr, "FAIL binary roundtrip\n");
        failures++;
    } else {
        printf("PASS binary roundtrip\n");
    }

    // Longer input to exercise SIMD path (>= 12 bytes)
    check_encode("Hello, World!",  "SGVsbG8sIFdvcmxkIQ==");
    check_decode("SGVsbG8sIFdvcmxkIQ==", "Hello, World!", 13);

    // Invalid inputs
    check_decode_invalid("Zg=");       // length not multiple of 4
    check_decode_invalid("Z===");      // bad padding position
    check_decode_invalid("Zm9!Yg=="); // invalid character

    printf("\n%s: %d failure(s)\n", failures == 0 ? "OK" : "FAILED", failures);
    return failures ? 1 : 0;
}
