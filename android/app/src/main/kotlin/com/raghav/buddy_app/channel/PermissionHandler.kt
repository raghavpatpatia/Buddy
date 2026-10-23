package com.raghav.buddy_app.channel

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import com.raghav.buddy_app.BuddyCore

/** Special-access checks shared by every handler that needs one. */
object Permissions {
    fun usage(ctx: Context): Boolean {
        val ops = ctx.getSystemService(AppOpsManager::class.java)
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        else @Suppress("DEPRECATION") ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun allFiles(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Environment.isExternalStorageManager() else true

    fun battery(ctx: Context): Boolean =
        ctx.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(ctx.packageName)
}

/** Permission status and the system settings screens that grant them. */
class PermissionHandler(private val ctx: Context) : ChannelHandler {
    override val routes: Map<String, Route> = mapOf(
        "permissions" to { _, result ->
            result.success(
                mapOf(
                    "usage" to Permissions.usage(ctx),
                    "accessibility" to BuddyCore.scrollTrackerOn(ctx),
                    "allFiles" to Permissions.allFiles(),
                    "battery" to Permissions.battery(ctx),
                    "companion" to BuddyCore.prefs(ctx).getBoolean("companion_on", false),
                    // The phone maker's battery manager that can switch the tracker off, if any (e.g. "DuraSpeed").
                    "killer" to BuddyCore.backgroundKiller(ctx)?.first,
                    "trackerOffCount" to BuddyCore.prefs(ctx).getInt("tracker_off_count", 0),
                )
            )
        },
        "open" to { call, result -> openSettings(call.argument<String>("what")!!, call.argument<String>("pkg")); result.success(null) },
    )

    private fun openSettings(what: String, pkg: String?) {
        val self = ctx.packageName
        if (what == "killer") {
            BuddyCore.backgroundKiller(ctx)?.let { ctx.startActivity(it.second) }
            return
        }
        val i = when (what) {
            "usage" -> Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            "allFiles" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:$self"))
            else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$self"))
            "battery" -> Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$self"))
            "appDetails" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${pkg ?: self}"))
            "uninstall" -> Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg"))
            "storage" -> Intent(Settings.ACTION_INTERNAL_STORAGE_SETTINGS)
            else -> Intent(Settings.ACTION_SETTINGS)
        }
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ctx.startActivity(i)
    }
}
