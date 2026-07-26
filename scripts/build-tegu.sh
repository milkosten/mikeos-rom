#!/usr/bin/env bash
#
# build-tegu.sh — build the MikeOS ROM for tegu (Pixel 9a).
#
# RUN THIS INSIDE THE BUILD CONTAINER, from the source root (default /srv/src),
# where the LineageOS 23.2 tree has already been `repo init`+`repo sync`'d.
# It does NOT sync sources (a sync is expensive and runs separately).
#
# It is safe to re-run.
#
# Prereqs (done once, see README runbook):
#   * repo init -u https://github.com/LineageOS/android.git -b lineage-23.2
#   * .repo/local_manifests/mikeos.xml in place (from this repo)
#   * repo sync
#   * this repo cloned/symlinked to $SRC_ROOT/vendor/mikeos
#   * tegu proprietary blobs extracted (see the BLOBS note below)
#
# Usage:
#   SRC_ROOT=/srv/src ./build-tegu.sh
#   VARIANT=user ./build-tegu.sh          # release variant (default: userdebug)

set -euo pipefail

SRC_ROOT="${SRC_ROOT:-/srv/src}"
VARIANT="${VARIANT:-userdebug}"          # userdebug | user
JOBS="${JOBS:-$(nproc)}"

banner() { printf '\n========== %s ==========\n' "$*"; }

banner "MikeOS ROM build — tegu (Pixel 9a) — variant=${VARIANT}"
echo "SRC_ROOT=${SRC_ROOT}  JOBS=${JOBS}"

cd "${SRC_ROOT}"

# --- ccache (big win on incremental builds) -----------------------------------
export USE_CCACHE=1
export CCACHE_EXEC="${CCACHE_EXEC:-$(command -v ccache || true)}"
export CCACHE_DIR="${CCACHE_DIR:-${SRC_ROOT}/.ccache}"
if [ -n "${CCACHE_EXEC}" ]; then
  ccache -M "${CCACHE_MAXSIZE:-100G}" >/dev/null 2>&1 || true
  echo "ccache: ${CCACHE_EXEC}  dir=${CCACHE_DIR}"
else
  echo "ccache: NOT found — build will be slower (set CCACHE_EXEC to enable)."
fi

# --- MikeOS: ensure LINEAGE_BUILD is derived for our mikeos_ product prefix ----
# LineageOS keys a lot of plumbing (BoardConfigLineage.mk / BoardConfigSoong.mk,
# which populate the lineageVarsPlugin soong namespace used by the kernel-header
# genrules) on LINEAGE_BUILD being non-empty. check_product() in
# vendor/lineage/build/envsetup.sh only sets LINEAGE_BUILD when the product name
# starts with "lineage_". Our product is mikeos_tegu, so without this the soong
# build fails with: unknown variable '$(TARGET_KERNEL_PLATFORM_TARGET)' /
# '$(KERNEL_BUILD_OUT_PREFIX)'. Teach check_product() the mikeos_ prefix too.
# Idempotent; re-applied here so a repo sync of vendor/lineage cannot silently
# revert it. See BUILD-FIXES-tegu.md.
banner "ensure LINEAGE_BUILD handles mikeos_ prefix (kernel soong vars)"
LINEAGE_ENVSETUP="${SRC_ROOT}/vendor/lineage/build/envsetup.sh"
if [ -f "${LINEAGE_ENVSETUP}" ] && ! grep -q 'mikeos_' "${LINEAGE_ENVSETUP}"; then
  python3 "${SRC_ROOT}/vendor/mikeos/scripts/patch-lineage-build-prefix.py" "${LINEAGE_ENVSETUP}"
else
  echo "  LINEAGE_BUILD mikeos_ prefix already handled (or patcher n/a)"
fi

# --- Envsetup -----------------------------------------------------------------
banner "source build/envsetup.sh"
# shellcheck disable=SC1091
source build/envsetup.sh

# --- breakfast: pull the tegu device/kernel/vendor trees via roomservice ------
# breakfast on a bare device name uses Lineage's default product; it fetches
# LineageOS/android_device_google_tegu (+ deps) into device/google/tegu and
# resolves the dependency manifest. Run it once so those trees exist before we
# lunch our own product.
banner "breakfast tegu (fetch device trees)"
breakfast tegu || {
  echo "breakfast tegu failed — ensure lineage-23.2 is synced and the device is supported." >&2
  exit 1
}

# --- Ensure vendor/mikeos is present ------------------------------------------
banner "check vendor/mikeos overlay present"
if [ ! -f "${SRC_ROOT}/vendor/mikeos/products/mikeos_tegu.mk" ]; then
  echo "ERROR: ${SRC_ROOT}/vendor/mikeos is missing." >&2
  echo "       Clone this repo into it, e.g.:" >&2
  echo "         git clone <mikeos-rom> ${SRC_ROOT}/vendor/mikeos" >&2
  echo "       (or symlink: ln -s /path/to/mikeos-rom/vendor/mikeos ${SRC_ROOT}/vendor/mikeos)" >&2
  exit 1
fi
echo "OK: vendor/mikeos/products/mikeos_tegu.mk found"

# --- BLOBS note ---------------------------------------------------------------
# The Google proprietary blobs for tegu must be present under vendor/google/tegu
# before a full build links. Two supported routes:
#   1. TheMuppets (recommended, unattended): provided by local_manifests/
#      mikeos.xml -> repo sync pulls vendor/google. Nothing else to do.
#   2. Extract from a stock image: with a stock tegu factory/OTA image or the
#      device connected in adb, run the device tree's extractor:
#         cd device/google/tegu && ./extract-files.sh <path-to-stock-or-adb>
#      This regenerates vendor/google/tegu from proprietary-files.txt.
# If the link step errors on missing tegu blobs, fix this first.
banner "blobs check (vendor/google/tegu)"
if [ -d "${SRC_ROOT}/vendor/google/tegu" ]; then
  echo "OK: vendor/google/tegu present"
else
  echo "WARN: vendor/google/tegu not found — see the BLOBS note in this script." >&2
  echo "      Continuing; the build will fail at link if blobs are truly missing." >&2
fi

# --- lunch our product + build ------------------------------------------------
# VERIFIED 2026-07-26 on the live LineageOS 23.2 build:
#   * Android 16 requires an explicit RELEASE in the combo:
#         lunch <product>-<release>-<variant>   e.g. mikeos_tegu-bp4a-userdebug
#     `lunch mikeos_tegu-userdebug` fails ("Invalid lunch combo"). The release
#     for tegu is bp4a (matches the stock BP4A.* platform); trunk_staging also exists.
#   * Do NOT use `brunch mikeos_tegu` — brunch PREPENDS `lineage_` and looks for a
#     nonexistent product `lineage_mikeos_tegu` (and tries roomservice on it).
#     For a custom product you must `lunch …` then `mka bacon`.
RELEASE="${RELEASE:-bp4a}"
banner "lunch mikeos_tegu-${RELEASE}-${VARIANT}"
lunch "mikeos_tegu-${RELEASE}-${VARIANT}" || {
  echo "lunch failed — check the release name (bp4a/trunk_staging) and that vendor/google/tegu blobs exist." >&2
  exit 1
}
echo "TARGET_PRODUCT=$(get_build_var TARGET_PRODUCT)  TARGET_RELEASE=${RELEASE}"

# --- Force the bootanimation to regenerate ------------------------------------
# Lineage's bootanimation genrule, when TARGET_BOOTANIMATION (a prebuilt zip) is set,
# just `cp`s that file to its output — but it interpolates the path as a STRING in the
# genrule cmd, NOT as a tracked `srcs` input. So a CONTENT change to our prebuilt
# (vendor/mikeos/prebuilt/media/bootanimation.zip) does NOT retrigger the copy, and the
# build ships a STALE bootanimation (it once shipped a 720x1600 zip after we'd already
# updated the source to the native 1080x2424 — letterboxed boot). Delete the cached
# genrule + install artifacts so ninja re-runs the cp from our current zip every build.
banner "force bootanimation regen (stale-genrule guard)"
find "${SRC_ROOT}/out" -path '*vendor/lineage/bootanimation*' -name 'bootanimation.zip' -delete 2>/dev/null || true
rm -f "${SRC_ROOT}/out/target/product/${PRODUCT_DEVICE:-tegu}/product/media/bootanimation.zip" 2>/dev/null || true

banner "mka bacon -j${JOBS} (build the flashable ROM zip)"
# bacon = the flashable/OTA zip target.
#
# THREADS / PERFORMANCE (learned the hard way):
#   AOSP is massively parallel — ninja runs dozens of clang++ at once. Give it cores.
#   * Size the BUILD CONTAINER to the cores the box can spare. The Hetzner box has 32
#     hardware threads; when the OSM/MikeMaps 48h import is IDLE, run the container with
#     ~28-30 cores (leave a few for the map-serving containers + host):
#         docker run --cpus=28 ...          (or: docker update --cpus=28 <container> live)
#     While the OSM import IS running, cap lower (e.g. --cpus=16) to not starve it.
#   * GOTCHA: with `--cpus=N` (a CFS *quota*), `nproc` inside the container still reports
#     the full 32, so ninja auto-tunes to -j32 and THRASHES against the quota
#     (oversubscription, load avg >> cores). Fix: pass an explicit -j that MATCHES the
#     container's real core budget (set JOBS=<the --cpus value>). Alternatively pin cores
#     with `--cpuset-cpus=0-27` so nproc reports the real count and ninja self-tunes.
#   * RAM is not the limit here (125GB; AOSP wants ~2GB/core → 28 cores ≈ 56GB). ccache
#     (USE_CCACHE=1) makes every rebuild after the first dramatically faster regardless.
# So: set JOBS to the container's core budget (default nproc), and pass it explicitly.
mka bacon -j"${JOBS}"

banner "BUILD DONE"
echo "Output ROM zip: ${SRC_ROOT}/out/target/product/tegu/*.zip"
echo "For a SIGNED release build, do NOT flash this dev zip — run scripts/sign-tegu.sh"
