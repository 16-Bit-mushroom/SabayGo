package com.sabaygo.edge

import android.Manifest
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.View
import android.view.WindowManager
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import com.sabaygo.edge.count.CountingService
import com.sabaygo.edge.count.Live
import com.sabaygo.edge.link.Api
import com.sabaygo.edge.link.Config
import com.sabaygo.edge.link.Outbox
import com.sabaygo.edge.link.ServerClock
import com.sabaygo.edge.link.layoutJson
import com.sabaygo.edge.track.DoorLayout
import java.io.IOException
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import kotlin.concurrent.thread

/**
 * The in-van phone's screen: what the camera sees, the van and trip it
 * counts for, and what waits to be sent. The Dispatcher draws the door
 * line here at mounting; the office enters the server and the phone's
 * token once, and runs the Realme checklist.
 *
 * Opening the app starts counting once it is set up: the phone's job is
 * to run all day, pausing itself when the server says the van has no trip
 * (brief 4.2 rule 13), not to wait for a button.
 */
class HomeActivity : ComponentActivity() {
    private lateinit var config: Config
    private lateinit var overlay: OverlayView
    private lateinit var status: TextView
    private lateinit var startStop: Button
    private lateinit var mainRow: View
    private lateinit var editRow: View
    private val ui = Handler(Looper.getMainLooper())

    private val ask = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        if (hasCamera()) startCounting()
        else status.text = "The camera is not allowed. Open the checklist."
    }

    private val tick = object : Runnable {
        override fun run() {
            overlay.invalidate()
            status.text = statusText()
            startStop.text = if (Live.running) "Stop" else "Start"
            ui.postDelayed(this, 500)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_home)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        config = Config(this)
        overlay = findViewById(R.id.overlay)
        status = findViewById(R.id.status)
        startStop = findViewById(R.id.start_stop)
        mainRow = findViewById(R.id.main_row)
        editRow = findViewById(R.id.edit_row)

        startStop.setOnClickListener { if (Live.running) CountingService.stop(this) else startCounting() }
        findViewById<Button>(R.id.door_line).setOnClickListener { editLine() }
        findViewById<Button>(R.id.setup).setOnClickListener { setupDialog() }
        findViewById<Button>(R.id.checklist).setOnClickListener { startActivity(Intent(this, ChecklistActivity::class.java)) }
        findViewById<Button>(R.id.benchmark).setOnClickListener {
            CountingService.stop(this)   // one camera user at a time
            startActivity(Intent(this, BenchActivity::class.java))
        }
        findViewById<Button>(R.id.flip).setOnClickListener {
            overlay.editing = overlay.editing?.let { it.copy(inside = -it.inside) }
        }
        findViewById<Button>(R.id.save).setOnClickListener { saveLine() }
        findViewById<Button>(R.id.cancel).setOnClickListener { endEdit() }

        takeSetupExtras(intent)
        if (config.ready) startCounting() else setupDialog()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        takeSetupExtras(intent)
    }

    override fun onResume() {
        super.onResume()
        Live.screenOn = true
        ui.post(tick)
    }

    override fun onPause() {
        Live.screenOn = false
        ui.removeCallbacks(tick)
        super.onPause()
    }

    private fun hasCamera() = checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    private fun startCounting() {
        val needed = buildList {
            add(Manifest.permission.CAMERA)
            add(Manifest.permission.ACCESS_FINE_LOCATION)
            add(Manifest.permission.ACCESS_COARSE_LOCATION)
            if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
        }.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (needed.isNotEmpty()) { ask.launch(needed.toTypedArray()); return }
        CountingService.start(this)
    }

    // ---------------------------------------------------------- set-up
    /**
     * A debuggable build also takes the server and token as intent extras,
     * so the office can set a phone up over adb (`am start ... --es server
     * URL --es token TOKEN`). A release build ignores them: any app on the
     * phone could send that intent and point the uploads elsewhere.
     */
    private fun takeSetupExtras(intent: Intent?) {
        if (intent == null || applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return
        val server = intent.getStringExtra("server")
        val token = intent.getStringExtra("token")
        if (server == null && token == null) return
        server?.let { config.server = it }
        token?.let { config.token = it }
        if (Live.running) CountingService.start(this, refresh = true)
    }

    private fun setupDialog() {
        val pad = (16 * resources.displayMetrics.density).toInt()
        val server = EditText(this).apply {
            hint = "Server, e.g. http://192.168.1.8:8000/api/v1"
            setText(config.server)
            inputType = InputType.TYPE_TEXT_VARIATION_URI
        }
        val token = EditText(this).apply {
            hint = "Phone token (shown once when the phone was added)"
            setText(config.token)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
        }
        val models = Config.MODELS
        val model = Spinner(this).apply {
            adapter = ArrayAdapter(context, android.R.layout.simple_spinner_dropdown_item,
                models.map { it.substringAfter('/').removeSuffix(".tflite") })
            setSelection(models.indexOf(config.model).coerceAtLeast(0))
        }
        val interval = EditText(this).apply {
            hint = "Min ms between detections (0 = every frame)"
            setText(config.minIntervalMs.toString())
            inputType = InputType.TYPE_CLASS_NUMBER
        }
        val form = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad / 2, pad, 0)
            listOf(server, token, model, interval).forEach(::addView)
        }
        AlertDialog.Builder(this)
            .setTitle("Phone set-up")
            .setView(form)
            .setPositiveButton("Save") { _, _ ->
                config.server = server.text.toString()
                config.token = token.text.toString()
                config.model = models[model.selectedItemPosition]
                config.minIntervalMs = interval.text.toString().toLongOrNull() ?: 0L
                if (Live.running) CountingService.start(this, refresh = true) else if (config.ready) startCounting()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    // ---------------------------------------------------------- door line
    private fun editLine() {
        if (Live.frame == null) {
            Toast.makeText(this, "Start the camera first.", Toast.LENGTH_LONG).show(); return
        }
        overlay.editing = Live.session?.layout ?: DoorLayout.DEFAULT
        mainRow.visibility = View.GONE
        editRow.visibility = View.VISIBLE
    }

    private fun endEdit() {
        overlay.editing = null
        editRow.visibility = View.GONE
        mainRow.visibility = View.VISIBLE
    }

    /** PUT /edge/door-layout: kept on the van, so the next phone in it has the line too. */
    private fun saveLine() {
        val layout = overlay.editing ?: return
        if (!config.ready) { toast("Enter the server and token first."); return }
        thread {
            val msg = try {
                val r = Api(config.server, config.token).send("PUT", "/edge/door-layout", layoutJson(layout))
                when {
                    r.ok -> { Live.session = Live.session?.copy(layout = layout); null }
                    r.code == 409 -> "This phone is not checked out to a van. Ask the office to check it out first."
                    r.code == 422 -> "The line is too short, or a point is off the picture."
                    else -> "The server answered ${r.code}."
                }
            } catch (e: IOException) {
                "No connection to the server: ${e.message}"
            }
            runOnUiThread {
                if (msg == null) { toast("Door line saved for this van."); endEdit() } else toast(msg)
            }
        }
    }

    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_LONG).show()

    // ---------------------------------------------------------- status
    private fun statusText(): String {
        val s = Live.session
        val now = System.currentTimeMillis()
        val lines = ArrayList<String>()
        lines += when {
            !config.ready -> "Not set up: tap Set-up and enter the server and this phone's token."
            Live.sessionError != null -> "Server: ${Live.sessionError}"
            s == null -> "Connecting to the server…"
            s.vanId == null -> "In the office: not checked out to a van."
            else -> "Van ${s.plate}  ·  Dispatcher ${s.dispatcher ?: "none"}"
        }
        if (Live.running) {
            lines += when {
                Live.counting && s?.tripId != null -> "Counting for ${s.tripId}"
                Live.counting -> "Counting (no answer from the server; kept until it returns)"
                else -> "Paused: no trip assigned to this van"
            }
            lines += "Door count ${Live.aboard}  (in ${Live.boards}, out ${Live.alights})" +
                (Live.lastEvent?.let { "  ·  last $it" } ?: "")
            val fix = Live.lastFix
            lines += "Camera ${ok(now - Live.lastFrameAt < 5_000)}  ·  GPS ${
                if (fix != null && now - Live.lastFixAt < 10_000) "ok ±${fix.accuracy.toInt()} m" else "no fix"
            }  ·  lens ${if (Live.lensBlocked) "COVERED" else "clear"}  ·  ${
                String.format(Locale.US, "%.1f", Live.detectionRateHz)} detections/s"
        } else {
            lines += "Stopped."
        }
        val waiting = Live.outbox?.waiting().orEmpty()
        val up = Live.uploader
        lines += "To send: ${waiting[Outbox.Kind.EVENT] ?: 0} events, ${waiting[Outbox.Kind.STILL] ?: 0} stills, " +
            "${waiting[Outbox.Kind.FIX] ?: 0} GPS, ${waiting[Outbox.Kind.REPORT] ?: 0} reports" +
            (up?.lastSentAt?.takeIf { it > 0 }?.let { "  ·  last sent ${clock(it)}" } ?: "")
        up?.lastError?.let { lines += "Upload: $it" }
        if (ServerClock.syncedAt > 0) lines += String.format(Locale.US, "Clock on the server's (%+.1f s)", ServerClock.offsetMs / 1000.0)
        Live.note?.let { lines += "⚠ $it" }
        return lines.joinToString("\n")
    }

    private fun ok(b: Boolean) = if (b) "ok" else "NOT REPORTING"
    private fun clock(ms: Long) = Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault()).toLocalTime().withNano(0).toString()
}
