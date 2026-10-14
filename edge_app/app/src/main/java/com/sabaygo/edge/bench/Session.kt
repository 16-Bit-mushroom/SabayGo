package com.sabaygo.edge.bench

import android.content.res.AssetManager
import androidx.camera.core.ImageProxy
import java.time.LocalDateTime
import java.util.Locale

/** One model and backend, warmed up and then measured; no measure limit runs until Stop. */
class Step(val model: String, val backend: Backend, val threads: Int, val warmupS: Int, val measureS: Int?)

/**
 * One Run or Sweep: its steps in order, one CSV row per counted frame.
 * Every call comes on the camera's analysis thread, so the detector and
 * the log are never used by two threads at once.
 *
 * Rows by phase: `load` (model compiled, time in the note), `warmup`,
 * `measure`, `error` (a step that failed, reason in the note, the sweep
 * goes on), `end`.
 */
class Session(
    private val assets: AssetManager,
    private val steps: List<Step>,
    private val minIntervalMs: Long,
    private val log: CsvLog,
    private val device: DeviceState,
    private val onStatus: (String) -> Unit,
    private val onFinished: (String) -> Unit,
) {
    var finished = false; private set
    private val started = System.nanoTime()
    private var index = 0
    private var detector: Detector? = null
    private var stepStart = 0L
    private var lastStart = 0L
    private var lastEnd = 0L
    private var lastStatus = 0L
    private var runs = 0
    private var inferenceSum = 0.0
    private var frameSum = 0.0
    private var frameCount = 0

    fun onFrame(image: ImageProxy) {
        if (finished) return
        val now = System.nanoTime()
        if (minIntervalMs > 0 && lastStart != 0L && now - lastStart < minIntervalMs * 1_000_000) return
        val step = steps[index]
        val d = detector ?: load(step) ?: return
        val inStep = (now - stepStart) / 1e9
        if (step.measureS != null && inStep >= step.warmupS + step.measureS) return next()
        val phase = if (inStep < step.warmupS) "warmup" else "measure"

        lastStart = now
        val r = try {
            d.count(image.toBitmap(), image.imageInfo.rotationDegrees)
        } catch (e: Exception) {
            row(step, "error", note = e.toString())
            return next()
        }
        val end = System.nanoTime()
        val frameMs = if (lastEnd == 0L) null else (end - lastEnd) / 1e6
        lastEnd = end
        row(step, phase, d.inputPx, r, frameMs)

        runs++; inferenceSum += r.inferenceMs
        frameMs?.let { frameSum += it; frameCount++ }
        if (end - lastStatus > 1_000_000_000) {
            lastStatus = end
            onStatus(status(step, phase, inStep, r.persons))
        }
    }

    fun finish(reason: String) {
        if (finished) return
        finished = true
        detector?.close()
        detector = null
        log.row(LocalDateTime.now().format(CsvLog.TIME), elapsed(), "end", *arrayOfNulls(13), reason)
        log.close()
        onFinished(reason)
    }

    private fun load(step: Step): Detector? {
        onStatus("step ${index + 1}/${steps.size}  loading ${name(step)} ${step.backend.label}")
        val t0 = System.nanoTime()
        return try {
            Detector(assets, step.model, step.backend, step.threads).also {
                detector = it
                stepStart = System.nanoTime()
                row(step, "load", it.inputPx, note = "load ${"%.0f".format(Locale.US, (stepStart - t0) / 1e6)} ms")
            }
        } catch (e: Exception) {
            row(step, "error", note = e.toString())
            next()
            null
        }
    }

    private fun next() {
        detector?.close()
        detector = null
        index++
        lastStart = 0L; lastEnd = 0L
        runs = 0; inferenceSum = 0.0; frameSum = 0.0; frameCount = 0
        if (index >= steps.size) finish("complete")
    }

    private fun row(step: Step, phase: String, inputPx: Int? = null, r: Result? = null,
                    frameMs: Double? = null, note: String? = null) = log.row(
        LocalDateTime.now().format(CsvLog.TIME), elapsed(), phase, name(step), inputPx, step.backend.label,
        step.threads.takeIf { step.backend.usesThreads }, r?.preprocessMs, r?.inferenceMs, r?.postprocessMs,
        frameMs, r?.persons, device.batteryC, device.batteryPct, device.plugged, device.thermalStatus, note,
    )

    private fun status(step: Step, phase: String, inStep: Double, persons: Int): String {
        val limit = step.measureS?.let { "/${step.warmupS + it}" } ?: ""
        val rate = if (frameCount > 0) 1000 * frameCount / frameSum else 0.0
        return String.format(
            Locale.US,
            "step %d/%d  %s  %s\n%s  %.0f%s s   persons %d\ninference %.1f ms avg   %.1f frames/s\nbattery %s °C  %s%%  %s   thermal %d",
            index + 1, steps.size, name(step), step.backend.label, phase, inStep, limit, persons,
            inferenceSum / runs, rate, device.batteryC ?: "?", device.batteryPct ?: "?", device.plugged,
            device.thermalStatus,
        )
    }

    private fun elapsed() = (System.nanoTime() - started) / 1e9
    private fun name(step: Step) = step.model.substringAfterLast('/').removeSuffix(".tflite")
}
