package com.sabaygo.edge.count

import com.sabaygo.edge.track.Box
import com.sabaygo.edge.track.Crossing
import com.sabaygo.edge.track.DoorCounter
import com.sabaygo.edge.track.Track
import java.io.Closeable
import java.io.File
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Debug builds only: what the counter saw, frame by frame, so a missed or
 * doubled crossing can be replayed from the file. One row per tracked
 * person per counted frame (their box, how far its middle is past the
 * door line, the side the counter holds, a crossing if one was counted),
 * and one row for a frame with nobody tracked. In the app's external
 * files directory (`trace/`), where `adb pull` reaches it; a new file per
 * service start, flushed every second.
 */
class Trace(dir: File) : Closeable {
    private val out = File(dir, "trace_${LocalDateTime.now().format(STAMP)}.csv").bufferedWriter()
    private var lastFlush = 0L

    init { out.write(HEADER); out.newLine() }

    fun frame(people: List<Box>, tracks: List<Track>, counter: DoorCounter?, crossings: List<Crossing>) {
        val now = System.currentTimeMillis()
        val t = LocalDateTime.now().format(CLOCK)
        val scores = people.sortedByDescending { it.score }.joinToString(";") { f(it.score) }
        if (tracks.isEmpty()) row("$t,${people.size},$scores,,,,,,,,,,")
        for (tr in tracks) {
            val b = tr.box
            val l = counter?.layout
            val crossed = crossings.firstOrNull { it.trackId == tr.id }?.let { if (it.boarding) "board" else "alight" } ?: ""
            row("$t,${people.size},$scores,${tr.id},${f(b.x1)},${f(b.y1)},${f(b.x2)},${f(b.y2)},${f(b.score)}," +
                "${l?.let { f(it.cabinward(b.cx, b.cy)) } ?: ""},${l?.let { f(it.along(b.cx, b.cy)) } ?: ""}," +
                "${counter?.sideOf(tr.id) ?: ""},$crossed")
        }
        if (now - lastFlush >= 1000) { out.flush(); lastFlush = now }
    }

    private fun row(s: String) { out.write(s); out.newLine() }

    private fun f(v: Float) = String.format(Locale.US, "%.4f", v)

    override fun close() = out.close()

    private companion object {
        const val HEADER = "time,people,scores,track,x1,y1,x2,y2,score,cabinward,along,side,crossing"
        val STAMP: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss")
        val CLOCK: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm:ss.SSS")
    }
}
