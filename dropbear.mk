DROPBEAR_VERSION ?= 2025.88
PROGRAMS ?= dropbear dbclient dropbearkey dropbearconvert scp
ifneq ($(strip $(CFLAGS)),)
DROPBEAR_CFLAGS ?= $(CFLAGS)
else
DROPBEAR_CFLAGS ?= -Os -fno-pie -mips32 -EB -Wno-undef
endif
ifneq ($(strip $(LDFLAGS)),)
DROPBEAR_LDFLAGS ?= $(LDFLAGS)
else
DROPBEAR_LDFLAGS ?= -static -no-pie
endif
ifneq ($(strip $(CPPFLAGS)),)
DROPBEAR_CPPFLAGS ?= $(CPPFLAGS)
else
DROPBEAR_CPPFLAGS ?= -DDROPBEAR_X11FWD -DDROPBEAR_ALLOW_RO_BSDPTY=1
endif
STRIP_BINARY ?= 1
DISABLE_LOGIN_RECORDS ?= 1
JOBS ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)

DROPBEAR_TAR := dropbear-$(DROPBEAR_VERSION).tar.bz2
DROPBEAR_URL := https://matt.ucc.asn.au/dropbear/releases/$(DROPBEAR_TAR)
DROPBEAR_TAR_PATH := $(DOWNLOAD_DIR)/$(DROPBEAR_TAR)
DROPBEAR_SRC_DIR := $(BUILD_ROOT)/dropbear-$(DROPBEAR_VERSION)
DROPBEAR_MULTI := $(DROPBEAR_SRC_DIR)/dropbearmulti
HOST_DROPBEARKEY := $(BUILD_ROOT)/dropbearkey
ROOTFS_DROPBEAR_DIR := $(ROOTFS_MERGE)/etc/dropbear
ROOTFS_DROPBEAR_ED25519_HOST_KEY := $(ROOTFS_DROPBEAR_DIR)/dropbear_ed25519_host_key
ROOTFS_DROPBEAR_RSA_HOST_KEY := $(ROOTFS_DROPBEAR_DIR)/dropbear_rsa_host_key
DROPBEAR_PATCH_FILE := $(ROOT_DIR)/dropbear-2025.88-ro-bsd-pty.patch

define stage-dropbear-in-rootfs
mkdir -p "$(1)/usr/sbin" "$(1)/usr/bin"
cp "$(DROPBEAR_MULTI)" "$(1)/usr/sbin/dropbearmulti"
chmod 775 "$(1)/usr/sbin/dropbearmulti"
ln -sf dropbearmulti "$(1)/usr/sbin/dropbear"
ln -sf ../sbin/dropbearmulti "$(1)/usr/bin/dropbearkey"
ln -sf ../sbin/dropbearmulti "$(1)/usr/bin/dropbearconvert"
ln -sf ../sbin/dropbearmulti "$(1)/usr/bin/dbclient"
ln -sf ../sbin/dropbearmulti "$(1)/usr/bin/ssh"
ln -sf ../sbin/dropbearmulti "$(1)/usr/bin/scp"
endef

DROPBEAR_CONFIGURE_FLAGS := \
	--host=$(TARGET) \
	--disable-pam \
	--disable-zlib \
	--enable-bundled-libtom \
	--enable-static \
	--disable-openpty

ifeq ($(DISABLE_LOGIN_RECORDS),1)
DROPBEAR_CONFIGURE_FLAGS += \
	--disable-lastlog \
	--disable-utmp \
	--disable-utmpx \
	--disable-wtmp \
	--disable-wtmpx \
	--disable-pututline \
	--disable-pututxline
endif

.PHONY: check-dropbear clean-dropbear distclean-dropbear dropbearkey-host-gen-hostkey clean-dropbear-host

dropbear: $(DROPBEAR_MULTI)

$(DROPBEAR_TAR_PATH): | $(DOWNLOAD_DIR)
	@echo "Downloading $(DROPBEAR_URL)"
	@if command -v curl >/dev/null 2>&1; then \
		curl -fL --retry 3 -o "$@" "$(DROPBEAR_URL)"; \
	elif command -v wget >/dev/null 2>&1; then \
		wget -O "$@" "$(DROPBEAR_URL)"; \
	else \
		echo "error: curl or wget is required to download $(DROPBEAR_URL)" >&2; \
		exit 1; \
	fi

$(DROPBEAR_SRC_DIR)/.unpacked: $(DROPBEAR_TAR_PATH) | $(BUILD_ROOT)
	rm -rf "$(DROPBEAR_SRC_DIR)"
	tar -C "$(BUILD_ROOT)" -xf "$(DROPBEAR_TAR_PATH)"
	touch "$@"

$(DROPBEAR_SRC_DIR)/.patched: $(DROPBEAR_SRC_DIR)/.unpacked $(DROPBEAR_PATCH_FILE)
	cd "$(DROPBEAR_SRC_DIR)" && patch -p1 < "$(DROPBEAR_PATCH_FILE)"
	touch "$@"

$(DROPBEAR_SRC_DIR)/.configured: $(DROPBEAR_SRC_DIR)/.patched
	cd "$(DROPBEAR_SRC_DIR)" && \
		CC="$(CC)" \
		AR="$(AR)" \
		RANLIB="$(RANLIB)" \
		STRIP="$(STRIP)" \
		CFLAGS="$(DROPBEAR_CFLAGS)" \
		LDFLAGS="$(DROPBEAR_LDFLAGS)" \
		CPPFLAGS="$(DROPBEAR_CPPFLAGS)" \
		./configure $(DROPBEAR_CONFIGURE_FLAGS)
	touch "$@"

$(DROPBEAR_MULTI): $(DROPBEAR_SRC_DIR)/.configured
	$(MAKE) -C "$(DROPBEAR_SRC_DIR)" -j "$(JOBS)" PROGRAMS="$(PROGRAMS)" MULTI=1 ARFLAGS=rc
ifeq ($(STRIP_BINARY),1)
	"$(STRIP)" "$@"
endif
	@echo
	@echo "Built $@"
	@if command -v file >/dev/null 2>&1; then file "$@"; fi
	@"$(READELF)" -h "$@" | sed -n '/Class:/p;/Data:/p;/Machine:/p;/Flags:/p'
	@"$(READELF)" -d "$@" || true
	@echo
	@echo "PTY config:"
	@grep -E 'HAVE_OPENPTY|USE_DEV_PTMX|HAVE__GETPTY|HAVE_DEV_PTS_AND_PTC' "$(DROPBEAR_SRC_DIR)/config.h"

check-dropbear: $(DROPBEAR_MULTI)
	@if command -v file >/dev/null 2>&1; then file "$(DROPBEAR_MULTI)"; fi
	"$(READELF)" -h "$(DROPBEAR_MULTI)" | sed -n '/Class:/p;/Data:/p;/Machine:/p;/Flags:/p'
	"$(READELF)" -d "$(DROPBEAR_MULTI)" || true
	grep -E 'HAVE_OPENPTY|USE_DEV_PTMX|HAVE__GETPTY|HAVE_DEV_PTS_AND_PTC' "$(DROPBEAR_SRC_DIR)/config.h"

clean-dropbear:
	rm -rf "$(DROPBEAR_SRC_DIR)"

distclean-dropbear: clean-dropbear
	rm -f "$(DROPBEAR_TAR_PATH)"


# Host tools
$(HOST_DROPBEARKEY): | $(BUILD_ROOT)
	if command -v dropbearkey >/dev/null 2>&1; then \
		ln -sf "$$(command -v dropbearkey)" "$@"; \
	else \
		rm -rf "$(BUILD_ROOT)/dropbear.host"; \
		rm -f "$(BUILD_ROOT)"/dropbear-bin_*.deb; \
		if cd "$(BUILD_ROOT)" && apt download dropbear-bin; then \
			dpkg-deb -x "$(BUILD_ROOT)"/dropbear-bin_*.deb "$(BUILD_ROOT)/dropbear.host"; \
			rm -f "$(BUILD_ROOT)"/dropbear-bin_*.deb; \
			ln -sf "$(BUILD_ROOT)/dropbear.host/usr/bin/dropbearkey" "$@"; \
		else \
			echo "error: dropbearkey not found, and apt download dropbear-bin failed." >&2; \
			echo "Please install dropbearkey and rerun make." >&2; \
			exit 1; \
		fi; \
	fi

dropbearkey-host: $(HOST_DROPBEARKEY)

$(ROOTFS_DROPBEAR_DIR):
	mkdir -p "$@"

$(ROOTFS_DROPBEAR_ED25519_HOST_KEY): | $(ROOTFS_DROPBEAR_DIR) $(HOST_DROPBEARKEY)
	rm -f "$@"
	"$(HOST_DROPBEARKEY)" -t ed25519 -f "$@"

$(ROOTFS_DROPBEAR_RSA_HOST_KEY): | $(ROOTFS_DROPBEAR_DIR) $(HOST_DROPBEARKEY)
	rm -f "$@"
	"$(HOST_DROPBEARKEY)" -t rsa -f "$@"

dropbearkey-host-gen-hostkey: $(ROOTFS_DROPBEAR_ED25519_HOST_KEY) $(ROOTFS_DROPBEAR_RSA_HOST_KEY)

clean-dropbear-host:
	rm -rf "$(BUILD_ROOT)/dropbear.host" "$(HOST_DROPBEARKEY)"
