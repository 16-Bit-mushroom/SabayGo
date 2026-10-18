package com.sabaygo.edge.count

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.HandlerThread
import android.util.Size
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import com.sabaygo.edge.HomeActivity
import com.sabaygo.edge.bench.DeviceState
import com.sabaygo.edge.link.Api
import com.sabaygo.edge.link.Config
import com.sabaygo.edge.link.Outbox
import com.sabaygo.edge.link.ServerClock
import com.sabaygo.edge.link.SessionInfo
import com.sabaygo.edge.link.Uploader
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * The in-van phone's work (brief 5.1), as a foreground service with the
 * camera and location types, so it keeps running behind the lock screen:
 *
 * - the camera, through [Pipeline], counting door events;
 * - GPS readings every second, while the phone is out with a van;
 * - GET /edge/session every 30 s: the server's clock, the van, its door
 *   line, and whether to count (rule 13);
 * - a status report every 30 s (brief 5.3: battery, temperature,
 *   charging, camera, GPS, detection rate, a covered lens);
 * - the outbox sent every 5 s, kept while offline.
 *
 * Started from [HomeActivity], visibly (Android 14 forbids starting a
 * camera service from the background); the Realme checklist keeps the
 * system from killing it, and the status reports show the office if it
 * did.
 */
class CountingService : LifecycleService() {
    private lateinit var config: Config
    private lateinit var outbox: Outbox
    private lateinit var uploader: Uploader
    private lateinit var pipeline: Pipeline
    private lateinit var device: DeviceState
    private val analysis = Executors.newSingleThreadExecutor()
    private val timer = Executors.newSingleThreadScheduledExecutor()
    private val gpsThread = HandlerThread("gps").apply { start() }
    private var locations: LocationManager? = null

    private val onFix = LocationListener { fix -> onFix(fix) }

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTE_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or
            ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        config = Config(this)
        outbox = Outbox(this)
        device = DeviceState(this)
        uploader = Uploader(outbox, { if (config.ready) Api(config.server, config.token) else null },
            { timer.execute { safely(::syncSession) } })
        pipeline = Pipeline(this, config, outbox)
        Live.outbox = outbox
        Live.uploader = uploader
        Live.running = true
        startCamera()
        startGps()
        timer.scheduleWithFixedDelay({ safely(::syncSession) }, 0, 30, TimeUnit.SECONDS)
        timer.scheduleWithFixedDelay({ safely(::report) }, 5, 30, TimeUnit.SECONDS)
        timer.scheduleWithFixedDelay({ safely { uploader.round() } }, 3, 5, TimeUnit.SECONDS)
    }

    override fun onDestroy() {
        Live.running = false
        Live.counting = false
        locations?.removeUpdates(onFix)
        gpsThread.quitSafely()
        timer.shutdownNow()
        analysis.execute { pipeline.close() }
        analysis.shutdown()
        device.close()
        super.onDestroy()
    }

    /** The settings changed: read the session again and let the uploader retry a refused token. */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        if (intent?.action == ACTION_REFRESH) {
            uploader.reset()
            timer.execute { safely(::syncSession) }
        }
        return START_STICKY
    }

    private fun startCamera() {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            val analysisCase = ImageAnalysis.Builder()
                .setResolutionSelector(ResolutionSelector.Builder().setResolutionStrategy(
                    ResolutionStrategy(Size(640, 480), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER),
                ).build())
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .build()
            analysisCase.setAnalyzer(analysis) { image -> image.use { safely { pipeline.onFrame(it) } } }
            try {
                future.get().apply { unbindAll(); bindToLifecycle(this@CountingService, CameraSelector.DEFAULT_BACK_CAMERA, analysisCase) }
            } catch (e: Exception) {
                Live.note = "The camera did not open: ${e.message}"
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun startGps() {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) return
        locations = getSystemService(LocationManager::class.java).also {
            it.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 0f, onFix, gpsThread.looper)
        }
    }

    private fun onFix(fix: Location) {
        Live.lastFix = fix
        Live.lastFixAt = System.currentTimeMillis()
        if (Live.session?.vanId == null) return   // in the office: the server would ignore it
        val body = JSONObject()
            .put("recorded_at", ServerClock.iso())
            .put("latitude", fix.latitude)
            .put("longitude", fix.longitude)
        if (fix.hasAccuracy()) body.put("accuracy_m", fix.accuracy.toDouble())
        if (fix.hasSpeed() && fix.speed * 3.6 <= 200) body.put("speed_kph", fix.speed * 3.6)
        if (fix.hasBearing() && fix.bearing < 360f) body.put("heading_deg", fix.bearing.toDouble())
        outbox.add(Outbox.Kind.FIX, body)
    }

    private fun syncSession() {
        if (!config.ready) return
        val sent = System.currentTimeMillis()
        val reply = try {
            Api(config.server, config.token).get("/edge/session")
        } catch (e: IOException) {
            Live.sessionError = "offline: ${e.message}"
            return
        }
        val received = System.currentTimeMillis()
        if (!reply.ok) {
            Live.sessionError = if (reply.code == 401) "the server refused this phone's token" else "server ${reply.code}"
            return
        }
        val j = reply.json()
        ServerClock.sync(j.getString("server_time"), sent, received)
        Live.session = SessionInfo.parse(j)
        Live.sessionOkAt = received
        Live.sessionError = null
    }

    private fun report() {
        val now = System.currentTimeMillis()
        val body = JSONObject()
            .put("recorded_at", ServerClock.iso())
            .put("camera_ok", now - Live.lastFrameAt < 5_000)
            .put("gps_ok", now - Live.lastFixAt < 10_000)
            .put("lens_blocked", Live.lensBlocked)
            .put("charging", device.plugged != "none" && device.plugged.isNotEmpty())
            .put("detection_rate_hz", Live.detectionRateHz)
        device.batteryPct?.let { body.put("battery_pct", it) }
        device.batteryC?.let { body.put("battery_temp_c", it.toDouble()) }
        outbox.add(Outbox.Kind.REPORT, body)
    }

    private fun notification(): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Door counting", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, HomeActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentTitle("SabayGo door counting")
            .setContentText("Camera and GPS on. Keep this phone in its holder.")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    /** A thrown exception would stop a scheduled task for good; log it on screen instead. */
    private inline fun safely(block: () -> Unit) {
        try { block() } catch (e: Exception) { Live.note = "${e.javaClass.simpleName}: ${e.message}" }
    }

    companion object {
        private const val NOTE_ID = 1
        private const val CHANNEL = "counting"
        const val ACTION_REFRESH = "com.sabaygo.edge.REFRESH"

        fun start(context: Context, refresh: Boolean = false) {
            val intent = Intent(context, CountingService::class.java)
            if (refresh) intent.action = ACTION_REFRESH
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) = context.stopService(Intent(context, CountingService::class.java))
    }
}
