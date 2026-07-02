CURL_VERSION ?= 8.21.0
CURL_ENABLE_SSL ?= 1
CURL_ENABLE_IPV6 ?= 1
CURL_ENABLE_HTTP2 ?= 1
NGHTTP2_VERSION ?= 1.66.0

CURL_TAR := curl-$(CURL_VERSION).tar.gz
CURL_URL := https://curl.se/download/$(CURL_TAR)
CURL_TAR_PATH := $(DOWNLOAD_DIR)/$(CURL_TAR)
CURL_SRC_DIR := $(BUILD_ROOT)/curl-$(CURL_VERSION)
CURL_BIN := $(CURL_SRC_DIR)/src/curl
CURL_DEPS_BUILD_DIR := $(BUILD_ROOT)/curl-deps
CURL_DEPS_PREFIX := $(CURL_DEPS_BUILD_DIR)/prefix
NGHTTP2_TAR := nghttp2-$(NGHTTP2_VERSION).tar.xz
NGHTTP2_URL := https://github.com/nghttp2/nghttp2/releases/download/v$(NGHTTP2_VERSION)/$(NGHTTP2_TAR)
NGHTTP2_TAR_PATH := $(DOWNLOAD_DIR)/$(NGHTTP2_TAR)
NGHTTP2_SRC_DIR := $(CURL_DEPS_BUILD_DIR)/nghttp2-$(NGHTTP2_VERSION)
NGHTTP2_BUILD_DIR := $(CURL_DEPS_BUILD_DIR)/nghttp2-build
NGHTTP2_STAMP := $(CURL_DEPS_PREFIX)/.nghttp2-installed
CURL_CONFIGURE_DEPS :=
CURL_PROTOCOL_CONFIGURE_FLAGS :=
CURL_PROTOCOL_LDFLAGS :=
CURL_PROTOCOL_LIBS :=

ifeq ($(CURL_ENABLE_HTTP2),1)
CURL_PROTOCOL_CONFIGURE_FLAGS += --with-nghttp2=$(CURL_DEPS_PREFIX)
CURL_PROTOCOL_LDFLAGS += -L$(CURL_DEPS_PREFIX)/lib
CURL_PROTOCOL_LIBS += -lnghttp2
CURL_CONFIGURE_DEPS += $(NGHTTP2_STAMP)
else
CURL_PROTOCOL_CONFIGURE_FLAGS += --without-nghttp2
endif

CURL_PROTOCOL_CONFIGURE_FLAGS += --without-nghttp3 --without-ngtcp2

ifeq ($(CURL_ENABLE_SSL),1)
CURL_SSL_CONFIGURE_FLAGS := \
	--with-openssl=$(TARGET_STAGING_DIR)/usr \
	--with-ca-bundle=/etc/ssl/certs/ca-certificates.crt
CURL_FEATURE_LDFLAGS := $(CURL_PROTOCOL_LDFLAGS) -L$(TARGET_STAGING_DIR)/usr/lib -L$(TARGET_STAGING_DIR)/root-bmips/lib -pthread
CURL_FEATURE_LIBS := $(CURL_PROTOCOL_LIBS) -lssl -lcrypto -lz -ldl -l:libatomic.a
else
CURL_SSL_CONFIGURE_FLAGS := \
	--without-ssl \
	--without-ca-bundle \
	--without-ca-path \
	--without-ca-fallback \
	--without-ca-embed
CURL_FEATURE_LDFLAGS := $(CURL_PROTOCOL_LDFLAGS)
CURL_FEATURE_LIBS := $(CURL_PROTOCOL_LIBS)
endif

ifeq ($(CURL_ENABLE_IPV6),1)
CURL_IPV6_CONFIGURE_FLAGS := --enable-ipv6
else
CURL_IPV6_CONFIGURE_FLAGS := --disable-ipv6
endif

ifneq ($(strip $(CFLAGS)),)
CURL_CFLAGS ?= $(CFLAGS)
else
CURL_CFLAGS ?= -Os -fno-pie -mips32 -EB
endif
ifneq ($(strip $(CPPFLAGS)),)
CURL_CPPFLAGS ?= $(CPPFLAGS)
else
CURL_CPPFLAGS ?= -I$(CURL_DEPS_PREFIX)/include -I$(TARGET_STAGING_DIR)/usr/include
endif
ifneq ($(strip $(LDFLAGS)),)
CURL_LDFLAGS ?= $(LDFLAGS)
else
CURL_LDFLAGS ?= -Wl,-Bstatic -static-libgcc -no-pie $(CURL_FEATURE_LDFLAGS)
endif
CURL_LIBS ?= $(CURL_FEATURE_LIBS)
CURL_CONFIGURE_ENV := \
	ac_cv_func_getaddrinfo=no \
	ac_cv_func_freeaddrinfo=no \
	ac_cv_func_getnameinfo=no \
	ac_cv_func_getifaddrs=no \
	curl_cv_func_getaddrinfo=no \
	curl_cv_func_getaddrinfo_threadsafe=no \
	curl_cv_func_freeaddrinfo=no \
	curl_cv_func_getnameinfo=no \
	curl_cv_func_getifaddrs=no \
	ac_cv_header_pthread_h=no \
	ac_cv_func_pthread_create=no \
	ac_cv_lib_pthread_pthread_create=no

CURL_CONFIGURE_FLAGS := \
	--host=$(TARGET) \
	--disable-dependency-tracking \
	--disable-shared \
	--enable-static \
	--enable-symbol-hiding \
	--enable-http \
	--enable-ftp \
	--enable-file \
	--disable-ipfs \
	--disable-ldap \
	--disable-ldaps \
	--disable-rtsp \
	--enable-proxy \
	--disable-dict \
	--enable-telnet \
	--enable-tftp \
	--disable-pop3 \
	--disable-imap \
	--enable-smb \
	--disable-smtp \
	--disable-gopher \
	--disable-mqtt \
	--without-zlib \
	$(CURL_SSL_CONFIGURE_FLAGS) \
	--without-brotli \
	--without-gssapi \
	--without-libgsasl \
	--without-libidn2 \
	--without-libpsl \
	--without-libssh \
	--without-libssh2 \
	--without-libuv \
	$(CURL_PROTOCOL_CONFIGURE_FLAGS) \
	--without-quiche \
	--without-zstd \
	--disable-ares \
	--disable-httpsrr \
	--disable-ech \
	--disable-ssls-export \
	--disable-proxy-http3 \
	--disable-libcurl-option \
	$(CURL_IPV6_CONFIGURE_FLAGS) \
	--disable-ca-native \
	--disable-ca-search \
	--disable-ca-search-safe \
	--disable-threaded-resolver \
	--enable-basic-auth \
	--enable-bearer-auth \
	--disable-digest-auth \
	--disable-kerberos-auth \
	--disable-negotiate-auth \
	--disable-aws \
	--enable-ntlm \
	--disable-tls-srp \
	--disable-unix-sockets \
	--disable-cookies \
	--disable-socketpair \
	--enable-http-auth \
	--disable-doh \
	--disable-mime \
	--disable-bindlocal \
	--disable-form-api \
	--disable-dateparse \
	--disable-netrc \
	--enable-progress-meter \
	--disable-sha512-256 \
	--disable-dnsshuffle \
	--disable-get-easy-options \
	--disable-alt-svc \
	--enable-headers-api \
	--disable-hsts \
	--enable-websockets \
	--disable-debug \
	--disable-docs \
	--disable-manual

.PHONY: curl check-curl clean-curl clean-curl-deps distclean-curl

curl: $(CURL_BIN)

$(NGHTTP2_TAR_PATH): | $(DOWNLOAD_DIR)
	@echo "Downloading $(NGHTTP2_URL)"
	@if command -v curl >/dev/null 2>&1; then \
		curl -fL --retry 3 -o "$@" "$(NGHTTP2_URL)"; \
	elif command -v wget >/dev/null 2>&1; then \
		wget -O "$@" "$(NGHTTP2_URL)"; \
	else \
		echo "error: curl or wget is required to download $(NGHTTP2_URL)" >&2; \
		exit 1; \
	fi

$(NGHTTP2_STAMP): $(NGHTTP2_TAR_PATH) | $(BUILD_ROOT)
	rm -rf "$(CURL_DEPS_PREFIX)" "$(NGHTTP2_SRC_DIR)" "$(NGHTTP2_BUILD_DIR)"
	mkdir -p "$(CURL_DEPS_BUILD_DIR)"
	tar -C "$(CURL_DEPS_BUILD_DIR)" -xf "$(NGHTTP2_TAR_PATH)"
	STAGING_DIR="$(STAGING_DIR)" cmake -S "$(NGHTTP2_SRC_DIR)" -B "$(NGHTTP2_BUILD_DIR)" \
		-DCMAKE_SYSTEM_NAME=Linux \
		-DCMAKE_C_COMPILER="$(CC)" \
		-DCMAKE_AR="$(AR)" \
		-DCMAKE_RANLIB="$(RANLIB)" \
		-DCMAKE_FIND_ROOT_PATH="$(TARGET_STAGING_DIR);$(CURL_DEPS_PREFIX)" \
		-DCMAKE_INSTALL_PREFIX="$(CURL_DEPS_PREFIX)" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_C_FLAGS="$(CURL_CFLAGS)" \
		-DCMAKE_EXE_LINKER_FLAGS="-no-pie" \
		-DBUILD_SHARED_LIBS=OFF \
		-DBUILD_STATIC_LIBS=ON \
		-DENABLE_LIB_ONLY=ON
	cmake --build "$(NGHTTP2_BUILD_DIR)" --parallel "$(JOBS)"
	cmake --install "$(NGHTTP2_BUILD_DIR)"
	touch "$@"

$(CURL_TAR_PATH): | $(DOWNLOAD_DIR)
	@echo "Downloading $(CURL_URL)"
	@if command -v curl >/dev/null 2>&1; then \
		curl -fL --retry 3 -o "$@" "$(CURL_URL)"; \
	elif command -v wget >/dev/null 2>&1; then \
		wget -O "$@" "$(CURL_URL)"; \
	else \
		echo "error: curl or wget is required to download $(CURL_URL)" >&2; \
		exit 1; \
	fi

$(CURL_SRC_DIR)/.unpacked: $(CURL_TAR_PATH) | $(BUILD_ROOT)
	rm -rf "$(CURL_SRC_DIR)"
	tar -C "$(BUILD_ROOT)" -xf "$(CURL_TAR_PATH)"
	touch "$@"

$(CURL_SRC_DIR)/.configured: $(CURL_SRC_DIR)/.unpacked $(CURL_CONFIGURE_DEPS)
	cd "$(CURL_SRC_DIR)" && \
		CC="$(CC)" \
		AR="$(AR)" \
		RANLIB="$(RANLIB)" \
		STRIP="$(STRIP)" \
		PKG_CONFIG_LIBDIR="$(CURL_DEPS_PREFIX)/lib/pkgconfig" \
		PKG_CONFIG_SYSROOT_DIR="" \
		CFLAGS="$(CURL_CFLAGS)" \
		CPPFLAGS="$(CURL_CPPFLAGS)" \
		LDFLAGS="$(CURL_LDFLAGS)" \
		LIBS="$(CURL_LIBS)" \
		$(CURL_CONFIGURE_ENV) \
		./configure $(CURL_CONFIGURE_FLAGS)
	sed -i \
		-e 's/^#define HAVE_FREEADDRINFO 1$$/\/\* #undef HAVE_FREEADDRINFO \*\//' \
		-e 's/^#define HAVE_GETADDRINFO 1$$/\/\* #undef HAVE_GETADDRINFO \*\//' \
		-e 's/^#define HAVE_GETADDRINFO_THREADSAFE 1$$/\/\* #undef HAVE_GETADDRINFO_THREADSAFE \*\//' \
		-e 's/^#define HAVE_GETIFADDRS 1$$/\/\* #undef HAVE_GETIFADDRS \*\//' \
		"$(CURL_SRC_DIR)/lib/curl_config.h"
	sed -i \
		-e 's/^#define USE_ALARM_TIMEOUT$$/\/\* #undef USE_ALARM_TIMEOUT \*\//' \
		"$(CURL_SRC_DIR)/lib/hostip.c"
	touch "$@"

$(CURL_BIN): $(CURL_SRC_DIR)/.configured | $(BUILD_ROOT)
	$(MAKE) -C "$(CURL_SRC_DIR)" -j "$(JOBS)"
ifeq ($(STRIP_BINARY),1)
	"$(STRIP)" "$@"
endif
	@echo
	@echo "Built $@"
	@if command -v file >/dev/null 2>&1; then file "$@"; fi
	@"$(READELF)" -h "$@" | sed -n '/Class:/p;/Data:/p;/Machine:/p;/Flags:/p'
	@"$(READELF)" -d "$@" || true

check-curl: $(CURL_BIN)
	@if command -v file >/dev/null 2>&1; then file "$(CURL_BIN)"; fi
	"$(READELF)" -h "$(CURL_BIN)" | sed -n '/Class:/p;/Data:/p;/Machine:/p;/Flags:/p'
	"$(READELF)" -d "$(CURL_BIN)" || true

clean-curl:
	rm -rf "$(CURL_SRC_DIR)" "$(BUILD_ROOT)/curl"

clean-curl-deps:
	rm -rf "$(CURL_DEPS_BUILD_DIR)"

distclean-curl: clean-curl clean-curl-deps
	rm -f "$(CURL_TAR_PATH)" "$(NGHTTP2_TAR_PATH)"
