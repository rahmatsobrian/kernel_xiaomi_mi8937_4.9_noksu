#!/bin/bash
# =================================================================
#  ReLIFE Kernel Build Script
#  Author    : rahmatsobrian
#  Enhanced  : Full CI/CD with advanced Telegram reporting
# =================================================================

set -euo pipefail

# ========================= COLOR =========================
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
cyan='\033[0;36m'
magenta='\033[0;35m'
bold='\033[1m'
white='\033[0m'

# ========================= PATH ==========================
ROOTDIR=$(pwd)
OUTDIR="$ROOTDIR/out/arch/arm64/boot"
ANYKERNEL_DIR="$ROOTDIR/AnyKernel"
LOG_DIR="$ROOTDIR/build_logs"
LOG_FILE="$LOG_DIR/build_$(date +%Y%m%d_%H%M%S).log"

KIMG_DTB="$OUTDIR/Image.gz-dtb"
KIMG="$OUTDIR/Image.gz"
KIMG_RAW="$OUTDIR/Image"

# ========================= TOOLCHAIN =====================
TC64="aarch64-linux-gnu-"
TC32="arm-linux-gnueabi-"

# ========================= DEFCONFIG =====================
DEFCONFIG="rahmatmsm8937hos_defconfig"
# DEFCONFIG="rahmatmsm8937_defconfig"  # uncomment to switch

# ========================= INFO ==========================
KERNEL_NAME="ReLIFE"
DEVICE="mi8937"
DEVICE_FULL="Xiaomi Snapdragon 430/435"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
COMMIT_MSG=$(git log --oneline -1 2>/dev/null | cut -c 9- || echo "unknown")
TOTAL_COMMITS=$(git rev-list --count HEAD 2>/dev/null || echo "?")

# ========================= DATE (WIB) ====================
DATE_TITLE=$(TZ=Asia/Jakarta date +"%d%m%Y")
TIME_TITLE=$(TZ=Asia/Jakarta date +"%H%M%S")
BUILD_DATETIME=$(TZ=Asia/Jakarta date +"%d %B %Y, %H:%M WIB")

# ========================= TELEGRAM ======================
TG_BOT_TOKEN="7443002324:AAFpDcG3_9L0Jhy4v98RCBqu2pGfznBCiDM"
TG_CHAT_ID="-1003520316735"
TG_THREAD_ID=""            # Optional: set message_thread_id for forum topics
SEND_LOG_ON_ERROR=true     # Send build log when build fails
SEND_LOG_ON_SUCCESS=false  # Send full log on success too

# ========================= BUILD FLAGS ===================
JOBS=$(nproc --all)
MAKE_FLAGS=(
    O=out
    ARCH=arm64
    CROSS_COMPILE=$TC64
    CROSS_COMPILE_ARM32=$TC32
    CROSS_COMPILE_COMPAT=$TC32
    -j"$JOBS"
)

# ========================= GLOBAL ========================
BUILD_TIME="unknown"
KERNEL_VERSION="unknown"
TC_INFO="unknown"
TC_VER_FULL="unknown"
IMG_USED="unknown"
MD5_HASH="unknown"
SHA1_HASH="unknown"
ZIP_SIZE="unknown"
ZIP_NAME=""
BUILD_STATUS="unknown"
ERROR_STAGE=""
TG_MSG_ID=""            # Store first message ID for editing
WARNINGS=0
ERRORS_COUNT=0

# ========================= LOGGING =======================

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log_info()    { echo -e "${cyan}[INFO]${white}  $*"; }
log_ok()      { echo -e "${green}[  OK]${white}  $*"; }
log_warn()    { echo -e "${yellow}[WARN]${white}  $*"; ((WARNINGS++)) || true; }
log_error()   { echo -e "${red}[FAIL]${white}  $*" >&2; }
log_section() { echo -e "\n${bold}${blue}══════════ $* ══════════${white}\n"; }
log_step()    { echo -e "${magenta}[STEP]${white}  $*"; }

# ========================= TELEGRAM FUNCTIONS ============

_tg_base_args() {
    local args=(-s -X POST)
    [[ -n "$TG_THREAD_ID" ]] && args+=(-d "message_thread_id=${TG_THREAD_ID}")
    echo "${args[@]}"
}

tg_send_message() {
    local text="$1"
    local extra_args=("${@:2}")
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "parse_mode=Markdown" \
        -d "disable_web_page_preview=true" \
        ${TG_THREAD_ID:+-d "message_thread_id=${TG_THREAD_ID}"} \
        -d "text=${text}" \
        "${extra_args[@]}" 2>/dev/null
}

tg_edit_message() {
    local msg_id="$1"
    local text="$2"
    [[ -z "$msg_id" ]] && return
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/editMessageText" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "message_id=${msg_id}" \
        -d "parse_mode=Markdown" \
        -d "disable_web_page_preview=true" \
        -d "text=${text}" 2>/dev/null
}

tg_send_document() {
    local file="$1"
    local caption="$2"
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
        -F "chat_id=${TG_CHAT_ID}" \
        -F "document=@${file}" \
        -F "parse_mode=Markdown" \
        -F "caption=${caption}" \
        ${TG_THREAD_ID:+-F "message_thread_id=${TG_THREAD_ID}"} 2>/dev/null
}

tg_get_msg_id() {
    echo "$1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['message_id'] if d.get('ok') else '')" 2>/dev/null || echo ""
}

tg_notify_start() {
    log_step "Sending build start notification..."
    local resp
    resp=$(tg_send_message "⚙️ *Kernel Build Started*

📱 *Device*     : \`${DEVICE}\` (${DEVICE_FULL})
🌿 *Branch*     : \`${BRANCH}\`
🔖 *Commit*     : \`${COMMIT_HASH}\` - ${COMMIT_MSG}
📊 *Total Commits* : ${TOTAL_COMMITS}
🛠 *Defconfig*  : \`${DEFCONFIG}\`
🔧 *Jobs*       : ${JOBS} threads
🕒 *Started*    : ${BUILD_DATETIME}")
    TG_MSG_ID=$(tg_get_msg_id "$resp")
    log_info "TG message ID: $TG_MSG_ID"
}

tg_notify_building() {
    tg_edit_message "$TG_MSG_ID" "🔨 *Kernel Compiling...*

📱 *Device*     : \`${DEVICE}\`
🌿 *Branch*     : \`${BRANCH}\`
🔖 *Commit*     : \`${COMMIT_HASH}\`
🛠 *Toolchain*  : ${TC_INFO}
🔧 *Jobs*       : ${JOBS} threads
⏳ *Status*     : Compiling, please wait..." || true
}

tg_notify_packing() {
    tg_edit_message "$TG_MSG_ID" "📦 *Packing Kernel Zip...*

📱 *Device*     : \`${DEVICE}\`
🌿 *Branch*     : \`${BRANCH}\`
🛠 *Toolchain*  : ${TC_INFO}
⏱ *Compile Time* : ${BUILD_TIME}
⏳ *Status*     : Creating flashable zip..." || true
}

tg_notify_uploading() {
    tg_edit_message "$TG_MSG_ID" "📤 *Uploading Kernel...*

📱 *Device*     : \`${DEVICE}\`
⏱ *Compile Time* : ${BUILD_TIME}
📁 *Zip Size*   : ${ZIP_SIZE}
⏳ *Status*     : Uploading to Telegram..." || true
}

tg_notify_success() {
    local caption="✅ *${KERNEL_NAME} Kernel — Build Success*

📱 *Device*        : \`${DEVICE}\` (${DEVICE_FULL})
🍃 *Kernel Version* : \`${KERNEL_VERSION}\`
📦 *Kernel Name*   : ${KERNEL_NAME}

🌿 *Branch*        : \`${BRANCH}\`
🔖 *Commit*        : \`${COMMIT_HASH}\`
💬 *Commit Msg*    : ${COMMIT_MSG}

🛠 *Toolchain*     : ${TC_INFO}
🖼 *Image Used*    : \`${IMG_USED}\`
🔧 *Defconfig*     : \`${DEFCONFIG}\`

⏱ *Compile Time*  : ${BUILD_TIME}
🕒 *Build Date*    : ${BUILD_DATETIME}

📁 *Size*          : ${ZIP_SIZE}
🔐 *MD5*           :
\`${MD5_HASH}\`
🔑 *SHA1*          :
\`${SHA1_HASH}\`

✅ *Flash via TWRP / Custom Recovery*"

    tg_send_document "$ANYKERNEL_DIR/$ZIP_NAME" "$caption"

    # Edit the original message to mark done
    tg_edit_message "$TG_MSG_ID" "✅ *Build Completed Successfully!*
⏱ ${BUILD_TIME} | 📦 ${ZIP_NAME}" || true

    [[ "$SEND_LOG_ON_SUCCESS" == true ]] && \
        tg_send_document "$LOG_FILE" "📋 Build log — ${ZIP_NAME}"
}

tg_notify_error() {
    local stage="${ERROR_STAGE:-unknown stage}"
    local caption="❌ *${KERNEL_NAME} Kernel — Build Failed*

📱 *Device*     : \`${DEVICE}\`
🌿 *Branch*     : \`${BRANCH}\`
🔖 *Commit*     : \`${COMMIT_HASH}\`
💬 *Commit Msg* : ${COMMIT_MSG}

🛠 *Toolchain*  : ${TC_INFO}
🔧 *Defconfig*  : \`${DEFCONFIG}\`

💥 *Failed At*  : ${stage}
⚠️ *Warnings*   : ${WARNINGS}
🕒 *Time*       : ${BUILD_DATETIME}

📋 *Log attached below*"

    tg_edit_message "$TG_MSG_ID" "❌ *Build Failed at: ${stage}*
Check the attached log for details." || true

    # Send error log
    if [[ "$SEND_LOG_ON_ERROR" == true ]] && [[ -f "$LOG_FILE" ]]; then
        tg_send_document "$LOG_FILE" "$caption"
    else
        tg_send_message "$caption"
    fi
}

# ========================= TRAP / ERROR HANDLER ==========

on_error() {
    local exit_code=$?
    local line_no=$1
    log_error "Script failed at line ${line_no} with exit code ${exit_code}"
    log_error "Failed stage: ${ERROR_STAGE}"
    tg_notify_error
    exit "$exit_code"
}

trap 'on_error $LINENO' ERR

# ========================= HELPER FUNCTIONS ==============

check_dependencies() {
    log_section "Checking Dependencies"
    local deps=(git make zip curl python3 md5sum sha1sum)
    local missing=()
    for dep in "${deps[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            log_ok "$dep found: $(command -v "$dep")"
        else
            log_warn "$dep NOT found"
            missing+=("$dep")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_error "Install them with: sudo apt install ${missing[*]}"
        exit 1
    fi
}

check_toolchain() {
    log_section "Checking Toolchain"
    if command -v "${TC64}gcc" >/dev/null 2>&1; then
        log_ok "64-bit toolchain found: ${TC64}gcc"
    else
        log_warn "64-bit toolchain '${TC64}gcc' not found in PATH"
    fi
    if command -v "${TC32}gcc" >/dev/null 2>&1; then
        log_ok "32-bit toolchain found: ${TC32}gcc"
    else
        log_warn "32-bit toolchain '${TC32}gcc' not found in PATH"
    fi
}

get_toolchain_info() {
    local gcc_bin="${TC64}gcc"
    if command -v "$gcc_bin" >/dev/null 2>&1; then
        local ver=$("$gcc_bin" -dumpversion)
        local full=$("$gcc_bin" --version | head -1)
        TC_INFO="GCC ${ver}"
        TC_VER_FULL="$full"
        log_info "Toolchain: $TC_VER_FULL"
    elif command -v gcc >/dev/null 2>&1; then
        local ver=$(gcc -dumpversion)
        TC_INFO="GCC ${ver} (host)"
        TC_VER_FULL=$(gcc --version | head -1)
    else
        TC_INFO="unknown"
        log_warn "No GCC found, build may fail"
    fi
}

get_kernel_version() {
    if [[ -f "Makefile" ]]; then
        local ver patch sub
        ver=$(grep -E '^VERSION\s*=' Makefile | awk '{print $3}' | head -1)
        patch=$(grep -E '^PATCHLEVEL\s*=' Makefile | awk '{print $3}' | head -1)
        sub=$(grep -E '^SUBLEVEL\s*=' Makefile | awk '{print $3}' | head -1)
        KERNEL_VERSION="${ver}.${patch}.${sub}"
        log_info "Kernel version: $KERNEL_VERSION"
    else
        log_warn "Makefile not found, kernel version unknown"
        KERNEL_VERSION="unknown"
    fi
}

print_build_summary() {
    log_section "Build Summary"
    echo -e "  ${bold}Kernel     :${white} ${KERNEL_NAME}"
    echo -e "  ${bold}Device     :${white} ${DEVICE} (${DEVICE_FULL})"
    echo -e "  ${bold}Version    :${white} ${KERNEL_VERSION}"
    echo -e "  ${bold}Branch     :${white} ${BRANCH}"
    echo -e "  ${bold}Commit     :${white} ${COMMIT_HASH} - ${COMMIT_MSG}"
    echo -e "  ${bold}Toolchain  :${white} ${TC_INFO}"
    echo -e "  ${bold}Defconfig  :${white} ${DEFCONFIG}"
    echo -e "  ${bold}Jobs       :${white} ${JOBS}"
    echo -e "  ${bold}Build Time :${white} ${BUILD_TIME}"
    echo -e "  ${bold}Image Used :${white} ${IMG_USED}"
    echo -e "  ${bold}Zip Name   :${white} ${ZIP_NAME}"
    echo -e "  ${bold}Zip Size   :${white} ${ZIP_SIZE}"
    echo -e "  ${bold}MD5        :${white} ${MD5_HASH}"
    echo -e "  ${bold}SHA1       :${white} ${SHA1_HASH}"
    echo -e "  ${bold}Warnings   :${white} ${WARNINGS}"
    echo -e "  ${bold}Log File   :${white} ${LOG_FILE}"
    echo ""
}

# ========================= CLONE ANYKERNEL ===============

clone_anykernel() {
    ERROR_STAGE="Clone AnyKernel"
    log_section "AnyKernel Setup"
    if [[ ! -d "$ANYKERNEL_DIR" ]]; then
        log_step "Cloning AnyKernel3 (branch: mi8937)..."
        git clone --depth=1 -b mi8937 \
            https://github.com/rahmatsobrian/AnyKernel3.git \
            "$ANYKERNEL_DIR"
        log_ok "AnyKernel3 cloned successfully"
    else
        log_info "AnyKernel3 already exists, pulling latest..."
        git -C "$ANYKERNEL_DIR" pull --rebase --autostash 2>/dev/null && \
            log_ok "AnyKernel3 updated" || \
            log_warn "AnyKernel3 pull failed, using existing"
    fi
    log_info "AnyKernel commit: $(git -C "$ANYKERNEL_DIR" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
}

# ========================= BUILD KERNEL ==================

build_kernel() {
    ERROR_STAGE="Build - Defconfig"
    log_section "Kernel Build"

    [[ ! -f "Makefile" ]] && { log_error "Not in kernel source root!"; exit 1; }

    log_step "Cleaning previous out directory..."
    rm -rf out
    log_ok "Cleaned out/"

    log_step "Generating defconfig: $DEFCONFIG"
    make "${MAKE_FLAGS[@]}" "$DEFCONFIG" 2>&1 | tee -a "$LOG_FILE"
    log_ok "Defconfig applied successfully"

    get_toolchain_info
    get_kernel_version

    tg_notify_start
    tg_notify_building

    ERROR_STAGE="Build - Compile"
    log_step "Starting compilation with $JOBS threads..."
    BUILD_START=$(TZ=Asia/Jakarta date +%s)

    make "${MAKE_FLAGS[@]}" 2>&1 | tee -a "$LOG_FILE"

    BUILD_END=$(TZ=Asia/Jakarta date +%s)
    local diff=$((BUILD_END - BUILD_START))
    BUILD_TIME="$((diff / 60)) min $((diff % 60)) sec"

    # Count warnings/errors from log
    WARNINGS=$(grep -c "warning:" "$LOG_FILE" 2>/dev/null || echo 0)
    ERRORS_COUNT=$(grep -c "error:" "$LOG_FILE" 2>/dev/null || echo 0)

    log_ok "Compilation finished in ${BUILD_TIME}"
    log_info "Warnings: ${WARNINGS} | Errors logged: ${ERRORS_COUNT}"

    get_kernel_version  # Re-read after build (version string may differ)
    ZIP_NAME="${KERNEL_NAME}-${DEVICE}-${KERNEL_VERSION}-${DATE_TITLE}-${TIME_TITLE}.zip"
}

# ========================= PACK KERNEL ===================

pack_kernel() {
    ERROR_STAGE="Pack - AnyKernel"
    log_section "Packaging"

    tg_notify_packing
    clone_anykernel

    cd "$ANYKERNEL_DIR" || { log_error "Cannot enter AnyKernel dir"; exit 1; }

    log_step "Cleaning old kernel images and zips..."
    rm -f Image* *.zip
    log_ok "Cleaned old files"

    # Detect which image to use
    ERROR_STAGE="Pack - Image Detection"
    if [[ -f "$KIMG_DTB" ]]; then
        cp "$KIMG_DTB" Image.gz-dtb
        IMG_USED="Image.gz-dtb"
        log_ok "Using Image.gz-dtb"
    elif [[ -f "$KIMG" ]]; then
        cp "$KIMG" Image.gz
        IMG_USED="Image.gz"
        log_ok "Using Image.gz"
    elif [[ -f "$KIMG_RAW" ]]; then
        cp "$KIMG_RAW" Image
        IMG_USED="Image"
        log_ok "Using raw Image"
    else
        log_error "No kernel image found in $OUTDIR!"
        log_error "Expected: Image.gz-dtb | Image.gz | Image"
        ERROR_STAGE="Pack - Image Not Found"
        exit 1
    fi

    ERROR_STAGE="Pack - Zip Creation"
    log_step "Creating flashable zip: $ZIP_NAME"
    zip -r9 "$ZIP_NAME" . -x ".git*" "README.md" "*.log" | \
        while IFS= read -r line; do log_info "$line"; done

    # Checksums
    MD5_HASH=$(md5sum "$ZIP_NAME" | awk '{print $1}')
    SHA1_HASH=$(sha1sum "$ZIP_NAME" | awk '{print $1}')

    # Zip size (human readable)
    ZIP_SIZE=$(du -sh "$ZIP_NAME" | awk '{print $1}')

    log_ok "Zip created: $ZIP_NAME"
    log_info "Size  : $ZIP_SIZE"
    log_info "MD5   : $MD5_HASH"
    log_info "SHA1  : $SHA1_HASH"

    cd "$ROOTDIR" || exit 1
}

# ========================= UPLOAD =========================

upload_telegram() {
    ERROR_STAGE="Upload - Telegram"
    local zip_path="$ANYKERNEL_DIR/$ZIP_NAME"

    if [[ ! -f "$zip_path" ]]; then
        log_warn "Zip not found at $zip_path, skipping upload"
        return 1
    fi

    log_section "Uploading to Telegram"
    tg_notify_uploading

    log_step "Uploading: $ZIP_NAME ($ZIP_SIZE)"
    tg_notify_success
    log_ok "Upload complete!"
}

# ========================= ENTRYPOINT ====================

main() {
    log_section "ReLIFE Kernel Build Script"
    log_info "Script started at: $BUILD_DATETIME"
    log_info "Working directory: $ROOTDIR"
    log_info "Log file: $LOG_FILE"

    GLOBAL_START=$(TZ=Asia/Jakarta date +%s)

    check_dependencies
    check_toolchain
    build_kernel
    pack_kernel
    upload_telegram

    GLOBAL_END=$(TZ=Asia/Jakarta date +%s)
    local total=$((GLOBAL_END - GLOBAL_START))

    print_build_summary

    log_ok "════════════════════════════════════════"
    log_ok " All done in $((total / 60)) min $((total % 60)) sec"
    log_ok " Zip : ${ZIP_NAME}"
    log_ok "════════════════════════════════════════"
}

main "$@"
