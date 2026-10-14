package com.sabaygo.edge

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Size
import android.view.WindowManager
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.Spinner
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import com.sabaygo.edge.bench.Backend
import com.sabaygo.edge.bench.CsvLog
import com.sabaygo.edge.bench.DeviceState
import com.sabaygo.edge.bench.Session
import com.sabaygo.edge.bench.Step
import java.util.concurrent.Executors

/**
 * The benchmark (brief 5.3, CLAUDE.md step 5.3): YOLOv8n on the phone's
 * camera, timed per frame, with battery temperature and level, to a CSV.
 *
 * Run: one model and backend until Stop, for the full trip on vehicle power.
 * Sweep: every model with every backend, 10 s warm-up and 60 s measured each.
 *
 * The run stops when the app leaves the foreground; keep it on screen.
 */
class MainActivity : ComponentActivity() {

    private lateinit var status: TextView
    private lateinit var modelPick: Spinner
    private lateinit var backendPick: Spinner
    private lateinit var threadsField: EditText
    private lateinit var intervalField: EditText
    private lateinit var runButton: Button
    private lateinit var sweepButton: Button
    private lateinit var stopButton: Button

    private val analysisThread = Executors.newSingleThreadExecutor()
    private lateinit var device: DeviceState
    private var models: List<String> = emptyList()
    private var session: Session? = null   // touched on analysisThread only

    private val askCamera = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) startCamera() else status.text = "Camera permission refused. The benchmark needs the camera."
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        status = findViewById(R.id.status)
        modelPick = findViewById(R.id.model)
        backendPick = findViewById(R.id.backend)
        threadsField = findViewById(R.id.threads)
        intervalField = findViewById(R.id.interval)
        runButton = findViewById(R.id.run)
        sweepButton = findViewById(R.id.sweep)
        stopButton = findViewById(R.id.stop)
        device = DeviceState(this)

        models = assets.list("models").orEmpty().filter { it.endsWith(".tflite") }.sorted().map { "models/$it" }
        modelPick.adapter = spinnerOf(models.map { it.substringAfter('/') })
        backendPick.adapter = spinnerOf(Backend.entries.map { it.label })

        runButton.setOnClickListener {
            start("run", listOf(Step(models[modelPick.selectedItemPosition],
                Backend.entries[backendPick.selectedItemPosition], threads(), WARMUP_S, null)))
        }
        sweepButton.setOnClickListener {
            start("sweep", models.flatMap { m ->
                Backend.entries.map { b -> Step(m, b, threads(), WARMUP_S, SWEEP_MEASURE_S) }
            })
        }
        stopButton.setOnClickListener { stop("stopped by user") }

        if (models.isEmpty()) {
            status.text = "No models in assets/models. Run tools/export_models.sh, then rebuild."
            runButton.isEnabled = false
            sweepButton.isEnabled = false
        } else {
            status.text = "Ready: ${models.size} models.\nCSV files go to ${getExternalFilesDir(null)}"
        }

        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) startCamera()
        else askCamera.launch(Manifest.permission.CAMERA)
    }

    override fun onStop() {
        super.onStop()
        stop("app left the foreground")
    }

    override fun onDestroy() {
        super.onDestroy()
        device.close()
        analysisThread.shutdown()
    }

    private fun startCamera() {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            val provider = future.get()
            val preview = Preview.Builder().build().also {
                it.surfaceProvider = findViewById<PreviewView>(R.id.preview).surfaceProvider
            }
            val analysis = ImageAnalysis.Builder()
                .setResolutionSelector(ResolutionSelector.Builder().setResolutionStrategy(
                    ResolutionStrategy(Size(640, 480), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER),
                ).build())
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .build()
            analysis.setAnalyzer(analysisThread) { image ->
                image.use { session?.onFrame(it) }
                if (session?.finished == true) session = null
            }
            provider.unbindAll()
            provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
        }, mainExecutor)
    }

    private fun start(mode: String, steps: List<Step>) {
        val log = CsvLog(getExternalFilesDir(null)!!, mode)
        val s = Session(
            assets, steps, interval(), log, device,
            onStatus = { text -> runOnUiThread { status.text = text } },
            onFinished = { reason -> runOnUiThread {
                setRunning(false)
                status.text = "Finished: $reason\n${log.file.name}"
            } },
        )
        analysisThread.execute { session = s }
        setRunning(true)
    }

    private fun stop(reason: String) {
        analysisThread.execute {
            session?.finish(reason)
            session = null
        }
    }

    /** Dims the screen while running: the display's own heat is not the model's. */
    private fun setRunning(running: Boolean) {
        runButton.isEnabled = !running && models.isNotEmpty()
        sweepButton.isEnabled = !running && models.isNotEmpty()
        stopButton.isEnabled = running
        window.attributes = window.attributes.apply {
            screenBrightness = if (running) 0.05f else WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
        }
    }

    private fun threads() = threadsField.text.toString().toIntOrNull()?.coerceIn(1, 8) ?: 4
    private fun interval() = intervalField.text.toString().toLongOrNull()?.coerceAtLeast(0) ?: 0L
    private fun spinnerOf(items: List<String>) =
        ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, items)

    private companion object {
        const val WARMUP_S = 10
        const val SWEEP_MEASURE_S = 60
    }
}
