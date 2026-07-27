#!/usr/bin/env python3
"""Remove LineageOS's SetupWizard + AOSP Provision stub from the product package set.

WHY A PATCH (not PRODUCT_PACKAGES_REMOVE): on this tree `PRODUCT_PACKAGES_REMOVE` is a
no-op — nothing in build/make consumes it — so the modules stayed in PRODUCT_PACKAGES and
shipped, giving a second "Welcome to LineageOS" onboarding after MikeSetup. We instead
strip the module tokens from the config makefiles that add them. Idempotent; re-run each
build (a `repo sync` would revert it).

Launcher3QuickStep is deliberately KEPT (as of v13): on Android 16 the navigation bar —
even the 3-button one on phones — is rendered by Launcher3's Taskbar framework (navbar
unification; SystemUI just delegates: `mTaskbarDelegate initialized=true navBarCount=0`).
Removing QuickStep therefore removes ALL navigation (no bar, no gestures, no Recents) and
the phone is unusable — the v12 "trapped in app" incident. MikeOS Home stays the default
HOME via the config_defaultHome overlay (RoleManager assigns it silently, no chooser);
QuickStep provides navbar + Recents/app-switcher + gesture handling.

Usage: patch-remove-lineage-apps.py [SRC_ROOT=/srv/src]
"""
import os, re, sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "/srv/src"

# file -> set of exact module tokens (a whole list entry) to drop
EDITS = {
    # AOSP base product (inherited by every handheld product):
    #  - Provision: the AOSP self-provisioning stub. It is directBootAware with a
    #    priority-1 HOME filter, so on first boot it wins the PRE-UNLOCK home
    #    resolution (MikeSetup isn't direct-boot aware), silently sets
    #    device_provisioned=1 + user_setup_complete=1, and MikeSetup's
    #    skip-if-provisioned guard then hides the whole onboarding ("zero
    #    onboarding" incident, 2026-07-27). With Provision gone, FallbackHome
    #    bridges the locked window and MikeSetup (priority 100) runs the wizard.
    "build/make/target/product/handheld_system_ext.mk": {"Provision"},
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
