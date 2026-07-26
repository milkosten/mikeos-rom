# MikeOS ROM — product registration for the build system.
#
# The Android build system discovers products by finding AndroidProducts.mk
# files on PRODUCT_MAKEFILE_PATHS (which includes vendor/*/products). Every
# product makefile we ship must be listed in PRODUCT_MAKEFILES, and every
# lunch/breakfast combo we want to appear must be in COMMON_LUNCH_CHOICES.

PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/mikeos_tegu.mk

# tegu = Pixel 9a. userdebug for development (adb root, more logging),
# user for a locked-down release build.
COMMON_LUNCH_CHOICES := \
    mikeos_tegu-userdebug \
    mikeos_tegu-user
