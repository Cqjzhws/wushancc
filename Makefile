ARCHS := arm64
TARGET := iphone:clang:latest:12.2

include $(THEOS)/makefiles/common.mk

XCODEPROJ_NAME = AnimationSpeed
BUILD_VERSION = "3.0.0"

include $(THEOS_MAKE_PATH)/xcodeproj.mk

before-package::
	@if [ -f $(THEOS_STAGING_DIR)/Applications/$(XCODEPROJ_NAME).app/Info.plist ]; then \
		echo -e "\033[32mSigning with ldid...\033[0m"; \
		ldid -Sentitlements.plist $(THEOS_STAGING_DIR)/Applications/$(XCODEPROJ_NAME).app; \
	else \
		echo -e "\033[31mNo Info.plist found. Skipping ldid signing.\033[0m"; \
	fi
	@echo -e "\033[32mRemoving _CodeSignature folder...\033[0m"
	@rm -rf $(THEOS_STAGING_DIR)/Applications/$(XCODEPROJ_NAME).app/_CodeSignature
	@echo -e "\033[32mCopy RootHelper to package...\033[0m"
	@cp -f RebootRootHelper $(THEOS_STAGING_DIR)/Applications/$(XCODEPROJ_NAME).app/

after-package::
	@echo -e "\033[32mRenaming .ipa to .tipa...\033[0m"
	@mv ./packages/com.developlab.animationspeed_$(BUILD_VERSION)_iphoneos-arm.tipa ./packages/AnimationSpeed_$(BUILD_VERSION).tipa 2>/dev/null || true
	@mv ./packages/com.developlab.animationspeed_$(BUILD_VERSION).ipa ./packages/AnimationSpeed_$(BUILD_VERSION).tipa 2>/dev/null || true
	@ls -la ./packages/
	@echo -e "\033[1;32m\n** App Build Succeeded **\033[0m"