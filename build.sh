#!/bin/bash
set -e

# ==========================================================
#  Main Kernel Build Script
# ==========================================================

# Source config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# ==========================================================
#  Colors & Styling
# ==========================================================
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[1;37m'
export NC='\033[0m'

# ==========================================================
#  Logging Functions
# ==========================================================
log_info() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${WHITE}[INFO]${NC}  $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${GREEN}[OK]${NC}  $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${YELLOW}[WARNING]${NC}  $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${RED}[ERROR]${NC}  $1" | tee -a "$LOG_FILE"
}

log_progress() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${PURPLE}[PROGRESS]${NC}  $1" | tee -a "$LOG_FILE"
}

# ==========================================================
#  Banner
# ==========================================================
print_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════╗
║                                              ║
║          KERNEL BUILD SCAMSUNG               ║
║                                              ║
╚══════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    log_info "Device: ${YELLOW}${DEVICE}${NC}"
    log_info "Config: ${YELLOW}${DEFCONFIG}${NC}"
    log_info "Builder: ${YELLOW}${KBUILD_BUILD_USER}@${KBUILD_BUILD_HOST}${NC}"
    echo ""
}

# ==========================================================
#  Progress Spinner
# ==========================================================
spinner() {
    local pid=$1
    local message=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %10 ))
        echo -ne "\r${CYAN}[$(date '+%H:%M:%S')]${NC} ${YELLOW}${spin:$i:1}${NC}  $message"
        sleep 0.1
    done
    echo -ne "\r"
}

# ==========================================================
#  Telegram Functions
# ==========================================================
send_to_telegram() {
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
#  Error Handler
# ==========================================================
error_exit() {
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

    echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                              ║${NC}"
    echo -e "${RED}║            BUILD FAILED                      ║${NC}"
    echo -e "${RED}║                                              ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
    exit 1
}

# ==========================================================
#  Git Clone Helper
# ==========================================================
clone_repo() {
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
#  Build Timer
# ==========================================================
start_timer() {
    export BUILD_START=$(date +%s)
}

end_timer() {
    local end_time=$(date +%s)
    local elapsed=$((end_time - BUILD_START))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))

    log_info "Build time: ${YELLOW}${minutes}m ${seconds}s${NC}"
}

# ==========================================================
#  Dependency Management
# ==========================================================
check_ksu() {
    if [ "${ENABLE_KSU:-0}" != "1" ]; then
        log_info "KernelSU support disabled"
        return 0
    fi

    if [ -z "$KSU_URL" ]; then
        log_error "KSU_URL is not set"
        return 1
    fi

    if [ ! -d "$SRC/KernelSU-Next" ]; then
        log_info "KernelSU-Next not found"
        log_progress "Cloning KernelSU-Next..."

        clone_repo "$KSU_URL" "$KSU_BRANCH" "$SRC/KernelSU-Next" "KernelSU-Next" || return 1
    else
        log_success "KernelSU-Next already exists"
    fi

    if [ ! -x "$SRC/KernelSU-Next/kernel/setup.sh" ]; then
        log_error "KernelSU setup script missing: $SRC/KernelSU-Next/kernel/setup.sh"
        return 1
    fi

    log_progress "Running KernelSU-Next setup..."
    pushd "$SRC" > /dev/null
    bash "$SRC/KernelSU-Next/kernel/setup.sh" "$KSU_BRANCH" >> "$LOG_FILE" 2>&1
    local setup_rc=$?
    popd > /dev/null

    if [ $setup_rc -ne 0 ]; then
        log_error "KernelSU-Next setup failed"
        return 1
    fi

    log_success "KernelSU-Next setup completed"
}

has_susfs() {
    [ -f "$SRC/fs/susfs.c" ] && [ -f "$SRC/include/linux/susfs.h" ]
}

check_susfs() {
    if [ "${ENABLE_SUSFS:-0}" != "1" ]; then
        log_info "SUSFS support disabled"
        return 0
    fi

    if has_susfs; then
        log_success "SUSFS already integrated into kernel source"
        return 0
    fi

    if [ -z "$SUSFS_URL" ] || [ -z "$SUSFS_BRANCH" ]; then
        log_error "SUSFS repository configuration is missing"
        return 1
    fi

    if [ ! -d "$SUSFS_DIR" ]; then
        log_info "susfs4ksu not found"
        log_progress "Cloning susfs4ksu..."
        clone_repo "$SUSFS_URL" "$SUSFS_BRANCH" "$SUSFS_DIR" "susfs4ksu" || return 1
    else
        log_success "susfs4ksu already exists"
    fi

    local patch_root="$SUSFS_DIR/kernel_patches"
    local kernel_patch
    kernel_patch=$(find "$patch_root" -maxdepth 2 -name '50_add_susfs_in_kernel*.patch' | head -n1)

    if [ -z "$kernel_patch" ]; then
        log_error "susfs4ksu kernel patch not found"
        return 1
    fi

    mkdir -p "$SRC/fs" "$SRC/include/linux"
    log_progress "Copying SUSFS kernel files into source tree..."
    cp -f "$patch_root/fs/"* "$SRC/fs/" 2>/dev/null || true
    cp -f "$patch_root/include/linux/"* "$SRC/include/linux/" 2>/dev/null || true

    if [ -f "$patch_root/KernelSU/10_enable_susfs_for_ksu.patch" ]; then
        log_progress "Applying SUSFS KernelSU patch..."
        pushd "$SRC/KernelSU-Next" > /dev/null
        patch -p1 --forward < "$patch_root/KernelSU/10_enable_susfs_for_ksu.patch" >> "$LOG_FILE" 2>&1
        local susfs_patch_rc=$?
        popd > /dev/null
        if [ $susfs_patch_rc -ne 0 ]; then
            log_error "Failed to apply KernelSU SUSFS patch"
            return 1
        fi
    fi

    log_progress "Applying SUSFS kernel patch..."
    pushd "$SRC" > /dev/null
    patch -p1 --forward < "$kernel_patch" >> "$LOG_FILE" 2>&1
    local kernel_patch_rc=$?
    popd > /dev/null

    if [ $kernel_patch_rc -ne 0 ]; then
        log_error "Failed to apply SUSFS kernel patch"
        return 1
    fi

    if has_susfs; then
        log_success "SUSFS integration completed"
        return 0
    fi

    log_error "SUSFS files still missing after patching"
    return 1
}

check_gcc() {
    if [ ! -d "$SRC/gcc" ]; then
        clone_repo "$GCC_URL" "$GCC_BRANCH" "$SRC/gcc" "GCC Toolchain" || return 1
    else
        log_success "GCC toolchain found"
    fi
}

check_clang() {
    if [ ! -d "$SRC/clang" ]; then
        clone_repo "$CLANG_URL" "$CLANG_BRANCH" "$SRC/clang" "Clang Toolchain" || return 1
    else
        log_success "Clang toolchain found"
    fi
}

check_toolchains() {
    log_info "Checking toolchains..."
    check_gcc || error_exit "Failed to setup GCC"
    check_clang || error_exit "Failed to setup Clang"
}

check_anykernel() {
    if [ ! -d "$ANYKERNEL_DIR" ]; then
        clone_repo "$ANYKERNEL_URL" "$ANYKERNEL_BRANCH" "$ANYKERNEL_DIR" "AnyKernel3" || return 1
    else
        log_success "AnyKernel3 already exists"
    fi
}

verify_dependencies() {
    log_info "Verifying dependencies..."

    local deps_ok=true

    for cmd in git curl zip make bc patch; do
        if ! command -v $cmd &> /dev/null; then
            log_error "Required command not found: $cmd"
            deps_ok=false
        fi
    done

    if [ "$deps_ok" = false ]; then
        error_exit "Missing required dependencies"
    fi

    log_success "All system dependencies verified"
}

setup_dependencies() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "Setting up build dependencies..."
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    verify_dependencies
    if [ "${ENABLE_KSU:-0}" = "1" ]; then
        check_ksu || error_exit "Failed to setup KernelSU-Next"
        check_susfs || error_exit "Failed to integrate SUSFS"
    fi
    check_toolchains
    check_anykernel

    echo ""
    log_success "All dependencies ready!"
    echo ""
}

# ==========================================================
#  Setup Build Environment
# ==========================================================
setup_environment() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "Setting up build environment..."
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    mkdir -p "$OUT_DIR"
    mkdir -p "$OUTPUT_DIR"

    log_info "Architecture: ${YELLOW}${ARCH}${NC}"
    log_info "Compiler: ${YELLOW}Clang + GCC${NC}"
    log_info "Threads: ${YELLOW}$(nproc)${NC}"

    echo ""
    log_success "Environment ready!"
    echo ""
}

# ==========================================================
#  Build Kernel
# ==========================================================
build_kernel() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "Starting kernel compilation..."
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    start_timer

    # Generate defconfig
    log_progress "Generating defconfig..."
    if make -C "$SRC" O="$OUT_DIR" $DEFCONFIG >> "$LOG_FILE" 2>&1; then
        log_success "Defconfig generated"
    else
        error_exit "Defconfig generation failed"
    fi

    echo ""
    log_progress "Compiling kernel with $(nproc) threads..."
    echo ""

    # Compile kernel
    if make -C "$SRC" O="$OUT_DIR" -j$(nproc) 2>&1 | tee -a "$LOG_FILE"; then
        echo ""
        log_success "Kernel compilation completed!"
    else
        error_exit "Kernel compilation failed"
    fi

    # Verify kernel image
    local image1="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"
    local image2="$OUT_DIR/arch/arm64/boot/Image.gz"

    if [ ! -f "$image1" ] && [ ! -f "$image2" ]; then
        error_exit "Kernel image not found after build"
    fi

    end_timer
    echo ""
}

# ==========================================================
#  Package Kernel
# ==========================================================
package_kernel() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "Creating flashable package..."
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    # Ensure AnyKernel exists
    check_anykernel

    # Clean old files
    log_progress "Cleaning AnyKernel directory..."
    rm -f "$ANYKERNEL_DIR/Image.gz" "$ANYKERNEL_DIR/Image.gz-dtb"

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

    # Create zip
    local zipname="${DEVICE}-$(date +%Y%m%d-%H%M).zip"
    log_progress "Creating ZIP package..."

    (cd "$ANYKERNEL_DIR" && zip -r9 "../output/$zipname" * > /dev/null 2>&1)

    if [ -f "$OUTPUT_DIR/$zipname" ]; then
        log_success "Package created: ${YELLOW}$zipname${NC}"
    else
        error_exit "Failed to create ZIP package"
    fi

    # Get kernel version
    local kernel_ver=$(gzip -dc "$kernel_image" | strings | grep -m1 "Linux version" || echo "Unknown")
    local date_now=$(date +"%d-%m-%Y %H:%M")

    # Prepare Telegram caption
    local caption="**${DEVICE} Kernel Build**

\`\`\`
Date     : ${date_now}
Version  : ${kernel_ver}
\`\`\`

**Flash via Recovery Only**"
    # Upload to Telegram
    echo ""
    send_to_telegram "$OUTPUT_DIR/$zipname" "$caption"
    echo ""
    log_success "Output: ${YELLOW}output/$zipname${NC}"
    echo ""
}

# ==========================================================
#  Main Build Process
# ==========================================================
main() {
    # Clear old log
    rm -f "$LOG_FILE"

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
    echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                              ║${NC}"
    echo -e "${GREEN}║          BUILD COMPLETED                     ║${NC}"
    echo -e "${GREEN}║                                              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"

    log_success "Build finished successfully!"
    log_info "Check output directory for flashable ZIP"
    echo ""
}

# ==========================================================
#  Run Main
# ==========================================================
main "$@"