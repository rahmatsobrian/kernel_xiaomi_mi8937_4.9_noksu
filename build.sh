#!/bin/bash
# ================================================================
#  ReLIFE Kernel Build Script
#  Telegram-first: semua info penting masuk ke Telegram
# ================================================================

# ================= COLOR =================
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
white='\033[0m'

# ================= PATH =================
ROOTDIR=$(pwd)
OUTDIR="$ROOTDIR/out/arch/arm64/boot"
ANYKERNEL_DIR="$ROOTDIR/AnyKernel"
LOG_DIR="$ROOTDIR/build_logs"
LOG_FILE="$LOG_DIR/build_$(date +%Y%m%d_%H%M%S).log"

KIMG_DTB="$OUTDIR/Image.gz-dtb"
KIMG="$OUTDIR/Image.gz"
KIMG_RAW="$OUTDIR/Image"

# ================= TOOLCHAIN =================
TC64="aarch64-linux-gnu-"
TC32="arm-linux-gnueabi-"

# ================= DEFCONFIG =================
# DEFCONFIG="rahmatmsm8937hos_defconfig"
DEFCONFIG="rahmatmsm8937_defconfig"

# ================= INFO =================
KERNEL_NAME="ReLIFE"
DEVICE="mi8937"
DEVICE_FULL="Xiaomi Snapdragon 430/435"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
COMMIT_MSG=$(git log --format="%s" -1 2>/dev/null || echo "unknown")
COMMIT_AUTHOR=$(git log --format="%an" -1 2>/dev/null || echo "unknown")
TOTAL_COMMITS=$(git rev-list --count HEAD 2>/dev/null || echo "?")

# ================= DATE (WIB) =================
DATE_TITLE=$(TZ=Asia/Jakarta date +"%d%m%Y")
TIME_TITLE=$(TZ=Asia/Jakarta date +"%H%M%S")
BUILD_DATETIME=$(TZ=Asia/Jakarta date +"%d %B %Y, %H:%M WIB")

# ================= TELEGRAM =================
TG_BOT_TOKEN="7443002324:AAFpDcG3_9L0Jhy4v98RCBqu2pGfznBCiDM"
TG_CHAT_ID="-1003520316735"

# ================= GLOBAL =================
BUILD_TIME="unknown"
KERNEL_VERSION="unknown"
TC_INFO="unknown"
LD_INFO="unknown"
IMG_USED="unknown"
IMG_SIZE="unknown"
MD5_HASH="unknown"
SHA1_HASH="unknown"
ZIP_SIZE="unknown"
ZIP_NAME=""
TG_MSG_ID=""
ERROR_STAGE=""
WARNINGS=0
JOBS=$(nproc --all)
RAM_GB=$(awk '/MemTotal/{printf "%.0f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "?")

# ================================================================
#  TELEGRAM CORE
# ================================================================

# Kirim pesan baru, simpan message_id ke TG_MSG_ID
tg_send() {
    local text="$1"
    local resp
    resp=$(curl -s --max-time 30 -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "parse_mode=Markdown" \
        -d "disable_web_page_preview=true" \
        --data-urlencode "text=${text}")
    # Ambil message_id dari response
    echo "$resp" | python3 -c \
        "import sys,json; d=json.load(sys.stdin); print(d['result']['message_id'] if d.get('ok') else '')" \
        2>/dev/null || echo ""
}

# Edit pesan yang sudah ada (pakai TG_MSG_ID)
tg_edit() {
    [[ -z "$TG_MSG_ID" ]] && return
    local text="$1"
    curl -s --max-time 30 -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/editMessageText" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "message_id=${TG_MSG_ID}" \
        -d "parse_mode=Markdown" \
        -d "disable_web_page_preview=true" \
        --data-urlencode "text=${text}" > /dev/null
}

# Upload file ke Telegram
tg_upload() {
    local file="$1"
    local caption="${2:-}"
    [[ ! -f "$file" ]] && { echo -e "${red}[!] File tidak ada: $file${white}"; return 1; }
    echo -e "${yellow}[TG]${white} Upload: $(basename "$file") ($(du -sh "$file" | awk '{print $1}'))"
    curl -s --max-time 180 -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
        -F "chat_id=${TG_CHAT_ID}" \
        -F "document=@${file};filename=$(basename "$file")" \
        -F "parse_mode=Markdown" \
        ${caption:+--form-string "caption=${caption}"} > /dev/null \
        && echo -e "${green}[✓] Upload selesai: $(basename "$file")${white}" \
        || echo -e "${red}[!] Upload gagal: $(basename "$file")${white}"
}

# ================================================================
#  NOTIFIKASI TELEGRAM — per stage
# ================================================================

# Dipanggil sebelum kompilasi dimulai
notify_start() {
    echo -e "${yellow}[TG]${white} Kirim notif START..."
    TG_MSG_ID=$(tg_send "🚀 *ReLIFE Kernel — Build Dimulai*

📱 *Device*        : \`${DEVICE}\` — ${DEVICE_FULL}
📦 *Kernel*        : ${KERNEL_NAME}
🍃 *Versi*         : \`${KERNEL_VERSION}\`

🌿 *Branch*        : \`${BRANCH}\`
🔖 *Commit*        : \`${COMMIT_HASH}\`
💬 *Pesan Commit*  : ${COMMIT_MSG}
👤 *Author*        : ${COMMIT_AUTHOR}
📊 *Total Commit*  : ${TOTAL_COMMITS}

🛠 *Toolchain*     : ${TC_INFO}
🔗 *Linker*        : ${LD_INFO}
🔧 *Defconfig*     : \`${DEFCONFIG}\`
⚙️ *Jobs*          : ${JOBS} thread
🖥 *RAM Host*      : ${RAM_GB} GB

🕒 *Mulai*         : ${BUILD_DATETIME}")
    echo -e "${green}[✓] Notif START terkirim (ID: $TG_MSG_ID)${white}"
}

# Edit pesan → status sedang compile
notify_compiling() {
    tg_edit "🔨 *ReLIFE Kernel — Sedang Dikompilasi...*

📱 *Device*    : \`${DEVICE}\`
🍃 *Versi*     : \`${KERNEL_VERSION}\`
🌿 *Branch*    : \`${BRANCH}\`
🔖 *Commit*    : \`${COMMIT_HASH}\`
🛠 *Toolchain* : ${TC_INFO}
⚙️ *Jobs*      : ${JOBS} thread

⏳ *Status*    : Kompilasi berjalan, harap tunggu...
🕒 *Mulai*     : ${BUILD_DATETIME}"
}

# Edit pesan → status packing zip
notify_packing() {
    tg_edit "📦 *ReLIFE Kernel — Membuat Zip...*

📱 *Device*        : \`${DEVICE}\`
🍃 *Versi*         : \`${KERNEL_VERSION}\`
⏱ *Waktu Compile* : ${BUILD_TIME}
🖼 *Image*         : \`${IMG_USED}\` (${IMG_SIZE})
⚠️ *Warnings*      : ${WARNINGS}

⏳ *Status*        : Membuat flashable zip..."
}

# Edit pesan → status uploading
notify_uploading() {
    tg_edit "📤 *ReLIFE Kernel — Mengupload...*

📱 *Device*        : \`${DEVICE}\`
📁 *File*          : \`${ZIP_NAME}\`
📏 *Ukuran*        : ${ZIP_SIZE}
⏱ *Waktu Compile* : ${BUILD_TIME}

⏳ *Status*        : Mengupload kernel ke Telegram..."
}

# Upload kernel zip + log, edit pesan ke summary final
notify_success() {
    local zip_path="$ANYKERNEL_DIR/$ZIP_NAME"
    local warn_note=""
    [[ "$WARNINGS" -gt 0 ]] && warn_note="
⚠️ *Warnings*       : ${WARNINGS} (warning log terlampir)"

    local caption="✅ *ReLIFE Kernel — Build Berhasil!*

📱 *Device*         : \`${DEVICE}\` — ${DEVICE_FULL}
📦 *Kernel*         : ${KERNEL_NAME}
🍃 *Versi Kernel*   : \`${KERNEL_VERSION}\`

🌿 *Branch*         : \`${BRANCH}\`
🔖 *Commit*         : \`${COMMIT_HASH}\`
💬 *Pesan Commit*   : ${COMMIT_MSG}
👤 *Author*         : ${COMMIT_AUTHOR}

🛠 *Toolchain*      : ${TC_INFO}
🔗 *Linker*         : ${LD_INFO}
🔧 *Defconfig*      : \`${DEFCONFIG}\`
🖼 *Image*          : \`${IMG_USED}\` (${IMG_SIZE})

⏱ *Waktu Compile*  : ${BUILD_TIME}
🕒 *Tanggal Build*  : ${BUILD_DATETIME}
${warn_note}
📁 *File*           : \`${ZIP_NAME}\`
📏 *Ukuran*         : ${ZIP_SIZE}
🔐 *MD5*            :
\`${MD5_HASH}\`
🔑 *SHA1*           :
\`${SHA1_HASH}\`

⚡ *Flash via TWRP / Custom Recovery*"

    # 1. Upload kernel zip
    tg_upload "$zip_path" "$caption"

    # 2. Upload build log
    tg_upload "$LOG_FILE" \
"📋 *Full Build Log* — ${KERNEL_NAME} \`${KERNEL_VERSION}\`
Branch: \`${BRANCH}\` | Commit: \`${COMMIT_HASH}\`
Warnings: ${WARNINGS} | Waktu: ${BUILD_TIME}"

    # 3. Upload warning log jika ada
    local warn_log="$LOG_DIR/warnings.log"
    if [[ "$WARNINGS" -gt 0 ]] && [[ -f "$warn_log" ]] && [[ -s "$warn_log" ]]; then
        tg_upload "$warn_log" \
"⚠️ *Warning Summary* — ${WARNINGS} warnings
${KERNEL_NAME} \`${KERNEL_VERSION}\` | \`${COMMIT_HASH}\`"
    fi

    # 4. Edit pesan awal ke ringkasan final
    tg_edit "✅ *Build Selesai — ${KERNEL_NAME} \`${KERNEL_VERSION}\`*

📦 \`${ZIP_NAME}\`
📏 Ukuran        : ${ZIP_SIZE}
⏱ Waktu Compile : ${BUILD_TIME}
⚠️ Warnings      : ${WARNINGS}
🔐 MD5           : \`${MD5_HASH}\`
🕒 Selesai       : $(TZ=Asia/Jakarta date +"%d %B %Y, %H:%M WIB")"
}

# Notif error + upload log
notify_error() {
    local stage="${ERROR_STAGE:-unknown}"
    local line="${1:-?}"

    # Ambil 15 baris error terakhir dari log
    local last_err="Tidak ada error yang tertangkap"
    if [[ -f "$LOG_FILE" ]]; then
        local raw
        raw=$(grep -E "(error:|Error|FAILED|undefined reference|fatal:)" \
            "$LOG_FILE" 2>/dev/null | tail -15 | \
            sed 's/\x1b\[[0-9;]*m//g' | sed "s/\`/'/g" | \
            awk '{print NR". "$0}' || true)
        [[ -n "$raw" ]] && last_err="$raw"
        [[ ${#last_err} -gt 800 ]] && \
            last_err="${last_err:0:800}
..._(terpotong, lihat log lengkap)_"
    fi

    # Edit pesan awal ke status GAGAL
    tg_edit "❌ *Build GAGAL — \`${stage}\`*

📱 Device   : \`${DEVICE}\`
🌿 Branch   : \`${BRANCH}\`
🔖 Commit   : \`${COMMIT_HASH}\`
💥 Gagal di : \`${stage}\`
📍 Baris    : ${line}
⚠️ Warnings : ${WARNINGS}
🕒 Waktu    : $(TZ=Asia/Jakarta date +"%H:%M WIB")

📋 Log lengkap terlampir di bawah..."

    # Kirim pesan detail error (pesan baru)
    tg_send "❌ *ReLIFE Kernel — Build GAGAL*

📱 *Device*       : \`${DEVICE}\` — ${DEVICE_FULL}
📦 *Kernel*       : ${KERNEL_NAME}
🌿 *Branch*       : \`${BRANCH}\`
🔖 *Commit*       : \`${COMMIT_HASH}\`
💬 *Pesan Commit* : ${COMMIT_MSG}
👤 *Author*       : ${COMMIT_AUTHOR}

🛠 *Toolchain*    : ${TC_INFO}
🔧 *Defconfig*    : \`${DEFCONFIG}\`

💥 *Gagal di*     : \`${stage}\`
📍 *Baris Script* : ${line}
⚠️ *Warnings*     : ${WARNINGS}
🕒 *Waktu*        : ${BUILD_DATETIME}

🔴 *Baris Error Terakhir:*
\`\`\`
${last_err}
\`\`\`" > /dev/null

    # Upload full build log
    if [[ -f "$LOG_FILE" ]]; then
        tg_upload "$LOG_FILE" \
"❌ *Full Build Log — GAGAL*
Stage: \`${stage}\` | Baris: ${line}
${KERNEL_NAME} | Branch: \`${BRANCH}\` | Commit: \`${COMMIT_HASH}\`
Warnings: ${WARNINGS}"
    fi

    # Upload filtered error log
    local err_log="$LOG_DIR/errors.log"
    grep -E "(error:|Error|FAILED|undefined reference|multiple definition|fatal:)" \
        "$LOG_FILE" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' > "$err_log" || true
    if [[ -s "$err_log" ]]; then
        tg_upload "$err_log" \
"🔴 *Filtered Error Log* — $(wc -l < "$err_log") baris error
${KERNEL_NAME} | Stage: \`${stage}\` | \`${COMMIT_HASH}\`"
    fi
}

# ================================================================
#  ERROR TRAP
# ================================================================

on_error() {
    local exit_code=$?
    local line="$1"
    echo -e "${red}[FAIL]${white} Script gagal di baris ${line} (exit ${exit_code})"
    echo -e "${red}[FAIL]${white} Stage: ${ERROR_STAGE:-unknown}"
    notify_error "$line"
    exit "$exit_code"
}

trap 'on_error $LINENO' ERR
set -Eeuo pipefail

# ================================================================
#  HELPER
# ================================================================

get_toolchain_info() {
    if command -v "${TC64}gcc" >/dev/null 2>&1; then
        local ver; ver=$("${TC64}gcc" -dumpversion)
        TC_INFO="GCC ${ver}"
        LD_INFO=$("${TC64}ld" --version 2>/dev/null | head -1 | awk '{print $NF}' || echo "unknown")
    elif command -v gcc >/dev/null 2>&1; then
        local ver; ver=$(gcc -dumpversion)
        TC_INFO="GCC ${ver} (host)"
        LD_INFO="unknown"
    else
        TC_INFO="unknown"
        LD_INFO="unknown"
    fi
}

get_kernel_version() {
    if [[ -f "Makefile" ]]; then
        local v p s e
        v=$(awk '/^VERSION\s*=/{print $3; exit}' Makefile)
        p=$(awk '/^PATCHLEVEL\s*=/{print $3; exit}' Makefile)
        s=$(awk '/^SUBLEVEL\s*=/{print $3; exit}' Makefile)
        e=$(awk '/^EXTRAVERSION\s*=/{print $3; exit}' Makefile 2>/dev/null || echo "")
        KERNEL_VERSION="${v}.${p}.${s}${e}"
    else
        KERNEL_VERSION="unknown"
    fi
}

# ================================================================
#  CLONE ANYKERNEL
# ================================================================

clone_anykernel() {
    if [[ ! -d "$ANYKERNEL_DIR" ]]; then
        echo -e "${yellow}[+] Cloning AnyKernel3...${white}"
        git clone --depth=1 -b mi8937 \
            https://github.com/rahmatsobrian/AnyKernel3.git \
            "$ANYKERNEL_DIR"
        echo -e "${green}[✓] AnyKernel3 cloned${white}"
    else
        echo -e "${yellow}[+] Updating AnyKernel3...${white}"
        git -C "$ANYKERNEL_DIR" pull --rebase --autostash 2>/dev/null \
            && echo -e "${green}[✓] AnyKernel3 updated${white}" \
            || echo -e "${yellow}[!] Pull gagal, pakai lokal${white}"
    fi
}

# ================================================================
#  BUILD
# ================================================================

build_kernel() {
    echo -e "${yellow}════════════════════════════${white}"
    echo -e "${yellow}  BUILD KERNEL${white}"
    echo -e "${yellow}════════════════════════════${white}"

    [[ ! -f "Makefile" ]] && {
        ERROR_STAGE="Sanity Check"
        echo -e "${red}[!] Bukan di root kernel source!${white}"
        exit 1
    }

    # Bersihkan output lama
    ERROR_STAGE="Clean"
    echo -e "${yellow}[+] Membersihkan out/...${white}"
    rm -rf out
    echo -e "${green}[✓] out/ bersih${white}"

    # Apply defconfig
    ERROR_STAGE="Defconfig"
    echo -e "${yellow}[+] Applying: $DEFCONFIG${white}"
    make O=out ARCH=arm64 "$DEFCONFIG" 2>&1 | tee -a "$LOG_FILE"
    echo -e "${green}[✓] Defconfig OK${white}"

    # Kumpulkan info toolchain & versi
    get_toolchain_info
    get_kernel_version

    # Kirim notif START ke Telegram
    notify_start

    # Mulai compile
    ERROR_STAGE="Compile"
    echo -e "${yellow}[+] Kompilasi dimulai ($JOBS jobs)...${white}"
    notify_compiling

    BUILD_START=$(TZ=Asia/Jakarta date +%s)

    make -j"$JOBS" O=out ARCH=arm64 \
        CROSS_COMPILE="$TC64" \
        CROSS_COMPILE_ARM32="$TC32" \
        CROSS_COMPILE_COMPAT="$TC32" \
        2>&1 | tee -a "$LOG_FILE"

    BUILD_END=$(TZ=Asia/Jakarta date +%s)
    local diff=$((BUILD_END - BUILD_START))
    BUILD_TIME="$((diff / 60)) min $((diff % 60)) sec"

    # Hitung warnings dari log
    WARNINGS=$(grep -c " warning:" "$LOG_FILE" 2>/dev/null || echo 0)

    # Simpan warning log (unique + sorted by count)
    if [[ "$WARNINGS" -gt 0 ]]; then
        grep " warning:" "$LOG_FILE" 2>/dev/null | \
            sed 's/\x1b\[[0-9;]*m//g' | sort | uniq -c | sort -rn \
            > "$LOG_DIR/warnings.log" || true
    fi

    get_kernel_version  # re-read post build
    ZIP_NAME="${KERNEL_NAME}-${DEVICE}-${KERNEL_VERSION}-${DATE_TITLE}-${TIME_TITLE}.zip"

    echo -e "${green}[✓] Kompilasi selesai: ${BUILD_TIME}${white}"
    echo -e "${green}[✓] Warnings: ${WARNINGS}${white}"
    echo -e "${green}[✓] Zip name: ${ZIP_NAME}${white}"
}

# ================================================================
#  PACK
# ================================================================

pack_kernel() {
    echo -e "${yellow}════════════════════════════${white}"
    echo -e "${yellow}  PACK KERNEL${white}"
    echo -e "${yellow}════════════════════════════${white}"

    clone_anykernel
    cd "$ANYKERNEL_DIR" || exit 1

    echo -e "${yellow}[+] Membersihkan file lama...${white}"
    rm -f Image* *.zip

    # Deteksi image yang tersedia
    ERROR_STAGE="Detect Image"
    if [[ -f "$KIMG_DTB" ]]; then
        cp "$KIMG_DTB" Image.gz-dtb
        IMG_USED="Image.gz-dtb"
        IMG_SIZE=$(du -sh "$KIMG_DTB" | awk '{print $1}')
    elif [[ -f "$KIMG" ]]; then
        cp "$KIMG" Image.gz
        IMG_USED="Image.gz"
        IMG_SIZE=$(du -sh "$KIMG" | awk '{print $1}')
    elif [[ -f "$KIMG_RAW" ]]; then
        cp "$KIMG_RAW" Image
        IMG_USED="Image"
        IMG_SIZE=$(du -sh "$KIMG_RAW" | awk '{print $1}')
    else
        echo -e "${red}[!] Tidak ada kernel image!${white}"
        echo -e "${red}    Expected: Image.gz-dtb | Image.gz | Image${white}"
        ERROR_STAGE="No Kernel Image"
        exit 1
    fi

    echo -e "${green}[✓] Image: $IMG_USED ($IMG_SIZE)${white}"

    # Update status TG → packing
    notify_packing

    # Buat zip
    ERROR_STAGE="Create Zip"
    echo -e "${yellow}[+] Membuat zip: $ZIP_NAME${white}"
    zip -r9 "$ZIP_NAME" . -x ".git*" "README.md" "*.log" "*.sh"

    MD5_HASH=$(md5sum  "$ZIP_NAME" | awk '{print $1}')
    SHA1_HASH=$(sha1sum "$ZIP_NAME" | awk '{print $1}')
    ZIP_SIZE=$(du -sh   "$ZIP_NAME" | awk '{print $1}')

    echo -e "${green}[✓] Zip: $ZIP_NAME${white}"
    echo -e "${green}[✓] Ukuran: $ZIP_SIZE${white}"
    echo -e "${green}[✓] MD5: $MD5_HASH${white}"
    echo -e "${green}[✓] SHA1: $SHA1_HASH${white}"

    cd "$ROOTDIR" || exit 1
}

# ================================================================
#  UPLOAD
# ================================================================

upload_kernel() {
    echo -e "${yellow}════════════════════════════${white}"
    echo -e "${yellow}  UPLOAD KE TELEGRAM${white}"
    echo -e "${yellow}════════════════════════════${white}"

    ERROR_STAGE="Upload Telegram"
    local zip_path="$ANYKERNEL_DIR/$ZIP_NAME"

    [[ ! -f "$zip_path" ]] && {
        echo -e "${red}[!] Zip tidak ditemukan: $zip_path${white}"
        return 1
    }

    notify_uploading
    notify_success

    echo -e "${green}[✓] Semua upload ke Telegram selesai!${white}"
}

# ================================================================
#  MAIN
# ================================================================

mkdir -p "$LOG_DIR"

# Semua output masuk log (strip ANSI di file log)
exec > >(tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE")) \
     2> >(tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE") >&2)

GLOBAL_START=$(TZ=Asia/Jakarta date +%s)

echo -e "${yellow}╔══════════════════════════════════════╗${white}"
echo -e "${yellow}║   ReLIFE Kernel Build Script         ║${white}"
echo -e "${yellow}║   Log: $LOG_FILE${white}"
echo -e "${yellow}╚══════════════════════════════════════╝${white}"

build_kernel
pack_kernel
upload_kernel

GLOBAL_END=$(TZ=Asia/Jakarta date +%s)
echo -e "${green}[✓] Total waktu: $((GLOBAL_END - GLOBAL_START)) detik${white}"
