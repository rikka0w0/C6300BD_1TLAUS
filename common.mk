TOOLCHAIN_DIR ?= /home/rikka/mcp/openwrt/staging_dir/toolchain-mips_mips32_gcc-14.3.0_musl
CROSS_PREFIX ?= mips-openwrt-linux
TARGET_STAGING_DIR ?= /home/rikka/mcp/openwrt/staging_dir/target-mips_mips32_musl
TARGET ?= $(CROSS_PREFIX)

TOOLCHAIN_BIN := $(TOOLCHAIN_DIR)/bin
STAGING_DIR ?= $(dir $(TOOLCHAIN_DIR))
export PATH := $(TOOLCHAIN_BIN):$(PATH)
export STAGING_DIR

ifeq ($(origin CC),default)
CC := $(TOOLCHAIN_BIN)/$(CROSS_PREFIX)-gcc
endif
ifeq ($(origin AR),default)
AR := $(TOOLCHAIN_BIN)/$(CROSS_PREFIX)-ar
endif
ifeq ($(origin RANLIB),default)
RANLIB := $(TOOLCHAIN_BIN)/$(CROSS_PREFIX)-ranlib
endif
ifeq ($(origin STRIP),default)
STRIP := $(TOOLCHAIN_BIN)/$(CROSS_PREFIX)-strip
endif
READELF ?= $(TOOLCHAIN_BIN)/$(CROSS_PREFIX)-readelf
ifeq ($(strip $(CC)),)
CC := $(TOOLCHAIN_BIN)/$(CROSS_PREFIX)-gcc
endif
ifeq ($(strip $(AR)),)
AR := $(TOOLCHAIN_BIN)/$(CROSS_PREFIX)-ar
endif
ifeq ($(strip $(RANLIB)),)
RANLIB := $(TOOLCHAIN_BIN)/$(CROSS_PREFIX)-ranlib
endif
ifeq ($(strip $(STRIP)),)
STRIP := $(TOOLCHAIN_BIN)/$(CROSS_PREFIX)-strip
endif
ifeq ($(strip $(READELF)),)
READELF := $(TOOLCHAIN_BIN)/$(CROSS_PREFIX)-readelf
endif

define check-host-commands
	@missing=""; \
	for cmd in $(1); do \
		if ! command -v "$$cmd" >/dev/null 2>&1; then \
			missing="$$missing $$cmd"; \
		fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo "error: missing required host command(s):$$missing" >&2; \
		echo "Please install the missing command(s) and rerun make." >&2; \
		exit 1; \
	fi
endef
