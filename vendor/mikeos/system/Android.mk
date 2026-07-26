# =============================================================================
# MikeOS daemon-as-system — Soong/Make module for the launcher binary.
#
# The init service execs /system/bin/mikeos-daemon, which MUST be executable
# (+x). PRODUCT_COPY_FILES cannot set the executable bit, so the launcher ships
# as a PREBUILT EXECUTABLE module (BUILD_PREBUILT with LOCAL_MODULE_CLASS :=
# EXECUTABLES installs 0755 into .../bin). The module (mikeos-daemon) is pulled
# in by PRODUCT_PACKAGES in system-daemon.mk.
#
# This is the standard AOSP idiom for "a script that must be executable in
# /system/bin". (A Soong `sh_binary` in an Android.bp would be equally correct;
# this tree already uses Android.mk / BUILD_PREBUILT for its prebuilts, so we
# stay consistent with that idiom.)
#
# KNOWN-UNVERIFIED (see README.md):
#   * LOCAL_MODULE_PATH := $(TARGET_OUT)/bin puts it in /system/bin. If the ROM
#     prefers /vendor/bin, switch to $(TARGET_OUT_VENDOR)/bin AND update the
#     sepolicy file_contexts + the .rc service path to match.
# =============================================================================

LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := mikeos-daemon
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_CLASS := EXECUTABLES
# The source is the POSIX-sh launcher checked in beside this Android.mk.
LOCAL_SRC_FILES := bin/mikeos-daemon
# Install into /system/bin (executable, 0755). See KNOWN-UNVERIFIED above.
LOCAL_MODULE_PATH := $(TARGET_OUT)/bin
include $(BUILD_PREBUILT)
