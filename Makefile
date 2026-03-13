APP_NAME   := PanePilot
BUNDLE_ID  := com.panepilot.app
BUILD_DIR  := .build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
DIST_DIR   := dist
VERSION_CONFIG := Config/Version.xcconfig

CONFIGURATION ?= debug
VERSION       ?= $(shell awk -F' = ' '/^MARKETING_VERSION = / { print $$2; exit }' $(VERSION_CONFIG))
BUILD_NUMBER  ?= $(shell awk -F' = ' '/^CURRENT_PROJECT_VERSION = / { print $$2; exit }' $(VERSION_CONFIG))
SIGN_IDENTITY ?= -

SWIFT_BUILD_FLAGS :=
ifneq ($(CONFIGURATION),debug)
SWIFT_BUILD_FLAGS += -c $(CONFIGURATION)
endif

.PHONY: app package run clean

app:
	swift build $(SWIFT_BUILD_FLAGS)
	bin_dir="$$(swift build $(SWIFT_BUILD_FLAGS) --show-bin-path)"; \
	resource_bundle="$$(find "$$bin_dir" -maxdepth 1 -name '$(APP_NAME)_*.bundle' -print -quit)"; \
	rm -rf "$(APP_BUNDLE)"; \
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"; \
	cp "$$bin_dir/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"; \
	if [ -n "$$resource_bundle" ]; then \
		cp -R "$$resource_bundle" "$(APP_BUNDLE)/Contents/Resources/"; \
	fi; \
	/usr/libexec/PlistBuddy \
		-c "Add :CFBundleExecutable string $(APP_NAME)" \
		-c "Add :CFBundleIdentifier string $(BUNDLE_ID)" \
		-c "Add :CFBundleName string $(APP_NAME)" \
		-c "Add :CFBundlePackageType string APPL" \
		-c "Add :CFBundleShortVersionString string $(VERSION)" \
		-c "Add :CFBundleVersion string $(BUILD_NUMBER)" \
		-c "Add :LSMinimumSystemVersion string 13.0" \
		-c "Add :LSUIElement bool true" \
		-c "Add :NSPrincipalClass string NSApplication" \
		-c "Add :NSAccessibilityUsageDescription string PanePilot needs Accessibility access to detect window positions and resize windows." \
		"$(APP_BUNDLE)/Contents/Info.plist"; \
	codesign --force --deep --sign "$(SIGN_IDENTITY)" "$(APP_BUNDLE)"

package: app
	mkdir -p "$(DIST_DIR)"
	rm -f "$(DIST_DIR)/$(APP_NAME)-$(VERSION)-macOS.zip"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_BUNDLE)" "$(DIST_DIR)/$(APP_NAME)-$(VERSION)-macOS.zip"

run: app
	pkill -x $(APP_NAME) 2>/dev/null || true
	sleep 0.3
	open "$(APP_BUNDLE)"

clean:
	rm -rf "$(APP_BUNDLE)" "$(DIST_DIR)"
