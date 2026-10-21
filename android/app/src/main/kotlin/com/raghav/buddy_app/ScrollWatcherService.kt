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

        val isReel = fullScreen && (pkg in pureShortVideoApps || reelIdHints.any { viewId.contains(it) } || onReelScreen(pkg, now))
        val date = BuddyCore.today()
        if (isReel) {
            BuddyCore.bump(this, "reels_${date}_$pkg")
            onReelSwipe(now)
        } else {
            BuddyCore.bump(this, "feed_${date}_$pkg")
        }
    }

    // The full-screen player, not the "Shorts" shelf on the home feed.
    private val playerHints = listOf("player", "watch", "pager", "recycler", "overlay", "viewer", "time_bar", "progress")
    private val screenCheckAt = HashMap<String, Long>()
    private val screenIsReel = HashMap<String, Boolean>()

    /**
     * YouTube renamed/removed the id on the Shorts pager itself, so the swiped view often has no "shorts"
     * id. Fall back to looking at what's on screen: any reel/shorts view id (player, overlay, buttons)
     * means we're in Shorts/Reels. Cached for 2 s and capped at 400 nodes to stay cheap.
     */
    private fun onReelScreen(pkg: String, now: Long): Boolean {
        if (now - (screenCheckAt[pkg] ?: 0) < 2000) return screenIsReel[pkg] ?: false
        screenCheckAt[pkg] = now
        val root = try { rootInActiveWindow } catch (_: Exception) { null }
        var found = false
        if (root != null && root.packageName?.toString() == pkg) {
            val queue = ArrayDeque<android.view.accessibility.AccessibilityNodeInfo>().apply { add(root) }
            var seen = 0
            while (queue.isNotEmpty() && seen < 400 && !found) {
                val n = queue.removeFirst()
                seen++
                val id = n.viewIdResourceName?.lowercase() ?: ""
                if (reelIdHints.any { id.contains(it) } && playerHints.any { id.contains(it) }) found = true
                for (i in 0 until n.childCount) n.getChild(i)?.let { queue.add(it) }
            }
        }
        screenIsReel[pkg] = found
        return found
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
