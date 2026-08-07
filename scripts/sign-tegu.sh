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

TF_ZIP="$(ls -t "${SRC_ROOT}"/out/dist/*target_files*.zip 2>/dev/null | head -n1 || true)"
if [ -z "${TF_ZIP}" ]; then
  echo "ERROR: no target-files zip found under out/dist/. Did 'm dist' succeed?" >&2
  exit 1
fi
echo "target-files: ${TF_ZIP}"

SIGNED_TF="${SRC_ROOT}/out/dist/${PRODUCT}-target_files-signed.zip"
FLASHABLE="${SRC_ROOT}/out/dist/${PRODUCT}-ota-signed.zip"

# --- 2. Re-sign all APKs + OTA cert with the MikeOS keys ----------------------
# --default_key_mappings points the 5 standard AOSP cert names at our KEYDIR
# (releasekey/platform/shared/media[/networkstack]). PRESIGNED prebuilts (the
# MikeOS apps) are left untouched by sign_target_files_apks by design.
banner "sign_target_files_apks"
./build/tools/releasetools/sign_target_files_apks \
    --default_key_mappings "${KEYDIR}" \
    "${TF_ZIP}" \
    "${SIGNED_TF}"
echo "signed target-files: ${SIGNED_TF}"

# --- 3. Build the flashable / sideloadable OTA zip ----------------------------
banner "ota_from_target_files (full flashable zip)"
./build/tools/releasetools/ota_from_target_files \
    -k "${KEYDIR}/releasekey" \
    --block \
    "${SIGNED_TF}" \
    "${FLASHABLE}"

banner "SIGN DONE"
echo "Flashable signed ROM: ${FLASHABLE}"
echo "Flash via Lineage recovery:  adb sideload ${FLASHABLE}"
