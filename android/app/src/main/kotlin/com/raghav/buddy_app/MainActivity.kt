package com.raghav.buddy_app

import android.app.AppOpsManager
import android.app.usage.StorageStatsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.media.ThumbnailUtils
import android.provider.MediaStore
import android.util.Size
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.Process
import android.os.storage.StorageManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "buddy/native").setMethodCallHandler { call, result ->
            try {
                val ctx = applicationContext
                val p = BuddyCore.prefs(ctx)
                when (call.method) {
                    "permissions" -> result.success(
                        mapOf(
                            "usage" to hasUsageAccess(),
                            "accessibility" to accessibilityOn(),
                            "allFiles" to allFilesAccess(),
                            "battery" to batteryIgnored(),
                            "companion" to p.getBoolean("companion_on", false),
                        )
                    )
                    "open" -> { openSettings(call.argument<String>("what")!!, call.argument<String>("pkg")); result.success(null) }
                    "startCompanion" -> {
                        p.edit().putBoolean("setup_done", true).putBoolean("companion_on", true).apply()
                        BuddyCore.startCompanion(ctx); result.success(null)
                    }
                    "getWater" -> result.success(
                        mapOf(
                            "count" to BuddyCore.waterCount(ctx),
                            "goal" to p.getInt("water_goal", 8),
                            "enabled" to p.getBoolean("water_enabled", true),
                            "interval" to p.getInt("water_interval_min", 60),
                            "start" to p.getInt("water_start_hour", 8),
                            "end" to p.getInt("water_end_hour", 22),
                            "lastDrink" to p.getLong("water_last_drink", 0),
                        )
                    )
                    "logDrink" -> { BuddyCore.logDrink(ctx, call.argument<Int>("delta") ?: 1); result.success(BuddyCore.waterCount(ctx)) }
                    "setWater" -> {
                        p.edit().apply {
                            call.argument<Int>("goal")?.let { putInt("water_goal", it) }
                            call.argument<Boolean>("enabled")?.let { putBoolean("water_enabled", it) }
                            call.argument<Int>("interval")?.let { putInt("water_interval_min", it) }
                            call.argument<Int>("start")?.let { putInt("water_start_hour", it) }
                            call.argument<Int>("end")?.let { putInt("water_end_hour", it) }
                        }.apply()
                        BuddyCore.refreshOngoing(ctx); result.success(null)
                    }
                    "setBrief" -> {
                        p.edit().apply {
                            call.argument<Boolean>("enabled")?.let { putBoolean("brief_enabled", it) }
                            call.argument<Int>("hour")?.let { putInt("brief_hour", it) }
                            call.argument<Int>("minute")?.let { putInt("brief_minute", it) }
                        }.apply()
                        result.success(null)
                    }
                    "setGrowth" -> {
                        p.edit().apply {
                            call.argument<Boolean>("enabled")?.let { putBoolean("growth_enabled", it) }
                            call.argument<Int>("hour")?.let { putInt("growth_hour", it) }
                            call.argument<String>("doneDate")?.let { putString("growth_done_date", it) }
                            call.argument<String>("skipDate")?.let { putString("growth_skip_date", it) }
                        }.apply()
                        if (call.argument<String>("doneDate") == BuddyCore.today() || call.argument<String>("skipDate") == BuddyCore.today()) {
                            getSystemService(android.app.NotificationManager::class.java).cancel(BuddyCore.ID_GROWTH)
                        }
                        result.success(null)
                    }
                    "testVibrate" -> { BuddyCore.nudge(ctx, BuddyCore.ID_WATER, "Buddy test", "This is how reminders feel: vibration, no sound."); result.success(null) }
                    "getScrollSettings" -> result.success(
                        mapOf(
                            "nudgeEnabled" to p.getBoolean("nudge_enabled", true),
                            "nudgeEvery" to p.getInt("nudge_every", 30),
                            "reelLimit" to p.getInt("reel_limit", 150),
                        )
                    )
                    "setScrollSettings" -> {
                        p.edit().apply {
                            call.argument<Boolean>("nudgeEnabled")?.let { putBoolean("nudge_enabled", it) }
                            call.argument<Int>("nudgeEvery")?.let { putInt("nudge_every", it) }
                            call.argument<Int>("reelLimit")?.let { putInt("reel_limit", it) }
                        }.apply(); result.success(null)
                    }
                    "scrollStats" -> result.success(scrollStats(call.argument<Int>("days") ?: 7))
                    // Slow system queries (per-app storage stats can take seconds): run off the main thread
                    // so the UI never freezes while a tab opens.
                    "usageToday" -> background(result) { if (hasUsageAccess()) usageToday() else null }
                    "appInsights" -> background(result) { if (hasUsageAccess()) appInsights() else null }
                    "mediaFiles" -> background(result) { if (allFilesAccess()) mediaFiles() else null }
                    "bankSms" -> background(result) { bankSms(call.argument<Number>("since")?.toLong() ?: 0L) }
                    "videoThumb" -> {
                        val path = call.argument<String>("path")!!
                        thumbExecutor.execute {
                            val bytes = videoThumb(path)
                            runOnUiThread { result.success(bytes) }
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("native", e.message, null)
            }
        }
    }

    private val thumbExecutor = Executors.newFixedThreadPool(2)

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        thumbExecutor.execute {
            val r = try { Result.success(work()) } catch (e: Exception) { Result.failure(e) }
            runOnUiThread {
                r.fold({ result.success(it) }, { result.error("native", it.message, null) })
            }
        }
    }

    /**
     * Bank transaction SMS since [since] (ms). Privacy filter happens here: only business sender IDs
     * (letters, e.g. "VM-HDFCBK") whose text mentions a debit/credit and an amount. SMS from phone
     * numbers (people) are never read into the app.
     */
    private fun bankSms(since: Long): List<Map<String, Any>> {
        if (checkSelfPermission(android.Manifest.permission.READ_SMS) != android.content.pm.PackageManager.PERMISSION_GRANTED) return emptyList()
        val out = ArrayList<Map<String, Any>>()
        val business = Regex("[A-Za-z]")
        val money = Regex("(?i)(rs\\.?|inr|₹)\\s*[0-9]")
        val txn = Regex("(?i)(debit|credit|spent|withdrawn|withdrawal|received|deposited|refund|paid|sent|purchase|deducted)")
        contentResolver.query(
            Uri.parse("content://sms/inbox"), arrayOf("_id", "address", "body", "date"),
            "date > ?", arrayOf(since.toString()), "date DESC"
        )?.use { c ->
            while (c.moveToNext() && out.size < 2000) {
                val addr = c.getString(1) ?: continue
                if (!business.containsMatchIn(addr)) continue
                val body = c.getString(2) ?: continue
                if (!money.containsMatchIn(body) || !txn.containsMatchIn(body)) continue
                out.add(mapOf("id" to c.getLong(0), "addr" to addr, "body" to body, "date" to c.getLong(3)))
            }
        }
        return out
    }

    /** JPEG preview of a video so the cleaner can show what you're deleting. */
    private fun videoThumb(path: String): ByteArray? = try {
        val bmp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            ThumbnailUtils.createVideoThumbnail(File(path), Size(320, 320), null)
        else @Suppress("DEPRECATION") ThumbnailUtils.createVideoThumbnail(path, MediaStore.Images.Thumbnails.MINI_KIND)
        bmp?.let { ByteArrayOutputStream().also { o -> it.compress(Bitmap.CompressFormat.JPEG, 80, o) }.toByteArray() }
    } catch (_: Exception) { null }

    /** Every file Android has indexed (photos, videos, audio, downloads, documents) in one query:
     *  far faster than stat-ing files one by one through the storage layer. */
    private fun mediaFiles(): Map<String, Any> {
        val paths = ArrayList<String>()
        val sizes = ArrayList<Long>()
        val mods = ArrayList<Long>()
        val uri = MediaStore.Files.getContentUri("external")
        @Suppress("DEPRECATION")
        val cols = arrayOf(MediaStore.MediaColumns.DATA, MediaStore.MediaColumns.SIZE, MediaStore.MediaColumns.DATE_MODIFIED)
        contentResolver.query(uri, cols, "${MediaStore.MediaColumns.SIZE} > 0", null, null)?.use { c ->
            while (c.moveToNext()) {
                val path = c.getString(0) ?: continue
                if (path.contains("/Android/data/")) continue
                paths.add(path)
                sizes.add(c.getLong(1))
                mods.add(c.getLong(2) * 1000)
            }
        }
        return mapOf("p" to paths, "s" to sizes.toLongArray(), "m" to mods.toLongArray())
    }

    // ---------- Permissions ----------
    private fun hasUsageAccess(): Boolean {
        val ops = getSystemService(AppOpsManager::class.java)
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        else @Suppress("DEPRECATION") ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun accessibilityOn(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        // Android may store the short form ("pkg/.ScrollWatcherService"); compare parsed components, not strings.
        val me = ComponentName(this, ScrollWatcherService::class.java)
        return enabled.split(':').any { ComponentName.unflattenFromString(it.trim()) == me }
    }

    private fun allFilesAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Environment.isExternalStorageManager() else true

    private fun batteryIgnored(): Boolean =
        getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName)

    private fun openSettings(what: String, pkg: String?) {
        val i = when (what) {
            "usage" -> Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            "allFiles" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:$packageName"))
            else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
            "battery" -> Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
            "appDetails" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${pkg ?: packageName}"))
            "uninstall" -> Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg"))
            "storage" -> Intent(Settings.ACTION_INTERNAL_STORAGE_SETTINGS)
            else -> Intent(Settings.ACTION_SETTINGS)
        }
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(i)
    }

    // ---------- Scroll / usage ----------
    private fun scrollStats(days: Int): List<Map<String, Any>> {
        val p = BuddyCore.prefs(this)
        val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val cal = Calendar.getInstance()
        val out = ArrayList<Map<String, Any>>()
        repeat(days) {
            val d = fmt.format(cal.time)
            val apps = HashMap<String, Map<String, Int>>()
            for ((pkg, label) in BuddyCore.SHORT_VIDEO_APPS) {
                val r = p.getInt("reels_${d}_$pkg", 0)
                val f = p.getInt("feed_${d}_$pkg", 0)
                if (r + f > 0) {
                    val prev = apps[label]
                    apps[label] = mapOf("reels" to r + (prev?.get("reels") ?: 0), "feed" to f + (prev?.get("feed") ?: 0))
                }
            }
            out.add(mapOf("date" to d, "apps" to apps))
            cal.add(Calendar.DAY_OF_YEAR, -1)
        }
        return out
    }

    /** Foreground minutes today per package, computed from resume/pause events. */
    private fun usageToday(): Map<String, Any> {
        val usm = getSystemService(UsageStatsManager::class.java)
        val start = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val now = System.currentTimeMillis()
        val events = usm.queryEvents(start, now)
        val ev = UsageEvents.Event()
        val openSince = HashMap<String, Long>()
        val totals = HashMap<String, Long>()
        while (events.hasNextEvent()) {
            events.getNextEvent(ev)
            when (ev.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> openSince[ev.packageName] = ev.timeStamp
                UsageEvents.Event.ACTIVITY_PAUSED, UsageEvents.Event.ACTIVITY_STOPPED -> {
                    openSince.remove(ev.packageName)?.let { totals[ev.packageName] = (totals[ev.packageName] ?: 0) + (ev.timeStamp - it) }
                }
            }
        }
        openSince.forEach { (pkg, t) -> totals[pkg] = (totals[pkg] ?: 0) + (now - t) }
        val pm = packageManager
        val top = totals.entries.filter { it.key != packageName && it.value > 60_000 }
            .sortedByDescending { it.value }.take(8).map {
                val label = try { pm.getApplicationLabel(pm.getApplicationInfo(it.key, 0)).toString() } catch (_: Exception) { it.key }
                mapOf("pkg" to it.key, "label" to label, "minutes" to (it.value / 60_000).toInt())
            }
        val shortVideo = HashMap<String, Int>()
        for ((pkg, label) in BuddyCore.SHORT_VIDEO_APPS) {
            val m = ((totals[pkg] ?: 0) / 60_000).toInt()
            if (m > 0) shortVideo[label] = (shortVideo[label] ?: 0) + m
        }
        return mapOf("top" to top, "shortVideo" to shortVideo, "totalMinutes" to (totals.values.sum() / 60_000).toInt())
    }

    /** Unused apps (30+ days) and biggest app caches, so the cleaner can point at them. */
    private fun appInsights(): Map<String, Any> {
        val usm = getSystemService(UsageStatsManager::class.java)
        val now = System.currentTimeMillis()
        val lastUsed = HashMap<String, Long>()
        usm.queryUsageStats(UsageStatsManager.INTERVAL_BEST, now - 90L * 86_400_000, now).forEach {
            if (it.lastTimeUsed > (lastUsed[it.packageName] ?: 0)) lastUsed[it.packageName] = it.lastTimeUsed
        }
        val pm = packageManager
        val ssm = getSystemService(StorageStatsManager::class.java)
        val apps = pm.getInstalledApplications(0).filter {
            it.flags and ApplicationInfo.FLAG_SYSTEM == 0 && it.packageName != packageName
        }
        val list = apps.mapNotNull { ai ->
            try {
                val st = ssm.queryStatsForPackage(StorageManager.UUID_DEFAULT, ai.packageName, Process.myUserHandle())
                val installed = pm.getPackageInfo(ai.packageName, 0).firstInstallTime
                val lu = lastUsed[ai.packageName] ?: 0
                val idleDays = ((now - maxOf(lu, installed)) / 86_400_000).toInt()
                mapOf(
                    "pkg" to ai.packageName,
                    "label" to pm.getApplicationLabel(ai).toString(),
                    "idleDays" to idleDays,
                    "cacheMB" to (st.cacheBytes / 1_048_576).toInt(),
                    "totalMB" to ((st.appBytes + st.dataBytes) / 1_048_576).toInt(),
                )
            } catch (_: Exception) { null }
        }
        return mapOf(
            "unused" to list.filter { (it["idleDays"] as Int) >= 30 }.sortedByDescending { it["totalMB"] as Int }.take(25),
            "bigCaches" to list.filter { (it["cacheMB"] as Int) >= 50 }.sortedByDescending { it["cacheMB"] as Int }.take(15),
        )
    }
}
