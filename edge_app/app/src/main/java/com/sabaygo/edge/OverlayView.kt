package com.sabaygo.edge

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import com.sabaygo.edge.count.Live
import com.sabaygo.edge.track.Box
import com.sabaygo.edge.track.DoorCounter
import com.sabaygo.edge.track.DoorLayout
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max

/** Drawing a van's door layout, one thing at a time. */
enum class EditStep { LINE, INSIDE, SEAT }

/**
 * The camera's latest frame with what the phone sees in it: person boxes
 * (grey), tracked people with their tracker number and a dot at the
 * middle of the box (green; that dot crossing the line is what counts),
 * the door line (yellow) with an arrow into the cabin and the strip the
 * dot must clear on both sides (pale yellow), and the driver's seat mask
 * (red).
 *
 * While [editing] is set, the Dispatcher lines the layout up with the
 * doorway at mounting (brief 5.5), in [step] order: drag the line's ends
 * across the doorway; tap the side that is inside the van; drag the seat
 * box over the driver (its middle moves it, a corner resizes it).
 */
class OverlayView(context: Context, attrs: AttributeSet?) : View(context, attrs) {
    var editing: DoorLayout? = null
        set(v) { field = v; invalidate() }
    var step = EditStep.LINE
        set(v) { field = v; invalidate() }

    private val dst = RectF()
    private var handle = NONE
    // Where the seat box was grabbed, from its top-left corner, while it moves.
    private var grabX = 0f
    private var grabY = 0f
    private val d = resources.displayMetrics.density
    private val boxPaint = stroke(Color.LTGRAY, 1.5f)
    private val trackPaint = stroke(Color.GREEN, 2.5f)
    private val centrePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.GREEN }
    private val centreEdge = stroke(Color.BLACK, 1.5f)
    private val bandPaint = Paint().apply { color = Color.argb(80, 255, 235, 59) }
    private val linePaint = stroke(Color.YELLOW, 4f)
    private val maskPaint = Paint().apply { color = Color.argb(70, 255, 0, 0) }
    private val maskEdge = stroke(Color.RED, 2f)
    private val insidePaint = Paint().apply { color = Color.argb(70, 0, 200, 80) }
    private val outsidePaint = Paint().apply { color = Color.argb(70, 255, 150, 0) }
    private val handlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.CYAN }
    private val handleEdge = stroke(Color.WHITE, 2f)
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textSize = 14 * d }
    private val label = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE; textSize = 16 * d; isFakeBoldText = true; textAlign = Paint.Align.CENTER
        setShadowLayer(4 * d, 0f, 0f, Color.BLACK)
    }

    private fun stroke(c: Int, w: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = c; style = Paint.Style.STROKE; strokeWidth = w * resources.displayMetrics.density
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(Color.BLACK)
        val f = Live.frame
        if (f == null) {
            canvas.drawText(if (Live.running) "No camera frame yet." else "Camera off: tap Start to count.",
                16 * d, 32 * d, text)
            return
        }
        val scale = minOf(width.toFloat() / f.image.width, height.toFloat() / f.image.height)
        val w = f.image.width * scale; val h = f.image.height * scale
        dst.set((width - w) / 2, (height - h) / 2, (width + w) / 2, (height + h) / 2)
        canvas.drawBitmap(f.image, null, dst, null)

        f.boxes.forEach { canvas.drawRect(rect(it), boxPaint) }
        f.tracks.forEach { (id, b) ->
            canvas.drawRect(rect(b), trackPaint)
            canvas.drawCircle(x(b.cx), y(b.cy), 12 * d, centrePaint)
            canvas.drawCircle(x(b.cx), y(b.cy), 12 * d, centreEdge)
            canvas.drawText("#$id", x(b.x1) + 4 * d, y(b.y1) + 16 * d, text)
        }
        val edit = editing
        val layout = edit ?: Live.session?.layout ?: return
        when {
            edit == null -> { seat(canvas, layout, false); line(canvas, layout, false); insideArrow(canvas, layout) }
            step == EditStep.LINE -> line(canvas, edit, true)
            step == EditStep.INSIDE -> { sides(canvas, edit); line(canvas, edit, false) }
            else -> { line(canvas, edit, false); insideArrow(canvas, edit); seat(canvas, edit, true) }
        }
    }

    private fun line(canvas: Canvas, l: DoorLayout, handles: Boolean) {
        band(canvas, l)
        canvas.drawLine(x(l.x1), y(l.y1), x(l.x2), y(l.y2), linePaint)
        if (!handles) return
        labelAt(canvas, "DOOR LINE", (x(l.x1) + x(l.x2)) / 2, (y(l.y1) + y(l.y2)) / 2 - 14 * d)
        dot(canvas, x(l.x1), y(l.y1)); dot(canvas, x(l.x2), y(l.y2))
    }

    private fun seat(canvas: Canvas, l: DoorLayout, handles: Boolean) {
        val m = l.seatMask ?: return
        val r = rect(m)
        canvas.drawRect(r, maskPaint); canvas.drawRect(r, maskEdge)
        if (!handles) return
        labelAt(canvas, "DRIVER'S SEAT", r.centerX(), r.centerY())
        labelAt(canvas, "not counted", r.centerX(), r.centerY() + 20 * d)
        dot(canvas, x(m.x1), y(m.y1)); dot(canvas, x(m.x2), y(m.y2))
    }

    /**
     * The strip along the line that a box's middle must clear: a crossing
     * counts only from beyond one edge to beyond the other
     * ([DoorCounter.MARGIN], in the counter's own units).
     */
    private fun band(canvas: Canvas, l: DoorLayout) {
        val dx = l.x2 - l.x1; val dy = l.y2 - l.y1
        val len = hypot(dx, dy).takeIf { it > 0 } ?: return
        val ox = -dy / len * DoorCounter.MARGIN; val oy = dx / len * DoorCounter.MARGIN
        canvas.drawPath(Path().apply {
            moveTo(x(l.x1 + ox), y(l.y1 + oy)); lineTo(x(l.x2 + ox), y(l.y2 + oy))
            lineTo(x(l.x2 - ox), y(l.y2 - oy)); lineTo(x(l.x1 - ox), y(l.y1 - oy)); close()
        }, bandPaint)
    }

    /** Each side of the line shaded and named: the cabin green, the doorway side orange. */
    private fun sides(canvas: Canvas, l: DoorLayout) {
        val (n, mx, my) = normal(l) ?: return
        val ux = n.second; val uy = -n.first   // along the line
        val far = 4f * max(width, height)
        canvas.save()
        canvas.clipRect(dst)
        canvas.drawPath(half(mx, my, ux, uy, n.first, n.second, far), insidePaint)
        canvas.drawPath(half(mx, my, ux, uy, -n.first, -n.second, far), outsidePaint)
        canvas.restore()
        labelAt(canvas, "INSIDE THE VAN", mx + n.first * 70 * d, my + n.second * 70 * d)
        labelAt(canvas, "OUTSIDE", mx - n.first * 70 * d, my - n.second * 70 * d)
    }

    private fun half(mx: Float, my: Float, ux: Float, uy: Float, nx: Float, ny: Float, far: Float) = Path().apply {
        moveTo(mx - ux * far, my - uy * far)
        lineTo(mx + ux * far, my + uy * far)
        lineTo(mx + ux * far + nx * far, my + uy * far + ny * far)
        lineTo(mx - ux * far + nx * far, my - uy * far + ny * far)
        close()
    }

    /** From the line's middle, square to it, into the cabin. */
    private fun insideArrow(canvas: Canvas, l: DoorLayout) {
        val (n, mx, my) = normal(l) ?: return
        val tipX = mx + n.first * 48 * d; val tipY = my + n.second * 48 * d
        canvas.drawLine(mx, my, tipX, tipY, linePaint)
        canvas.drawText("inside", tipX + 4 * d, tipY, text)
    }

    /** The unit normal pointing into the cabin, on screen, and the line's middle. */
    private fun normal(l: DoorLayout): Triple<Pair<Float, Float>, Float, Float>? {
        val dx = x(l.x2) - x(l.x1); val dy = y(l.y2) - y(l.y1)
        val len = hypot(dx, dy).takeIf { it > 0 } ?: return null
        return Triple(-dy / len * l.inside to dx / len * l.inside, (x(l.x1) + x(l.x2)) / 2, (y(l.y1) + y(l.y2)) / 2)
    }

    private fun labelAt(canvas: Canvas, s: String, cx: Float, cy: Float) {
        val half = label.measureText(s) / 2
        canvas.drawText(s, cx.coerceIn(dst.left + half, dst.right - half),
            cy.coerceIn(dst.top + label.textSize, dst.bottom - 4 * d), label)
    }

    private fun dot(canvas: Canvas, cx: Float, cy: Float) {
        canvas.drawCircle(cx, cy, 14 * d, handlePaint)
        canvas.drawCircle(cx, cy, 14 * d, handleEdge)
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        val l = editing ?: return false
        if (dst.width() <= 0) return true
        val nx = ((e.x - dst.left) / dst.width()).coerceIn(0f, 1f)
        val ny = ((e.y - dst.top) / dst.height()).coerceIn(0f, 1f)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> handle = when (step) {
                EditStep.LINE -> nearest(listOf(l.x1 to l.y1, l.x2 to l.y2), e)
                EditStep.INSIDE -> { editing = l.withCabinAt(nx, ny); NONE }
                EditStep.SEAT -> l.seatMask?.let { m ->
                    val corner = nearest(listOf(m.x1 to m.y1, m.x2 to m.y2), e)
                    when {
                        corner != NONE -> corner + 2
                        m.contains(nx, ny) -> { grabX = nx - minOf(m.x1, m.x2); grabY = ny - minOf(m.y1, m.y2); MOVE }
                        else -> NONE
                    }
                } ?: NONE
            }
            MotionEvent.ACTION_MOVE -> if (handle != NONE) editing = moved(l, handle, nx, ny)
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> handle = NONE
        }
        return true
    }

    /** The point within reach of the finger, or [NONE]. */
    private fun nearest(points: List<Pair<Float, Float>>, e: MotionEvent): Int =
        points.withIndex().minByOrNull { (_, p) -> hypot(x(p.first) - e.x, y(p.second) - e.y) }
            ?.takeIf { (_, p) -> hypot(x(p.first) - e.x, y(p.second) - e.y) < 48 * d }?.index ?: NONE

    private fun moved(l: DoorLayout, h: Int, nx: Float, ny: Float): DoorLayout {
        val m = l.seatMask
        return when (h) {
            0 -> l.copy(x1 = nx, y1 = ny)
            1 -> l.copy(x2 = nx, y2 = ny)
            2 -> l.copy(seatMask = m?.copy(x1 = nx, y1 = ny))
            3 -> l.copy(seatMask = m?.copy(x2 = nx, y2 = ny))
            else -> m?.let {
                // The whole box, kept on the picture.
                val bw = abs(it.x2 - it.x1); val bh = abs(it.y2 - it.y1)
                val left = (nx - grabX).coerceIn(0f, 1f - bw); val top = (ny - grabY).coerceIn(0f, 1f - bh)
                l.copy(seatMask = Box(left, top, left + bw, top + bh))
            } ?: l
        }
    }

    private fun x(v: Float) = dst.left + v * dst.width()
    private fun y(v: Float) = dst.top + v * dst.height()
    private fun rect(b: Box) = RectF(x(minOf(b.x1, b.x2)), y(minOf(b.y1, b.y2)), x(maxOf(b.x1, b.x2)), y(maxOf(b.y1, b.y2)))

    private companion object {
        const val NONE = -1
        const val MOVE = 4   // the seat box as a whole
    }
}
