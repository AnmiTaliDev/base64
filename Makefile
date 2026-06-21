# SPDX-FileCopyrightText: 2026 AnmiTaliDev <anmitalidev@nuros.org>
# SPDX-License-Identifier: GPL-3.0-or-later

CC        := gcc
NASM      := nasm
AR        := ar

BUILD     := build
SRC       := src
ENCDIR    := src/encode
DECDIR    := src/decode
TESTDIR   := tests

ARCH := $(shell uname -m)

# Architecture-specific flags and source sets.
ifeq ($(ARCH),x86_64)
CFLAGS       := -std=c11 -Wall -Wextra -Wpedantic -O2 -march=x86-64-v2 -Iinclude
NASMFLAGS    := -f elf64
ENC_ASM_SRCS := $(wildcard $(ENCDIR)/*.asm)
ENC_ASM_OBJS := $(patsubst $(ENCDIR)/%.asm, $(BUILD)/enc_%.o, $(ENC_ASM_SRCS))
DEC_ASM_SRCS := $(wildcard $(DECDIR)/*.asm)
DEC_ASM_OBJS := $(patsubst $(DECDIR)/%.asm, $(BUILD)/dec_%.o, $(DEC_ASM_SRCS))
else
CFLAGS       := -std=c11 -Wall -Wextra -Wpedantic -O2 -Iinclude
ENC_ASM_SRCS :=
ENC_ASM_OBJS :=
DEC_ASM_SRCS :=
DEC_ASM_OBJS :=
endif

# Core objects (size helpers)
CORE_OBJS := $(BUILD)/base64.o

# Encoder C sources (dispatch + per-arch implementations)
ENC_C_SRCS   := $(wildcard $(ENCDIR)/*.c)
ENC_C_OBJS   := $(patsubst $(ENCDIR)/%.c, $(BUILD)/enc_%.o, $(ENC_C_SRCS))

# GAS sources (.S — compiled through the C preprocessor; AArch64 NEON etc.)
# Output files use the _s suffix to avoid colliding with same-named .c stubs.
ENC_GAS_SRCS := $(wildcard $(ENCDIR)/*.S)
ENC_GAS_OBJS := $(patsubst $(ENCDIR)/%.S, $(BUILD)/enc_%_s.o, $(ENC_GAS_SRCS))

DEC_C_SRCS   := $(wildcard $(DECDIR)/*.c)
DEC_C_OBJS   := $(patsubst $(DECDIR)/%.c, $(BUILD)/dec_%.o, $(DEC_C_SRCS))

ENC_OBJS  := $(ENC_C_OBJS) $(ENC_ASM_OBJS) $(ENC_GAS_OBJS)
DEC_OBJS  := $(DEC_C_OBJS) $(DEC_ASM_OBJS)
ALL_OBJS  := $(CORE_OBJS) $(ENC_OBJS) $(DEC_OBJS)

LIB      := $(BUILD)/libbase64.a
TARGET   := $(BUILD)/base64
TEST_BIN := $(BUILD)/test_base64

.PHONY: all lib test clean

all: $(TARGET)

lib: $(LIB)

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/base64.o: $(SRC)/base64.c include/base64.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/enc_%.o: $(ENCDIR)/%.c $(ENCDIR)/encode.h include/base64.h | $(BUILD)
	$(CC) $(CFLAGS) -I$(ENCDIR) -c $< -o $@

$(BUILD)/enc_%.o: $(ENCDIR)/%.asm | $(BUILD)
	$(NASM) $(NASMFLAGS) $< -o $@

$(BUILD)/enc_%_s.o: $(ENCDIR)/%.S | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/dec_%.o: $(DECDIR)/%.c $(DECDIR)/decode.h include/base64.h | $(BUILD)
	$(CC) $(CFLAGS) -I$(DECDIR) -c $< -o $@

$(BUILD)/dec_%.o: $(DECDIR)/%.asm | $(BUILD)
	$(NASM) $(NASMFLAGS) $< -o $@

$(BUILD)/main.o: $(SRC)/main.c include/base64.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

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
