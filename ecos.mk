# eCos firmware helpers.
# Defaults match stock-nand/image1.bin from C6300BD_1TLAUS_V1.04.13u_150901.

ECOS_FIRMWARE_PACK_IN ?= $(ROOT_DIR)/stock-nand/image1.bin
STOCK_ECOS_IMAGE := $(BUILD_ROOT)/stock-ecos.bin
PATCHED_ECOS_IMAGE := $(BUILD_ROOT)/patched-ecos.bin
PATCHED_ECOS_FIRMWARE := $(BUILD_ROOT)/C6300BD_1TLAUS_V1.04.13u_TELNET.bin

ECOS_PROGRAMSTORE_COMPRESSION ?= 4
ECOS_PROGRAMSTORE_SIGNATURE ?= a0eb
ECOS_PROGRAMSTORE_VERSION ?= 0003.0000
ECOS_PROGRAMSTORE_TIME ?= 1441096784
ECOS_PROGRAMSTORE_LOAD_ADDRESS ?= 80004000

.PHONY: clean-ecos

$(STOCK_ECOS_IMAGE): $(PROGRAMSTORE) $(ECOS_FIRMWARE_PACK_IN) | $(BUILD_ROOT)
	"$(PROGRAMSTORE)" -x -f "$(ECOS_FIRMWARE_PACK_IN)" -o "$@"

unpack-ecos: $(STOCK_ECOS_IMAGE)

$(PATCHED_ECOS_IMAGE): $(STOCK_ECOS_IMAGE) $(ROOT_DIR)/patch-ecos-vsif-telnet-enable.py $(ROOT_DIR)/patch-ecos-iphal-dload-stack.py | $(BUILD_ROOT)
	"$(ROOT_DIR)/patch-ecos-vsif-telnet-enable.py" "$(STOCK_ECOS_IMAGE)" -o "$@.tmp" -f
	"$(ROOT_DIR)/patch-ecos-iphal-dload-stack.py" "$@.tmp" -o "$@" -f
	rm -f "$@.tmp"

patch-ecos: $(PATCHED_ECOS_IMAGE)

$(PATCHED_ECOS_FIRMWARE): $(PROGRAMSTORE) $(PATCHED_ECOS_IMAGE) | $(BUILD_ROOT)
	cd "$(BUILD_ROOT)" && "$(PROGRAMSTORE)" \
		-f "$(PATCHED_ECOS_IMAGE)" \
		-o "$(@F)" \
		-c "$(ECOS_PROGRAMSTORE_COMPRESSION)" \
		-s "$(ECOS_PROGRAMSTORE_SIGNATURE)" \
		-v "$(ECOS_PROGRAMSTORE_VERSION)" \
		-t "$(ECOS_PROGRAMSTORE_TIME)" \
		-a "$(ECOS_PROGRAMSTORE_LOAD_ADDRESS)"

pack-ecos: $(PATCHED_ECOS_FIRMWARE)

clean-ecos:
	rm -f \
		"$(STOCK_ECOS_IMAGE)" \
		"$(PATCHED_ECOS_IMAGE).tmp" \
		"$(PATCHED_ECOS_IMAGE)" \
		"$(PATCHED_ECOS_FIRMWARE)"
