// SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
// SPDX-License-Identifier: GPL-3.0-or-later

#include "base64.h"
#include <stddef.h>

size_t base64_encoded_size(size_t input_len)
{
    return ((input_len + 2) / 3) * 4 + 1;
}

size_t base64_decoded_max_size(size_t encoded_len)
{
    return (encoded_len / 4) * 3;
}
