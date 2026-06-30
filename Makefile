ROOT_DIR ?= $(CURDIR)
BUILD_ROOT ?= $(ROOT_DIR)/build
DOWNLOAD_DIR ?= $(ROOT_DIR)/downloads

# Options
LINUX_FIRMWARE_PACK_IN ?= $(ROOT_DIR)/stock-nand/C6300BD_1TLAUS_K2630V1.01.06u_140526.bin
ENABLE_TELNET ?= 1
ENABLE_DROPBEAR ?= 1
LINUX_KERNEL_RW_ALL_MTD ?= 0
PROGRAMSTORE_URL ?= https://github.com/rikka0w0/aeolus/releases/download/C6300BD-1TLAUS/ProgramStore_linux_amd64

PROGRAMSTORE := $(DOWNLOAD_DIR)/ProgramStore
STOCK_LINUX_KERNEL := $(BUILD_ROOT)/stock-linux-kernel.bin
STOCK_LINUX_ROOTFS := $(BUILD_ROOT)/stock-linux-rootfs.bin
PATCHED_LINUX_KERNEL := $(BUILD_ROOT)/patched-linux-kernel.bin
ROOTFS_FAKEROOT := $(BUILD_ROOT)/rootfs.fakeroot
ROOTFS_FAKEROOT_STAMP := $(ROOTFS_FAKEROOT).unpacked.stamp
ROOTFS_FAKEROOT_STATE := $(ROOTFS_FAKEROOT).fakeroot.state
ROOTFS_FAKEROOT_FIXED := $(ROOTFS_FAKEROOT).fixed.sqfs
ROOTFS_FAKEROOT_META := $(ROOTFS_FAKEROOT).c6300bd-sqfs.env
ROOTFS_MERGE := $(ROOT_DIR)/rootfs.merge
ROOTFS_MERGE_FILES := $(shell find "$(ROOTFS_MERGE)" -mindepth 1 -print 2>/dev/null)
PATCHED_LINUX_ROOTFS := $(BUILD_ROOT)/patched-linux-rootfs.bin
PATCHED_FIRMWARE := $(BUILD_ROOT)/C6300BD_1TLAUS_K2630_PATCHED.bin
LINUXAPPS_DIR := $(ROOT_DIR)/linuxapps
LINUXAPPS_FILES := $(shell find "$(LINUXAPPS_DIR)" -mindepth 1 -print 2>/dev/null)
LINUXAPPS_IMAGE := $(BUILD_ROOT)/mtdblock3.bin
LINUXAPPS_BLOCK_SIZE ?= 65536
LINUXAPPS_MKFS_TIME ?= 1401088145
ROOTFS_HOST_COMMANDS := mksquashfs unsquashfs fakeroot
.DEFAULT_GOAL := pack-firmware

include $(ROOT_DIR)/common.mk
include $(ROOT_DIR)/dropbear.mk
include $(ROOT_DIR)/ecos.mk

.PHONY: check-host-packages clean clean-linux clean-linuxapps

$(BUILD_ROOT) $(DOWNLOAD_DIR):
	mkdir -p $@

check-host-packages:
	$(call check-host-commands,$(ROOTFS_HOST_COMMANDS))

clean: clean-linux clean-dropbear clean-dropbear-host clean-linuxapps clean-ecos

clean-linux:
	rm -rf \
		"$(STOCK_LINUX_KERNEL)" \
		"$(STOCK_LINUX_ROOTFS)" \
		"$(PATCHED_LINUX_KERNEL)" \
		"$(ROOTFS_FAKEROOT)" \
		"$(ROOTFS_FAKEROOT_STAMP)" \
		"$(ROOTFS_FAKEROOT_STATE)" \
		"$(ROOTFS_FAKEROOT_FIXED)" \
		"$(ROOTFS_FAKEROOT_META)" \
		"$(PATCHED_LINUX_ROOTFS)" \
		"$(PATCHED_FIRMWARE)"

$(PROGRAMSTORE): | $(DOWNLOAD_DIR)
	wget -O "$@" "$(PROGRAMSTORE_URL)"
	chmod 755 "$@"

$(STOCK_LINUX_KERNEL): $(PROGRAMSTORE) $(LINUX_FIRMWARE_PACK_IN) | $(BUILD_ROOT)
	"$(PROGRAMSTORE)" -x -f "$(LINUX_FIRMWARE_PACK_IN)" -o "$@"

extract-linux-kernel: $(STOCK_LINUX_KERNEL)

$(STOCK_LINUX_ROOTFS): $(PROGRAMSTORE) $(LINUX_FIRMWARE_PACK_IN) | $(BUILD_ROOT)
	"$(PROGRAMSTORE)" -x3 -f "$(LINUX_FIRMWARE_PACK_IN)" -o "$@"

extract-linux-rootfs: $(STOCK_LINUX_ROOTFS)

$(PATCHED_LINUX_KERNEL): $(STOCK_LINUX_KERNEL) | $(BUILD_ROOT)
	if [ "$(LINUX_KERNEL_RW_ALL_MTD)" = "1" ]; then \
		"$(ROOT_DIR)/patch_img1_maskflags_writable.py" "$(STOCK_LINUX_KERNEL)" "$@"; \
	else \
		cp "$(STOCK_LINUX_KERNEL)" "$@"; \
	fi

patch-linux-kernel: $(PATCHED_LINUX_KERNEL)

$(ROOTFS_FAKEROOT_STAMP): $(STOCK_LINUX_ROOTFS) $(ROOT_DIR)/c6300bd-sqfs-unpack.sh | $(BUILD_ROOT) check-host-packages
	"$(ROOT_DIR)/c6300bd-sqfs-unpack.sh" -f "$(STOCK_LINUX_ROOTFS)" "$(ROOTFS_FAKEROOT)"
	touch "$@"

$(ROOTFS_FAKEROOT): $(ROOTFS_FAKEROOT_STAMP)

unpack-linux-rootfs: $(ROOTFS_FAKEROOT_STAMP)

$(PATCHED_LINUX_ROOTFS): $(ROOTFS_FAKEROOT_STAMP) $(ROOTFS_MERGE) $(ROOTFS_MERGE_FILES) | $(BUILD_ROOT) check-host-packages
	cp -a "$(ROOTFS_MERGE)/." "$(ROOTFS_FAKEROOT)/"

	# Enable telnet if requested, and ensure /opt/startup.sh is called from rcS
	# /opt/startup.sh is our own startup script
	if [ "$(ENABLE_TELNET)" = "1" ]; then \
		sed -i "s|^\([[:space:]]*\)grep nouart /proc/cmdline > /dev/null|\1/bin/true # grep nouart /proc/cmdline > /dev/null|" \
			"$(ROOTFS_FAKEROOT)/etc/init.d/rcS"; \
	fi
	if ! sed -n '\|^/opt/startup\.sh$$|q 0; $$q 1' "$(ROOTFS_FAKEROOT)/etc/init.d/rcS"; then \
		sed -i '$$a/opt/startup.sh' "$(ROOTFS_FAKEROOT)/etc/init.d/rcS"; \
	fi

	# Install dropbear binaries
ifeq ($(ENABLE_DROPBEAR),1)
	$(call stage-dropbear-in-rootfs,$(ROOTFS_FAKEROOT))
endif

	"$(ROOT_DIR)/c6300bd-sqfs-pack.sh" -f "$(ROOTFS_FAKEROOT)" "$@"

pack-linux-rootfs: $(PATCHED_LINUX_ROOTFS)

ifeq ($(ENABLE_DROPBEAR),1)
$(PATCHED_LINUX_ROOTFS): $(DROPBEAR_MULTI) | dropbearkey-host-gen-hostkey
endif

$(PATCHED_FIRMWARE): $(PROGRAMSTORE) $(PATCHED_LINUX_KERNEL) $(PATCHED_LINUX_ROOTFS) | $(BUILD_ROOT)
	"$(PROGRAMSTORE)" \
		-f "$(PATCHED_LINUX_KERNEL)" \
		-f3 "$(PATCHED_LINUX_ROOTFS)" \
		-o "$@" \
		-c 4 \
		-p 0x1a0000 \
		-s a0eb \
		-v 0114.0514

pack-firmware: $(PATCHED_FIRMWARE)

$(LINUXAPPS_IMAGE): $(LINUXAPPS_DIR) $(LINUXAPPS_FILES) | $(BUILD_ROOT)
	@command -v mksquashfs >/dev/null 2>&1 || { echo "error: missing required host command(s): mksquashfs" >&2; exit 1; }
	rm -f "$@"
	mksquashfs "$(LINUXAPPS_DIR)" "$@" \
		-noappend \
		-comp lzma \
		-b "$(LINUXAPPS_BLOCK_SIZE)" \
		-mkfs-time "$(LINUXAPPS_MKFS_TIME)" \
		-all-root

	# 2. Fix the SquashFS magic
	# Broadcom's magic is shsq: 73 68 73 71
	# Standard little-endian SquashFS magic is hsqs: 68 73 71 73
	printf '\163\150\163\161' | dd of="$@" bs=1 seek=0 count=4 conv=notrunc status=none

	# 3. Fix the compression field
	# In the SquashFS superblock, offset 0x14 is the compression field
	# The original squashfs puts 02 00 here, which means LZMA
	# The actual data blocks are LZMA-Alone, but the vendor format requires 01 00, which means gzip...
	printf '\001\000' | dd of="$@" bs=1 seek=$$((0x14)) count=2 conv=notrunc status=none

clean-linuxapps:
	rm -f "$(LINUXAPPS_IMAGE)"

pack-linuxapps: $(LINUXAPPS_IMAGE)
