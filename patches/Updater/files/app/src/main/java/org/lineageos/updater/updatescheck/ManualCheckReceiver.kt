/*
 * SPDX-FileCopyrightText: The MikeOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.updater.updatescheck

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * MikeOS test-bench hook: force an immediate OTA check (and, once an update is
 * available + downloaded, the normal auto-flow takes over) without the UI.
 *
 * Trigger from adb:
 *   adb shell am broadcast -a com.mikeos.ota.CHECK_NOW \
 *       -n org.lineageos.updater/.updatescheck.ManualCheckReceiver
 *
 * Exported (see AndroidManifest) so the test bench can reach it. Kept minimal for
 * the build phase; the only side effect is enqueuing a one-shot check worker.
 */
class ManualCheckReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ACTION_CHECK_NOW) {
            return
        }
        Log.i(TAG, "Manual OTA check requested via $ACTION_CHECK_NOW")
        UpdatesCheckWorker.scheduleOneshotCheck(context.applicationContext)
    }

    companion object {
        private const val TAG = "ManualCheckReceiver"
        const val ACTION_CHECK_NOW = "com.mikeos.ota.CHECK_NOW"
    }
}
