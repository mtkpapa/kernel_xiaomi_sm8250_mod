#!/bin/bash

# Some logics of this script are copied from [scripts/build_kernel]. Thanks to UtsavBalar1231.

# Ensure the script exits on error
set -e

TARGET_DEVICE=$1

if [ -z "$1" ]; then
    echo "Error: No argument provided, please specific a target device." 
    echo "If you need KernelSU, please add [ksu] as the second arg."
    echo "Examples:"
    echo "Build for lmi(K30 Pro/POCO F2 Pro) without KernelSU:"
    echo "    bash build.sh lmi"
    echo "Build for umi(Mi10) with KernelSU:"
    echo "    bash build.sh umi ksu"
    exit 1
fi

if ! command -v clang >/dev/null 2>&1; then
    echo "[clang] does not exist, please check your environment."
    exit 1
fi


# Enable ccache for speed up compiling 
export CCACHE_DIR="$HOME/.cache/ccache_mikernel" 
export PATH="/usr/lib/ccache:$PATH"
echo "CCACHE_DIR: [$CCACHE_DIR]"


MAKE_ARGS=(
	ARCH=arm64
	SUBARCH=arm64
	O=out
	"CC=ccache clang"
	"CXX=ccache clang++"
	CROSS_COMPILE=aarch64-linux-gnu-
	CROSS_COMPILE_ARM32=arm-linux-gnueabi-
	CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
	CLANG_TRIPLE=aarch64-linux-gnu-
	AR=llvm-ar
	NM=llvm-nm
	OBJCOPY=llvm-objcopy
	OBJDUMP=llvm-objdump
	STRIP=llvm-strip
	"HOSTCC=ccache clang"
	"HOSTCXX=ccache clang++"
	LD=ld.lld
	LLVM=1
	LLVM_IAS=0
)

if [ ! -f "arch/arm64/configs/${TARGET_DEVICE}_defconfig" ]; then
    echo "No target device [${TARGET_DEVICE}] found."
    echo "Avaliable defconfigs, please choose one target from below down:"
    ls arch/arm64/configs/*_defconfig
    exit 1
fi


# Check clang is existing.
clang --version



if [ "$2" == "ksu" ]; then
    KSU_ENABLE=1
else
    KSU_ENABLE=0
fi


echo "TARGET_DEVICE: $TARGET_DEVICE"

echo "Cleaning..."

rm -rf anykernel/

echo "Clone AnyKernel3 for packing kernel (repo: https://github.com/liyafe1997/AnyKernel3)"
git clone https://github.com/liyafe1997/AnyKernel3 -b kona --single-branch --depth=1 anykernel

# Add date to local version
local_version_str="-perf"
local_version_date_str="-IlyafeKernel-$(date +%Y%m%d)"

KOUT_PATH="/mnt/d/users/juan/kernels/${TARGET_DEVICE}/"


# ------------- Building for MIUI -------------

build_miui() {
	echo "Clearning [out/] and build for MIUI....."
	rm -rf out/

	if [ $KSU_ENABLE -eq 1 -a "$1" == "sukisu" ]; then
		KSU_ZIP_STR=SukiSU-SUSFS
		curl -LSs "https://github.com/liyafe1997/SukiSU-Ultra/raw/4ff14cf0051d04209c4abd5027d99d8e7780ef5b/kernel/setup.sh" | bash -s f4863b20cc8dc0f8cc67418980f022e43014b598
	elif [ $KSU_ENABLE -eq 1 ]; then
		KSU_ZIP_STR=KernelSU-Next-SUSFS
		curl -LSs "https://raw.githubusercontent.com/mtkpapa/KernelSU-Next/next-susfs/kernel/setup.sh" | bash -s next-susfs_v1.5.5-v1.5.7
	else 
		KSU_ZIP_STR=NoKernelSU
	fi
	
	make "${MAKE_ARGS[@]}" ${TARGET_DEVICE}_defconfig
	
	sed -i "s/${local_version_str}/${local_version_date_str}/g" out/.config
	
	if [ $KSU_ENABLE -eq 1 ]; then
		scripts/config --file out/.config \
		-e KSU \
		-e KSU_SUSFS_HAS_MAGIC_MOUNT \
		-d KSU_SUSFS_SUS_PATH \
		-e KSU_SUSFS_SUS_MOUNT \
		-e KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT \
		-e KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT \
		-e KSU_SUSFS_SUS_KSTAT \
		-d KSU_SUSFS_SUS_OVERLAYFS \
		-e KSU_SUSFS_TRY_UMOUNT \
		-e KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT \
		-e KSU_SUSFS_SPOOF_UNAME \
		-e KSU_SUSFS_ENABLE_LOG \
		-e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
		-e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
		-d KSU_SUSFS_OPEN_REDIRECT \
		-d KSU_SUSFS_SUS_SU 
	else
		scripts/config --file out/.config -d KSU
	fi
	
	if [ "$1" == "sukisu" ]; then
		scripts/config --file out/.config \
		-e SUKISU \
		-e KPM \
		-e KSU_MANUAL_HOOK
	else
		scripts/config --file out/.config \
		-e KSUN
	fi
	
	scripts/config --file out/.config \
		--set-str STATIC_USERMODEHELPER_PATH /system/bin/micd \
		-e PERF_CRITICAL_RT_TASK	\
		-e SF_BINDER		\
		-e OVERLAY_FS		\
		-d DEBUG_FS \
		-e MIGT \
		-e MIGT_ENERGY_MODEL \
		-e MIHW \
		-e PACKAGE_RUNTIME_INFO \
		-e BINDER_OPT \
		-e KPERFEVENTS \
		-e MILLET \
		-e PERF_HUMANTASK \
		-d LOCALVERSION_AUTO \
		-e SF_BINDER \
		-e XIAOMI_MIUI \
		-d MI_MEMORY_SYSFS \
		-e TASK_DELAY_ACCT \
		-e MIUI_ZRAM_MEMORY_TRACKING \
		-d CONFIG_MODULE_SIG_SHA512 \
		-d CONFIG_MODULE_SIG_HASH \
		-e MI_FRAGMENTION \
		-e PERF_HELPER \
		-e BOOTUP_RECLAIM \
		-e MI_RECLAIM \
		-e RTMM \
	
	make "${MAKE_ARGS[@]}" -j$(nproc)
	
	
	
	if [ -f "out/arch/arm64/boot/Image" ]; then
		echo "The file [out/arch/arm64/boot/Image] exists. MIUI Build successfully."
	else
		echo "The file [out/arch/arm64/boot/Image] does not exist. Seems MIUI build failed."
		exit 1
	fi
	
	echo "Generating [out/arch/arm64/boot/dtb]......"
	find out/arch/arm64/boot/dts -name '*.dtb' -exec cat {} + >out/arch/arm64/boot/dtb
	
	rm -rf anykernel/kernels/
	mkdir -p anykernel/kernels/
	
	# Patch for SukiSU KPM support. 
	if [ "$1" == "sukisu" ]; then
    cd out/arch/arm64/boot/
    wget https://github.com/ShirkNeko/SukiSU_KernelPatch_patch/releases/download/0.12.0/patch_linux
    chmod +x patch_linux
    ./patch_linux
    rm Image
    mv oImage Image
    cd -
	fi
	
	cp out/arch/arm64/boot/Image anykernel/kernels/
	cp out/arch/arm64/boot/dtb anykernel/kernels/
	
	echo "Build for MIUI finished."

	cd anykernel 
	
	ZIP_FILENAME=IlyafeKernel_MIUI_${TARGET_DEVICE}_${KSU_ZIP_STR}_$(date +'%Y%m%d_%H%M%S').zip
	
	zip -r9 $ZIP_FILENAME ./* -x .git .gitignore out/ ./*.zip
	
	mv $ZIP_FILENAME $KOUT_PATH
	
	cd ..
	
	rm -rf KernelSU-Next/
	rm -rf KernelSU/
}
# ------------- End of Building for MIUI -------------
#  If you don't need MIUI you can comment out the above block [Building for MIUI]

if [ "$3" == "test" ]; then
	echo "MIUI only build"
	if [ "$4" == "sukisu" ]; then
		echo "SukiSU build"
		build_miui "sukisu"
	else
		echo "KernelSU-Next build"
		build_miui
	fi
else
	build_miui
	if [ $KSU_ENABLE -eq 1 ]; then
	build_miui "sukisu"
	fi
fi

echo "Done. The flashable zip is: [./$ZIP_FILENAME]"

rm -rf out/
rm -rf anykernel/
