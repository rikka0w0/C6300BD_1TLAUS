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
