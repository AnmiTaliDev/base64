// SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: GPL-3.0-or-later

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "base64.h"

static void usage(const char *prog)
{
    fprintf(stderr, "usage: %s [-d] <input>\n", prog);
    fprintf(stderr, "  -d   decode (default: encode)\n");
}

int main(int argc, char *argv[])
{
    int decode = 0;
    const char *input = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-d") == 0) {
            decode = 1;
        } else if (argv[i][0] == '-') {
            usage(argv[0]);
            return 1;
        } else {
            input = argv[i];
        }
    }

    if (!input) {
        usage(argv[0]);
        return 1;
    }

    size_t in_len = strlen(input);

    if (!decode) {
        size_t out_size = base64_encoded_size(in_len);
        char *out = malloc(out_size);
        if (!out) {
            perror("malloc");
            return 1;
        }
        base64_encode((const uint8_t *)input, in_len, out);
        puts(out);
        free(out);
    } else {
        size_t out_size = base64_decoded_max_size(in_len);
        uint8_t *out = malloc(out_size + 1);
        if (!out) {
            perror("malloc");
            return 1;
        }
        size_t written = base64_decode(input, in_len, out);
        if (written == (size_t)-1) {
            fprintf(stderr, "error: invalid base64 input\n");
            free(out);
            return 1;
        }
        out[written] = '\0';
        fwrite(out, 1, written, stdout);
        putchar('\n');
        free(out);
    }

    return 0;
}
