#!/usr/bin/env bash
#
# fetch-apps.sh — (re)download every MikeOS app APK from the MikeOS App Store
# into vendor/mikeos/prebuilt/apps/<package>.apk, then regenerate the prebuilt
# Android.mk so its BUILD_PREBUILT module list stays in sync with what's on disk.
#
# Idempotent: safe to re-run. Downloads to a .tmp then atomically mv's into
# place, so an interrupted run never leaves a truncated APK in the tree.
#
# Requires: curl, python3. Reads $APPSTORE_URL from ~/.mikeos/provider-keys.env
# (falls back to the known public URL if the env file is absent).
#
# Usage:
#   scripts/fetch-apps.sh            # fetch all + regenerate Android.mk
#
# NOTE on signing: these are the store's release/debug-signed APKs. We install
# them with LOCAL_CERTIFICATE := PRESIGNED, which tells the build to keep each
# APK's existing signature untouched. That is REQUIRED so the on-device App
# Store / daemon Updater can OTA-update them later (an update APK must be signed
# by the same key as the installed one). Do NOT re-sign these with the platform
# key.

set -euo pipefail

# --- Locate repo paths --------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APPS_DIR="${REPO_ROOT}/vendor/mikeos/prebuilt/apps"
ANDROID_MK="${APPS_DIR}/Android.mk"
mkdir -p "${APPS_DIR}"

# --- Config -------------------------------------------------------------------
KEYS_ENV="${HOME}/.mikeos/provider-keys.env"
if [ -f "${KEYS_ENV}" ]; then
  # shellcheck disable=SC1090
  set -a; source "${KEYS_ENV}"; set +a
fi
APPSTORE_URL="${APPSTORE_URL:-https://mikeos-appstore.up.railway.app}"

echo "==> MikeOS app fetch"
echo "    store : ${APPSTORE_URL}"
echo "    dest  : ${APPS_DIR}"

# --- 1. Pull the catalog and extract com.mikeos.* packages --------------------
CATALOG_JSON="$(curl -fsS -m 60 "${APPSTORE_URL}/api/apps")"

# Distinct, sorted, only well-formed com.mikeos.* ids. The catalog has
# occasionally contained a stray malformed id (e.g. "mikeos-shopping"); the
# regex filter drops anything that isn't a real dotted package.
mapfile -t PACKAGES < <(printf '%s' "${CATALOG_JSON}" | python3 -c '
import sys, json, re
d = json.load(sys.stdin)
apps = d["apps"] if isinstance(d, dict) and "apps" in d else d
pkgs = set()
for a in apps:
    p = a.get("app", "")
    if re.fullmatch(r"com\.mikeos\.[a-z0-9]+", p):
        pkgs.add(p)
for p in sorted(pkgs):
    print(p)
')

echo "==> ${#PACKAGES[@]} MikeOS packages in catalog"

# --- 2. Download each latest APK ----------------------------------------------
OK=(); FAIL=()
for pkg in "${PACKAGES[@]}"; do
  out="${APPS_DIR}/${pkg}.apk"
  tmp="${out}.tmp"
  url="${APPSTORE_URL}/api/apps/${pkg}/download"
  printf '    %-28s ' "${pkg}"
  # -f: fail on HTTP >=400 (no truncated body written); -L: follow redirects.
  if curl -fsSL -m 300 -o "${tmp}" "${url}"; then
    # Sanity: must be a ZIP/APK (PK\x03\x04). Guards against an HTML error page.
    if [ -s "${tmp}" ] && [ "$(head -c 2 "${tmp}")" = "PK" ]; then
      mv -f "${tmp}" "${out}"
      sz=$(stat -c%s "${out}" 2>/dev/null || echo '?')
      echo "ok (${sz} bytes)"
      OK+=("${pkg}")
    else
      rm -f "${tmp}"
      echo "FAIL (not an APK / empty)"
      FAIL+=("${pkg}")
    fi
  else
    rm -f "${tmp}"
    echo "FAIL (download error)"
    FAIL+=("${pkg}")
  fi
done

echo "==> downloaded: ${#OK[@]}   failed: ${#FAIL[@]}"
if [ "${#FAIL[@]}" -gt 0 ]; then
  echo "    (failed, left previous copy if any): ${FAIL[*]}"
fi

# --- 3. Map package -> Soong/Make module name ---------------------------------
# Stable, deterministic mapping so common.mk's PRODUCT_PACKAGES list matches.
#   com.mikeos.launcher -> MikeHome     (the default launcher; special-cased)
#   com.mikeos.setup    -> MikeSetup    (the Setup Wizard; special-cased)
#   com.mikeos.<x>      -> Mike<Titlecased x>   (e.g. browser -> MikeBrowser)
module_name_for() {
  local pkg="$1" suffix
  suffix="${pkg#com.mikeos.}"
  case "${pkg}" in
    com.mikeos.launcher) echo "MikeHome" ;;
    com.mikeos.setup)    echo "MikeSetup" ;;
    *) # Titlecase the suffix: browser -> Browser, ai -> Ai
       echo "Mike$(printf '%s' "${suffix:0:1}" | tr '[:lower:]' '[:upper:]')${suffix:1}" ;;
  esac
}

# launcher + setup + voice go to priv-app (privileged); everything else to product/app.
#
# com.mikeos.voice is privileged because the two-stream call recorder needs
# CAPTURE_AUDIO_OUTPUT, which is signature|privileged: the platform signature
# ALONE is not enough, the app must also sit in priv-app AND be listed in a
# privapp-permissions allowlist. Proven on tegu 2026-08-06 — without both,
# CAPTURE_AUDIO_OUTPUT reports granted=false and VOICE_UPLINK/VOICE_DOWNLINK
# return silence. The allowlist ships at
# vendor/mikeos/etc/permissions/privapp-permissions-com.mikeos.voice.xml
# (copied to /product/etc/permissions by config/common.mk).
is_privileged() {
  case "$1" in
    com.mikeos.launcher|com.mikeos.setup|com.mikeos.voice) return 0 ;;
    *) return 1 ;;
  esac
}

# --- 4. Regenerate Android.mk from the APKs actually on disk ------------------
# We enumerate the .apk files present (not the catalog) so the module list can
# never reference an APK that failed to download.
shopt -s nullglob
APK_FILES=("${APPS_DIR}"/com.mikeos.*.apk)
shopt -u nullglob

{
  cat <<'HEADER'
# =============================================================================
# MikeOS ROM — prebuilt app modules (AUTO-GENERATED by scripts/fetch-apps.sh).
#
# DO NOT edit by hand — re-run scripts/fetch-apps.sh to regenerate. One
# BUILD_PREBUILT module per MikeOS APK. All are LOCAL_CERTIFICATE := PRESIGNED
# so the store's original signatures are preserved (required for OTA updates
# from the on-device App Store to keep working — an update must be signed by the
# same key as the installed app).
#
# Module names are referenced from vendor/mikeos/config/common.mk via
# PRODUCT_PACKAGES. Keep the two in sync (this script emits both sides from the
# same package->module mapping).
#
# launcher (MikeHome) and setup (MikeSetup) are placed in priv-app (privileged)
# so they can hold privileged permissions (default HOME role, setup wizard
# flows). Everything else lands in the product partition's /app.
#
# KNOWN-UNVERIFIED (see README): priv-app placement may require a matching
# privapp-permissions allowlist entry on Android 16 if either app requests a
# signature|privileged permission; if the build fails with a
# "privapp-permissions" / "not allowed" error, add an allowlist XML under
# vendor/mikeos/ (etc/permissions) or move the app back to /app.
# =============================================================================

LOCAL_PATH := $(call my-dir)

HEADER

  for apk in "${APK_FILES[@]}"; do
    base="$(basename "${apk}")"          # com.mikeos.browser.apk
    pkg="${base%.apk}"                    # com.mikeos.browser
    mod="$(module_name_for "${pkg}")"
    if is_privileged "${pkg}"; then
      path='$(TARGET_OUT_PRODUCT)/priv-app'
      priv_note="   # privileged (priv-app)"
    else
      path='$(TARGET_OUT_PRODUCT)/app'
      priv_note=""
    fi
    cat <<MODULE
# ${pkg}${priv_note}
include \$(CLEAR_VARS)
LOCAL_MODULE := ${mod}
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := \$(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_SRC_FILES := ${base}
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_MODULE_PATH := ${path}
LOCAL_DEX_PREOPT := false
include \$(BUILD_PREBUILT)

MODULE
  done
} > "${ANDROID_MK}"

echo "==> regenerated ${ANDROID_MK} (${#APK_FILES[@]} modules)"

# --- 5. Emit the PRODUCT_PACKAGES line for common.mk (informational) ----------
# Print the module list so common.mk can be kept in sync by a human if the app
# set ever changes. common.mk currently lists these explicitly.
echo "==> module names (for common.mk PRODUCT_PACKAGES):"
for apk in "${APK_FILES[@]}"; do
  base="$(basename "${apk}")"; pkg="${base%.apk}"
  printf '    %s\n' "$(module_name_for "${pkg}")"
done

echo "==> done."
