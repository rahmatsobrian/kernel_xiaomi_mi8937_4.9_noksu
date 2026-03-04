#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║          ReLIFE Kernel CI Build Script — Ultra Edition          ║
# ║  Author   : rahmatsobrian                                        ║
# ║  Feature  : Full Telegram CI/CD, Live status, Log upload,       ║
# ║             Error trace, Warning summary, Resource monitor       ║
# ╚══════════════════════════════════════════════════════════════════╝

set -Eeuo pipefail

# ═══════════════════════════ COLOR ═══════════════════════════════════
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
cyan='\033[0;36m'
magenta='\033[0;35m'
bold='\033[1m'
dim='\033[2m'
white='\033[0m'

# ═══════════════════════════ PATH ════════════════════════════════════
ROOTDIR=$(pwd)
OUTDIR="$ROOTDIR/out/arch/arm64/boot"
ANYKERNEL_DIR="$ROOTDIR/AnyKernel"
LOG_DIR="$ROOTDIR/build_logs"
TIMESTAMP=$(TZ=Asia/Jakarta date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/build_${TIMESTAMP}.log"
ERR_LOG="$LOG_DIR/errors_${TIMESTAMP}.log"
WARN_LOG="$LOG_DIR/warnings_${TIMESTAMP}.log"

KIMG_DTB="$OUTDIR/Image.gz-dtb"
KIMG="$OUTDIR/Image.gz"
KIMG_RAW="$OUTDIR/Image"

# ═══════════════════════════ TOOLCHAIN ═══════════════════════════════
TC64="aarch64-linux-gnu-"
TC32="arm-linux-gnueabi-"

# ═══════════════════════════ DEFCONFIG ═══════════════════════════════
DEFCONFIG="rahmatmsm8937hos_defconfig"
# DEFCONFIG="rahmatmsm8937_defconfig"   # uncomment to switch

# ═══════════════════════════ KERNEL INFO ═════════════════════════════
KERNEL_NAME="ReLIFE"
DEVICE="mi8937"
DEVICE_FULL="Xiaomi Snapdragon 430/435"

# Git info (safe fallbacks)
BRANCH=$(git rev-parse --abbrev-ref HEAD            2>/dev/null || echo "unknown")
COMMIT_HASH=$(git rev-parse --short HEAD             2>/dev/null || echo "unknown")
COMMIT_MSG=$(git log --format="%s" -1                2>/dev/null || echo "unknown")
COMMIT_AUTHOR=$(git log --format="%an" -1            2>/dev/null || echo "unknown")
COMMIT_DATE=$(git log --format="%cd" \
    --date=format:"%d %b %Y %H:%M" -1               2>/dev/null || echo "unknown")
TOTAL_COMMITS=$(git rev-list --count HEAD            2>/dev/null || echo "?")
DIRTY=$(git status --short                           2>/dev/null | wc -l | xargs || echo "0")

# ═══════════════════════════ DATE / TIME ═════════════════════════════
DATE_TITLE=$(TZ=Asia/Jakarta date +"%d%m%Y")
TIME_TITLE=$(TZ=Asia/Jakarta date +"%H%M%S")
BUILD_DATETIME=$(TZ=Asia/Jakarta date +"%d %B %Y, %H:%M WIB")

# ═══════════════════════════ TELEGRAM CONFIG ══════════════════════════
TG_BOT_TOKEN="7443002324:AAFpDcG3_9L0Jhy4v98RCBqu2pGfznBCiDM"
TG_CHAT_ID="-1003520316735"
TG_THREAD_ID=""               # Forum topic thread id (leave empty if not using)

# Feature toggles
SEND_LOG_ON_SUCCESS=true      # Upload full build log after success
SEND_LOG_ON_ERROR=true        # Upload full build log on failure
SEND_ERRLOG_ON_ERROR=true     # Upload filtered error-only log on failure
SEND_WARNLOG_ON_SUCCESS=true  # Upload warning summary log on success
TG_DISABLE=false              # Set true to disable all Telegram notifications

# ═══════════════════════════ BUILD CONFIG ════════════════════════════
JOBS=$(nproc --all)
RAM_GB=$(awk '/MemTotal/{printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "?")
MAKE_FLAGS=(
    O=out
    ARCH=arm64
    CROSS_COMPILE="$TC64"
    CROSS_COMPILE_ARM32="$TC32"
    CROSS_COMPILE_COMPAT="$TC32"
    -j"$JOBS"
)

# ═══════════════════════════ GLOBALS ═════════════════════════════════
BUILD_TIME="unknown"
KERNEL_VERSION="unknown"
TC_INFO="unknown"
TC_VER_FULL="unknown"
LD_INFO="unknown"
IMG_USED="unknown"
IMG_SIZE="unknown"
MD5_HASH="unknown"
SHA1_HASH="unknown"
ZIP_SIZE="unknown"
ZIP_NAME=""
ERROR_STAGE=""
ERROR_LINE=""
ERROR_FUNC=""
TG_MSG_ID=""
WARNINGS_COUNT=0
ERRORS_COUNT=0
HOST_DISK="unknown"

# ═══════════════════════════ LOGGING ═════════════════════════════════
mkdir -p "$LOG_DIR"

# stdout+stderr → terminal AND log file (ANSI stripped in log)
exec > >(tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE")) \
     2> >(tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE") >&2)

_ts() { date +"%H:%M:%S"; }
log_info()    { echo -e "${cyan}[INFO ]${white} $(_ts)  $*"; }
log_ok()      { echo -e "${green}[ OK  ]${white} $(_ts)  $*"; }
log_warn()    { echo -e "${yellow}[WARN ]${white} $(_ts)  $*"; }
log_error()   { echo -e "${red}[ERROR]${white} $(_ts)  $*"; }
log_step()    { echo -e "${magenta}[STEP ]${white} $(_ts)  $*"; }
log_divider() { echo -e "${dim}──────────────────────────────────────────────────${white}"; }
log_section() {
    echo -e ""
    echo -e "${bold}${blue}┌──────────────────────────────────────────────┐${white}"
    printf "${bold}${blue}│  %-44s│${white}\n" "$*"
    echo -e "${bold}${blue}└──────────────────────────────────────────────┘${white}"
    echo -e ""
}

# ═══════════════════════════ TELEGRAM CORE ═══════════════════════════

tg_send_message() {
    [[ "$TG_DISABLE" == true ]] && return 0
    local text="$1"
    curl -s --max-time 30 -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "parse_mode=Markdown" \
        -d "disable_web_page_preview=true" \
        ${TG_THREAD_ID:+-d "message_thread_id=${TG_THREAD_ID}"} \
        --data-urlencode "text=${text}" \
        2>/dev/null || { log_warn "tg_send_message failed"; return 1; }
}

tg_edit_message() {
    [[ "$TG_DISABLE" == true ]] && return 0
    [[ -z "${TG_MSG_ID:-}" ]] && return 0
    local text="$1"
    curl -s --max-time 30 -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/editMessageText" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "message_id=${TG_MSG_ID}" \
        -d "parse_mode=Markdown" \
        -d "disable_web_page_preview=true" \
        --data-urlencode "text=${text}" \
        2>/dev/null || { log_warn "tg_edit_message failed"; return 1; }
}

tg_send_document() {
    [[ "$TG_DISABLE" == true ]] && return 0
    local file="$1"
    local caption="${2:-}"
    if [[ ! -f "$file" ]]; then
        log_warn "tg_send_document: file not found — $file"
        return 1
    fi
    local fsize
    fsize=$(du -sh "$file" | awk '{print $1}')
    log_step "Uploading: $(basename "$file") ($fsize) → Telegram"
    curl -s --max-time 180 -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
        -F "chat_id=${TG_CHAT_ID}" \
        -F "document=@${file};filename=$(basename "$file")" \
        -F "parse_mode=Markdown" \
        ${TG_THREAD_ID:+-F "message_thread_id=${TG_THREAD_ID}"} \
        ${caption:+--form-string "caption=${caption}"} \
        2>/dev/null || { log_warn "tg_send_document failed: $(basename "$file")"; return 1; }
    log_ok "Uploaded: $(basename "$file")"
}

tg_get_msg_id() {
    echo "$1" | python3 -c \
        "import sys,json
d=json.load(sys.stdin)
print(d['result']['message_id'] if d.get('ok') else '')" \
        2>/dev/null || echo ""
}

# ═══════════════════════════ INFO HELPERS ════════════════════════════

get_system_info() {
    HOST_DISK=$(df -h "$ROOTDIR" 2>/dev/null | awk 'NR==2{print $4" free / "$2" total"}' || echo "unknown")
}

get_toolchain_info() {
    local gcc_bin="${TC64}gcc"
    if command -v "$gcc_bin" >/dev/null 2>&1; then
        local ver; ver=$("$gcc_bin" -dumpversion)
        TC_VER_FULL=$("$gcc_bin" --version | head -1)
        TC_INFO="GCC ${ver}"
    elif command -v gcc >/dev/null 2>&1; then
        local ver; ver=$(gcc -dumpversion)
        TC_VER_FULL=$(gcc --version | head -1)
        TC_INFO="GCC ${ver} (host fallback)"
    else
        TC_INFO="unknown"
        log_warn "No GCC found — build will likely fail"
    fi

    if command -v "${TC64}ld" >/dev/null 2>&1; then
        LD_INFO=$("${TC64}ld" --version 2>/dev/null | head -1 || echo "unknown")
    fi

    log_info "Toolchain : $TC_VER_FULL"
    log_info "Linker    : $LD_INFO"
}

get_kernel_version() {
    if [[ -f "Makefile" ]]; then
        local ver patch sub extra
        ver=$(awk  '/^VERSION\s*=/{print $3; exit}'   Makefile)
        patch=$(awk '/^PATCHLEVEL\s*=/{print $3; exit}' Makefile)
        sub=$(awk  '/^SUBLEVEL\s*=/{print $3; exit}'  Makefile)
        extra=$(awk '/^EXTRAVERSION\s*=/{print $3; exit}' Makefile 2>/dev/null || echo "")
        KERNEL_VERSION="${ver}.${patch}.${sub}${extra}"
        log_info "Kernel version: $KERNEL_VERSION"
    else
        KERNEL_VERSION="unknown"
        log_warn "Makefile not found — version unknown"
    fi
}

# ═══════════════════════════ TELEGRAM STAGES ═════════════════════════

tg_notify_start() {
    log_step "Sending BUILD START notification..."
    local tree_status="✅ Clean"
    [[ "$DIRTY" -gt 0 ]] && tree_status="⚠️ ${DIRTY} uncommitted change(s)"

    local msg
    msg="🚀 *ReLIFE Kernel CI — Build Started*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device*         : \`${DEVICE}\` — ${DEVICE_FULL}
📦 *Kernel*         : ${KERNEL_NAME}
🍃 *Version*        : \`${KERNEL_VERSION}\`

🌿 *Branch*         : \`${BRANCH}\`
🔖 *Commit*         : \`${COMMIT_HASH}\`
💬 *Commit Msg*     : ${COMMIT_MSG}
👤 *Author*         : ${COMMIT_AUTHOR}
📅 *Commit Date*    : ${COMMIT_DATE}
📊 *Total Commits*  : ${TOTAL_COMMITS}
🗂 *Tree Status*    : ${tree_status}

🛠 *Toolchain*      : ${TC_INFO}
🔗 *Linker*         : ${LD_INFO}
🔧 *Defconfig*      : \`${DEFCONFIG}\`
⚙️ *Jobs*           : ${JOBS} threads
🖥 *Host RAM*       : ${RAM_GB} GB
💾 *Disk*           : ${HOST_DISK}

🕒 *Started At*     : ${BUILD_DATETIME}"

    local resp
    resp=$(tg_send_message "$msg")
    TG_MSG_ID=$(tg_get_msg_id "$resp")
    log_info "Telegram pinned message ID: ${TG_MSG_ID:-[failed to capture]}"
}

tg_notify_defconfig() {
    tg_edit_message "⚙️ *Applying Defconfig...*
━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device*    : \`${DEVICE}\`
🔧 *Defconfig* : \`${DEFCONFIG}\`
⏳ *Status*    : Running make defconfig..."
}

tg_notify_compiling() {
    tg_edit_message "🔨 *Kernel Compiling...*
━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device*    : \`${DEVICE}\`
🌿 *Branch*    : \`${BRANCH}\`
🔖 *Commit*    : \`${COMMIT_HASH}\`
🍃 *Version*   : \`${KERNEL_VERSION}\`
🛠 *Toolchain* : ${TC_INFO}
⚙️ *Jobs*      : ${JOBS} threads

⏳ *Status*    : Compiling, please wait...
🕒 *Started*   : ${BUILD_DATETIME}"
}

tg_notify_packing() {
    tg_edit_message "📦 *Packing Flashable Zip...*
━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device*       : \`${DEVICE}\`
🍃 *Version*      : \`${KERNEL_VERSION}\`
⏱ *Compile Time* : ${BUILD_TIME}
🖼 *Image*        : \`${IMG_USED}\` (${IMG_SIZE})
⚠️ *Warnings*     : ${WARNINGS_COUNT}

⏳ *Status*       : Creating AnyKernel3 zip..."
}

tg_notify_uploading() {
    tg_edit_message "📤 *Uploading to Telegram...*
━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device*       : \`${DEVICE}\`
📁 *Zip*          : \`${ZIP_NAME}\`
📏 *Size*         : ${ZIP_SIZE}
⏱ *Compile Time* : ${BUILD_TIME}

⏳ *Status*       : Uploading kernel zip..."
}

tg_notify_success() {
    local zip_path="$ANYKERNEL_DIR/$ZIP_NAME"
    local warn_note=""
    [[ "$WARNINGS_COUNT" -gt 0 ]] && \
        warn_note="
⚠️ *Warnings*       : ${WARNINGS_COUNT} (warning log attached)"

    local caption
    caption="✅ *ReLIFE Kernel — Build Successful!*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device*         : \`${DEVICE}\` — ${DEVICE_FULL}
📦 *Kernel Name*    : ${KERNEL_NAME}
🍃 *Kernel Version* : \`${KERNEL_VERSION}\`

🌿 *Branch*         : \`${BRANCH}\`
🔖 *Commit*         : \`${COMMIT_HASH}\`
💬 *Commit Msg*     : ${COMMIT_MSG}
👤 *Author*         : ${COMMIT_AUTHOR}

🛠 *Toolchain*      : ${TC_INFO}
🔗 *Linker*         : ${LD_INFO}
🔧 *Defconfig*      : \`${DEFCONFIG}\`
🖼 *Image Used*     : \`${IMG_USED}\` (${IMG_SIZE})

⏱ *Compile Time*   : ${BUILD_TIME}
🕒 *Build Date*     : ${BUILD_DATETIME}
${warn_note}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📁 *File*           : \`${ZIP_NAME}\`
📏 *Size*           : ${ZIP_SIZE}
🔐 *MD5*            :
\`${MD5_HASH}\`
🔑 *SHA1*           :
\`${SHA1_HASH}\`
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚡ *Flash via TWRP or any Custom Recovery*"

    # 1. Upload flashable zip
    tg_send_document "$zip_path" "$caption"

    # 2. Upload full build log
    if [[ "$SEND_LOG_ON_SUCCESS" == true ]] && [[ -f "$LOG_FILE" ]]; then
        tg_send_document "$LOG_FILE" \
"📋 *Full Build Log* — ${KERNEL_NAME} \`${KERNEL_VERSION}\`
Branch: \`${BRANCH}\` | Commit: \`${COMMIT_HASH}\`
Jobs: ${JOBS} | Warnings: ${WARNINGS_COUNT} | Time: ${BUILD_TIME}"
    fi

    # 3. Upload warning summary if any
    if [[ "$SEND_WARNLOG_ON_SUCCESS" == true ]] && \
       [[ "$WARNINGS_COUNT" -gt 0 ]] && [[ -s "$WARN_LOG" ]]; then
        tg_send_document "$WARN_LOG" \
"⚠️ *Warning Summary* — ${WARNINGS_COUNT} unique warnings
${KERNEL_NAME} \`${KERNEL_VERSION}\` | \`${COMMIT_HASH}\`"
    fi

    # 4. Edit pinned message to final done state
    tg_edit_message "✅ *Build Done — ${KERNEL_NAME} \`${KERNEL_VERSION}\`*
━━━━━━━━━━━━━━━━━━━━━━━━
📦 \`${ZIP_NAME}\`
📏 Size        : ${ZIP_SIZE}
⏱ Compile    : ${BUILD_TIME}
⚠️ Warnings   : ${WARNINGS_COUNT}
🔐 MD5        : \`${MD5_HASH}\`
🕒 Finished   : $(TZ=Asia/Jakarta date +"%d %B %Y, %H:%M WIB")"
}

tg_notify_error() {
    local stage="${ERROR_STAGE:-unknown}"
    local line="${ERROR_LINE:-?}"
    local func="${ERROR_FUNC:-unknown}"

    # Collect last error lines from log
    local last_errors="No error lines captured"
    if [[ -f "$LOG_FILE" ]]; then
        local raw
        raw=$(grep -E "(error:|Error|FAILED|undefined reference|multiple definition|fatal:)" \
            "$LOG_FILE" 2>/dev/null | grep -v "^Binary\|^--" | tail -20 \
            | sed "s/\x1b\[[0-9;]*m//g" \
            | sed "s/\`/'/g" \
            | awk '{print NR". "$0}' || true)
        [[ -n "$raw" ]] && last_errors="$raw"
    fi

    # Telegram 4096-char cap — trim if needed
    if [[ ${#last_errors} -gt 800 ]]; then
        last_errors="${last_errors:0:800}
..._(truncated — full log attached)_"
    fi

    # Edit pinned message first (fast)
    tg_edit_message "❌ *Build FAILED — \`${stage}\`*
━━━━━━━━━━━━━━━━━━━━━━━━
💥 Stage    : \`${stage}\`
📍 Line     : ${line}
🔁 Function : \`${func}\`
⚠️ Warnings : ${WARNINGS_COUNT}
🕒 At       : $(TZ=Asia/Jakarta date +"%H:%M WIB")
📋 Detailed report + logs below..."

    # Send detailed error message
    local msg
    msg="❌ *ReLIFE Kernel — Build FAILED*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device*      : \`${DEVICE}\` — ${DEVICE_FULL}
📦 *Kernel*      : ${KERNEL_NAME}
🌿 *Branch*      : \`${BRANCH}\`
🔖 *Commit*      : \`${COMMIT_HASH}\`
💬 *Commit Msg*  : ${COMMIT_MSG}
👤 *Author*      : ${COMMIT_AUTHOR}

🛠 *Toolchain*   : ${TC_INFO}
🔧 *Defconfig*   : \`${DEFCONFIG}\`

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💥 *Failed Stage* : \`${stage}\`
📍 *Script Line*  : ${line}
🔁 *In Function*  : \`${func}\`
⚠️ *Warnings*     : ${WARNINGS_COUNT}
🔢 *Error Count*  : ${ERRORS_COUNT}
🕒 *Time*         : ${BUILD_DATETIME}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔴 *Last Error Lines:*
\`\`\`
${last_errors}
\`\`\`"

    tg_send_message "$msg"

    # Upload full build log
    if [[ "$SEND_LOG_ON_ERROR" == true ]] && [[ -f "$LOG_FILE" ]]; then
        tg_send_document "$LOG_FILE" \
"📋 *Full Build Log — FAILED*
Stage: \`${stage}\` | Line: ${line}
${KERNEL_NAME} | Branch: \`${BRANCH}\` | Commit: \`${COMMIT_HASH}\`
Warnings: ${WARNINGS_COUNT} | Errors: ${ERRORS_COUNT}"
    fi

    # Upload filtered error-only log
    if [[ "$SEND_ERRLOG_ON_ERROR" == true ]] && [[ -f "$ERR_LOG" ]] && [[ -s "$ERR_LOG" ]]; then
        tg_send_document "$ERR_LOG" \
"🔴 *Filtered Error Log*
Stage: \`${stage}\` | Line: ${line}
${KERNEL_NAME} | \`${COMMIT_HASH}\` | Errors: $(wc -l < "$ERR_LOG")"
    fi
}

# ═══════════════════════════ ERROR TRAP ══════════════════════════════

on_error() {
    local exit_code=$?
    ERROR_LINE="${1:-?}"
    # Walk call stack
    local stack=""
    local i
    for (( i=1; i<${#FUNCNAME[@]}; i++ )); do
        stack+=" → ${FUNCNAME[$i]}(${BASH_LINENO[$((i-1))]})"
    done
    ERROR_FUNC="${FUNCNAME[1]:-main}"

    log_divider
    log_error "BUILD FAILED with exit code ${exit_code}"
    log_error "Stage    : ${ERROR_STAGE:-unknown}"
    log_error "Line     : ${ERROR_LINE}"
    log_error "Stack    :${stack}"
    log_divider

    # Extract error lines to dedicated file
    if [[ -f "$LOG_FILE" ]]; then
        grep -E "(error:|Error|FAILED|undefined reference|multiple definition|fatal:)" \
            "$LOG_FILE" 2>/dev/null | \
            sed 's/\x1b\[[0-9;]*m//g' > "$ERR_LOG" || true
        local err_lines
        err_lines=$(wc -l < "$ERR_LOG" 2>/dev/null || echo "0")
        log_error "Error log: $ERR_LOG ($err_lines lines)"
    fi

    tg_notify_error
    exit "$exit_code"
}

trap 'on_error $LINENO' ERR

# ═══════════════════════════ PRE-BUILD CHECKS ═════════════════════════

check_dependencies() {
    log_section "Dependency Check"
    local deps=(git make zip curl python3 md5sum sha1sum bc nproc awk)
    local missing=()
    for dep in "${deps[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            log_ok "$dep → $(command -v "$dep")"
        else
            log_warn "$dep → NOT FOUND"
            missing+=("$dep")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing deps: ${missing[*]}"
        log_error "Fix: sudo apt install ${missing[*]}"
        ERROR_STAGE="Dependency Check"
        exit 1
    fi
}

check_toolchain() {
    log_section "Toolchain Check"
    for tc in "${TC64}gcc" "${TC32}gcc" "${TC64}ld"; do
        if command -v "$tc" >/dev/null 2>&1; then
            log_ok "$tc → $(command -v "$tc")"
        else
            log_warn "$tc → NOT in PATH (build may fail)"
        fi
    done
}

check_disk_space() {
    log_section "Disk Space Check"
    local avail_kb
    avail_kb=$(df -k "$ROOTDIR" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
    local avail_gb
    avail_gb=$(echo "scale=1; $avail_kb / 1024 / 1024" | bc 2>/dev/null || echo "?")
    log_info "Available: ${avail_gb} GB in $ROOTDIR"
    if [[ "$avail_kb" -lt 5000000 ]]; then
        log_warn "Low disk space (${avail_gb} GB) — build may fail!"
    else
        log_ok "Disk OK: ${avail_gb} GB available"
    fi
}

# ═══════════════════════════ CLONE ANYKERNEL ══════════════════════════

clone_anykernel() {
    log_section "AnyKernel3 Setup"
    ERROR_STAGE="Clone AnyKernel3"
    if [[ ! -d "$ANYKERNEL_DIR" ]]; then
        log_step "Cloning AnyKernel3 (branch: mi8937)..."
        git clone --depth=1 -b mi8937 \
            https://github.com/rahmatsobrian/AnyKernel3.git \
            "$ANYKERNEL_DIR"
        log_ok "Cloned successfully"
    else
        log_info "AnyKernel3 exists — pulling latest..."
        git -C "$ANYKERNEL_DIR" pull --rebase --autostash 2>/dev/null \
            && log_ok "Up-to-date" \
            || log_warn "Pull failed — using local copy"
    fi
    log_info "AnyKernel3 commit: $(git -C "$ANYKERNEL_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
}

# ═══════════════════════════ BUILD ═══════════════════════════════════

build_kernel() {
    log_section "Kernel Build"

    [[ ! -f "Makefile" ]] && {
        log_error "Not in kernel source root! (no Makefile in $ROOTDIR)"
        ERROR_STAGE="Sanity Check"
        exit 1
    }

    # Clean old output
    ERROR_STAGE="Clean out/"
    log_step "Cleaning out/ directory..."
    rm -rf out
    log_ok "out/ cleaned"

    # Apply defconfig
    ERROR_STAGE="Apply Defconfig"
    log_step "Applying defconfig: $DEFCONFIG"
    tg_notify_defconfig
    make "${MAKE_FLAGS[@]}" "$DEFCONFIG" 2>&1
    log_ok "Defconfig OK: $DEFCONFIG"

    # Gather all info
    get_toolchain_info
    get_kernel_version
    get_system_info

    # Announce start on Telegram
    tg_notify_start
    tg_notify_compiling

    # Compile
    ERROR_STAGE="Compile Kernel"
    log_step "Starting compilation with $JOBS jobs..."
    log_divider
    BUILD_START=$(TZ=Asia/Jakarta date +%s)

    make "${MAKE_FLAGS[@]}" 2>&1

    BUILD_END=$(TZ=Asia/Jakarta date +%s)
    local diff=$((BUILD_END - BUILD_START))
    BUILD_TIME="$((diff / 60)) min $((diff % 60)) sec"

    log_divider
    log_ok "Compilation finished in ${BUILD_TIME}"

    # Stats from log
    WARNINGS_COUNT=$(grep -c " warning:" "$LOG_FILE" 2>/dev/null || echo 0)
    ERRORS_COUNT=$(grep -c " error:" "$LOG_FILE" 2>/dev/null || echo 0)
    log_info "Compiler warnings : $WARNINGS_COUNT"
    log_info "Compiler errors   : $ERRORS_COUNT"

    # Save deduped warning log
    if [[ "$WARNINGS_COUNT" -gt 0 ]]; then
        grep " warning:" "$LOG_FILE" 2>/dev/null | \
            sed 's/\x1b\[[0-9;]*m//g' | sort | uniq -c | sort -rn > "$WARN_LOG" || true
        log_info "Warning log: $WARN_LOG ($(wc -l < "$WARN_LOG") unique)"
    fi

    get_kernel_version  # Re-read post-build
    ZIP_NAME="${KERNEL_NAME}-${DEVICE}-${KERNEL_VERSION}-${DATE_TITLE}-${TIME_TITLE}.zip"
    log_info "Final zip name: $ZIP_NAME"
}

# ═══════════════════════════ PACK ════════════════════════════════════

pack_kernel() {
    log_section "Packaging Kernel"
    tg_notify_packing
    clone_anykernel

    cd "$ANYKERNEL_DIR" || { log_error "Cannot cd AnyKernel3 dir"; exit 1; }

    # Clean old artifacts
    ERROR_STAGE="Pack - Clean"
    log_step "Removing old images/zips..."
    rm -f Image* *.zip
    log_ok "Cleaned"

    # Auto-detect image type
    ERROR_STAGE="Pack - Detect Image"
    if [[ -f "$KIMG_DTB" ]]; then
        cp "$KIMG_DTB" Image.gz-dtb
        IMG_USED="Image.gz-dtb"
        IMG_SIZE=$(du -sh "$KIMG_DTB" | awk '{print $1}')
        log_ok "Image: Image.gz-dtb ($IMG_SIZE)"
    elif [[ -f "$KIMG" ]]; then
        cp "$KIMG" Image.gz
        IMG_USED="Image.gz"
        IMG_SIZE=$(du -sh "$KIMG" | awk '{print $1}')
        log_ok "Image: Image.gz ($IMG_SIZE)"
    elif [[ -f "$KIMG_RAW" ]]; then
        cp "$KIMG_RAW" Image
        IMG_USED="Image"
        IMG_SIZE=$(du -sh "$KIMG_RAW" | awk '{print $1}')
        log_ok "Image: Image raw ($IMG_SIZE)"
    else
        log_error "No kernel image found in $OUTDIR"
        log_error "  Expected: Image.gz-dtb | Image.gz | Image"
        ERROR_STAGE="Pack - No Kernel Image"
        exit 1
    fi

    # Create zip
    ERROR_STAGE="Pack - Create Zip"
    log_step "Creating flashable zip: $ZIP_NAME"
    zip -r9 "$ZIP_NAME" . \
        -x ".git*" "README.md" "*.log" "*.sh" "*.md" 2>&1 | \
        grep -E "(adding:|deflating:)" | \
        while IFS= read -r line; do log_info "  $line"; done

    # Checksums
    MD5_HASH=$(md5sum  "$ZIP_NAME" | awk '{print $1}')
    SHA1_HASH=$(sha1sum "$ZIP_NAME" | awk '{print $1}')
    ZIP_SIZE=$(du -sh   "$ZIP_NAME" | awk '{print $1}')

    log_ok "Zip  : $ZIP_NAME"
    log_ok "Size : $ZIP_SIZE"
    log_ok "MD5  : $MD5_HASH"
    log_ok "SHA1 : $SHA1_HASH"

    cd "$ROOTDIR" || exit 1
}

# ═══════════════════════════ UPLOAD ══════════════════════════════════

upload_telegram() {
    log_section "Telegram Upload"
    ERROR_STAGE="Upload - Telegram"
    local zip_path="$ANYKERNEL_DIR/$ZIP_NAME"

    if [[ ! -f "$zip_path" ]]; then
        log_warn "Zip not found: $zip_path — skipping upload"
        return 1
    fi

    tg_notify_uploading
    tg_notify_success
    log_ok "All uploads complete"
}

# ═══════════════════════════ SUMMARY ═════════════════════════════════

print_summary() {
    log_section "Final Build Summary"
    local c="${bold}${green}"
    echo -e "  ${c}Kernel Name   ${white}: ${KERNEL_NAME}"
    echo -e "  ${c}Device        ${white}: ${DEVICE} — ${DEVICE_FULL}"
    echo -e "  ${c}Kernel Ver    ${white}: ${KERNEL_VERSION}"
    echo -e "  ${c}Branch        ${white}: ${BRANCH}"
    echo -e "  ${c}Commit        ${white}: ${COMMIT_HASH} — ${COMMIT_MSG}"
    echo -e "  ${c}Author        ${white}: ${COMMIT_AUTHOR} (${COMMIT_DATE})"
    log_divider
    echo -e "  ${c}Toolchain     ${white}: ${TC_INFO}"
    echo -e "  ${c}Linker        ${white}: ${LD_INFO}"
    echo -e "  ${c}Defconfig     ${white}: ${DEFCONFIG}"
    echo -e "  ${c}Jobs          ${white}: ${JOBS}"
    log_divider
    echo -e "  ${c}Compile Time  ${white}: ${BUILD_TIME}"
    echo -e "  ${c}Build Date    ${white}: ${BUILD_DATETIME}"
    echo -e "  ${c}Warnings      ${white}: ${WARNINGS_COUNT}"
    echo -e "  ${c}Errors        ${white}: ${ERRORS_COUNT}"
    log_divider
    echo -e "  ${c}Image Used    ${white}: ${IMG_USED} (${IMG_SIZE})"
    echo -e "  ${c}Zip File      ${white}: ${ZIP_NAME}"
    echo -e "  ${c}Zip Size      ${white}: ${ZIP_SIZE}"
    echo -e "  ${c}MD5           ${white}: ${MD5_HASH}"
    echo -e "  ${c}SHA1          ${white}: ${SHA1_HASH}"
    log_divider
    echo -e "  ${c}Build Log     ${white}: $LOG_FILE"
    echo -e "  ${c}Error Log     ${white}: $ERR_LOG"
    echo -e "  ${c}Warning Log   ${white}: $WARN_LOG"
    echo ""
}

# ═══════════════════════════ MAIN ════════════════════════════════════

main() {
    log_section "ReLIFE Kernel CI — Ultra Build Script"
    log_info "Started     : $BUILD_DATETIME"
    log_info "Working dir : $ROOTDIR"
    log_info "Log file    : $LOG_FILE"
    log_info "Host        : $(uname -n) | $(uname -sr)"
    log_info "CPU         : $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo unknown)"
    log_info "RAM         : ${RAM_GB} GB"
    log_divider

    GLOBAL_START=$(TZ=Asia/Jakarta date +%s)

    check_dependencies
    check_toolchain
    check_disk_space

    build_kernel
    pack_kernel
    upload_telegram

    GLOBAL_END=$(TZ=Asia/Jakarta date +%s)
    local total=$((GLOBAL_END - GLOBAL_START))

    print_summary

    log_ok "╔══════════════════════════════════════════════════════╗"
    log_ok "║  ALL DONE in $((total / 60)) min $((total % 60)) sec"
    log_ok "║  ${ZIP_NAME}"
    log_ok "╚══════════════════════════════════════════════════════╝"
}

main "$@"