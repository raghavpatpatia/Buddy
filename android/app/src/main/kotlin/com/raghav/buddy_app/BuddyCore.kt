package com.raghav.buddy_app

import android.app.AlarmManager
import android.app.KeyguardManager
import android.media.AudioManager
import android.os.PowerManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/** Shared native state + helpers used by the service, receivers and the Flutter bridge. */
object BuddyCore {
    const val PREFS = "buddy_native"
    const val CH_ONGOING = "buddy_ongoing"
    const val CH_NUDGE = "buddy_nudge"
    const val ID_ONGOING = 1
    const val ID_WATER = 2
    const val ID_SCROLL = 3
    const val ID_GROWTH = 4
    private const val TICK_MS = 15 * 60 * 1000L

    val SHORT_VIDEO_APPS = linkedMapOf(
        "com.instagram.android" to "Instagram",
        "com.google.android.youtube" to "YouTube",
        "com.zhiliaoapp.musically" to "TikTok",
        "com.ss.android.ugc.trill" to "TikTok",
        "com.facebook.katana" to "Facebook",
        "com.snapchat.android" to "Snapchat",
        "in.mohalla.video" to "Moj",
        "com.eterno.shortvideos" to "Josh",
        "in.mohalla.sharechat" to "ShareChat",
    )

    fun prefs(ctx: Context): SharedPreferences = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun today(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CH_ONGOING, "Buddy running", NotificationManager.IMPORTANCE_MIN).apply {
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            }
        )
        // Silent channel: we vibrate ourselves, never play a sound.
        nm.createNotificationChannel(
            NotificationChannel(CH_NUDGE, "Buddy nudges (vibrate only)", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(null, null)
                enableVibration(false)
            }
        )
    }

    fun vibrate(ctx: Context, pattern: LongArray = longArrayOf(0, 180, 120, 180)) {
        val v: Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            ctx.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            v.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            v.vibrate(pattern, -1)
        }
    }

    fun openAppIntent(ctx: Context): PendingIntent {
        val i = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)!!
        return PendingIntent.getActivity(ctx, 0, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    fun nudge(ctx: Context, id: Int, title: String, text: String) {
        ensureChannels(ctx)
        val n = NotificationCompat.Builder(ctx, CH_NUDGE)
            .setSmallIcon(R.drawable.ic_stat_buddy)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setSilent(true)
            .setAutoCancel(true)
            .setContentIntent(openAppIntent(ctx))
            .build()
        ctx.getSystemService(NotificationManager::class.java).notify(id, n)
        vibrate(ctx)
    }

    fun ongoingNotification(ctx: Context) = NotificationCompat.Builder(ctx, CH_ONGOING)
        .setSmallIcon(R.drawable.ic_stat_buddy)
        .setContentTitle("Buddy is watching out for you")
        .setContentText(statusLine(ctx))
        .setOngoing(true)
        .setSilent(true)
        .setPriority(NotificationCompat.PRIORITY_MIN)
        .setContentIntent(openAppIntent(ctx))
        .build()

    fun refreshOngoing(ctx: Context) {
        ensureChannels(ctx)
        ctx.getSystemService(NotificationManager::class.java).notify(ID_ONGOING, ongoingNotification(ctx))
    }

    private fun statusLine(ctx: Context): String {
        val p = prefs(ctx)
        return "💧 ${waterCount(ctx)}/${p.getInt("water_goal", 8)} glasses · 🎬 ${totalReels(ctx, today())} reels today"
    }

    // ---------- Water ----------
    fun waterCount(ctx: Context): Int {
        val p = prefs(ctx)
        return if (p.getString("water_date", "") == today()) p.getInt("water_count", 0) else 0
    }

    fun logDrink(ctx: Context, delta: Int) {
        val c = (waterCount(ctx) + delta).coerceAtLeast(0)
        prefs(ctx).edit()
            .putString("water_date", today())
            .putInt("water_count", c)
            .putLong("water_last_drink", if (delta > 0) System.currentTimeMillis() else prefs(ctx).getLong("water_last_drink", 0))
            .apply()
        refreshOngoing(ctx)
    }

    fun checkWater(ctx: Context) {
        val p = prefs(ctx)
        if (!p.getBoolean("water_enabled", true)) return
        val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        if (hour < p.getInt("water_start_hour", 8) || hour >= p.getInt("water_end_hour", 22)) return
        val goal = p.getInt("water_goal", 8)
        if (waterCount(ctx) >= goal) return
        val now = System.currentTimeMillis()
        val intervalMs = p.getInt("water_interval_min", 60) * 60_000L
        val last = maxOf(p.getLong("water_last_drink", 0), p.getLong("water_last_reminder", 0))
        // 2 min tolerance so a 15-min tick doesn't skip a whole slot
        if (now - last < intervalMs - 120_000) return
        p.edit().putLong("water_last_reminder", now).apply()
        val lines = listOf(
            "Sip time! 💧 You're at ${waterCount(ctx)}/$goal glasses.",
            "Your brain is ~75% water. Top it up! (${waterCount(ctx)}/$goal)",
            "Hydrated devs ship fewer bugs. Grab a glass 💧",
            "Buddy's mouth is dry just looking at you. Drink up!",
        )
        nudge(ctx, ID_WATER, "Water break", lines.random())
    }

    // ---------- Scroll counters ----------
    fun bump(ctx: Context, key: String) {
        val p = prefs(ctx)
        p.edit().putInt(key, p.getInt(key, 0) + 1).apply()
    }

    fun totalReels(ctx: Context, date: String): Int =
        SHORT_VIDEO_APPS.keys.sumOf { prefs(ctx).getInt("reels_${date}_$it", 0) }

    // ---------- Morning brief ----------
    const val ID_BRIEF = 5

    /** Posts the brief Dart prepared (key flutter.brief_<date> in Flutter's prefs) at the chosen time. */
    fun checkBrief(ctx: Context) {
        val p = prefs(ctx)
        if (!p.getBoolean("brief_enabled", true) || !p.getBoolean("setup_done", false)) return
        val today = today()
        if (p.getString("brief_sent_date", "") == today) return
        val cal = Calendar.getInstance()
        val nowMin = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        val at = p.getInt("brief_hour", 7) * 60 + p.getInt("brief_minute", 30)
        if (nowMin < at || nowMin > at + 180) return // only in the 3 h after the chosen time
        val raw = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).getString("flutter.brief_$today", null)
        var title = "☀️ Good morning!"
        val lines = ArrayList<String>()
        try {
            if (raw != null) {
                val j = org.json.JSONObject(raw)
                title = j.optString("title", title)
                val arr = j.optJSONArray("lines")
                if (arr != null) for (i in 0 until arr.length()) lines.add(arr.getString(i))
            }
        } catch (_: Exception) {}
        if (lines.isEmpty()) lines.add("Open Buddy for today's stars, top news and your 2 growth tasks 🌱")
        ensureChannels(ctx)
        val style = NotificationCompat.InboxStyle()
        lines.forEach { style.addLine(it) }
        val n = NotificationCompat.Builder(ctx, CH_NUDGE)
            .setSmallIcon(R.drawable.ic_stat_buddy)
            .setContentTitle(title)
            .setContentText(lines.first())
            .setStyle(style.setBigContentTitle(title))
            .setSilent(true)
            .setAutoCancel(true)
            .setContentIntent(openAppIntent(ctx))
            .build()
        ctx.getSystemService(NotificationManager::class.java).notify(ID_BRIEF, n)
        vibrate(ctx, longArrayOf(0, 60, 80, 60))
        p.edit().putString("brief_sent_date", today).apply()
    }

    // ---------- Daily growth check ----------
    /** Opens Buddy (or posts a full-screen reminder) when today's growth tasks are overdue. */
    private fun skip(why: String) { android.util.Log.i("BuddyGrowth", "skip: $why") }

    fun checkGrowth(ctx: Context) {
        val p = prefs(ctx)
        if (!p.getBoolean("growth_enabled", true) || !p.getBoolean("setup_done", false)) return skip("disabled/not set up")
        val today = today()
        if (p.getString("growth_done_date", "") == today || p.getString("growth_skip_date", "") == today) return skip("done/skipped today")
        val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        if (hour < p.getInt("growth_hour", 20) || hour >= 23) return skip("outside window ($hour)")
        // Max 3 forced opens a day, at least 55 min apart.
        val count = if (p.getString("growth_open_date", "") == today) p.getInt("growth_open_count", 0) else 0
        val now = System.currentTimeMillis()
        if (count >= 3 || now - p.getLong("growth_last_open", 0) < 55 * 60_000) return skip("rate limit ($count)")
        // Never interrupt calls, a locked phone or Do Not Disturb.
        val audio = ctx.getSystemService(AudioManager::class.java)
        if (audio.mode == AudioManager.MODE_IN_CALL || audio.mode == AudioManager.MODE_IN_COMMUNICATION) return skip("in call")
        if (!ctx.getSystemService(PowerManager::class.java).isInteractive) return skip("screen off")
        if (ctx.getSystemService(KeyguardManager::class.java).isKeyguardLocked) return skip("locked")
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (nm.currentInterruptionFilter > NotificationManager.INTERRUPTION_FILTER_ALL) return skip("do not disturb")
        android.util.Log.i("BuddyGrowth", "opening growth check (a11y=${ScrollWatcherService.instance != null})")

        p.edit().putString("growth_open_date", today).putInt("growth_open_count", count + 1).putLong("growth_last_open", now).apply()
        val open = Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            .putExtra("growth_gate", true)
        // Accessibility-service apps may start activities from the background; others fall back to a full-screen notification.
        val launched = ScrollWatcherService.instance?.let {
            try { it.startActivity(open); true } catch (_: Exception) { false }
        } ?: false
        if (!launched) {
            ensureChannels(ctx)
            val pi = PendingIntent.getActivity(ctx, 7, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val n = NotificationCompat.Builder(ctx, CH_NUDGE)
                .setSmallIcon(R.drawable.ic_stat_buddy)
                .setContentTitle("Growth check 🌱")
                .setContentText("2 small things before the day ends: learn 1 thing + read 1 story.")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setFullScreenIntent(pi, true)
                .setContentIntent(pi)
                .setAutoCancel(true)
                .setSilent(true)
                .build()
            nm.notify(ID_GROWTH, n)
        }
        vibrate(ctx, longArrayOf(0, 120, 80, 120, 80, 300))
    }

    // ---------- 24x7 ----------
    fun startCompanion(ctx: Context) {
        val i = Intent(ctx, BuddyForegroundService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(i) else ctx.startService(i)
        } catch (_: Exception) {
            // Background-start restrictions; the alarm tick will retry.
        }
        scheduleTick(ctx)
    }

    fun scheduleTick(ctx: Context) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        val pi = PendingIntent.getBroadcast(
            ctx, 42, Intent(ctx, TickReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        // Inexact + allow-while-idle: fires even in Doze, no exact-alarm permission needed.
        am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, SystemClock.elapsedRealtime() + TICK_MS, pi)
        scheduleGrowthDeadline(ctx, am)
    }

    /** Extra alarm right at the growth deadline (10-min window, the minimum Android allows without exact-alarm access),
     *  so the check doesn't wait for the batched 15-min tick. */
    private fun scheduleGrowthDeadline(ctx: Context, am: AlarmManager) {
        val p = prefs(ctx)
        if (!p.getBoolean("growth_enabled", true)) return
        val at = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, p.getInt("growth_hour", 20)); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 5)
        }
        if (at.timeInMillis <= System.currentTimeMillis()) at.add(Calendar.DAY_OF_YEAR, 1)
        val pi = PendingIntent.getBroadcast(
            ctx, 43, Intent(ctx, TickReceiver::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        am.setWindow(AlarmManager.RTC_WAKEUP, at.timeInMillis, 10 * 60_000L, pi)
    }
}
