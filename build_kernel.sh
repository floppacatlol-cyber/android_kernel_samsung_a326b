#!/usr/bin/env bash

set -e

# ==========================================================
#  Kernel Build Script
# ==========================================================
#  Rufnx Changes 30/01/2026
# ==========================================================

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# ==========================================================
# Configuration
# ==========================================================
SRC="$SCRIPT_DIR"
OUT_DIR="$SRC/out"
OUTPUT_DIR="$SRC/output"
LOG_FILE="$OUTPUT_DIR/build.log"

# Device Configuration
DEVICE="a32x"
DEFCONFIG="rufnx_defconfig"
ARCH="arm64"
KBUILD_BUILD_USER="rufnx"
KBUILD_BUILD_HOST=$(hostname)

# Toolchain URLs
TOOLCHAIN_URL="https://github.com/rufnx/toolchains.git"
CLANG_BRANCH="clang-12"
GCC_ARM64_BRANCH="androidcc-4.9"
GCC_ARM_BRANCH="arm-gnu"

# Toolchain Paths
CLANG_DIR="$SRC/toolchains/clang"
GCC_ARM64_DIR="$SRC/toolchains/gcc-arm64"
GCC_ARM_DIR="$SRC/toolchains/gcc-arm"

# AnyKernel Configuration
ANYKERNEL_URL="https://github.com/rufnx/anykernel.git"
ANYKERNEL_BRANCH="a32x"
ANYKERNEL_DIR="$SRC/AnyKernel3"


# Telegram Configuration (optional - set these in environment)
# export BOT_TOKEN="your_bot_token"
# export CHAT_ID="your_chat_id"

# ==========================================================
# Color Options
# ==========================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ==========================================================
# Logging Functions
# ==========================================================
function log_info() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${WHITE}[INFO]${NC}  $1" | tee -a "$LOG_FILE"
}

function log_success() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${GREEN}[OK]${NC}    $1" | tee -a "$LOG_FILE"
}

function log_warning() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${YELLOW}[WARN]${NC}  $1" | tee -a "$LOG_FILE"
}

function log_error() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

function log_progress() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${PURPLE}[WORK]${NC}  $1" | tee -a "$LOG_FILE"
}

# ==========================================================
# Banner Function
# ==========================================================
function print_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
╔════════════════════════════╗
║                                              ║
║         KERNEL BUILD SAMSUNG A32X            ║
║              by Rufnx Team                   ║
║                                              ║
╚════════════════════════════╝
EOF
    echo -e "${NC}"
    log_info "Device: ${YELLOW}${DEVICE}${NC}"
    log_info "Config: ${YELLOW}${DEFCONFIG}${NC}"
    log_info "Builder: ${YELLOW}${KBUILD_BUILD_USER}@${KBUILD_BUILD_HOST}${NC}"
    log_info "Date: ${YELLOW}$(date '+%d-%m-%Y %H:%M:%S')${NC}"
    echo ""
}

# ==========================================================
# Spinner Animation
# ==========================================================
function spinner() {
    local pid=$1
    local message=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %10 ))
        printf "\r${CYAN}[$(date '+%H:%M:%S')]${NC} ${YELLOW}${spin:$i:1}${NC}  %-50s" "$message"
        sleep 0.1
    done
    printf "\r"
}

# ==========================================================
# Telegram Upload Function
# ==========================================================
function send_to_telegram() {
    local file="$1"
    local caption="$2"

    if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
        log_warning "Telegram credentials not set. Skipping upload."
        return
    fi

    log_progress "Uploading to Telegram..."

    local response=$(curl -s -F document=@"$file" \
         -F chat_id="$CHAT_ID" \
         -F parse_mode="Markdown" \
         -F caption="$caption" \
         "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument")

    if echo "$response" | grep -q '"ok":true'; then
        log_success "Upload successful!"
    else
        log_error "Upload failed. Check log for details."
        echo "$response" >> "$LOG_FILE"
    fi
}

# ==========================================================
# Error Handler
# ==========================================================
function error_exit() {
    local message="$1"
    log_error "$message"

    if [ -f "$LOG_FILE" ]; then
        local caption="**Kernel Build Failed!**

\`\`\`
Error: $message
Device: $DEVICE
Time: $(date '+%d-%m-%Y %H:%M')
\`\`\`"
        send_to_telegram "$LOG_FILE" "$caption"
    fi

    echo -e "${RED}╔═══════════════════════════╗${NC}"
    echo -e "${RED}║                                              ║${NC}"
    echo -e "${RED}║              BUILD FAILED                    ║${NC}"
    echo -e "${RED}║                                              ║${NC}"
    echo -e "${RED}╚═══════════════════════════╝${NC}"
    exit 1
}

# ==========================================================
# Clone Repository Function
# ==========================================================
function clone_repo() {
    local url="$1"
    local branch="$2"
    local target="$3"
    local name="$4"

    log_progress "Cloning ${name}..."
    git clone --depth=1 "$url" -b "$branch" "$target" >> "$LOG_FILE" 2>&1 &
    spinner $! "Cloning ${name}..."
    wait $!

    if [ $? -eq 0 ]; then
        log_success "${name} cloned successfully"
        return 0
    else
        log_error "Failed to clone ${name}"
        return 1
    fi
}

# ==========================================================
# Timer Functions
# ==========================================================
function start_timer() {
    export BUILD_START=$(date +%s)
}

function end_timer() {
    local end_time=$(date +%s)
    local elapsed=$((end_time - BUILD_START))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))

    log_info "Build time: ${YELLOW}${minutes}m ${seconds}s${NC}"
}

# ==========================================================
# Toolchain Setup Functions
# ==========================================================
function check_clang() {
    if [ ! -d "$CLANG_DIR" ]; then
        clone_repo "$TOOLCHAIN_URL" "$CLANG_BRANCH" "$CLANG_DIR" "Clang Toolchain" || return 1
    else
        log_success "Clang toolchain found"
    fi
}

function check_gcc_arm64() {
    if [ ! -d "$GCC_ARM64_DIR" ]; then
        clone_repo "$TOOLCHAIN_URL" "$GCC_ARM64_BRANCH" "$GCC_ARM64_DIR" "GCC ARM64 Toolchain" || return 1
    else
        log_success "GCC ARM64 toolchain found"
    fi
}

function check_gcc_arm() {
    if [ ! -d "$GCC_ARM_DIR" ]; then
        clone_repo "$TOOLCHAIN_URL" "$GCC_ARM_BRANCH" "$GCC_ARM_DIR" "GCC ARM Toolchain" || return 1
    else
        log_success "GCC ARM toolchain found"
    fi
}

function check_toolchains() {
    log_info "Checking toolchains..."
    check_clang || error_exit "Failed to setup Clang"
    check_gcc_arm64 || error_exit "Failed to setup GCC ARM64"
    check_gcc_arm || error_exit "Failed to setup GCC ARM"
}

# ==========================================================
# AnyKernel Setup
# ==========================================================
function check_anykernel() {
    if [ ! -d "$ANYKERNEL_DIR" ]; then
        clone_repo "$ANYKERNEL_URL" "$ANYKERNEL_BRANCH" "$ANYKERNEL_DIR" "AnyKernel3" || return 1
    else
        log_success "AnyKernel3 already exists"
    fi
}

# ==========================================================
# Dependency Verification
# ==========================================================
function verify_dependencies() {
    log_info "Verifying system dependencies..."

    local deps_ok=true
    local missing_deps=""

    for cmd in git curl zip make bc bison flex; do
        if ! command -v $cmd &> /dev/null; then
            log_error "Required command not found: $cmd"
            missing_deps="$missing_deps $cmd"
            deps_ok=false
        fi
    done

    if [ "$deps_ok" = false ]; then
        error_exit "Missing required dependencies:$missing_deps"
    fi

    log_success "All system dependencies verified"
}

# ==========================================================
# Setup Dependencies
# ==========================================================
function setup_dependencies() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "Setting up build dependencies..."
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    verify_dependencies
    # check_ksu  # Uncomment if you want KernelSU
    check_toolchains
    check_anykernel

    echo ""
    log_success "All dependencies ready!"
    echo ""
}

# ==========================================================
# Setup Build Environment
# ==========================================================
function setup_environment() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "Setting up build environment..."
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    # Create output directories
    mkdir -p "$OUT_DIR"
    mkdir -p "$OUTPUT_DIR"

    # Setup toolchain paths
    export PATH="$CLANG_DIR/bin:$GCC_ARM64_DIR/bin:$GCC_ARM_DIR/bin:$PATH"
    
    # Export compiler variables
    export CLANG_TRIPLE="aarch64-linux-gnu-"
    export CROSS_COMPILE="aarch64-linux-android-"
    export CROSS_COMPILE_ARM32="arm-linux-gnueabi-"
    
    log_info "Architecture: ${YELLOW}${ARCH}${NC}"
    log_info "Compiler: ${YELLOW}Clang + GCC${NC}"
    log_info "Threads: ${YELLOW}$(nproc)${NC}"
    log_info "Clang: ${YELLOW}$(clang --version | head -n1)${NC}"

    echo ""
    log_success "Environment ready!"
    echo ""
}

function build_kernel() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "Starting kernel compilation..."
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    start_timer

    # Clean old build
    log_progress "Cleaning old build files..."
    make -C "$SRC" O="$OUT_DIR" clean >> "$LOG_FILE" 2>&1 || true
    make -C "$SRC" O="$OUT_DIR" mrproper >> "$LOG_FILE" 2>&1 || true

    # Generate defconfig
    log_progress "Generating defconfig..."
    if make -C "$SRC" O="$OUT_DIR" ARCH="$ARCH" "$DEFCONFIG" >> "$LOG_FILE" 2>&1; then
        log_success "Defconfig generated"
    else
        error_exit "Defconfig generation failed"
    fi

    echo ""
    log_progress "Compiling kernel with $(nproc) threads..."
    echo -e "${YELLOW}This may take several minutes...${NC}\n"

    # Compile kernel with proper flags
    if make -C "$SRC" \
        O="$OUT_DIR" \
        ARCH="$ARCH" \
        CC="$CC" \
        CLANG_TRIPLE="$CLANG_TRIPLE" \
        CROSS_COMPILE="$CROSS_COMPILE" \
        CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32" \
        -j$(nproc) 2>&1 | tee -a "$LOG_FILE"; then
        echo ""
        log_success "Kernel compilation completed!"
    else
        error_exit "Kernel compilation failed"
    fi

    # Verify kernel image
    local image_dtb="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"
    local image="$OUT_DIR/arch/arm64/boot/Image.gz"

    if [ ! -f "$image_dtb" ] && [ ! -f "$image" ]; then
        error_exit "Kernel image not found after build"
    fi

    end_timer
    echo ""
}

function package_kernel() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "Creating flashable package..."
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    # Ensure AnyKernel exists
    check_anykernel

    # Clean old files
    log_progress "Cleaning AnyKernel directory..."
    rm -f "$ANYKERNEL_DIR"/*.zip
    rm -f "$ANYKERNEL_DIR"/Image* 
    rm -f "$ANYKERNEL_DIR"/dtbo.img

    # Determine kernel image
    local kernel_image=""
    if [ -f "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" ]; then
        kernel_image="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"
        log_info "Using: ${YELLOW}Image.gz-dtb${NC}"
    else
        kernel_image="$OUT_DIR/arch/arm64/boot/Image.gz"
        log_info "Using: ${YELLOW}Image.gz${NC}"
    fi

    # Copy kernel image
    log_progress "Copying kernel image..."
    if cp "$kernel_image" "$ANYKERNEL_DIR/"; then
        log_success "Kernel image copied"
    else
        error_exit "Failed to copy kernel image"
    fi

    # Copy dtbo if exists
    if [ -f "$OUT_DIR/arch/arm64/boot/dtbo.img" ]; then
        log_progress "Copying DTBO image..."
        cp "$OUT_DIR/arch/arm64/boot/dtbo.img" "$ANYKERNEL_DIR/" && \
        log_success "DTBO image copied"
    fi

    # Create zip with timestamp
    local timestamp=$(date +%Y%m%d-%H%M)
    local zipname="Rufnx-${DEVICE}-${timestamp}.zip"
    
    log_progress "Creating ZIP package..."

    (cd "$ANYKERNEL_DIR" && zip -r9 "../output/$zipname" * -x '*.git*' >> "$LOG_FILE" 2>&1)

    if [ -f "$OUTPUT_DIR/$zipname" ]; then
        local zipsize=$(du -h "$OUTPUT_DIR/$zipname" | cut -f1)
        log_success "Package created: ${YELLOW}$zipname${NC} (${zipsize})"
    else
        error_exit "Failed to create ZIP package"
    fi

    # Get kernel version
    local kernel_ver=$(strings "$kernel_image" | grep -m1 "Linux version" | cut -d' ' -f1-3 || echo "Unknown")
    local build_date=$(date +"%d %B %Y %H:%M")
    local builder="${KBUILD_BUILD_USER}@${KBUILD_BUILD_HOST}"

    # Calculate build time
    local end_time=$(date +%s)
    local elapsed=$((end_time - BUILD_START))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))

    # Prepare Telegram caption
    local caption="**Kernel Build Successful!**

**Device:** \`${DEVICE}\`
**Version:** \`${kernel_ver}\`
**Date:** \`${build_date}\`
**Builder:** \`${builder}\`
**Build Time:** \`${minutes}m ${seconds}s\`
**Size:** \`${zipsize}\`

**Flash via Recovery Only**
**AnyKernel3 Package**"

    # Upload to Telegram
    echo ""
    send_to_telegram "$OUTPUT_DIR/$zipname" "$caption"
    echo ""
    
    log_success "Output: ${YELLOW}$OUTPUT_DIR/$zipname${NC}"
    log_info "MD5: ${YELLOW}$(md5sum "$OUTPUT_DIR/$zipname" | cut -d' ' -f1)${NC}"
    echo ""
}

function main() {
    # Create output directory first
    mkdir -p "$OUTPUT_DIR"
    
    # Clear old log
    rm -f "$LOG_FILE"
    touch "$LOG_FILE"

    # Show banner
    print_banner

    # Start build
    log_info "Build started at $(date '+%d-%m-%Y %H:%M:%S')"
    echo ""

    # Setup dependencies
    setup_dependencies

    # Setup environment
    setup_environment

    # Build kernel
    build_kernel

    # Package kernel
    package_kernel

    # Success banner
    echo -e "${GREEN}╔═══════════════════════════╗${NC}"
    echo -e "${GREEN}║                                              ║${NC}"
    echo -e "${GREEN}║               BUILD COMPLETED                ║${NC}"
    echo -e "${GREEN}║                                              ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════╝${NC}"

    log_success "Build finished successfully!"
    log_info "Flashable ZIP: ${YELLOW}$OUTPUT_DIR/${NC}"
    log_info "Build log: ${YELLOW}$LOG_FILE${NC}"
    echo ""
}

main "$@"
