#!/usr/bin/env python3
# MikeOS ROM build glue.
#
# Teach LineageOS' check_product() (vendor/lineage/build/envsetup.sh) to derive
# LINEAGE_BUILD from a "mikeos_" product prefix, not only "lineage_".
#
# WHY: LineageOS gates BoardConfigLineage.mk / BoardConfigSoong.mk (which create
# the "lineageVarsPlugin" soong config namespace holding the kernel-header
# genrule vars TARGET_KERNEL_PLATFORM_TARGET, KERNEL_BUILD_OUT_PREFIX, etc.) on
# LINEAGE_BUILD being non-empty (build/make/core/config.mk:
#   ifneq ($(LINEAGE_BUILD),) ... include vendor/lineage/config/BoardConfigLineage.mk).
# check_product() only sets LINEAGE_BUILD for product names starting "lineage_".
# The MikeOS product is renamed to "mikeos_tegu" (to stop brunch mangling the
# name), so LINEAGE_BUILD stayed empty -> the namespace was never created ->
# soong errored: unknown variable '$(TARGET_KERNEL_PLATFORM_TARGET)' /
# '$(KERNEL_BUILD_OUT_PREFIX)' in vendor/lineage/build/soong/Android.bp, ninja
# stopped in seconds. Adding the mikeos_ branch fixes it.
#
# Idempotent: safe to re-run (build-tegu.sh calls it every build so a repo sync
# of vendor/lineage cannot silently revert the fix).
import sys

path = sys.argv[1]
s = open(path).read()

old = (
    '    if (echo -n $1 | grep -q -e "^lineage_") ; then\n'
    "        LINEAGE_BUILD=$(echo -n $1 | sed -e 's/^lineage_//g')\n"
    '    else\n'
    '        LINEAGE_BUILD=\n'
    '    fi'
)
new = (
    '    if (echo -n $1 | grep -q -e "^lineage_") ; then\n'
    "        LINEAGE_BUILD=$(echo -n $1 | sed -e 's/^lineage_//g')\n"
    '    elif (echo -n $1 | grep -q -e "^mikeos_") ; then\n'
    "        LINEAGE_BUILD=$(echo -n $1 | sed -e 's/^mikeos_//g')\n"
    '    else\n'
    '        LINEAGE_BUILD=\n'
    '    fi'
)

if new in s or '^mikeos_' in s:
    print("  check_product() already handles mikeos_ prefix - skipped")
    sys.exit(0)
if old not in s:
    print("  WARNING: check_product() prefix block not found - upstream may have "
          "changed; verify LINEAGE_BUILD is set for mikeos_ products manually",
          file=sys.stderr)
    sys.exit(1)
s = s.replace(old, new)
open(path, "w").write(s)
print("  patched check_product() for mikeos_ prefix")
