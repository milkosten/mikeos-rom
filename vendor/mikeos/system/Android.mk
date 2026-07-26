# =============================================================================
# MikeOS daemon-as-system — Soong/Make module for the launcher binary.
#
# The init service execs /product/bin/mikeos-daemon, which MUST be executable
# (+x). PRODUCT_COPY_FILES cannot set the executable bit, so the launcher ships
# as a PREBUILT EXECUTABLE module (BUILD_PREBUILT with LOCAL_MODULE_CLASS :=
# EXECUTABLES installs 0755 into .../bin). The module (mikeos-daemon) is pulled
# in by PRODUCT_PACKAGES in system-daemon.mk.
#
# This is the standard AOSP idiom for "a script that must be executable in
# a bin/ dir". (A Soong `sh_binary` in an Android.bp would be equally correct;
# this tree already uses Android.mk / BUILD_PREBUILT for its prebuilts, so we
# stay consistent with that idiom.)
#
# PARTITION: installs to /PRODUCT/bin, NOT /system/bin. tegu (Pixel) enforces
# PRODUCT_ARTIFACT_PATH_REQUIREMENT — overlay content may NOT land in /system/*
# (a /system/bin/mikeos-daemon install fails the build with
# artifact_path_requirements.mk error). All MikeOS overlay content lives on the
# product/vendor partitions. Hence LOCAL_PRODUCT_MODULE + TARGET_OUT_PRODUCT.
# The .rc (below) and sepolicy file_contexts reference /product/bin/mikeos-daemon
# to match.
# =============================================================================

LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := mikeos-daemon
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_CLASS := EXECUTABLES
# The source is the POSIX-sh launcher checked in beside this Android.mk.
LOCAL_SRC_FILES := bin/mikeos-daemon
# Install into /PRODUCT/bin (executable, 0755) — NOT /system/bin (blocked by
# tegu's PRODUCT_ARTIFACT_PATH_REQUIREMENT). LOCAL_PRODUCT_MODULE marks it as a
# product-partition module; TARGET_OUT_PRODUCT/bin is /product/bin at runtime.
LOCAL_PRODUCT_MODULE := true
LOCAL_MODULE_PATH := $(TARGET_OUT_PRODUCT)/bin
# The launcher is a POSIX-sh SCRIPT, not an ELF binary. BUILD_PREBUILT of an
# EXECUTABLES module runs check_elf_file by default, which fails the build with
# "must have a valid ELF magic word". Skip the ELF check for this script module.
LOCAL_CHECK_ELF_FILES := false
include $(BUILD_PREBUILT)
