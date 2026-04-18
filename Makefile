# SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
# SPDX-License-Identifier: GPL-3.0-or-later

CC        := gcc
NASM      := nasm
AR        := ar

CFLAGS    := -std=c11 -Wall -Wextra -Wpedantic -O2 -march=x86-64-v2 -Iinclude
NASMFLAGS := -f elf64

BUILD     := build
SRC       := src
ENCDIR    := src/encode
TESTDIR   := tests

# Core objects (helpers + decoder)
CORE_OBJS := $(BUILD)/base64.o

# Encoder objects: dispatch + all implementations found in src/encode/
# C sources
ENC_C_SRCS   := $(wildcard $(ENCDIR)/*.c)
ENC_C_OBJS   := $(patsubst $(ENCDIR)/%.c, $(BUILD)/enc_%.o, $(ENC_C_SRCS))

# NASM sources (.asm — x86/x86-64)
ENC_ASM_SRCS := $(wildcard $(ENCDIR)/*.asm)
ENC_ASM_OBJS := $(patsubst $(ENCDIR)/%.asm, $(BUILD)/enc_%.o, $(ENC_ASM_SRCS))

# GAS sources (.S — compiled through the C preprocessor; used for AArch64 NEON)
# Output files use the _s suffix to avoid colliding with same-named .c stubs.
ENC_GAS_SRCS := $(wildcard $(ENCDIR)/*.S)
ENC_GAS_OBJS := $(patsubst $(ENCDIR)/%.S, $(BUILD)/enc_%_s.o, $(ENC_GAS_SRCS))

ENC_OBJS     := $(ENC_C_OBJS) $(ENC_ASM_OBJS) $(ENC_GAS_OBJS)

ALL_OBJS     := $(CORE_OBJS) $(ENC_OBJS)

LIB          := $(BUILD)/libbase64.a
TARGET       := $(BUILD)/base64
TEST_BIN     := $(BUILD)/test_base64

.PHONY: all lib test clean

all: $(TARGET)

lib: $(LIB)

$(BUILD):
	mkdir -p $(BUILD)

# Core
$(BUILD)/base64.o: $(SRC)/base64.c include/base64.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

# Encoder C files
$(BUILD)/enc_%.o: $(ENCDIR)/%.c $(ENCDIR)/encode.h include/base64.h | $(BUILD)
	$(CC) $(CFLAGS) -I$(ENCDIR) -c $< -o $@

# Encoder NASM files (.asm)
$(BUILD)/enc_%.o: $(ENCDIR)/%.asm | $(BUILD)
	$(NASM) $(NASMFLAGS) $< -o $@

# Encoder GAS files (.S — preprocessed by the C compiler)
$(BUILD)/enc_%_s.o: $(ENCDIR)/%.S | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

# Main CLI
$(BUILD)/main.o: $(SRC)/main.c include/base64.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

# Tests
$(BUILD)/test_base64.o: $(TESTDIR)/test_base64.c include/base64.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(LIB): $(ALL_OBJS)
	$(AR) rcs $@ $^

$(TARGET): $(ALL_OBJS) $(BUILD)/main.o
	$(CC) $(CFLAGS) $^ -o $@

$(TEST_BIN): $(ALL_OBJS) $(BUILD)/test_base64.o
	$(CC) $(CFLAGS) $^ -o $@

test: $(TEST_BIN)
	./$(TEST_BIN)

clean:
	rm -rf $(BUILD)
