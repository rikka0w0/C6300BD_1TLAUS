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
ROOTFS_HOST_COMMANDS := mksquashfs unsquashfs fakeroot
.DEFAULT_GOAL := pack-firmware

include $(ROOT_DIR)/common.mk
include $(ROOT_DIR)/dropbear.mk

.PHONY: check-host-packages clean clean-linux

$(BUILD_ROOT) $(DOWNLOAD_DIR):
	mkdir -p $@

check-host-packages:
	$(call check-host-commands,$(ROOTFS_HOST_COMMANDS))

clean: clean-linux clean-dropbear clean-dropbear-host

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

	# Enable telnet if requested, and ensure /bin/startup.sh is called from rcS
	# /bin/startup.sh is our own startup script
	if [ "$(ENABLE_TELNET)" = "1" ]; then \
		sed -i "s|^\([[:space:]]*\)grep nouart /proc/cmdline > /dev/null|\1/bin/true # grep nouart /proc/cmdline > /dev/null|" \
			"$(ROOTFS_FAKEROOT)/etc/init.d/rcS"; \
	fi
	if ! sed -n '\|^/bin/startup\.sh$$|q 0; $$q 1' "$(ROOTFS_FAKEROOT)/etc/init.d/rcS"; then \
		sed -i '$$a/bin/startup.sh' "$(ROOTFS_FAKEROOT)/etc/init.d/rcS"; \
	fi

	# Install dropbear binaries
ifeq ($(ENABLE_DROPBEAR),1)
	$(call stage-dropbear-in-rootfs,$(ROOTFS_FAKEROOT))
endif

	"$(ROOT_DIR)/c6300bd-sqfs-pack.sh" -f "$(ROOTFS_FAKEROOT)" "$@"

pack-linux-rootfs: $(PATCHED_LINUX_ROOTFS)

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

ifeq ($(ENABLE_DROPBEAR),1)
$(PATCHED_LINUX_ROOTFS): $(DROPBEAR_MULTI) | dropbearkey-host-gen-hostkey
endif
