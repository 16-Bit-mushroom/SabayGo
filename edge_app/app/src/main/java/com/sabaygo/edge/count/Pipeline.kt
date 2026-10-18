package com.sabaygo.edge.count

import android.content.Context
import android.graphics.Bitmap
import android.os.SystemClock
import androidx.camera.core.ImageProxy
import com.sabaygo.edge.link.Config
import com.sabaygo.edge.link.Outbox
import com.sabaygo.edge.link.ServerClock
import com.sabaygo.edge.track.Box
import com.sabaygo.edge.track.ByteTrack
import com.sabaygo.edge.track.Crossing
import com.sabaygo.edge.track.DoorCounter
import com.sabaygo.edge.track.DoorLayout
import com.sabaygo.edge.track.Track
import com.sabaygo.edge.vision.Backend
import com.sabaygo.edge.vision.Detector
import org.json.JSONObject
import java.io.File
import java.util.UUID

/**
 * Phase 1 of the four (brief 6.2), on the phone: each camera frame goes
 * through YOLOv8n, ByteTrack and the door line; each crossing becomes a
 * door event in the outbox with its blurred still.
 *
 * Runs on the camera's analysis thread only. The model runs while the
 * server says to count; otherwise only while the screen is on, a few
 * times a second, so the Dispatcher can place the door line.
 */
class Pipeline(context: Context, private val config: Config, private val outbox: Outbox) {
    private val assets = context.assets
    private val stillDir = File(context.filesDir, "stills").apply { mkdirs() }
    private var detector: Detector? = null
    private val tracker = ByteTrack()
    private var counter: DoorCounter? = null
    private var tripId: String? = null
    private var wasCounting = false
    private val lens = LensCheck()
    private var lastRun = 0L
    private var lastShown = 0L
    private var lastLens = 0L
    private val runs = ArrayDeque<Long>()

    fun onFrame(image: ImageProxy) {
        val now = SystemClock.elapsedRealtime()
        Live.lastFrameAt = System.currentTimeMillis()
        val rotation = image.imageInfo.rotationDegrees
        val frame: Bitmap by lazy { image.toBitmap() }
        if (now - lastLens >= 500) {
            lastLens = now
            lens.sample(frame, now)
            Live.lensBlocked = lens.blocked
        }

        val counting = Live.shouldCount()
        followTrip(counting)
        Live.counting = counting
        val show = Live.screenOn && now - lastShown >= 500
        val layout = Live.session?.layout
        Live.note = when {
            counting && layout == null -> "No door line for this van yet: draw it, or nothing is counted."
            else -> null
        }

        if (counting) {
            if (config.minIntervalMs > 0 && now - lastRun < config.minIntervalMs) return
            lastRun = now
            val det = detector()?.detect(frame, rotation, LOW) ?: return
            noteRun(now)
            if (counter?.layout != layout) counter = layout?.let(::DoorCounter)
            val people = if (layout == null) det.boxes else det.boxes.filterNot(layout::masked)
            val tracks = tracker.update(people, now / 1000.0)
            counter?.update(tracks)?.forEach { record(it, frame, rotation, det.boxes, layout) }
            if (show) show(frame, rotation, tracks, det.boxes, now)
        } else {
            noteRun(null)
            if (!show) return
            val det = detector()?.detect(frame, rotation, Detector.CONF) ?: return
            show(frame, rotation, emptyList(), det.boxes, now)
        }
    }

    fun close() {
        detector?.close()
        detector = null
    }

    /** A new trip, or counting resumed after a pause: the count and the tracker start again. */
    private fun followTrip(counting: Boolean) {
        val id = Live.session?.tripId
        when {
            !counting -> Unit
            !wasCounting -> startTrip(id)
            id != null && tripId != null && id != tripId -> startTrip(id)
            id != null -> tripId = id   // counted offline, now placed: same ride
        }
        wasCounting = counting
    }

    private fun startTrip(id: String?) {
        tracker.reset()
        counter = null
        tripId = id
        Live.aboard = 0; Live.boards = 0; Live.alights = 0
    }

    private fun record(c: Crossing, frame: Bitmap, rotation: Int, people: List<Box>, layout: DoorLayout?) {
        if (c.boarding) Live.boards++ else Live.alights++
        Live.aboard = (Live.boards - Live.alights).coerceAtLeast(0)
        val id = UUID.randomUUID().toString()
        val still = Stills.make(Stills.upright(frame, rotation, STILL_PX), people, layout, c.box)
        val file = File(stillDir, "$id.jpg").apply { writeBytes(still) }
        val at = ServerClock.now()
        val body = JSONObject()
            .put("event_id", id)
            .put("event_type", if (c.boarding) "board" else "alight")
            .put("event_at", ServerClock.iso(at))
            // The door count (boards less alightings); the server takes the crew off.
            .put("occupancy_after", Live.aboard.coerceAtMost(255))
            .put("track_id", c.trackId)
            .put("snapshot_hash", Stills.sha256(still))
        Live.lastFix?.takeIf { System.currentTimeMillis() - Live.lastFixAt < FIX_FRESH_MS }?.let {
            body.put("latitude", it.latitude).put("longitude", it.longitude)
        }
        outbox.add(Outbox.Kind.EVENT, body, ref = id)
        outbox.add(Outbox.Kind.STILL, JSONObject(), ref = id, file = file)
        Live.lastEvent = "${if (c.boarding) "boarding" else "alighting"} at ${at.atZone(java.time.ZoneId.systemDefault()).toLocalTime().withNano(0)}"
    }

    private fun show(frame: Bitmap, rotation: Int, tracks: List<Track>, boxes: List<Box>, now: Long) {
        lastShown = now
        Live.frame = Frame(Stills.upright(frame, rotation, SCREEN_PX), tracks.map { it.id to it.box }, boxes)
    }

    /** The detection rate actually reached over the last half minute, for the status report. */
    private fun noteRun(now: Long?) {
        val t = now ?: SystemClock.elapsedRealtime()
        if (now != null) runs.addLast(now)
        while (runs.isNotEmpty() && t - runs.first() > RATE_WINDOW_MS) runs.removeFirst()
        Live.detectionRateHz = runs.size * 1000.0 / RATE_WINDOW_MS
    }

    private fun detector(): Detector? {
        val want = config.model
        detector?.let { if (it.assetPath == want) return it; it.close() }
        detector = try {
            Detector(assets, want, Backend.CPU_FP16, THREADS)
        } catch (e: Exception) {
            Live.note = "The model did not load: $e"
            null
        }
        return detector
    }

    private companion object {
        const val LOW = 0.1f              // ByteTrack's low score: ultralytics' track_low_thresh
        const val THREADS = 4             // as benchmarked (docs/benchmarks/edge_sweep_2026-10-18.md)
        const val STILL_PX = 640
        const val SCREEN_PX = 480
        const val FIX_FRESH_MS = 10_000L
        const val RATE_WINDOW_MS = 30_000L
    }
}
