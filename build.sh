#!/usr/bin/env bash

# =========================================================
#        ReLIFE Kernel CI - Ultimate Build Script
# =========================================================

# ================= COLOR =================
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
white='\033[0m'

# ================= PATH =================
ROOTDIR=$(pwd)
OUTDIR="$ROOTDIR/out/arch/arm64/boot"
ANYKERNEL_DIR="$ROOTDIR/AnyKernel"

KIMG_DTB="$OUTDIR/Image.gz-dtb"
KIMG="$OUTDIR/Image.gz"

# ================= TOOLCHAIN =================
TC64="aarch64-linux-gnu-"
TC32="arm-linux-gnueabi-"

# ================= DEVICE INFO =================
KERNEL_NAME="ReLIFE"
DEVICE="mi8937"
DEVICE_FULL="Xiaomi Snapdragon 430/435"
DEFCONFIG="rahmatmsm8937hos_defconfig"

# ================= TELEGRAM =================
TG_BOT_TOKEN="7443002324:AAFpDcG3_9L0Jhy4v98RCBqu2pGfznBCiDM"
TG_CHAT_ID="-1003520316735"

# ================= DATE =================
DATE_TITLE=$(TZ=Asia/Jakarta date +"%d%m%Y")
TIME_TITLE=$(TZ=Asia/Jakarta date +"%H%M%S")
BUILD_DATETIME=$(TZ=Asia/Jakarta date +"%d %B %Y %H:%M WIB")

# ================= GLOBAL =================
BUILD_TIME="unknown"
KERNEL_VERSION="unknown"
KERNEL_LOCALVERSION=""
ZIP_NAME=""
IMG_USED="unknown"
MD5_HASH="unknown"
SHA1_HASH="unknown"
ZIP_SIZE="unknown"

# ================= MACHINE INFO =================
HOST_NAME=$(hostname)
HOST_OS=$(uname -sr)
HOST_CPU=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)
HOST_CORES=$(nproc)
RAM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
RAM_FREE=$(free -h | awk '/Mem:/ {print $7}')
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')

# ================= GIT INFO =================
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null)
COMMIT_MSG=$(git log --format="%s" -1 2>/dev/null)
COMMIT_AUTHOR=$(git log --format="%an" -1 2>/dev/null)
COMMIT_DATE=$(git log --format="%cd" --date=format:"%d %b %Y %H:%M" -1 2>/dev/null)
TOTAL_COMMITS=$(git rev-list --count HEAD 2>/dev/null)
DIRTY_COUNT=$(git status --porcelain | wc -l)

# ================= KERNELSU =================
KSU_ENABLED="false"
KSU_VERSION="N/A"
KSU_VARIANT="KernelSU-Next"
KSU_MANAGER_VER="N/A"

# ================= SUSFS =================
SUSFS_ENABLED="false"
SUSFS_DIR="N/A"
SUSFS_GIT_COMMIT="N/A"

# =========================================================
# FUNCTIONS
# =========================================================

clone_anykernel() {

if [ ! -d "$ANYKERNEL_DIR" ]; then
echo -e "$yellow[+] Cloning AnyKernel3...$white"
git clone -b mi8937 https://github.com/rahmatsobrian/AnyKernel3.git "$ANYKERNEL_DIR" || exit 1
fi

}

# =========================================================

get_kernel_version() {

VERSION=$(grep '^VERSION =' Makefile | awk '{print $3}')
PATCHLEVEL=$(grep '^PATCHLEVEL =' Makefile | awk '{print $3}')
SUBLEVEL=$(grep '^SUBLEVEL =' Makefile | awk '{print $3}')

KERNEL_VERSION="${VERSION}.${PATCHLEVEL}.${SUBLEVEL}"

}

# =========================================================

get_localversion() {

if [ -f "out/.config" ]; then
KERNEL_LOCALVERSION=$(grep CONFIG_LOCALVERSION out/.config | cut -d'"' -f2)
fi

}

# =========================================================

get_toolchain_info() {

if command -v "${TC64}gcc" >/dev/null 2>&1; then
TC_INFO=$("${TC64}gcc" --version | head -1)
fi

if command -v "${TC64}ld" >/dev/null 2>&1; then
LD_INFO=$("${TC64}ld" --version | head -1)
fi

}

# =========================================================

get_kernelsu_info() {

for d in "KernelSU" "kernelsu" "drivers/kernelsu" "fs/kernelsu"; do
if [ -d "$ROOTDIR/$d" ]; then
KSU_ENABLED="true"

if git -C "$ROOTDIR/$d" rev-parse --git-dir >/dev/null 2>&1; then
KSU_VERSION=$(git -C "$ROOTDIR/$d" describe --tags --abbrev=0 2>/dev/null)
fi

break
fi
done

}

# =========================================================

get_susfs_info() {

for d in "susfs" "fs/susfs" "drivers/susfs" "security/susfs"; do
if [ -d "$ROOTDIR/$d" ]; then
SUSFS_ENABLED="true"
SUSFS_DIR="$d"

if git -C "$ROOTDIR/$d" rev-parse --git-dir >/dev/null 2>&1; then
SUSFS_GIT_COMMIT=$(git -C "$ROOTDIR/$d" rev-parse --short HEAD)
fi

break
fi
done

}

# =========================================================

send_telegram_start() {

if [ "$DIRTY_COUNT" -gt 0 ]; then
TREE_STATUS="⚠️ ${DIRTY_COUNT} modified files"
else
TREE_STATUS="✅ Bersih"
fi

curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
-d chat_id="${TG_CHAT_ID}" \
-d parse_mode=Markdown \
-d text="🚀 *ReLIFE Kernel — Build Dimulai*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📱 Device        : ${DEVICE} — ${DEVICE_FULL}
🍃 Versi Kernel  : ${KERNEL_VERSION}
🏷 Localversion  : ${KERNEL_LOCALVERSION}

🔑 KernelSU      : $([ "$KSU_ENABLED" = "true" ] && echo "✅ Aktif" || echo "❌ Tidak ada")
   Variant       : ${KSU_VARIANT}
   Versi         : ${KSU_VERSION}

🛡 SUSFS         : $([ "$SUSFS_ENABLED" = "true" ] && echo "✅ Aktif" || echo "❌ Tidak ada")
   Directory     : ${SUSFS_DIR}
   Commit        : ${SUSFS_GIT_COMMIT}

📂 Source Info
🌿 Branch        : ${BRANCH}
🔖 Commit        : ${COMMIT_HASH}
💬 Pesan Commit  : ${COMMIT_MSG}
👤 Author        : ${COMMIT_AUTHOR}
📅 Tgl Commit    : ${COMMIT_DATE}
📊 Total Commit  : ${TOTAL_COMMITS}
🗂 Status Tree   : ${TREE_STATUS}

🛠 Build Config
⚙️ Compiler      : ${TC_INFO}
🔗 Linker        : ${LD_INFO}
🔧 Defconfig     : ${DEFCONFIG}
🖥 Jobs          : ${HOST_CORES} thread

💻 Host Machine
🖥 Hostname      : ${HOST_NAME}
⚙️ CPU           : ${HOST_CPU}
🧠 Cores         : ${HOST_CORES}
💾 RAM           : ${RAM_FREE} free / ${RAM_TOTAL} total
💿 Disk          : ${DISK_FREE} free / ${DISK_TOTAL}
🐧 OS            : ${HOST_OS}

🕒 Mulai         : ${BUILD_DATETIME}"
}

# =========================================================

build_kernel() {

echo -e "$yellow[+] Building kernel...$white"

rm -rf out

make O=out ARCH=arm64 ${DEFCONFIG} || exit 1

get_kernel_version
get_localversion
get_toolchain_info
get_kernelsu_info
get_susfs_info

send_telegram_start

BUILD_START=$(date +%s)

make -j$(nproc) O=out ARCH=arm64 \
CROSS_COMPILE=$TC64 \
CROSS_COMPILE_ARM32=$TC32 \
CROSS_COMPILE_COMPAT=$TC32 || exit 1

BUILD_END=$(date +%s)

DIFF=$((BUILD_END - BUILD_START))
BUILD_TIME="$((DIFF / 60))m $((DIFF % 60))s"

ZIP_NAME="${KERNEL_NAME}-${DEVICE}-${KERNEL_VERSION}-${DATE_TITLE}-${TIME_TITLE}.zip"

}

# =========================================================

pack_kernel() {

clone_anykernel

cd "$ANYKERNEL_DIR" || exit 1

rm -f Image* *.zip

if [ -f "$KIMG_DTB" ]; then
cp "$KIMG_DTB" Image.gz-dtb
IMG_USED="Image.gz-dtb"
elif [ -f "$KIMG" ]; then
cp "$KIMG" Image.gz
IMG_USED="Image.gz"
else
exit 1
fi

zip -r9 "$ZIP_NAME" . -x ".git*" "README.md"

MD5_HASH=$(md5sum "$ZIP_NAME" | awk '{print $1}')
SHA1_HASH=$(sha1sum "$ZIP_NAME" | awk '{print $1}')
ZIP_SIZE=$(du -h "$ZIP_NAME" | awk '{print $1}')

}

# =========================================================

upload_telegram() {

ZIP_PATH="$ANYKERNEL_DIR/$ZIP_NAME"

curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
-F chat_id="${TG_CHAT_ID}" \
-F document=@"${ZIP_PATH}" \
-F parse_mode=Markdown \
-F caption="✅ *ReLIFE Kernel Build Success*

📱 Device : ${DEVICE}
🍃 Kernel : ${KERNEL_VERSION}

🖼 Image  : ${IMG_USED}
📦 Zip    : ${ZIP_SIZE}

⏱ Build Time : ${BUILD_TIME}

🔐 MD5
\`${MD5_HASH}\`

🔑 SHA1
\`${SHA1_HASH}\`"

}

# =========================================================
# RUN
# =========================================================

START=$(date +%s)

build_kernel
pack_kernel
upload_telegram

END=$(date +%s)

echo -e "$green[✓] Done in $((END - START)) seconds$white"
