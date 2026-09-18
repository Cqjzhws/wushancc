ARCHS := arm64
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AnimationSpeedTweak
AnimationSpeedTweak_FILES = Tweak.xm
AnimationSpeedTweak_FRAMEWORKS = UIKit CoreFoundation QuartzCore Foundation
AnimationSpeedTweak_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

# 单独输出 dylib 给 TrollFools 注入
after-stage::
	@mkdir -p $(THEOS_STAGING_DIR)/dylib
	@cp -f $(THEOS_OBJ_DIR)/AnimationSpeedTweak.dylib $(THEOS_STAGING_DIR)/dylib/AnimationSpeedTweak.dylib 2>/dev/null || true

# 把 dylib 拷到 packages 根目录
after-package::
	@mkdir -p ./packages/dylib
	@cp -f $(THEOS_OBJ_DIR)/AnimationSpeedTweak.dylib ./packages/dylib/AnimationSpeedTweak.dylib 2>/dev/null || true
	@echo -e "\033[1;32m\n** Tweak dylib ready **\033[0m"