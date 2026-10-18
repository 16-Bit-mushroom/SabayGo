package com.sabaygo.edge.count

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import com.sabaygo.edge.track.Box
import com.sabaygo.edge.track.DoorLayout
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import kotlin.math.max

/**
 * The blurred still sent with each door event (brief 5.1: "only event
 * details and a blurred snapshot, no video"). Every person box is
 * pixelated, so the Terminal Manager reviewing it sees that someone
 * crossed, never who; the door line and the box that crossed are drawn
 * on it. Its SHA-256 goes with the event and joins the hash chain, so the
 * image cannot be swapped later (R5c).
 */
object Stills {
    private const val BLOCK = 12          // pixels per pixelation block
    private const val QUALITY = 75

    private val line = Paint().apply { color = Color.YELLOW; strokeWidth = 3f; isAntiAlias = true }
    private val outline = Paint().apply { color = Color.WHITE; strokeWidth = 2f; style = Paint.Style.STROKE }

    /** The camera frame turned upright and no wider or taller than [maxSide]. */
    fun upright(frame: Bitmap, rotationDegrees: Int, maxSide: Int): Bitmap {
        val scale = minOf(1f, maxSide.toFloat() / max(frame.width, frame.height))
        val m = Matrix().apply { postRotate(rotationDegrees.toFloat()); postScale(scale, scale) }
        return Bitmap.createBitmap(frame, 0, 0, frame.width, frame.height, m, true)
    }

    fun make(upright: Bitmap, people: List<Box>, layout: DoorLayout?, crossed: Box): ByteArray {
        val out = upright.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = Canvas(out)
        people.forEach { pixelate(out, canvas, it) }
        val w = out.width.toFloat(); val h = out.height.toFloat()
        layout?.let { canvas.drawLine(it.x1 * w, it.y1 * h, it.x2 * w, it.y2 * h, line) }
        canvas.drawRect(crossed.x1 * w, crossed.y1 * h, crossed.x2 * w, crossed.y2 * h, outline)
        return ByteArrayOutputStream().use { out.compress(Bitmap.CompressFormat.JPEG, QUALITY, it); it.toByteArray() }
    }

    fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun pixelate(bmp: Bitmap, canvas: Canvas, b: Box) {
        val l = (b.x1 * bmp.width).toInt().coerceIn(0, bmp.width - 1)
        val t = (b.y1 * bmp.height).toInt().coerceIn(0, bmp.height - 1)
        val r = (b.x2 * bmp.width).toInt().coerceIn(l + 1, bmp.width)
        val btm = (b.y2 * bmp.height).toInt().coerceIn(t + 1, bmp.height)
        val region = Bitmap.createBitmap(bmp, l, t, r - l, btm - t)
        val tiny = Bitmap.createScaledBitmap(region, max(1, (r - l) / BLOCK), max(1, (btm - t) / BLOCK), true)
        canvas.drawBitmap(Bitmap.createScaledBitmap(tiny, r - l, btm - t, false), l.toFloat(), t.toFloat(), null)
    }
}

/**
 * A covered lens (brief 5.3: "a frame that stays dark or unchanged"): the
 * frame is near black and nearly uniform for [holdMs]. Both together, so a
 * van cabin at night, dark but with lit windows and lamps, is not taken
 * for a covered lens; a hand or tape over the lens is both.
 */
class LensCheck(private val holdMs: Long = 15_000) {
    var blocked = false; private set
    private var since = 0L
    private val px = IntArray(32 * 24)

    fun sample(frame: Bitmap, nowMs: Long) {
        Bitmap.createScaledBitmap(frame, 32, 24, true).getPixels(px, 0, 32, 0, 0, 32, 24)
        var sum = 0.0; var sq = 0.0
        for (p in px) {
            val y = (0.299 * ((p shr 16) and 0xFF) + 0.587 * ((p shr 8) and 0xFF) + 0.114 * (p and 0xFF)) / 255
            sum += y; sq += y * y
        }
        val mean = sum / px.size
        val std = kotlin.math.sqrt(maxOf(0.0, sq / px.size - mean * mean))
        val covered = mean < 0.04 && std < 0.02
        if (!covered) { since = 0; blocked = false; return }
        if (since == 0L) since = nowMs
        blocked = nowMs - since >= holdMs
    }
}
