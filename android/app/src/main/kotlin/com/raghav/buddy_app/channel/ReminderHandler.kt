package com.raghav.buddy_app.channel

import android.app.NotificationManager
import android.content.Context
import com.raghav.buddy_app.BuddyCore

/** Companion service, water, morning brief and growth reminders. */
class ReminderHandler(private val ctx: Context) : ChannelHandler {
    private val p get() = BuddyCore.prefs(ctx)

    override val routes: Map<String, Route> = mapOf(
        "startCompanion" to { _, result ->
            p.edit().putBoolean("setup_done", true).putBoolean("companion_on", true).apply()
            BuddyCore.startCompanion(ctx); result.success(null)
        },
        "getWater" to { _, result ->
            result.success(
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
        },
        "logDrink" to { call, result -> BuddyCore.logDrink(ctx, call.argument<Int>("delta") ?: 1); result.success(BuddyCore.waterCount(ctx)) },
        "setWater" to { call, result ->
            p.edit().apply {
                call.argument<Int>("goal")?.let { putInt("water_goal", it) }
                call.argument<Boolean>("enabled")?.let { putBoolean("water_enabled", it) }
                call.argument<Int>("interval")?.let { putInt("water_interval_min", it) }
                call.argument<Int>("start")?.let { putInt("water_start_hour", it) }
                call.argument<Int>("end")?.let { putInt("water_end_hour", it) }
            }.apply()
            BuddyCore.refreshOngoing(ctx); result.success(null)
        },
        "setBrief" to { call, result ->
            p.edit().apply {
                call.argument<Boolean>("enabled")?.let { putBoolean("brief_enabled", it) }
                call.argument<Int>("hour")?.let { putInt("brief_hour", it) }
                call.argument<Int>("minute")?.let { putInt("brief_minute", it) }
            }.apply()
            result.success(null)
        },
        "setGrowth" to { call, result ->
            p.edit().apply {
                call.argument<Boolean>("enabled")?.let { putBoolean("growth_enabled", it) }
                call.argument<Int>("hour")?.let { putInt("growth_hour", it) }
                call.argument<String>("doneDate")?.let { putString("growth_done_date", it) }
                call.argument<String>("skipDate")?.let { putString("growth_skip_date", it) }
            }.apply()
            if (call.argument<String>("doneDate") == BuddyCore.today() || call.argument<String>("skipDate") == BuddyCore.today()) {
                ctx.getSystemService(NotificationManager::class.java).cancel(BuddyCore.ID_GROWTH)
            }
            result.success(null)
        },
        "testVibrate" to { _, result -> BuddyCore.nudge(ctx, BuddyCore.ID_WATER, "Buddy test", "This is how reminders feel: vibration, no sound."); result.success(null) },
    )
}
