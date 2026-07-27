#!/usr/bin/env python3
"""Remove LineageOS's Trebuchet launcher + SetupWizard from the product package set.

WHY A PATCH (not PRODUCT_PACKAGES_REMOVE): on this tree `PRODUCT_PACKAGES_REMOVE` is a
no-op — nothing in build/make consumes it — so the modules stayed in PRODUCT_PACKAGES and
shipped in system_ext, giving a "pick a launcher" chooser AND a second "Welcome to
LineageOS" onboarding after MikeSetup. We instead strip the module tokens from the Lineage
config makefiles that add them. Idempotent; re-run each build (a `repo sync` of
vendor/lineage would revert it). MikeOS Home + MikeSetup replace both.

Usage: patch-remove-lineage-apps.py [SRC_ROOT=/srv/src]
"""
import os, re, sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "/srv/src"

# file -> set of exact module tokens (a whole list entry) to drop
EDITS = {
    # AOSP base product default launcher (inherited by every handheld product) —
    # this is the one that actually keeps Trebuchet/Launcher3QuickStep in the set.
    "build/make/target/product/handheld_system_ext.mk": {"Launcher3QuickStep"},
    "vendor/lineage/config/common_mobile.mk": {"Launcher3QuickStep"},
    "vendor/lineage/config/common.mk":        {"LineageSetupWizard"},
}

for rel, mods in EDITS.items():
    path = os.path.join(SRC, rel)
    if not os.path.isfile(path):
        print(f"  skip (not found): {rel}")
        continue
    lines = open(path, "r").read().split("\n")
    out, removed = [], 0
    for ln in lines:
        token = ln.strip().rstrip("\\").strip()
        if token in mods:
            removed += 1
            # Keep line-continuation valid: preserve a trailing backslash if present
            # (leaves an empty list slot), else emit an empty line.
            if ln.rstrip().endswith("\\"):
                indent = re.match(r"^(\s*)", ln).group(1)
                out.append(indent + "\\")
            else:
                out.append("")
            continue
        out.append(ln)
    open(path, "w").write("\n".join(out))
    print(f"  patched {rel}: removed {sorted(mods)} ({removed} line(s))")

print("done")
