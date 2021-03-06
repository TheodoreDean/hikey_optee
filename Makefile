# Makefile for HiKey UEFI boot firmware
#
# 'make help' for details

SHELL = /bin/bash
CURL = curl -L

ifeq ($(V),1)
  Q :=
  ECHO := @:
else
  Q := @
  ECHO := @echo
endif

# Non-secure user mode (root fs binaries): 32 or 64-bit
NSU ?= 64
# Secure kernel (OP-TEE OS): 32 or 64bit
SK ?= 64
# Secure user mode (Trusted Apps): 32 or 64-bit
SU ?= 32

# Uncomment to enable
#WITH_STRACE ?= 1
# mmc (mmc-utils)
#WITH_MMC-UTILS ?= 1
#WITH_VALGRIND = 1
CFG_SQL_FS = y

.PHONY: FORCE

.PHONY: _all
_all:
	$(Q)$(MAKE) all $(filter-out _all,$(MAKECMDGOALS))

all: build-lloader build-fip build-boot-img build-nvme build-ptable

clean: clean-bl1-bl2-bl31-fip clean-bl33 clean-lloader-ptable
clean: clean-linux clean-boot-img clean-initramfs
clean: clean-optee-client clean-bl32
clean: clean-tee-stats
clean: clean-grub clean-dtb

cleaner: clean cleaner-nvme cleaner-aarch64-gcc cleaner-arm-gcc cleaner-busybox

distclean: cleaner distclean-aarch64-gcc distclean-arm-gcc distclean-busybox distclean-grub

help:
	@echo "Makefile for HiKey board UEFI firmware/kernel"
	@echo
	@echo "- Run 'make' to build the following images:"
	@echo "  LLOADER = $(LLOADER), contains:"
	@echo "      [BL1 = $(BL1)]"
	@echo "      [l-loader/*.S]"
	@echo "  PTABLE = $(PTABLE)"
	@echo "  FIP = $(FIP), contains:"
	@echo "      [BL2 = $(BL2)]"
	@echo "      [BL30 = $(BL30)]"
	@echo "      [BL31 = $(BL31)]"
	@echo "      [BL32 = $(BL32)]"
	@echo "      [BL33 = $(BL33)]"
	@echo "  NVME = $(NVME)"
	@echo "      [downloaded from GitHub]"
	@echo "  BOOT-IMG = $(BOOT-IMG), contains:"
	@echo "      [LINUX = $(LINUX)]"
	@echo "      [DTB = $(DTB)]"
	@echo "      [GRUB = $(GRUB)]"
	@echo "      [INITRAMFS = $(INITRAMFS)], contains:"
	@echo "          [busybox/*]"
	@if [ $(WITH_STRACE) ]; then \
		echo "          [STRACE = $(STRACE)]"; \
	 fi
	@echo "          [OPTEE-CLIENT = optee_client/out/libteec.so*" \
	                 "optee_client/out/tee-supplicant/tee-supplicant]"
	@echo "          [OPTEE-TEST = optee_test/out/xtest/xtest" \
	                 "optee_test/out/ta/.../*.ta]"
	@echo "- 'make clean' removes most files generated by make, except the"
	@echo "downloaded files/tarballs and the directories they were"
	@echo "extracted to."
	@echo "- 'make cleaner' also removes tar directories."
	@echo "- 'make distclean' removes all generated or downloaded files."
	@echo
	@echo "Image files can be built separately with e.g., 'make build-fip'"
	@echo "or 'make build-bl1', and so on (use the uppercase names above,"
	@echo "make them lowercase and prepend build-)."
	@echo "Note about dependencies: In order to speed up the build and"
	@echo "reduce output when working on a single component, build-<foo>"
	@echo "will NOT invoke build-<bar> automatically."
	@echo "Therefore, if you want to make sure that <bar> is up-to-date,"
	@echo "use 'make build-<foo> build-<bar>'."
	@echo "Plain 'make' or 'make all' do check all dependencies, however."
	@echo
	@echo "Use 'make SK=32'  for 32-bit secure kernel (OP-TEE OS) [default 64]"
	@echo "    'make NSU=32' for 32-bit non-secure user-mode [default 64]"
	@echo "    'make SU=64'  for 64-bit secure user-mode [default 32, requires SK=64]"
	@echo
	@echo "Flashing micro-howto:"
	@echo "  # First time flashing the board (or broken eMMC):"
	@echo "  # Set J15 pins 1-2 closed 3-4 closed 5-6 open (recovery mode)"
	@echo "  python burn-boot/hisi-idt.py --img1=$(LLOADER)"
	@echo "  # Board is now in fastboot mode. Later you may skip the above step"
	@echo "  # and enter fastboot directly by setting:"
	@echo "  # J15 pins 1-2 closed 3-4 open 5-6 closed (fastboot mode)"
	@echo "  fastboot flash ptable $(PTABLE)"
	@echo "  fastboot flash fastboot $(FIP)"
	@echo "  fastboot flash nvme $(NVME)"
	@echo "  fastboot flash boot $(BOOT-IMG)"
	@echo "  # Set J15 pins 1-2 closed 3-4 open 5-6 open (boot from eMMC)"
	@echo "Use 'make flash' to run all the above commands"

ifneq (,$(shell which ccache))
CCACHE = ccache # do not remove this comment or the trailing space will go
endif

filename = $(lastword $(subst /, ,$(1)))

# Read stdin, expand ${VAR} environment variables, output to stdout
# http://superuser.com/a/302847
define expand-env-var
awk '{while(match($$0,"[$$]{[^}]*}")) {var=substr($$0,RSTART+2,RLENGTH -3);gsub("[$$]{"var"}",ENVIRON[var])}}1'
endef

BUSYBOX_URL = http://busybox.net/downloads/busybox-1.23.0.tar.bz2
BUSYBOX_TARBALL = $(call filename,$(BUSYBOX_URL))
BUSYBOX_DIR = $(BUSYBOX_TARBALL:.tar.bz2=)

#
# Aarch64 toolchain
#
AARCH64_GCC_URL = https://releases.linaro.org/14.09/components/toolchain/binaries/gcc-linaro-aarch64-linux-gnu-4.9-2014.09_linux.tar.xz
AARCH64_GCC_TARBALL = $(call filename,$(AARCH64_GCC_URL))
AARCH64_GCC_DIR = $(AARCH64_GCC_TARBALL:.tar.xz=)
# If you don't want to download the aarch64 toolchain, comment out
# the next line and set CROSS_COMPILE to your compiler command
aarch64-linux-gnu-gcc := toolchains/$(AARCH64_GCC_DIR)
export CROSS_COMPILE ?= $(CCACHE)$(PWD)/toolchains/$(AARCH64_GCC_DIR)/bin/aarch64-linux-gnu-
#export CROSS_COMPILE ?= $(CCACHE)aarch64-linux-gnu-

#
# Aarch32 toolchain
#
ARM_GCC_URL = https://releases.linaro.org/14.09/components/toolchain/binaries/gcc-linaro-arm-linux-gnueabihf-4.9-2014.09_linux.tar.xz
ARM_GCC_TARBALL = $(call filename,$(ARM_GCC_URL))
ARM_GCC_DIR = $(ARM_GCC_TARBALL:.tar.xz=)
# If you don't want to download the aarch32 toolchain, comment out
# the next line and set CROSS_COMPILE32 to your compiler command
arm-linux-gnueabihf-gcc := toolchains/$(ARM_GCC_DIR)
CROSS_COMPILE32 ?= $(CCACHE)$(PWD)/toolchains/$(ARM_GCC_DIR)/bin/arm-linux-gnueabihf-
#CROSS_COMPILE32 ?= $(CCACHE)arm-linux-gnueabihf-

ifeq ($(NSU),64)
CROSS_COMPILE_HOST := $(CROSS_COMPILE)
host-gcc := $(aarch64-linux-gnu-gcc)
MULTIARCH := aarch64-linux-gnu
VALGRIND_ARCH := arm64
else
CROSS_COMPILE_HOST := $(CROSS_COMPILE32)
host-gcc := $(arm-linux-gnueabihf-gcc)
MULTIARCH := arm-linux-gnueabihf
VALGRIND_ARCH := arm
endif

ifeq ($(SU),64)
CROSS_COMPILE_S_USER := $(CROSS_COMPILE)
ta-gcc := $(aarch64-linux-gnu-gcc)
else
CROSS_COMPILE_S_USER := $(CROSS_COMPILE32)
ta-gcc := $(arm-linux-gnueabihf-gcc)
endif

#
# Download rules
#

downloads/$(AARCH64_GCC_TARBALL):
	$(ECHO) '  CURL    $@'
	$(Q)$(CURL) $(AARCH64_GCC_URL) -o $@

toolchains/$(AARCH64_GCC_DIR): downloads/$(AARCH64_GCC_TARBALL)
	$(ECHO) '  TAR     $@'
	$(Q)rm -rf toolchains/$(AARCH64_GCC_DIR)
	$(Q)cd toolchains && tar xf ../downloads/$(AARCH64_GCC_TARBALL)
	$(Q)touch $@

cleaner-aarch64-gcc:
	$(ECHO) '  CLEANER $@'
	$(Q)rm -rf toolchains/$(AARCH64_GCC_DIR)

distclean-aarch64-gcc:
	$(ECHO) '  DISTCL  $@'
	$(Q)rm -f downloads/$(AARCH64_GCC_TARBALL)

downloads/$(ARM_GCC_TARBALL):
	$(ECHO) '  CURL    $@'
	$(Q)$(CURL) $(ARM_GCC_URL) -o $@

toolchains/$(ARM_GCC_DIR): downloads/$(ARM_GCC_TARBALL)
	$(ECHO) '  TAR     $@'
	$(Q)rm -rf toolchains/$(ARM_GCC_DIR)
	$(Q)cd toolchains && tar xf ../downloads/$(ARM_GCC_TARBALL)
	$(Q)touch $@

cleaner-arm-gcc:
	$(ECHO) '  CLEANER $@'
	$(Q)rm -rf toolchains/$(ARM_GCC_DIR)

distclean-arm-gcc:
	$(ECHO) '  DISTCL  $@'
	$(Q)rm -f downloads/$(ARM_GCC_TARBALL)

.busybox: downloads/$(BUSYBOX_TARBALL)
	$(ECHO) '  TAR     busybox'
	$(Q)rm -rf $(BUSYBOX_DIR) busybox
	$(Q)tar xf downloads/$(BUSYBOX_TARBALL) && mv $(BUSYBOX_DIR) busybox
	$(Q)touch $@

downloads/$(BUSYBOX_TARBALL):
	$(ECHO) '  CURL    $@'
	$(Q)$(CURL) $(BUSYBOX_URL) -o $@

cleaner-busybox:
	$(ECHO) '  CLEANER $@'
	$(Q)rm -rf $(BUSYBOX_DIR) busybox .busybox

distclean-busybox:
	$(ECHO) '  DISTCL  $@'
	$(Q)rm -f downloads/$(BUSYBOX_TARBALL)


#
# UEFI
#

EDK2_DEBUG = 0
ifeq ($(EDK2_DEBUG),1)
EDK2_DEB_REL=DEBUG
else
EDK2_DEB_REL=RELEASE
endif

BL33 = edk2/Build/HiKey/$(EDK2_DEB_REL)_GCC49/FV/BL33_AP_UEFI.fd
EDK2_VARS := EDK2_ARCH=AARCH64 EDK2_DSC=HisiPkg/HiKeyPkg/HiKey.dsc EDK2_TOOLCHAIN=GCC49 EDK2_BUILD=$(EDK2_DEB_REL)
# Tell EDK2 to use UART0 for console I/O (defaults to UART3)
EDK2_VARS += EDK2_MACROS="-DSERIAL_BASE=0xF8015000"

.PHONY: build-bl33
build-bl33:: $(aarch64-linux-gnu-gcc)
build-bl33 $(BL33):: .edk2basetools
	$(ECHO) '  BUILD   build-bl33'
	$(Q)set -e ; cd edk2 ; export GCC49_AARCH64_PREFIX='"$(CROSS_COMPILE)"' ; \
	    . edksetup.sh ; \
	    $(MAKE) -j1 -f HisiPkg/HiKeyPkg/Makefile $(EDK2_VARS)
	$(Q)touch ${BL33}

clean-bl33: clean-edk2-basetools
	$(ECHO) '  CLEAN   $@'
	$(Q)set -e ; cd edk2 ; . edksetup.sh ; \
	    $(MAKE) -f HisiPkg/HiKeyPkg/Makefile $(EDK2_VARS) clean

.edk2basetools:
	$(ECHO) '  BUILD   edk2/BaseTools'
	$(Q)set -e ; cd edk2 ; . edksetup.sh ; \
	    $(MAKE) -j1 -C BaseTools CC="$(CCACHE)gcc" CXX="$(CCACHE)g++"
	$(Q)touch $@

clean-edk2-basetools:
	$(ECHO) '  CLEAN   $@'
	$(Q)set -e ; cd edk2 ; . edksetup.sh ; \
	    $(MAKE) -C BaseTools clean
	$(Q)rm -f .edk2basetools

#
# ARM Trusted Firmware
#

ATF_DEBUG = 0
ifeq ($(ATF_DEBUG),1)
ATF = arm-trusted-firmware/build/hikey/debug
else
ATF = arm-trusted-firmware/build/hikey/release
endif
BL1 = $(ATF)/bl1.bin
BL2 = $(ATF)/bl2.bin
BL30 = edk2/HisiPkg/HiKeyPkg/NonFree/mcuimage.bin
BL31 = $(ATF)/bl31.bin
# Comment out to not include OP-TEE OS image in fip.bin
BL32 = optee_os/out/arm-plat-hikey/core/tee.bin
FIP = $(ATF)/fip.bin

ARMTF_FLAGS := PLAT=hikey DEBUG=$(ATF_DEBUG)
# TF console now defaults to UART3 (on the low-speed header connector).
# The following line selects UART0 (the unpopulated pads next to J15),
# which is also used by the boot ROM.
ARMTF_FLAGS += CONSOLE_BASE=PL011_UART0_BASE CRASH_CONSOLE_BASE=PL011_UART0_BASE
#ARMTF_FLAGS += LOG_LEVEL=40
ARMTF_EXPORTS := BL30=$(PWD)/$(BL30) BL33=$(PWD)/$(BL33) #CFLAGS=""
ifneq (,$(BL32))
ARMTF_FLAGS += SPD=opteed
ARMTF_EXPORTS += BL32=$(PWD)/$(BL32)
endif

define arm-tf-make
        $(ECHO) '  BUILD   build-$(strip $(1)) [$@]'
        +$(Q)export $(ARMTF_EXPORTS) ; \
	    $(MAKE) -C arm-trusted-firmware $(ARMTF_FLAGS) $(1)
endef

.PHONY: build-bl1
build-bl1 $(BL1): $(aarch64-linux-gnu-gcc)
	$(call arm-tf-make, bl1)

.PHONY: build-bl2
build-bl2 $(BL2): $(aarch64-linux-gnu-gcc)
	$(call arm-tf-make, bl2)

.PHONY: build-bl31
build-bl31 $(BL31): $(aarch64-linux-gnu-gcc)
	$(call arm-tf-make, bl31)


ifneq ($(filter all build-bl2,$(MAKECMDGOALS)),)
tf-deps += build-bl2
endif
ifneq ($(filter all build-bl31,$(MAKECMDGOALS)),)
tf-deps += build-bl31
endif
ifneq ($(filter all build-bl32,$(MAKECMDGOALS)),)
tf-deps += build-bl32
endif
ifneq ($(filter all build-bl33,$(MAKECMDGOALS)),)
tf-deps += build-bl33
endif

.PHONY: build-fip
build-fip:: $(tf-deps)
build-fip $(FIP)::
	$(call arm-tf-make, fip)

clean-bl1-bl2-bl31-fip:
	$(ECHO) '  CLEAN   edk2/BaseTools'
	$(Q)export $(ARMTF_EXPORTS) ; \
	    $(MAKE) -C arm-trusted-firmware $(ARMTF_FLAGS) clean

#
# l-loader
#

LLOADER = l-loader/l-loader.bin
PTABLE = l-loader/ptable-linux-4g.img

ifneq ($(filter all build-bl1,$(MAKECMDGOALS)),)
lloader-deps += build-bl1
endif

# FIXME: adding $(BL1) as a dependency [after $(LLOADER)::] breaks
# parallel build (-j) because the same rule is run twice simultaneously
# $ make -j9 build-bl1 build-lloader
#   BUILD   build-bl1 # $@ = build-bl1
#   BUILD   build-bl1 # $@ = arm-trusted-firmware/build/.../bl1.bin
# make[1]: Entering directory '/home/jerome/work/hikey_uefi/arm-trusted-firmware'
# make[1]: Entering directory '/home/jerome/work/hikey_uefi/arm-trusted-firmware'
#   DEPS    build/hikey/debug/bl31/bl31.ld.d
#   DEPS    build/hikey/debug/bl31/bl31.ld.d
.PHONY: build-lloader
build-lloader:: $(arm-linux-gnueabihf-gcc) $(lloader-deps)
build-lloader $(LLOADER)::
	$(ECHO) '  BUILD   build-lloader'
	$(Q)$(MAKE) -C l-loader BL1=$(PWD)/$(BL1) CROSS_COMPILE="$(CROSS_COMPILE32)" l-loader.bin

build-ptable: $(PTABLE)
$(PTABLE):
	$(ECHO) '  BUILD   build-ptable'
	$(Q)$(MAKE) -C l-loader PTABLE_LST=linux-4g ptable.img

clean-lloader-ptable:
	$(ECHO) '  CLEAN   $@'
	$(Q)$(MAKE) -C l-loader clean

#
# Linux/DTB
#

# FIXME: 'make build-linux' needlessy (?) recompiles a few files (efi.o...)
# each time it is run

LINUX = linux/arch/arm64/boot/Image
DTB = hi6220-hikey.dtb
# Config fragments to merge with the default kernel configuration
KCONFIGS += kernel_config/dmabuf.conf
#KCONFIGS += kernel_config/usb_net_dm9601.conf
KCONFIGS += kernel_config/optee_gendrv.conf
#KCONFIGS += kernel_config/ftrace.conf

.PHONY: build-linux
build-linux:: $(aarch64-linux-gnu-gcc)
build-linux $(LINUX):: linux/.config
	$(ECHO) '  BUILD   build-linux'
	$(Q)flock .linuxbuildinprogress $(MAKE) -C linux ARCH=arm64 LOCALVERSION= Image modules

build-dtb:: $(aarch64-linux-gnu-gcc)
build-dtb:: $(DTB) 

$(DTB): linux/.config linux/arch/arm64/boot/dts/hisilicon/hi6220-hikey.dts linux/scripts/dtc/dtc
	$(ECHO) '  BUILD   $(DTB)'
	$(Q)$(CROSS_COMPILE)gcc -E -nostdinc -I./linux/arch/arm64/boot/dts -I./linux/arch/arm64/boot/dts/include -D__DTS__ -x assembler-with-cpp hi6220-hikey.dts | ./linux/scripts/dtc/dtc -O dtb -o hi6220-hikey.dtb -i linux/arch/arm64/boot/dts/hisilicon

linux/.config: $(KCONFIGS)
	$(ECHO) '  BUILD   $@'
	$(Q)cd linux && ARCH=arm64 scripts/kconfig/merge_config.sh \
	    arch/arm64/configs/defconfig $(patsubst %,../%,$(KCONFIGS))

linux/usr/gen_init_cpio: linux/.config
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C linux/usr ARCH=arm64 gen_init_cpio

linux/scripts/dtc/dtc:
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C linux ARCH=arm64 scripts/dtc/dtc
clean-linux:
	$(ECHO) '  CLEAN   $@'
	$(Q)$(MAKE) -C linux ARCH=arm64 clean
	$(Q)rm -f linux/.config
	$(Q)rm -f .linuxbuildinprogress

clean-dtb:
	$(ECHO) '  CLEAN $(DTB)'
	$(Q)rm -f $(DTB)

#
# EFI boot partition
#

BOOT-IMG = boot.img

ifneq ($(filter all build-linux,$(MAKECMDGOALS)),)
boot-img-deps += build-linux
endif
ifneq ($(filter all build-dtb,$(MAKECMDGOALS)),)
boot-img-deps += build-dtb
endif
ifneq ($(filter all build-initramfs,$(MAKECMDGOALS)),)
boot-img-deps += build-initramfs
endif
ifneq ($(filter all build-bl33,$(MAKECMDGOALS)),)
boot-img-deps += build-bl33
endif
ifneq ($(filter all build-grub,$(MAKECMDGOALS)),)
boot-img-deps += build-grub
endif

.PHONY: build-boot-img
build-boot-img:: $(boot-img-deps)
build-boot-img $(BOOT-IMG)::
	$(ECHO) '  GEN    $(BOOT-IMG)'
	$(Q)rm -f $(BOOT-IMG)
	$(Q)mformat -i $(BOOT-IMG) -n 64 -h 255 -T 131072 -v "BOOT IMG" -C ::
	$(Q)mcopy -i $(BOOT-IMG) $(LINUX) $(DTB) $(GRUB) ::
	$(Q)mcopy -i $(BOOT-IMG) $(INITRAMFS) ::/initrd.img
	$(Q)mcopy -i $(BOOT-IMG) edk2/Build/HiKey/$(EDK2_DEB_REL)_GCC49/AARCH64/AndroidFastbootApp.efi ::

clean-boot-img:
	$(ECHO) '  CLEAN   $@'
	$(Q)rm -f $(BOOT-IMG)

#
# Initramfs
#

INITRAMFS = initramfs.cpio.gz

ifneq ($(filter all build-optee-client,$(MAKECMDGOALS)),)
initramfs-deps += build-optee-client
endif
ifneq ($(filter all build-tee-stats,$(MAKECMDGOALS)),)
initramfs-deps += build-tee-stats
endif
ifneq ($(filter all build-optee-test,$(MAKECMDGOALS)),)
initramfs-deps += build-optee-test
endif
ifeq ($(WITH_STRACE),1)
ifneq ($(filter all build-strace,$(MAKECMDGOALS)),)
initramfs-deps += build-strace
endif
endif
ifeq ($(WITH_MMC-UTILS),1)
ifneq ($(filter all build-mmc-utils,$(MAKECMDGOALS)),)
initramfs-deps += build-mmc-utils
endif
endif
ifeq ($(WITH_VALGRIND),1)
ifneq ($(filter all build-valgrind,$(MAKECMDGOALS)),)
initramfs-deps += build-valgrind
endif
endif

.PHONY: build-initramfs
build-initramfs:: $(initramfs-deps)
build-initramfs $(INITRAMFS):: gen_rootfs/filelist-all.txt linux/usr/gen_init_cpio
	$(ECHO) "  GEN    $(INITRAMFS)"
	$(Q)(cd gen_rootfs && ../linux/usr/gen_init_cpio filelist-all.txt) | gzip >$(INITRAMFS)

# Warning:
# '=' not ':=' because we don't want the right-hand side to be evaluated
# immediately. This would be a problem when IFGP is '#'
INITRAMFS_EXPORTS = TOP='$(CURDIR)' IFGP='$(IFGP)' IFSTRACE='$(IFSTRACE)' MULTIARCH='$(MULTIARCH)' IFIW='$(IFIW)' IFWLFW='$(IFWLFW)' IFMMCUTILS='$(IFMMCUTILS)' VALGRIND_ARCH='$(VALGRIND_ARCH)' IFSQLFS='$(IFSQLFS)'

.initramfs_exports: FORCE
	$(ECHO) '  CHK     $@'
	$(Q)echo $(INITRAMFS_EXPORTS) >$@.new && (cmp $@ $@.new >/dev/null 2>&1 || mv $@.new $@)
	$(Q)rm -rf $@.new

gen_rootfs/filelist-all.txt: gen_rootfs/filelist-final.txt initramfs-add-files.txt .initramfs_exports
	$(ECHO) '  GEN    $@'
	$(Q)cat gen_rootfs/filelist-final.txt | sed '/fbtest/d' >$@
	$(Q)export KERNEL_VERSION=`cd linux ; $(MAKE) --no-print-directory -s kernelversion` ;\
	    export $(INITRAMFS_EXPORTS) ; \
	    $(expand-env-var) <initramfs-add-files.txt >>$@

gen_rootfs/filelist-final.txt: .busybox $(host-gcc)
	$(ECHO) '  GEN    gen_rootfs/filelist-final.txt'
	$(Q)cd gen_rootfs ; \
	    export CROSS_COMPILE="$(CROSS_COMPILE_HOST)" ; \
	    ./generate-cpio-rootfs.sh hikey nocpio

clean-initramfs:
	$(ECHO) "  CLEAN  $@"
	$(Q)cd gen_rootfs ; \
	    export CROSS_COMPILE="$(CROSS_COMPILE_HOST)" ; \
	    ./generate-cpio-rootfs.sh hikey clean
	$(Q)rm -f $(INITRAMFS) gen_rootfs/filelist-all.txt gen_rootfs/filelist-final.txt
	$(Q)rm -f .initramfs_exports .initramfs_exports.new

#
# Grub
#

GRUB = grubaa64.efi grub.cfg

grub-flags := CC="$(CCACHE)gcc" \
	TARGET_CC="$(CROSS_COMPILE)gcc" \
	TARGET_OBJCOPY="$(CROSS_COMPILE)objcopy" \
	TARGET_NM="$(CROSS_COMPILE)nm" \
	TARGET_RANLIB="$(CROSS_COMPILE)ranlib" \
	TARGET_STRIP="$(CROSS_COMPILE)strip"

ifneq ($(filter all build-grub,$(MAKECMDGOALS)),)
.PHONY: grub-force
endif
grub-force:

.PHONY: build-grub
build-grub: $(GRUB)

grubaa64.efi:: grub/grub-mkimage grub-force
	$(ECHO) '  GEN    $@'
	$(Q)cd grub ; ./grub-mkimage --output=../$@ \
		--config=../grub.configfile \
		--format=arm64-efi \
		--directory=grub-core \
		--prefix=/boot/grub \
		configfile fat linux normal help part_gpt

grub/grub-mkimage: $(aarch64-linux-gnu-gcc) grub/Makefile grub-force
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C grub

grub/configure: grub/configure.ac
	$(ECHO) '  GEN     $@'
	$(Q)cd grub ; ./autogen.sh

grub/Makefile: grub/configure
	$(ECHO) '  GEN     $@'
	$(Q)cd grub ; ./configure --target=aarch64 --enable-boot-time $(grub-flags)

clean-grub:
	$(ECHO) '  CLEAN       $@'
	$(Q)if [ -e grub/Makefile ] ; then $(MAKE) -C grub clean ; fi
	$(Q)rm -f grubaa64.efi

distclean-grub:
	$(ECHO) '  DISTCLEAN   $@'
	$(Q)if [ -e grub/Makefile ] ; then $(MAKE) -C grub distclean ; fi
	$(Q)rm -f grub/configure

#
# Download nvme.img
#

NVME = nvme.img

.PHONY: build-nvme
build-nvme: $(NVME)

$(NVME):
	$(CURL) https://builds.96boards.org/releases/hikey/linaro/binaries/15.05/nvme.img -o $(NVME)

cleaner-nvme:
	$(ECHO) '  CLEANER $(NVME)'
	$(Q)rm -f $(NVME)

#
# OP-TEE client library and tee-supplicant executable
#

optee-client-flags := CROSS_COMPILE="$(CROSS_COMPILE_HOST)"
#optee-client-flags += CFG_TEE_SUPP_LOG_LEVEL=4 CFG_TEE_CLIENT_LOG_LEVEL=4
#optee-client-flags += RPMB_EMU=

ifeq ($(CFG_SQL_FS),y)
optee-client-flags += CFG_SQL_FS=y
else
IFSQLFS=\#
endif

.PHONY: build-optee-client
build-optee-client: $(aarch64-linux-gnu-gcc)
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C optee_client $(optee-client-flags)

clean-optee-client:
	$(ECHO) '  CLEAN   $@'
	$(Q)$(MAKE) -C optee_client $(optee-client-flags) clean

#
# OP-TEE OS
#

CFG_TEE_CORE_LOG_LEVEL ?= 2 # 0=none 1=err 2=info 3=debug 4=flow
optee-os-flags := CROSS_COMPILE="$(CROSS_COMPILE32)" PLATFORM=hikey
optee-os-flags += DEBUG=0
optee-os-flags += CFG_TEE_CORE_LOG_LEVEL=$(CFG_TEE_CORE_LOG_LEVEL)
#optee-os-flags += CFG_WITH_PAGER=y
optee-os-flags += CFG_TEE_TA_LOG_LEVEL=3
CFG_CONSOLE_UART ?= 0
optee-os-flags += CFG_CONSOLE_UART=$(CFG_CONSOLE_UART)
# See also RPMB_EMU= in optee-client-flags
optee-os-flags += CFG_RPMB_FS=y
# Uncomment to use an eMMC module in the microSD slot instead of embedded eMMC
#optee-os-flags += CFG_RPMB_FS_DEV_ID=1
#optee-os-flags += CFG_RPMB_TESTKEY=y
#optee-os-flags += CFG_RPMB_RESET_FAT=y
ifeq ($(CFG_SQL_FS),y)
optee-os-flags += CFG_SQL_FS=y
endif
CFG_WITH_STATS ?= n
optee-os-flags += CFG_WITH_STATS=$(CFG_WITH_STATS) # Needed by tee-stats

# 64-bit TEE Core
# FIXME: Compiler bug? xtest 4002 hangs (endless loop) when:
# - TEE Core is 64-bit and compiler is aarch64-linux-gnu-gcc
#   4.9.2-10ubuntu13, and
# - DEBUG=0, and
# - 32-bit user libraries are built with arm-linux-gnueabihf-gcc 4.9.2-10ubuntu10
# Set DEBUG=1, or set $(arm-linux-gnueabihf-) to build user code with:
#   'arm-linux-gnueabihf-gcc (crosstool-NG linaro-1.13.1-4.8-2013.08 - Linaro GCC 2013.08)
#    4.8.2 20130805 (prerelease)'
# or with:
#   'arm-linux-gnueabihf-gcc (Linaro GCC 2014.11) 4.9.3 20141031 (prerelease)'
# and the problem disappears.
ifeq ($(SK),64)
optee-os-flags += CFG_ARM64_core=y CROSS_COMPILE_core="$(CROSS_COMPILE)"
optee-os-flags += CROSS_COMPILE_ta_arm64="$(CROSS_COMPILE)"
endif

.PHONY: build-bl32
build-bl32:: $(aarch64-linux-gnu-gcc) $(arm-linux-gnueabihf-gcc)
build-bl32::
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C optee_os $(optee-os-flags)

.PHONY: clean-bl32
clean-bl32:
	$(ECHO) '  CLEAN   $@'
	$(Q)$(MAKE) -C optee_os $(optee-os-flags) clean


#
# OP-TEE tests (xtest)
#

# To build with GlobalPlatform tests ("extended xtest"), just extract
# TEE_Initial_Configuration-Test_Suite_v1_1_0_4-2014_11_07.7z under optee_test.
#
# NOTE: If you have built with GlobalPlatform tests and later remove them
# (or force GP_TESTS=0), you will need to clean the repository:
#   cd optee_test ; git reset --hard HEAD
ifneq (,$(wildcard optee_test/TEE_Initial_Configuration-Test_Suite_v1_1_0_4-2014_11_07))
GP_TESTS=1
endif

ifneq ($(GP_TESTS),1)
IFGP=\#
endif

all: build-optee-test
clean: clean-optee-test

# TODO: now that OP-TEE supports 32- and 64-bit TAs, make it configurable
optee-test-flags := CROSS_COMPILE_HOST="$(CROSS_COMPILE_HOST)" \
		    CROSS_COMPILE_TA="$(CROSS_COMPILE_S_USER)" \
		    TA_DEV_KIT_DIR=$(PWD)/optee_os/out/arm-plat-hikey/export-ta_arm$(SU) \
		    O=$(PWD)/optee_test/out #CFG_TEE_TA_LOG_LEVEL=3
ifeq ($(GP_TESTS),1)
optee-test-flags += CFG_GP_PACKAGE_PATH=$(PWD)/optee_test/TEE_Initial_Configuration-Test_Suite_v1_1_0_4-2014_11_07
optee-test-flags += COMPILE_NS_USER=$(NSU)
endif
# optee_test/Makefile does "CFLAGS += ..." so the below will work, but
# "make CFLAGS=..." wouldn't
#optee-test-exports := CFLAGS="-ggdb"

ifneq ($(filter all build-bl32,$(MAKECMDGOALS)),)
optee-test-deps += build-bl32
endif
ifneq ($(filter all build-optee-client,$(MAKECMDGOALS)),)
optee-test-deps += build-optee-client
endif
ifeq ($(GP_TESTS),1)
optee-test-deps += optee-test-do-patch
endif


.PHONY: build-optee-test
build-optee-test:: $(optee-test-deps)
build-optee-test:: $(ta-gcc)
	$(ECHO) '  BUILD   $@'
	$(Q)[ "$(optee-test-exports)" ] && export $(optee-test-exports); $(MAKE) -C optee_test $(optee-test-flags)

# FIXME:
# No "make clean" in optee_test: fails if optee_os has been cleaned
# previously.
clean-optee-test:
	$(ECHO) '  CLEAN   $@'
	$(Q)rm -rf optee_test/out

.PHONY: optee-test-do-patch
optee-test-do-patch:
	$(Q)$(MAKE) -C optee_test $(optee-test-flags) patch

#
# tee-stats (statistics gathering tool, client side of
# core/arch/arm/sta/stats.c)
#

tee-stats-flags := CROSS_COMPILE_HOST="$(CROSS_COMPILE_HOST)"

ifneq ($(filter all build-optee-client,$(MAKECMDGOALS)),)
tee-stats-deps += build-optee-client
endif

.PHONY: build-tee-stats
build-tee-stats:: $(tee-stats-deps)
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C tee-stats $(tee-stats-flags)

clean-tee-stats:
	$(ECHO) '  CLEAN   $@'
	$(Q)rm -rf tee-stats/out

#
define fastboot-flash
$(Q)stderr=$$(fastboot flash $1 $2 2>&1) || echo $${stderr}
endef

.PHONY: flash
flash:
	$(ECHO) '  FLASH   $(LLOADER)'
	$(Q)python burn-boot/hisi-idt.py --img1=$(LLOADER) >/dev/null
	$(ECHO) '  FLASH   $(PTABLE)'
	$(call fastboot-flash,ptable,$(PTABLE))
	$(ECHO) '  FLASH   $(FIP)'
	$(call fastboot-flash,fastboot,$(FIP))
	$(ECHO) '  FLASH   $(NVME)'
	$(call fastboot-flash,nvme,$(NVME))
	$(ECHO) '  FLASH   $(BOOT-IMG)'
	$(call fastboot-flash,boot,$(BOOT-IMG))

#
# strace
#

ifeq ($(WITH_STRACE),1)

STRACE = strace/strace
STRACE_EXPORTS := CC='$(CROSS_COMPILE_HOST)gcc' LD='$(CROSS_COMPILE_HOST)ld'

build-strace $(STRACE): strace/Makefile
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C strace

.strace_exports: FORCE
	$(ECHO) '  CHK     $@'
	$(Q)echo $(STRACE_EXPORTS) >$@.new && (cmp $@ $@.new >/dev/null 2>&1 || mv $@.new $@)
	$(Q)rm -rf $@.new

strace/Makefile: strace/configure .strace_exports
	$(ECHO) '  GEN     $@'
	$(Q)set -e ; export $(STRACE_EXPORTS) ; \
	    cd strace ; ./configure --host=$(MULTIARCH)

strace/configure: strace/bootstrap
	$(ECHO) ' GEN      $@'
	$(Q)cd strace ; ./bootstrap

.PHONY: clean-strace
clean-strace:
	$(ECHO) '  CLEAN   $@'
	$(Q)export $(STRACE_EXPORTS) ; [ -d strace ] && $(MAKE) -C strace clean || :
	$(Q)rm -f .strace_exports .strace_exports.new

.PHONY: cleaner-strace
cleaner-strace:
	$(ECHO) '  CLEANER $@'
	$(Q)rm -f strace/Makefile strace/configure

cleaner: cleaner-strace

else

IFSTRACE=\#

endif

#
# mmc-utils
#

MMC-UTILS_FLAGS := CC='$(CROSS_COMPILE_HOST)gcc'

ifeq ($(WITH_MMC-UTILS),1)

build-mmc-utils:
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C mmc-utils $(MMC-UTILS_FLAGS)

clean-mmc-utils:
	$(ECHO) '  CLEAN   $@'
	$(Q)$(MAKE) -C mmc-utils clean

clean: clean-mmc-utils

else

IFMMCUTILS=\#

endif

ifeq ($(WITH_VALGRIND),1)

VALGRIND = valgrind/valgrind
VALGRIND_EXPORTS := CC='$(CROSS_COMPILE_HOST)gcc' LD='$(CROSS_COMPILE_HOST)ld' AR='$(CROSS_COMPILE_HOST)ar'

build-valgrind $(VALGRIND): valgrind/Makefile
	$(ECHO) '  BUILD   $@'
	$(Q)$(MAKE) -C valgrind install DESTDIR=$(PWD)/inst/valgrind

.valgrind_exports: FORCE
	$(ECHO) '  CHK     $@'
	$(Q)echo $(VALGRIND_EXPORTS) >$@.new && (cmp $@ $@.new >/dev/null 2>&1 || mv $@.new $@)
	$(Q)rm -rf $@.new

valgrind/Makefile: valgrind/configure .valgrind_exports
	$(ECHO) '  GEN     $@'
	$(Q)set -e ; export $(VALGRIND_EXPORTS) ; \
	    cd valgrind ; ./configure --host=$(MULTIARCH) --prefix=/usr

# FIXME: valgrind/VEX must be 
valgrind/configure: valgrind/autogen.sh
	$(ECHO) ' GEN      $@'
	$(Q)cd valgrind ; ./autogen.sh

.PHONY: clean-valgrind
clean-valgrind:
	$(ECHO) '  CLEAN   $@'
	$(Q)export $(VALGRIND_EXPORTS) ; [ -d valgrind ] && $(MAKE) -C valgrind clean || :
	$(Q)rm -f .valgrind_exports .valgrind_exports.new

.PHONY: cleaner-valgrind
cleaner-valgrind:
	$(ECHO) '  CLEANER $@'
	$(Q)rm -f valgrind/Makefile valgrind/configure

cleaner: cleaner-valgrind

else

IFVALGRIND=\#

endif

