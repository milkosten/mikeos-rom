#!/usr/bin/env bash
#
# sign-tegu.sh — produce a SIGNED, flashable MikeOS ROM zip for tegu.
#
# Run inside the build container, from the source root, AFTER build-tegu.sh has
# produced a target-files package. This re-signs the build with the MikeOS
# release keys (from generate-keys.sh) instead of the AOSP test-keys, then wraps
# it into an OTA/flashable zip.
#
# This is the standard AOSP release-signing flow:
#   1. `m dist`            -> emits a target-files .zip under out/dist/
#   2. sign_target_files_apks -> re-signs every APK + the OTA cert with our keys
#   3. ota_from_target_files  -> builds the flashable/sideloadable zip
#
# Usage:
#   SRC_ROOT=/srv/src KEYDIR=/srv/keys/mikeos VARIANT=user ./sign-tegu.sh
#
# KNOWN-UNVERIFIED (see README): exact target-files filename glob and whether
# `m dist` vs `brunch` already produced dist output; the releasetools flags on
# lineage-23.2 (e.g. --avb_* args for AVB-signed boot on tegu). If flashing a
# signed build fails AVB verification, boot/vbmeta must be signed with the AVB
# key too (releasetools --avb_*_key / --avb_*_algorithm) — resolve at build time
# against the tegu device tree's BoardConfig AVB settings.

set -euo pipefail

SRC_ROOT="${SRC_ROOT:-/srv/src}"
KEYDIR="${KEYDIR:-${SRC_ROOT}/vendor/mikeos-keys}"
VARIANT="${VARIANT:-user}"                 # sign the release (user) variant
PRODUCT="mikeos_tegu"

banner() { printf '\n========== %s ==========\n' "$*"; }

cd "${SRC_ROOT}"
banner "MikeOS ROM sign — ${PRODUCT}-${VARIANT}"

# AOSP's envsetup.sh references unset variables (TOP); under `set -u` that aborts
# immediately with "TOP: unbound variable". Same trap as build-tegu.sh. Keep -e
# and pipefail so genuine failures still stop the signing run.
set +u
# shellcheck disable=SC1091
source build/envsetup.sh
# NOTE: VARIANT must carry the release token on this tree, e.g. "bp4a-userdebug",
# because Android 16 lunch expects product-release-variant. Plain "user" gives
# `lunch mikeos_tegu-user`, which does not resolve. Match the variant that
# build-tegu.sh actually built, or `m dist` rebuilds the world.
lunch "${PRODUCT}-${VARIANT}"

# --- 1. Produce a target-files package ----------------------------------------
banner "m dist (produce target-files)"
# `m dist` emits out/dist/<product>-target_files-*.zip. If build-tegu.sh already
# ran `brunch`, you can add `dist` there instead; running it explicitly is safe.
m dist -j"$(nproc)"

# Pick the newest UNSIGNED target-files. Excluding *signed* matters: this script
# writes its own *-target_files-*signed.zip into the same directory, and a bare
# `ls -t *target_files*` would happily pick that up on a re-run and sign an
# already-signed package.
TF_ZIP="$(ls -t "${SRC_ROOT}"/out/dist/*target_files*.zip 2>/dev/null | grep -v -- '-signed' | head -n1 || true)"
if [ -z "${TF_ZIP}" ]; then
  echo "ERROR: no target-files zip found under out/dist/. Did 'm dist' succeed?" >&2
  exit 1
fi
echo "target-files: ${TF_ZIP}"

# TAG the outputs with the ROM version (e.g. TAG=v40) so releases do not overwrite
# each other and stay greppable. Falls back to ro.mikeos.version from the overlay.
TAG="${TAG:-v$(sed -n 's/.*ro\.mikeos\.version=\([0-9]*\)-tegu.*/\1/p' \
    "${SRC_ROOT}/vendor/mikeos/config/version.mk" | head -1)}"
SIGNED_TF="${SRC_ROOT}/out/dist/${PRODUCT}-target_files-${TAG}-signed.zip"
FLASHABLE="${SRC_ROOT}/out/dist/${PRODUCT}-ota-${TAG}-signed.zip"
IMGZIP="${SRC_ROOT}/out/dist/${PRODUCT}-img-${TAG}-signed.zip"

# The releasetools that ship as SOURCE under build/make/tools/releasetools are .py
# modules; the RUNNABLE ones are the host binaries built into out/host by `m dist`
# (they bundle their deps). The old path ./build/tools/releasetools/<tool> has no
# such executable and failed with "No such file or directory".
RT="${SRC_ROOT}/out/host/linux-x86/bin"

# --- 2. Re-sign all APKs + OTA cert with the MikeOS keys ----------------------
# --default_key_mappings points the 5 standard AOSP cert names at our KEYDIR
# (releasekey/platform/shared/media[/networkstack]). PRESIGNED prebuilts (the
# MikeOS apps) are left untouched by sign_target_files_apks by design.
banner "sign_target_files_apks"
# -o replaces the OTA cert. The --avb_* flags are NOT optional on tegu: the board
# enables AVB and chains vbmeta, vbmeta_system (system/system_ext/product/
# system_dlkm), vbmeta_vendor, boot and init_boot to ONE custom key. Without them
# the APKs get MikeOS keys but every vbmeta stays signed with the AOSP test key,
# so the device fails verified boot / cannot be re-locked. One avb.pem (RSA-4096)
# for all of them, hence SHA256_RSA4096 everywhere.
AVB_ALG=SHA256_RSA4096
AVB_KEY="${KEYDIR}/avb.pem"
"${RT}/sign_target_files_apks" \
    -o \
    -d "${KEYDIR}" \
    --avb_vbmeta_key        "${AVB_KEY}" --avb_vbmeta_algorithm        "${AVB_ALG}" \
    --avb_vbmeta_system_key "${AVB_KEY}" --avb_vbmeta_system_algorithm "${AVB_ALG}" \
    --avb_vbmeta_vendor_key "${AVB_KEY}" --avb_vbmeta_vendor_algorithm "${AVB_ALG}" \
    --avb_boot_key          "${AVB_KEY}" --avb_boot_algorithm          "${AVB_ALG}" \
    --avb_init_boot_key     "${AVB_KEY}" --avb_init_boot_algorithm     "${AVB_ALG}" \
    "${TF_ZIP}" \
    "${SIGNED_TF}"
echo "signed target-files: ${SIGNED_TF}"

# --- 3. Build the flashable / sideloadable OTA zip ----------------------------
banner "ota_from_target_files (sideloadable OTA zip)"
"${RT}/ota_from_target_files" \
    -k "${KEYDIR}/releasekey" \
    "${SIGNED_TF}" \
    "${FLASHABLE}"

# --- 4. Build the fastboot image zip ------------------------------------------
# The OTA zip is for `adb sideload` from recovery; a clean flash (or recovering a
# bricked device) needs the fastboot img zip. Both come from the SAME signed
# target-files, so they are guaranteed to be the same build.
banner "img_from_target_files (fastboot image zip)"
"${RT}/img_from_target_files" "${SIGNED_TF}" "${IMGZIP}"

banner "SIGN DONE"
echo "Signed target-files : ${SIGNED_TF}"
echo "Sideload OTA zip    : ${FLASHABLE}"
echo "Fastboot image zip  : ${IMGZIP}"
echo
echo "Sideload:  adb sideload ${FLASHABLE}"
echo "Fastboot:  fastboot update ${IMGZIP}"
