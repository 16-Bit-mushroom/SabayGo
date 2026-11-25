package com.sabaygo.edge.count

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.rtsp.RtspMediaSource
import com.sabaygo.edge.link.Config
import java.io.IOException
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Socket
import java.nio.ByteBuffer
import java.util.concurrent.Callable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The door camera when it is a Tapo on this phone's hotspot (decided
 * 16 Nov: the camera only films; the model stays on the phone, and no
 * video leaves the van). Its RTSP `stream2` (H.264, 1280 x 720, 15 fps
 * on the hotspot, measured 24 Nov) is decoded here, read back at
 * 640 x 360 through [GlFrames], and each frame goes to [Pipeline] as the
 * phone's own camera's does, already upright.
 *
 * - **Found, not configured.** The hotspot picks a new subnet when it
 *   restarts, and the phone, as its host, has no list of who joined, so
 *   [CameraFinder] asks each address beside the phone's own for the
 *   Tapo's ONVIF (2020) and RTSP (554) ports. The address that last sent
 *   a picture is tried first.
 * - **A dropped stream is never filled in.** An error, or 15 s without a
 *   frame, closes it; it is opened again 5 s later, and after two
 *   failures the camera is looked for again. Meanwhile no frame reaches
 *   the pipeline, so the status report says `camera_ok` false and the
 *   trip goes Unaudited: no count is made up for the time it was blind.
 * - The audio track is never played.
 *
 * A frame that arrives while the pipeline is busy is dropped, not queued
 * (CameraX's keep-only-latest), so the decoder never waits on the model.
 */
@OptIn(UnstableApi::class)
class TapoCamera(
    private val context: Context,
    private val config: Config,
    private val analysis: Executor,
    private val onFrame: (rotation: Int, toBitmap: () -> Bitmap) -> Unit,
) {
    private val thread = HandlerThread("tapo").apply { start() }
    private val handler = Handler(thread.looper)
    private val busy = AtomicBoolean(false)
    // Touched on [thread] only: the player's looper and the GL context's thread.
    private var frames: GlFrames? = null
    private var player: ExoPlayer? = null
    private var host: String? = null
    private var confirmed = false
    private var failures = 0
    private var lastFrameAt = 0L
    private var stopped = false

    private val connectTask = Runnable { connect() }
    private val watchdog = object : Runnable {
        override fun run() {
            if (player == null) return
            if (SystemClock.elapsedRealtime() - lastFrameAt > STALL_MS) fail("no picture for ${STALL_MS / 1000} s")
            else handler.postDelayed(this, WATCH_MS)
        }
    }
    private val listener = object : Player.Listener {
        override fun onPlayerError(error: PlaybackException) {
            val why = error.cause?.message ?: error.errorCodeName
            handler.post { fail(why) }
        }

        override fun onPlaybackStateChanged(state: Int) {
            if (state == Player.STATE_ENDED) handler.post { fail("the stream ended") }
        }
    }

    fun start() {
        handler.post {
            frames = try {
                GlFrames(OUT_W, OUT_H, handler, ::onVideoFrame)
            } catch (e: RuntimeException) {
                note("this phone cannot read video frames: ${e.message}")
                return@post
            }
            connect()
        }
    }

    /** Waits (at most 2 s) until the stream is closed, so nothing is decoded once the service has stopped. */
    fun stop() {
        val done = CountDownLatch(1)
        handler.post {
            stopped = true
            handler.removeCallbacksAndMessages(null)
            release()
            frames?.release()
            frames = null
            done.countDown()
        }
        done.await(2, TimeUnit.SECONDS)
        thread.quitSafely()
        Live.cameraNote = null
    }

    private fun connect() {
        val out = frames ?: return
        if (stopped) return
        val found = config.cameraHost.ifBlank { null } ?: CameraFinder.find()
        if (stopped) return
        if (found == null) {
            note("looking for the Tapo on this phone's hotspot")
            handler.postDelayed(connectTask, FIND_AGAIN_MS)
            return
        }
        host = found
        confirmed = false
        note("connecting to the Tapo at $found")
        val uri = Uri.parse("rtsp://${Uri.encode(config.cameraUser)}:${Uri.encode(config.cameraPass)}@$found:554/stream2")
        player = ExoPlayer.Builder(context)
            .setLooper(thread.looper)
            // Live: start on a quarter second of video, keep at most two, so a crossing is stamped near when it happened.
            .setLoadControl(DefaultLoadControl.Builder().setBufferDurationsMs(500, 2_000, 250, 250).build())
            .build()
            .apply {
                trackSelectionParameters = trackSelectionParameters.buildUpon()
                    .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true).build()
                volume = 0f
                addListener(listener)
                setVideoSurface(out.surface)
                // TCP, as the 24 Nov stream test ran: a lost packet is resent, not a torn frame.
                setMediaSource(RtspMediaSource.Factory().setForceUseRtpTcp(true).setTimeoutMs(TIMEOUT_MS)
                    .createMediaSource(MediaItem.fromUri(uri)))
                playWhenReady = true
                prepare()
            }
        lastFrameAt = SystemClock.elapsedRealtime()
        handler.postDelayed(watchdog, WATCH_MS)
    }

    /** The current attempt failed: close it and try again; after [FORGET_AFTER] in a row, look for the camera again. */
    private fun fail(why: String) {
        if (stopped || player == null) return   // already handled
        release()
        if (++failures >= FORGET_AFTER) {
            failures = 0
            config.cameraHost = ""
        }
        note("the Tapo at $host is not sending ($why); trying again")
        handler.removeCallbacks(connectTask)
        handler.postDelayed(connectTask, RETRY_MS)
    }

    private fun release() {
        handler.removeCallbacks(watchdog)
        player?.run { removeListener(listener); release() }
        player = null
    }

    /**
     * On [thread], for every decoded frame. Read back only when the
     * pipeline is free: the read-back buffer is reused, and it is not
     * written again until the pipeline is done with it.
     */
    private fun onVideoFrame(read: () -> ByteBuffer) {
        if (player == null) return
        lastFrameAt = SystemClock.elapsedRealtime()
        if (!confirmed) {
            confirmed = true
            failures = 0
            host?.let { config.cameraHost = it; note("Tapo at $it") }
        }
        if (!busy.compareAndSet(false, true)) return
        val pixels = read()
        try {
            analysis.execute {
                try {
                    onFrame(0) { Bitmap.createBitmap(OUT_W, OUT_H, Bitmap.Config.ARGB_8888).apply { copyPixelsFromBuffer(pixels.rewind()) } }
                } finally {
                    busy.set(false)
                }
            }
        } catch (e: RejectedExecutionException) {
            busy.set(false)
        }
    }

    private fun note(s: String) {
        Live.cameraNote = s
    }

    private companion object {
        // Half of stream2's 1280 x 720: about what the phone's own camera gave (640 x 480); the model sees 320 or 416.
        const val OUT_W = 640
        const val OUT_H = 360
        const val TIMEOUT_MS = 8_000L     // an RTSP request unanswered
        const val STALL_MS = 15_000L
        const val WATCH_MS = 5_000L
        const val RETRY_MS = 5_000L
        const val FIND_AGAIN_MS = 10_000L
        const val FORGET_AFTER = 2
    }
}

/**
 * The Tapo among the phone's neighbours: the first address that accepts a
 * connection on both its ONVIF and RTSP ports. Only the /24 around each of
 * the phone's own private addresses is asked (Android's hotspot is a /24),
 * and never a mobile-data interface: that /24 is the carrier's.
 */
internal object CameraFinder {
    private const val ONVIF_PORT = 2020
    private const val RTSP_PORT = 554
    private const val CONNECT_MS = 400
    /** Mobile data on Qualcomm, MediaTek (the realme 8 5G) and Unisoc phones, and its 464XLAT. */
    private val CELLULAR = listOf("rmnet", "ccmni", "seth", "v4-")

    fun find(): String? {
        val mine = try {
            NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
                .filter { it.isUp && !it.isLoopback && CELLULAR.none(it.name::startsWith) }
                .flatMap { it.inetAddresses.toList() }
                .filterIsInstance<Inet4Address>()
                .filter { it.isSiteLocalAddress }
                .mapNotNull { it.hostAddress }
        } catch (e: IOException) {
            return null
        }
        val candidates = mine.flatMap { me -> (1..254).map { "${me.substringBeforeLast('.')}.$it" } }.distinct() - mine.toSet()
        if (candidates.isEmpty()) return null
        val pool = Executors.newFixedThreadPool(64)
        return try {
            candidates
                .map { ip -> pool.submit(Callable { ip.takeIf { open(it, ONVIF_PORT) && open(it, RTSP_PORT) } }) }
                .firstNotNullOfOrNull { it.get() }
        } finally {
            pool.shutdownNow()
        }
    }

    private fun open(ip: String, port: Int) = try {
        Socket().use { it.connect(InetSocketAddress(ip, port), CONNECT_MS) }
        true
    } catch (e: IOException) {
        false
    }
}
