package com.sabaygo.edge

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import com.sabaygo.edge.count.Live
import com.sabaygo.edge.track.Box
import com.sabaygo.edge.track.DoorLayout
import kotlin.math.hypot

/**
 * The camera's latest frame with what the phone sees in it: person boxes
 * (grey), tracked people with their tracker number (green), the door line
 * (yellow) with an arrow into the cabin, and the driver's seat mask (red).
 *
 * While [editing] is set, its four handles (the line's ends, the mask's
 * corners) can be dragged: this is how the Dispatcher lines it up with the
 * doorway at mounting (brief 5.5).
 */
class OverlayView(context: Context, attrs: AttributeSet?) : View(context, attrs) {
    var editing: DoorLayout? = null
        set(v) { field = v; invalidate() }

    private val dst = RectF()
    private var handle = -1
    private val d = resources.displayMetrics.density
    private val boxPaint = stroke(Color.LTGRAY, 1.5f)
    private val trackPaint = stroke(Color.GREEN, 2.5f)
    private val linePaint = stroke(Color.YELLOW, 4f)
    private val maskPaint = Paint().apply { color = Color.argb(70, 255, 0, 0) }
    private val maskEdge = stroke(Color.RED, 2f)
    private val handlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.CYAN }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textSize = 14 * d }

    private fun stroke(c: Int, w: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = c; style = Paint.Style.STROKE; strokeWidth = w * resources.displayMetrics.density
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawColor(Color.BLACK)
        val f = Live.frame
        if (f == null) {
            canvas.drawText("No camera frame yet.", 16 * d, 32 * d, text)
            return
        }
        val scale = minOf(width.toFloat() / f.image.width, height.toFloat() / f.image.height)
        val w = f.image.width * scale; val h = f.image.height * scale
        dst.set((width - w) / 2, (height - h) / 2, (width + w) / 2, (height + h) / 2)
        canvas.drawBitmap(f.image, null, dst, null)

        f.boxes.forEach { canvas.drawRect(rect(it), boxPaint) }
        f.tracks.forEach { (id, b) ->
            canvas.drawRect(rect(b), trackPaint)
            canvas.drawText("#$id", x(b.x1) + 4 * d, y(b.y1) + 16 * d, text)
        }
        val layout = editing ?: Live.session?.layout ?: return
        layout.seatMask?.let { canvas.drawRect(rect(it), maskPaint); canvas.drawRect(rect(it), maskEdge) }
        canvas.drawLine(x(layout.x1), y(layout.y1), x(layout.x2), y(layout.y2), linePaint)
        cabinArrow(canvas, layout)
        if (editing != null) points(layout).forEach { (px, py) -> canvas.drawCircle(x(px), y(py), 10 * d, handlePaint) }
    }

    /** From the line's middle, square to it, into the cabin. */
    private fun cabinArrow(canvas: Canvas, l: DoorLayout) {
        val mx = (x(l.x1) + x(l.x2)) / 2; val my = (y(l.y1) + y(l.y2)) / 2
        val dx = x(l.x2) - x(l.x1); val dy = y(l.y2) - y(l.y1)
        val len = hypot(dx, dy).takeIf { it > 0 } ?: return
        val nx = -dy / len * l.inside; val ny = dx / len * l.inside
        val tipX = mx + nx * 48 * d; val tipY = my + ny * 48 * d
        canvas.drawLine(mx, my, tipX, tipY, linePaint)
        canvas.drawText("cabin", tipX + 4 * d, tipY, text)
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        val l = editing ?: return false
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                handle = points(l).withIndex().minByOrNull { (_, p) -> hypot(x(p.first) - e.x, y(p.second) - e.y) }
                    ?.takeIf { (_, p) -> hypot(x(p.first) - e.x, y(p.second) - e.y) < 48 * d }?.index ?: -1
            }
            MotionEvent.ACTION_MOVE -> if (handle >= 0 && dst.width() > 0) {
                val nx = ((e.x - dst.left) / dst.width()).coerceIn(0f, 1f)
                val ny = ((e.y - dst.top) / dst.height()).coerceIn(0f, 1f)
                editing = moved(l, handle, nx, ny)
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> handle = -1
        }
        return true
    }

    private fun points(l: DoorLayout): List<Pair<Float, Float>> = buildList {
        add(l.x1 to l.y1); add(l.x2 to l.y2)
        l.seatMask?.let { add(it.x1 to it.y1); add(it.x2 to it.y2) }
    }

    private fun moved(l: DoorLayout, i: Int, nx: Float, ny: Float): DoorLayout = when (i) {
        0 -> l.copy(x1 = nx, y1 = ny)
        1 -> l.copy(x2 = nx, y2 = ny)
        2 -> l.copy(seatMask = l.seatMask?.copy(x1 = nx, y1 = ny))
        else -> l.copy(seatMask = l.seatMask?.copy(x2 = nx, y2 = ny))
    }

    private fun x(v: Float) = dst.left + v * dst.width()
    private fun y(v: Float) = dst.top + v * dst.height()
    private fun rect(b: Box) = RectF(x(minOf(b.x1, b.x2)), y(minOf(b.y1, b.y2)), x(maxOf(b.x1, b.x2)), y(maxOf(b.y1, b.y2)))
}
