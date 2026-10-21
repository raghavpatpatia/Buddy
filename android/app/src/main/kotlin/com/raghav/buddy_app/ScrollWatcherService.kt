package com.raghav.buddy_app

import android.accessibilityservice.AccessibilityService
import android.graphics.Rect
import android.view.accessibility.AccessibilityEvent

/**
 * Counts swipes in short-video feeds. Heuristic: a scroll on a (near) full-screen
 * container is a reel/short swipe; in IG/YT/FB we also require a reels-ish view id
 * so normal feed scrolling is counted separately as "feed scrolls".
 */
class ScrollWatcherService : AccessibilityService() {
    companion object {
        /** Set while the system has us bound; lets Buddy open itself for the growth check. */
        @Volatile var instance: ScrollWatcherService? = null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    private val lastAt = HashMap<String, Long>()
    private val lastIndex = HashMap<String, Int>()
    private var sessionCount = 0
    private var sessionLastAt = 0L

    private val reelIdHints = listOf("clips", "reel", "shorts", "short_video", "video_pager", "spotlight")
    private val pureShortVideoApps = setOf(
        "com.zhiliaoapp.musically", "com.ss.android.ugc.trill",
        "in.mohalla.video", "com.eterno.shortvideos",
    )

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || event.eventType != AccessibilityEvent.TYPE_VIEW_SCROLLED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg !in BuddyCore.SHORT_VIDEO_APPS) return

        val now = System.currentTimeMillis()
        // One physical swipe emits several scroll events; debounce.
        if (now - (lastAt[pkg] ?: 0) < 450) return
        val idx = event.fromIndex
        if (idx >= 0 && lastIndex[pkg] == idx) return
        lastAt[pkg] = now
        lastIndex[pkg] = idx

        val src = event.source
        val viewId = src?.viewIdResourceName?.lowercase() ?: ""
        val bounds = Rect().also { src?.getBoundsInScreen(it) }
        val screenH = resources.displayMetrics.heightPixels
        val fullScreen = bounds.height() >= screenH * 0.7

        val isReel = fullScreen && (pkg in pureShortVideoApps || reelIdHints.any { viewId.contains(it) })
        val date = BuddyCore.today()
        if (isReel) {
            BuddyCore.bump(this, "reels_${date}_$pkg")
            onReelSwipe(now)
        } else {
            BuddyCore.bump(this, "feed_${date}_$pkg")
        }
    }

    private fun onReelSwipe(now: Long) {
        // A "session" = swipes less than 5 min apart.
        sessionCount = if (now - sessionLastAt < 5 * 60_000) sessionCount + 1 else 1
        sessionLastAt = now
        val p = BuddyCore.prefs(this)
        val every = p.getInt("nudge_every", 30)
        if (p.getBoolean("nudge_enabled", true) && every > 0 && sessionCount % every == 0) {
            val total = BuddyCore.totalReels(this, BuddyCore.today())
            val limit = p.getInt("reel_limit", 150)
            val msg = when {
                total >= limit -> "You've passed your daily limit ($total/$limit reels). Buddy is sad 😢 Time to stop?"
                sessionCount >= every * 3 -> "$sessionCount reels in a row… that's a rabbit hole. Stretch, drink water, come back later?"
                else -> "$sessionCount reels this session. Still enjoying it, or just scrolling?"
            }
            BuddyCore.nudge(this, BuddyCore.ID_SCROLL, "Scroll check 👀", msg)
        }
        if (sessionCount % 10 == 0) BuddyCore.refreshOngoing(this)
    }

    override fun onInterrupt() {}
}
