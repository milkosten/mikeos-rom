/*
 * SPDX-FileCopyrightText: The MikeOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.updater.notifications

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.getSystemService
import org.lineageos.updater.R
import org.lineageos.updater.UpdatesActivity
import org.lineageos.updater.misc.Utils
import java.util.Calendar

/**
 * MikeOS install-prompt scheduler.
 *
 * When an update finishes downloading + verifying, the stock Updater already posts an
 * "update downloaded / install" notification the user can act on at any time (kept as-is).
 * ADDITIONALLY, MikeOS schedules a branded reminder at [INSTALL_PROMPT_HOUR]:00 local
 * ("MikeOS update ready — install tonight?"). Tapping it triggers the same A/B install
 * (a quick reboot to the staged slot). The user is never forced: they can ignore/defer it,
 * and the immediate download-complete notification remains available.
 *
 * Uses AlarmManager.setExactAndAllowWhileIdle so the reminder fires even in Doze.
 */
object InstallPromptScheduler {
    private const val TAG = "InstallPromptScheduler"

    /** Local hour of day (24h) at which to remind the user to install. Easy to change. */
    const val INSTALL_PROMPT_HOUR = 20

    private const val CHANNEL_INSTALL_PROMPT = "install_prompt_notification_channel"
    private const val ID_INSTALL_PROMPT = 42

    const val ACTION_INSTALL_PROMPT = "com.mikeos.ota.INSTALL_PROMPT_ALARM"
    const val EXTRA_DOWNLOAD_ID = "download_id"

    /**
     * Schedule (or reschedule) the branded install reminder for the next [INSTALL_PROMPT_HOUR]:00
     * local time. Called from the download-complete (VERIFIED) flow.
     */
    fun scheduleInstallPrompt(context: Context, downloadId: String) {
        val appContext = context.applicationContext
        val alarmManager = appContext.getSystemService<AlarmManager>() ?: run {
            Log.w(TAG, "No AlarmManager; skipping install-prompt schedule")
            return
        }

        val triggerAtMillis = nextPromptTimeMillis()

        val pendingIntent = PendingIntent.getBroadcast(
            appContext,
            ID_INSTALL_PROMPT,
            Intent(appContext, InstallPromptReceiver::class.java).apply {
                action = ACTION_INSTALL_PROMPT
                putExtra(EXTRA_DOWNLOAD_ID, downloadId)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        try {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
            Log.i(TAG, "Scheduled MikeOS install prompt for $triggerAtMillis (downloadId=$downloadId)")
        } catch (e: SecurityException) {
            // Exact-alarm permission may be withheld; fall back to inexact so we still remind.
            Log.w(TAG, "Exact alarm denied, using inexact", e)
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
        }
    }

    /** Next occurrence of [INSTALL_PROMPT_HOUR]:00 local time, in epoch millis. */
    private fun nextPromptTimeMillis(): Long {
        val now = Calendar.getInstance()
        val target = (now.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, INSTALL_PROMPT_HOUR)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (!target.after(now)) {
            target.add(Calendar.DAY_OF_YEAR, 1)
        }
        return target.timeInMillis
    }

    internal fun ensureChannel(notificationManager: NotificationManager, context: Context) {
        notificationManager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_INSTALL_PROMPT,
                context.getString(R.string.new_updates_channel_title),
                NotificationManager.IMPORTANCE_DEFAULT,
            )
        )
    }

    internal fun showInstallPrompt(context: Context, downloadId: String?) {
        val appContext = context.applicationContext
        val notificationManager = appContext.getSystemService<NotificationManager>() ?: return
        ensureChannel(notificationManager, appContext)

        // Tapping the notification triggers the same A/B install action as the UI/immediate
        // notification. If we lost the downloadId, just open the Updater so the user can act.
        val contentIntent: PendingIntent = if (downloadId != null) {
            PendingIntent.getBroadcast(
                appContext,
                1,
                Intent(appContext, InstallPromptReceiver::class.java).apply {
                    action = InstallPromptReceiver.ACTION_INSTALL_NOW
                    putExtra(EXTRA_DOWNLOAD_ID, downloadId)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        } else {
            PendingIntent.getActivity(
                appContext,
                1,
                Intent(appContext, UpdatesActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val notification = Notification.Builder(appContext, CHANNEL_INSTALL_PROMPT)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_RECOMMENDATION)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(contentIntent)
            .setContentTitle(appContext.getString(R.string.mikeos_install_prompt_title))
            .setContentText(appContext.getString(R.string.mikeos_install_prompt_text))
            .setStyle(
                Notification.BigTextStyle()
                    .bigText(appContext.getString(R.string.mikeos_install_prompt_text))
            )
            .setSmallIcon(R.drawable.ic_notification)
            .build()
        notificationManager.notify(ID_INSTALL_PROMPT, notification)
    }
}

/**
 * Fires at [InstallPromptScheduler.INSTALL_PROMPT_HOUR]:00 (the scheduled alarm) to post the
 * branded reminder, and also handles the "install now" tap (A/B: reboot to staged slot).
 */
class InstallPromptReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val downloadId = intent?.getStringExtra(InstallPromptScheduler.EXTRA_DOWNLOAD_ID)
        when (intent?.action) {
            InstallPromptScheduler.ACTION_INSTALL_PROMPT ->
                InstallPromptScheduler.showInstallPrompt(context, downloadId)

            ACTION_INSTALL_NOW -> {
                if (downloadId != null) {
                    Log.i(TAG, "User accepted MikeOS install prompt; triggering install")
                    Utils.triggerUpdate(context.applicationContext, downloadId)
                }
            }
        }
    }

    companion object {
        private const val TAG = "InstallPromptReceiver"
        const val ACTION_INSTALL_NOW = "com.mikeos.ota.INSTALL_NOW"
    }
}
