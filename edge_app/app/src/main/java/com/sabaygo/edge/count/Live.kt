package com.sabaygo.edge.count

import android.graphics.Bitmap
import android.location.Location
import com.sabaygo.edge.link.Outbox
import com.sabaygo.edge.link.SessionInfo
import com.sabaygo.edge.link.Uploader
import com.sabaygo.edge.track.Box

/** The latest frame for the screen, upright, with what was seen in it. */
class Frame(val image: Bitmap, val tracks: List<Pair<Int, Box>>, val boxes: List<Box>)

/**
 * What the counting service knows, for the screen to show. Written by the
 * service's threads, read by the activity; one process, so plain
 * volatile fields are enough.
 */
object Live {
    @Volatile var running = false
    @Volatile var screenOn = false

    @Volatile var session: SessionInfo? = null
    @Volatile var sessionOkAt = 0L
    @Volatile var sessionError: String? = null

    @Volatile var counting = false
    @Volatile var aboard = 0
    @Volatile var boards = 0
    @Volatile var alights = 0
    @Volatile var lastEvent: String? = null
    @Volatile var detectionRateHz = 0.0
    @Volatile var note: String? = null

    @Volatile var lastFrameAt = 0L
    @Volatile var lensBlocked = false
    @Volatile var lastFix: Location? = null
    @Volatile var lastFixAt = 0L
    @Volatile var frame: Frame? = null

    @Volatile var outbox: Outbox? = null
    @Volatile var uploader: Uploader? = null

    /** The server stops answering for this long: keep counting for the van rather than lose what boards. */
    const val STALE_MS = 120_000L

    /**
     * Count from the van's assignment until it arrives, as the server says
     * (brief 4.2 rule 13). Offline, a phone out with a van counts anyway:
     * the server holds what it cannot place yet, and nothing seen is lost.
     */
    fun shouldCount(): Boolean {
        val s = session ?: return false
        val stale = System.currentTimeMillis() - sessionOkAt > STALE_MS
        return s.counting || (stale && s.vanId != null)
    }
}
