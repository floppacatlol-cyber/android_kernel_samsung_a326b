#!/bin/bash
# ==========================================================
#  Kernel Build Configuration
# ==========================================================

# Device Config
export DEVICE="a32x"
export DEFCONFIG="a32x_defconfig"
export KBUILD_BUILD_USER="ron144"
export KBUILD_BUILD_HOST="ron144"

# Directories
export SRC="$(pwd)"
export LOG_FILE="$SRC/build.log"
export OUT_DIR="$SRC/out"
export ANYKERNEL_DIR="$SRC/AnyKernel3"
export OUTPUT_DIR="$SRC/output"

# Toolchain URLs
export GCC_URL="https://github.com/H33CKER/toolchains"
export GCC_BRANCH="gcc-4.9" #gcc-4.9 or gcc-6.4
export CLANG_URL="https://github.com/H33CKER/toolchains"
export CLANG_BRANCH="clang-12"  # clang-11 or clang-12

# AnyKernel
export ANYKERNEL_URL="https://github.com/H33CKER/AnyKernel3.git"
export ANYKERNEL_BRANCH="A32"

# KSU
export ENABLE_KSU=1
export KSU_URL="https://github.com/KernelSU-Next/KernelSU-Next.git"
export KSU_BRANCH="legacy"

# SUSFS
export ENABLE_SUSFS=1
export SUSFS_URL="https://gitlab.com/simonpunk/susfs4ksu.git"
export SUSFS_BRANCH="kernel-4.14"
export SUSFS_DIR="$SRC/susfs4ksu"

# Build Config
export ARCH=arm64
export CROSS_COMPILE="$SRC/gcc/bin/aarch64-linux-androidkernel-"
export CC="$SRC/clang/bin/clang"
export CLANG_TRIPLE=aarch64-linux-gnu-
export PATH="$SRC/clang/bin:$SRC/gcc/bin:$PATH"
export KCFLAGS=-w
export CONFIG_SECTION_MISMATCH_WARN_ONLY=y

# Telegram (optional - set via environment or here)
export BOT_TOKEN=""
export CHAT_ID=""
# or set in repo secret action
