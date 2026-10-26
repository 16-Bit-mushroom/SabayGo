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
import android.os.SystemClock
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
    private lateinit var editTitle: TextView
    private lateinit var editHint: TextView
    private lateinit var back: Button
    private lateinit var extra: Button
    private lateinit var next: Button
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
            // Faster while the door line is drawn, so the picture follows the camera.
            ui.postDelayed(this, if (Live.editing) 100 else 500)
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
        editTitle = findViewById(R.id.edit_title)
        editHint = findViewById(R.id.edit_hint)
        back = findViewById(R.id.back)
        extra = findViewById(R.id.extra)
        next = findViewById(R.id.next)

        startStop.setOnClickListener { if (Live.running) confirmStop() else startCounting() }
        findViewById<Button>(R.id.door_line).setOnClickListener { editLine() }
        findViewById<Button>(R.id.setup).setOnClickListener { setupDialog() }
        findViewById<Button>(R.id.checklist).setOnClickListener { startActivity(Intent(this, ChecklistActivity::class.java)) }
        findViewById<Button>(R.id.benchmark).setOnClickListener {
            CountingService.stop(this)   // one camera user at a time
            startActivity(Intent(this, BenchActivity::class.java))
        }
        back.setOnClickListener {
            if (overlay.step == EditStep.LINE) endEdit() else showStep(EditStep.entries[overlay.step.ordinal - 1])
        }
        next.setOnClickListener {
            if (overlay.step == EditStep.SEAT) saveLine() else showStep(EditStep.entries[overlay.step.ordinal + 1])
        }
        extra.setOnClickListener {
            overlay.editing = overlay.editing?.let { it.copy(seatMask = if (it.seatMask == null) DoorLayout.DEFAULT.seatMask else null) }
            showStep(EditStep.SEAT)
        }

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

    /** Asked first: a stopped phone counts nothing, and the trip goes unaudited. */
    private fun confirmStop() {
        AlertDialog.Builder(this)
            .setTitle("Stop counting?")
            .setMessage("Nothing at the door is counted until you tap Start again.")
            .setPositiveButton("Stop") { _, _ -> CountingService.stop(this) }
            .setNegativeButton("Keep counting", null)
            .show()
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
        Live.editing = true
        mainRow.visibility = View.GONE
        editRow.visibility = View.VISIBLE
        showStep(EditStep.LINE)
    }

    /** One thing at a time: the line, which side is the cabin, the driver's seat. */
    private fun showStep(s: EditStep) {
        overlay.step = s
        val noSeat = overlay.editing?.seatMask == null
        editTitle.text = when (s) {
            EditStep.LINE -> "Step 1 of 3 · The door line"
            EditStep.INSIDE -> "Step 2 of 3 · Inside the van"
            EditStep.SEAT -> "Step 3 of 3 · The driver's seat"
        }
        editHint.text = when (s) {
            EditStep.LINE -> "Drag the two blue dots so the yellow line crosses the doorway where the middle of " +
                "a person passes, about waist height in the picture, not at their feet, and across the whole " +
                "path people walk. A person is counted when the green dot on their body clears the pale strip " +
                "on the other side."
            EditStep.INSIDE -> "Tap the side of the line that is inside the van; it turns green. Crossing " +
                "towards it is a boarding, crossing away an alighting."
            EditStep.SEAT -> if (noSeat) "The driver's seat is not in view, so nobody in the picture is left out. " +
                "Tap Mark driver's seat if it is in view."
            else "Drag the red box over the driver's seat: its middle moves it, a blue dot resizes it. " +
                "Whoever sits there is never counted."
        }
        back.text = if (s == EditStep.LINE) "Cancel" else "Back"
        next.text = if (s == EditStep.SEAT) "Save" else "Next"
        extra.visibility = if (s == EditStep.SEAT) View.VISIBLE else View.INVISIBLE
        extra.text = if (noSeat) "Mark driver's seat" else "Driver not in view"
    }

    private fun endEdit() {
        overlay.editing = null
        Live.editing = false
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
            lines += "Inside now ${Live.aboard}  ·  so far ${Live.boards} in, ${Live.alights} out" +
                (Live.lastEvent?.let { "  ·  last $it" } ?: "")
            val fix = Live.lastFix
            lines += "Camera ${ok(now - Live.lastFrameAt < 5_000)}  ·  GPS ${
                if (fix != null && now - Live.lastFixAt < 10_000) "ok ±${fix.accuracy.toInt()} m" else "no fix"
            }  ·  lens ${if (Live.lensBlocked) "COVERED" else "clear"}  ·  ${
                String.format(Locale.US, "%.1f", Live.detectionRateHz)} detections/s"
            val dev = Live.device
            dev?.batteryPct?.let { pct ->
                lines += "Battery $pct %${if (dev.plugged == "none") ", not charging" else ", charging"}" +
                    (dev.batteryC?.let { String.format(Locale.US, "  ·  %.0f °C", it) } ?: "")
            }
            // A person takes about a second to step through: a few frames is too few to track them.
            if (Live.counting && SystemClock.elapsedRealtime() - Live.startedAt > SLOW_AFTER_MS &&
                Live.detectionRateHz < SLOW_HZ) {
                lines += "⚠ Only ${String.format(Locale.US, "%.0f", Live.detectionRateHz)} detections/s: people " +
                    "can be missed. The phone may be too hot or low: cool it and plug it in."
            }
        } else {
            lines += "Stopped: nothing is counted. Tap Start."
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

    private companion object {
        const val SLOW_HZ = 10.0              // detections/s below which a crossing can be missed
        const val SLOW_AFTER_MS = 40_000L     // the rate's 30 s window, filled
    }
}
