package com.raghav.buddy_app.channel

import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import com.raghav.buddy_app.BuddyCore
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/** Reel/feed counts from the scroll watcher, nudge settings and today's screen time. */
class ScrollHandler(private val ctx: Context) : ChannelHandler {
    private val p get() = BuddyCore.prefs(ctx)

    override val routes: Map<String, Route> = mapOf(
        "getScrollSettings" to { _, result ->
            result.success(
                mapOf(
                    "nudgeEnabled" to p.getBoolean("nudge_enabled", true),
                    "nudgeEvery" to p.getInt("nudge_every", 30),
                    "reelLimit" to p.getInt("reel_limit", 150),
                )
            )
        },
        "setScrollSettings" to { call, result ->
            p.edit().apply {
                call.argument<Boolean>("nudgeEnabled")?.let { putBoolean("nudge_enabled", it) }
                call.argument<Int>("nudgeEvery")?.let { putInt("nudge_every", it) }
                call.argument<Int>("reelLimit")?.let { putInt("reel_limit", it) }
            }.apply(); result.success(null)
        },
        "scrollStats" to { call, result -> result.success(scrollStats(call.argument<Int>("days") ?: 7)) },
        "usageToday" to { _, result -> Background.run(result) { if (Permissions.usage(ctx)) usageToday() else null } },
    )

    private fun scrollStats(days: Int): List<Map<String, Any>> {
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
        val usm = ctx.getSystemService(UsageStatsManager::class.java)
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
        val pm = ctx.packageManager
        val top = totals.entries.filter { it.key != ctx.packageName && it.value > 60_000 }
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
}
