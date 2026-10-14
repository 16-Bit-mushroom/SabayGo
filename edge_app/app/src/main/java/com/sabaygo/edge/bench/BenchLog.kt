package com.sabaygo.edge.bench

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.PowerManager
import androidx.core.content.ContextCompat
import java.io.Closeable
import java.io.File
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Battery and thermal readings, kept current by the battery broadcast. */
class DeviceState(private val context: Context) : BroadcastReceiver(), Closeable {
    @Volatile var batteryC: Float? = null; private set
    @Volatile var batteryPct: Int? = null; private set
    @Volatile var plugged: String = ""; private set
    private val power = context.getSystemService(PowerManager::class.java)

    /** 0 none … 6 shutdown (PowerManager.THERMAL_STATUS_*); 1 light is where throttling starts. */
    val thermalStatus: Int get() = power.currentThermalStatus

    init {
        ContextCompat.registerReceiver(
            context, this, IntentFilter(Intent.ACTION_BATTERY_CHANGED), ContextCompat.RECEIVER_NOT_EXPORTED,
        )?.let { onReceive(context, it) }
    }

    override fun onReceive(context: Context, intent: Intent) {
        intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
            .takeIf { it != Int.MIN_VALUE }?.let { batteryC = it / 10f }
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level >= 0 && scale > 0) batteryPct = level * 100 / scale
        plugged = when (intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)) {
            BatteryManager.BATTERY_PLUGGED_AC -> "ac"
            BatteryManager.BATTERY_PLUGGED_USB -> "usb"
            BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
            0 -> "none"
            else -> "other"
        }
    }

    override fun close() = context.unregisterReceiver(this)
}

/**
 * One CSV per Run or Sweep, in the app's external files directory so
 * `adb pull` reaches it. Flushed every second: a run cut short by a crash
 * or a flat battery keeps all but the last second.
 */
class CsvLog(dir: File, mode: String) : Closeable {
    val file = File(dir, "bench_${LocalDateTime.now().format(STAMP)}_$mode.csv")
    private val out = file.bufferedWriter()
    private var lastFlush = 0L

    init { line(HEADER) }

    fun row(vararg cols: Any?) = line(cols.joinToString(",") { cell(it) })

    private fun line(text: String) {
        out.write(text); out.newLine()
        val now = System.currentTimeMillis()
        if (now - lastFlush >= 1000) { out.flush(); lastFlush = now }
    }

    override fun close() = out.close()

    companion object {
        const val HEADER = "time_local,elapsed_s,phase,model,input_px,backend,threads," +
            "preprocess_ms,inference_ms,postprocess_ms,frame_ms,persons," +
            "battery_c,battery_pct,plugged,thermal_status,note"
        private val STAMP = DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss")
        val TIME: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS")

        private fun cell(v: Any?): String = when (v) {
            null -> ""
            is Double -> String.format(Locale.US, "%.2f", v)
            is Float -> String.format(Locale.US, "%.1f", v)
            else -> v.toString().replace(',', ';').replace('\n', ' ')
        }
    }
}
