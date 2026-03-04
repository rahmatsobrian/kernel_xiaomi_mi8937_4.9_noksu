#!/bin/bash

# ================= COLOR =================
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
cyan='\033[0;36m'
white='\033[0m'

# ================= BASIC =================
KERNEL_NAME="ReLIFE"
DEVICE="mi8937"

ROOTDIR=$(pwd)
OUTDIR="$ROOTDIR/out/arch/arm64/boot"
ANYKERNEL="$ROOTDIR/AnyKernel"

THREAD=$(nproc)

# ================= TOOLCHAIN =================
TC64="aarch64-linux-gnu-"
TC32="arm-linux-gnueabi-"

# ================= TELEGRAM =================
TG_TOKEN="7443002324:AAFpDcG3_9L0Jhy4v98RCBqu2pGfznBCiDM"
TG_CHAT="-1003520316735"

# ================= DATE =================
DATE=$(TZ=Asia/Jakarta date +"%d %B %Y %H:%M WIB")
DATE_TITLE=$(TZ=Asia/Jakarta date +"%d%m%Y-%H%M")

# ================= GIT =================
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
COMMIT=$(git log --pretty=format:'%h : %s' -1 2>/dev/null)
HASH=$(git rev-parse --short HEAD 2>/dev/null)

# ================= SYSTEM =================
BUILDER=$(whoami)
HOST=$(hostname)
CPU=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d ":" -f2)

# ================= GLOBAL =================
IMAGE=""
ZIP=""
MD5=""
KERNEL_VERSION="unknown"
ANDROID_VERSION="Unknown"
KSU_VERSION="None"
SUSFS_VERSION="None"
COMPILER="Unknown"
BUILD_TIME="0"

# ================= TELEGRAM =================

tg_send() {
curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
-d chat_id="$TG_CHAT" \
-d parse_mode="Markdown" \
-d text="$1" > /dev/null
}

tg_file() {
curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendDocument" \
-F chat_id="$TG_CHAT" \
-F document=@"$1" \
-F parse_mode="Markdown" \
-F caption="$2" > /dev/null
}

# ================= DETECT =================

detect_android() {

if grep -qi android15 arch/arm64/configs/* 2>/dev/null; then
ANDROID_VERSION="Android 15"
elif grep -qi android14 arch/arm64/configs/* 2>/dev/null; then
ANDROID_VERSION="Android 14"
elif grep -qi android13 arch/arm64/configs/* 2>/dev/null; then
ANDROID_VERSION="Android 13"
elif grep -qi android12 arch/arm64/configs/* 2>/dev/null; then
ANDROID_VERSION="Android 12"
fi

}

detect_kernel_version() {

VERSION=$(grep '^VERSION =' Makefile | awk '{print $3}')
PATCH=$(grep '^PATCHLEVEL =' Makefile | awk '{print $3}')
SUBLEVEL=$(grep '^SUBLEVEL =' Makefile | awk '{print $3}')

KERNEL_VERSION="$VERSION.$PATCH.$SUBLEVEL"

}

detect_compiler() {

if command -v ${TC64}gcc >/dev/null 2>&1; then
COMPILER=$(${TC64}gcc --version | head -n1)
elif command -v clang >/dev/null 2>&1; then
COMPILER=$(clang --version | head -n1)
fi

}

detect_kernelsu() {

if grep -q "CONFIG_KSU=y" out/.config 2>/dev/null; then
KSU_VERSION="Enabled"
fi

}

detect_susfs() {

if grep -q "CONFIG_KSU_SUSFS" out/.config 2>/dev/null; then
SUSFS_VERSION="Enabled"
fi

}

# ================= BUILD =================

build_kernel() {

echo -e "${yellow}[+] Kernel build started${white}"

rm -rf out

make O=out ARCH=arm64 rahmatmsm8937hos_defconfig || exit 1

detect_android
detect_compiler
detect_kernel_version

tg_send "🚀 *Kernel CI Started*

Device : $DEVICE
Branch : $BRANCH
Android : $ANDROID_VERSION
Threads : $THREAD"

START=$(date +%s)

make -j$THREAD \
O=out \
ARCH=arm64 \
CROSS_COMPILE=$TC64 \
CROSS_COMPILE_ARM32=$TC32 \
CROSS_COMPILE_COMPAT=$TC32 \
2>&1 | tee build.log

END=$(date +%s)

BUILD_TIME=$((END-START))

detect_kernelsu
detect_susfs

}

# ================= PACK =================

pack_kernel() {

if [ -f "$OUTDIR/Image.gz-dtb" ]; then
IMAGE="Image.gz-dtb"
elif [ -f "$OUTDIR/Image.gz" ]; then
IMAGE="Image.gz"
else
echo "Kernel image not found"
exit 1
fi

if [ ! -d "$ANYKERNEL" ]; then
git clone https://github.com/rahmatsobrian/AnyKernel3 "$ANYKERNEL"
fi

cp "$OUTDIR/$IMAGE" "$ANYKERNEL/"

cd "$ANYKERNEL" || exit 1

ZIP="${KERNEL_NAME}-${DEVICE}-${KERNEL_VERSION}-${DATE_TITLE}.zip"

zip -r9 "$ZIP" . -x ".git*" "README.md"

MD5=$(md5sum "$ZIP" | awk '{print $1}')

}

# ================= EXTRA FILE =================

upload_extra() {

BOOTIMG="$OUTDIR/../../boot.img"
DTBOIMG="$OUTDIR/../../dtbo.img"

if [ -f "$BOOTIMG" ]; then
tg_file "$BOOTIMG" "boot.img"
fi

if [ -f "$DTBOIMG" ]; then
tg_file "$DTBOIMG" "dtbo.img"
fi

}

# ================= RESULT =================

send_result() {

tg_file "$ANYKERNEL/$ZIP" "

🔥 *ReLIFE Kernel Build Success*

Device : $DEVICE
Android : $ANDROID_VERSION

Kernel :
$KERNEL_VERSION

Branch :
$BRANCH

Commit :
\`$COMMIT\`

KernelSU :
$KSU_VERSION

SUSFS :
$SUSFS_VERSION

Compiler :
\`$COMPILER\`

CPU :
$CPU

Threads :
$THREAD

Build Time :
${BUILD_TIME}s

MD5 :
\`$MD5\`

Build Date :
$DATE
"

}

# ================= LOG =================

upload_log() {

if [ -f "build.log" ]; then
tg_file "build.log" "Kernel Build Log"
fi

}

# ================= RUN =================

build_kernel
pack_kernel
upload_extra
send_result
upload_log

echo -e "${green}[✓] Build Finished${white}"
