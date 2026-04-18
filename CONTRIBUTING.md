# Contributing

## Code style

- C standard: C11 (`-std=c11`)
- Indentation: 4 spaces, no tabs
- Line length: 80 columns soft limit, 100 hard limit
- All public symbols declared in `include/base64.h`; internal symbols stay in
  their translation units or in `src/encode/encode.h`
- No decorative comment separators (`//---`, `/* === */`, etc.)
- Comments only when the _why_ is non-obvious — not to restate the code

## SPDX headers

Every file must start with:

```
// SPDX-FileCopyrightText: <year> <Name> <email>
// SPDX-License-Identifier: GPL-3.0-or-later
```

Use the equivalent comment syntax for NASM (`;`) and Makefile (`#`).

## Adding a new encoder backend

See the "Adding a new optimizer" section in [README.md](README.md).

When submitting a new backend, include:

- The implementation file in `src/encode/`
- The two new declarations in `src/encode/encode.h`
- One new entry in the `encoders[]` table in `src/encode/dispatch.c`
- At minimum one test in `tests/test_base64.c` that exercises the new path
  (you can force it by calling `<name>_encode` directly)

## Running tests

```sh
make test
```

All tests must pass before submitting.

## Commit messages

- Imperative mood, present tense: "add AVX2 encoder", not "added" or "adding"
- First line 72 characters or fewer
- Reference the relevant file or subsystem where helpful
