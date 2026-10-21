package com.raghav.buddy_app.channel

import android.app.usage.StorageStatsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.media.ThumbnailUtils
import android.os.Build
import android.os.Process
import android.os.storage.StorageManager
import android.provider.MediaStore
import android.util.Size
import java.io.ByteArrayOutputStream
import java.io.File

/** Data the phone cleaner needs: indexed files, video previews and app storage. */
class StorageHandler(private val ctx: Context) : ChannelHandler {
    override val routes: Map<String, Route> = mapOf(
        "appInsights" to { _, result -> Background.run(result) { if (Permissions.usage(ctx)) appInsights() else null } },
        "mediaFiles" to { _, result -> Background.run(result) { if (Permissions.allFiles()) mediaFiles() else null } },
        "videoThumb" to { call, result ->
            val path = call.argument<String>("path")!!
            Background.run(result) { videoThumb(path) }
        },
    )

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
        ctx.contentResolver.query(uri, cols, "${MediaStore.MediaColumns.SIZE} > 0", null, null)?.use { c ->
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

    /** Unused apps (30+ days) and biggest app caches, so the cleaner can point at them. */
    private fun appInsights(): Map<String, Any> {
        val usm = ctx.getSystemService(UsageStatsManager::class.java)
        val now = System.currentTimeMillis()
        val lastUsed = HashMap<String, Long>()
        usm.queryUsageStats(UsageStatsManager.INTERVAL_BEST, now - 90L * 86_400_000, now).forEach {
            if (it.lastTimeUsed > (lastUsed[it.packageName] ?: 0)) lastUsed[it.packageName] = it.lastTimeUsed
        }
        val pm = ctx.packageManager
        val ssm = ctx.getSystemService(StorageStatsManager::class.java)
        val apps = pm.getInstalledApplications(0).filter {
            it.flags and ApplicationInfo.FLAG_SYSTEM == 0 && it.packageName != ctx.packageName
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
