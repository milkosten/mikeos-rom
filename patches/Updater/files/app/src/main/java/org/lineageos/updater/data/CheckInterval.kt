/*
 * SPDX-FileCopyrightText: The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.updater.data

import kotlin.time.Duration
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.hours

enum class CheckInterval(val duration: Duration, val storageValue: String) {
    // MikeOS: hourly OTA polling. WorkManager periodic minimum is 15 min, so 1h is valid.
    HOURLY(1.hours, "hourly"),
    DAILY(1.days, "daily"),
    WEEKLY(7.days, "weekly"),
    MONTHLY(30.days, "monthly");

    companion object {
        // MikeOS: default to hourly so devices pick up OTA builds quickly out of the box.
        val default = HOURLY

        fun fromStorageValue(value: String?) =
            entries.find { it.storageValue == value } ?: default
    }
}
