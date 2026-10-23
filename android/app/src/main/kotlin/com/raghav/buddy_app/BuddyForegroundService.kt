package com.raghav.buddy_app

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat

/** Always-on companion. START_STICKY + boot receiver + alarm tick keep it alive 24x7. */
class BuddyForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    // Check the growth commitment as soon as the user unlocks the phone (implicit broadcast: must be registered at runtime).
    private val unlockReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            android.util.Log.i("BuddyGrowth", "unlock event: ${intent.action}")
            BuddyCore.checkBrief(ctx) // first unlock of the morning gets the brief right away
            BuddyCore.checkGrowth(ctx)
            BuddyCore.checkScrollTracker(ctx) // catch a tracker the phone switched off as soon as you're back
        }
    }

    override fun onCreate() {
        super.onCreate()
        val filter = android.content.IntentFilter(Intent.ACTION_USER_PRESENT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) registerReceiver(unlockReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else registerReceiver(unlockReceiver, filter)
    }

    override fun onDestroy() {
        try { unregisterReceiver(unlockReceiver) } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        BuddyCore.ensureChannels(this)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0
        ServiceCompat.startForeground(this, BuddyCore.ID_ONGOING, BuddyCore.ongoingNotification(this), type)
        BuddyCore.prefs(this).edit().putBoolean("companion_on", true).apply()
        BuddyCore.scheduleTick(this)
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // User swiped Buddy away from recents: come right back.
        BuddyCore.startCompanion(applicationContext)
        super.onTaskRemoved(rootIntent)
    }
}

class TickReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        BuddyCore.checkWater(ctx)
        BuddyCore.checkGrowth(ctx)
        BuddyCore.checkBrief(ctx)
        BuddyCore.checkScrollTracker(ctx)
        BuddyCore.refreshOngoing(ctx)
        if (BuddyCore.prefs(ctx).getBoolean("companion_on", false)) BuddyCore.startCompanion(ctx)
        else BuddyCore.scheduleTick(ctx)
    }
}

class BootReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (BuddyCore.prefs(ctx).getBoolean("setup_done", false)) BuddyCore.startCompanion(ctx)
    }
}
