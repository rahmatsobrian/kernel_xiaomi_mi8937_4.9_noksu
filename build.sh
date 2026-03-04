#!/usr/bin/env bash

# =========================================================
# ReLIFE Kernel CI - Telegram Stable Edition
# =========================================================

# ================= PATH =================
ROOTDIR=$(pwd)
OUTDIR="$ROOTDIR/out/arch/arm64/boot"
ANYKERNEL_DIR="$ROOTDIR/AnyKernel"

KIMG_DTB="$OUTDIR/Image.gz-dtb"
KIMG="$OUTDIR/Image.gz"

# ================= TOOLCHAIN =================
TC64="aarch64-linux-gnu-"
TC32="arm-linux-gnueabi-"

# ================= DEVICE =================
KERNEL_NAME="ReLIFE"
DEVICE="mi8937"
DEVICE_FULL="Xiaomi Snapdragon 430/435"
DEFCONFIG="rahmatmsm8937hos_defconfig"

# ================= TELEGRAM =================
TG_BOT_TOKEN="7443002324:AAFpDcG3_9L0Jhy4v98RCBqu2pGfznBCiDM"
TG_CHAT_ID="-1003520316735"

# ================= DATE =================
DATE_TITLE=$(date +"%d%m%Y")
TIME_TITLE=$(date +"%H%M%S")
BUILD_DATETIME=$(date +"%d %B %Y %H:%M")

# ================= GLOBAL =================
BUILD_TIME="unknown"
KERNEL_VERSION="unknown"
KERNEL_LOCALVERSION=""
IMG_USED="unknown"
ZIP_NAME=""
MD5_HASH=""
SHA1_HASH=""
ZIP_SIZE=""

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

# ================= SUSFS =================
SUSFS_ENABLED="false"
SUSFS_DIR="N/A"

# =========================================================
# TELEGRAM FUNCTIONS
# =========================================================

send_telegram() {

MESSAGE="$1"

curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
-d chat_id="${TG_CHAT_ID}" \
--data-urlencode text="$MESSAGE" >/dev/null

}

upload_telegram() {

ZIP_PATH="$ANYKERNEL_DIR/$ZIP_NAME"

CAPTION="ReLIFE Kernel Build Success

Device : ${DEVICE}
Kernel : ${KERNEL_VERSION}

Image : ${IMG_USED}
Zip Size : ${ZIP_SIZE}

Build Time : ${BUILD_TIME}

MD5
${MD5_HASH}

SHA1
${SHA1_HASH}"

curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
-F chat_id="${TG_CHAT_ID}" \
-F document=@"${ZIP_PATH}" \
--form-string caption="$CAPTION" >/dev/null

}

# =========================================================
# INFO FUNCTIONS
# =========================================================

get_kernel_version() {

VERSION=$(grep '^VERSION =' Makefile | awk '{print $3}')
PATCHLEVEL=$(grep '^PATCHLEVEL =' Makefile | awk '{print $3}')
SUBLEVEL=$(grep '^SUBLEVEL =' Makefile | awk '{print $3}')

KERNEL_VERSION="${VERSION}.${PATCHLEVEL}.${SUBLEVEL}"

}

get_localversion() {

if [ -f "out/.config" ]; then
KERNEL_LOCALVERSION=$(grep CONFIG_LOCALVERSION out/.config | cut -d'"' -f2)
fi

}

get_toolchain_info() {

if command -v "${TC64}gcc" >/dev/null 2>&1; then
TC_INFO=$("${TC64}gcc" --version | head -1)
fi

if command -v "${TC64}ld" >/dev/null 2>&1; then
LD_INFO=$("${TC64}ld" --version | head -1)
fi

}

get_kernelsu_info() {

for d in KernelSU kernelsu drivers/kernelsu fs/kernelsu; do
if [ -d "$ROOTDIR/$d" ]; then
KSU_ENABLED="true"
break
fi
done

}

get_susfs_info() {

for d in susfs fs/susfs drivers/susfs security/susfs; do
if [ -d "$ROOTDIR/$d" ]; then
SUSFS_ENABLED="true"
SUSFS_DIR="$d"
break
fi
done

}

# =========================================================
# TELEGRAM START MESSAGE
# =========================================================

send_telegram_start() {

if [ "$DIRTY_COUNT" -gt 0 ]; then
TREE_STATUS="Dirty ($DIRTY_COUNT files)"
else
TREE_STATUS="Clean"
fi

MSG="ReLIFE Kernel Build Started
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Device : ${DEVICE} — ${DEVICE_FULL}
Kernel Version : ${KERNEL_VERSION}
Localversion : ${KERNEL_LOCALVERSION}

KernelSU : $([ "$KSU_ENABLED" = "true" ] && echo "Enabled" || echo "Not Found")
Variant : ${KSU_VARIANT}

SUSFS : $([ "$SUSFS_ENABLED" = "true" ] && echo "Enabled" || echo "Not Found")
Directory : ${SUSFS_DIR}

Source Info
Branch : ${BRANCH}
Commit : ${COMMIT_HASH}
Message : ${COMMIT_MSG}
Author : ${COMMIT_AUTHOR}
Date : ${COMMIT_DATE}
Commits : ${TOTAL_COMMITS}
Tree : ${TREE_STATUS}

Build Config
Compiler : ${TC_INFO}
Linker : ${LD_INFO}
Defconfig : ${DEFCONFIG}
Jobs : ${HOST_CORES}

Host Machine
Hostname : ${HOST_NAME}
CPU : ${HOST_CPU}
Cores : ${HOST_CORES}
RAM : ${RAM_FREE} / ${RAM_TOTAL}
Disk : ${DISK_FREE} / ${DISK_TOTAL}
OS : ${HOST_OS}

Start Time : ${BUILD_DATETIME}"

send_telegram "$MSG"

}

# =========================================================
# BUILD
# =========================================================

build_kernel() {

echo "Building kernel..."

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
# PACK
# =========================================================

pack_kernel() {

if [ ! -d "$ANYKERNEL_DIR" ]; then
git clone -b mi8937 https://github.com/rahmatsobrian/AnyKernel3.git "$ANYKERNEL_DIR"
fi

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
# RUN
# =========================================================

START=$(date +%s)

build_kernel
pack_kernel
upload_telegram

END=$(date +%s)

echo "Done in $((END - START)) seconds"
