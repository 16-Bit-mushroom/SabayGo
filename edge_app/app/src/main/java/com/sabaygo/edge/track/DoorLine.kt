package com.sabaygo.edge.track

import kotlin.math.sqrt

/**
 * A van's door line and driver's seat mask (brief 5.2, migration 031), in
 * fractions of the upright frame. [inside] is the sign of the cross
 * product (p2 - p1) x (q - p1) for a point q in the cabin.
 */
data class DoorLayout(
    val x1: Float, val y1: Float, val x2: Float, val y2: Float,
    val inside: Int,
    val seatMask: Box?,
) {
    init { require(inside == 1 || inside == -1) { "inside is 1 or -1" } }

    /** Distance from the line, positive on the cabin side, in frame fractions. */
    fun cabinward(x: Float, y: Float): Float {
        val dx = x2 - x1; val dy = y2 - y1
        val len = sqrt(dx * dx + dy * dy)
        return inside * (dx * (y - y1) - dy * (x - x1)) / len
    }

    /** Where (x, y) falls along the line: 0 at its first point, 1 at its second. */
    fun along(x: Float, y: Float): Float {
        val dx = x2 - x1; val dy = y2 - y1
        return ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)
    }

    /** The driver: a box centred in the seat mask is never tracked (brief 5.2 item 2). */
    fun masked(b: Box) = seatMask?.contains(b.cx, b.cy) == true

    companion object {
        /** A start for a van with none yet: across the lower part of the frame, cabin above. */
        val DEFAULT = DoorLayout(0.2f, 0.8f, 0.8f, 0.8f, inside = -1, seatMask = Box(0.0f, 0.0f, 0.3f, 0.4f))
    }
}

/** A tracked person crossing the door line: inward a boarding, outward an alighting (brief 5.2 item 1). */
data class Crossing(val trackId: Int, val boarding: Boolean, val box: Box)

/**
 * Counts door-line crossings of confirmed tracks by their box centre.
 *
 * A track's side changes only once its centre is [margin] past the line,
 * so a person standing on it, jittering a little between frames, is not
 * counted again and again. A track's first side is where it is first
 * seen and counts nothing: someone already inside when counting starts
 * did not board in front of the camera. Only movement across the drawn
 * segment counts (with [endSlack] beyond each end), not someone passing
 * the line's extension elsewhere in the frame.
 */
class DoorCounter(val layout: DoorLayout, private val margin: Float = 0.03f, private val endSlack: Float = 0.1f) {
    private val side = HashMap<Int, Int>()   // track id -> 1 cabin, -1 outside

    fun update(tracks: List<Track>): List<Crossing> {
        val out = ArrayList<Crossing>()
        val seen = HashSet<Int>()
        for (t in tracks) {
            seen += t.id
            val b = t.box
            val d = layout.cabinward(b.cx, b.cy)
            val now = when {
                d > margin -> 1
                d < -margin -> -1
                else -> continue
            }
            val before = side[t.id]
            if (before == null) { side[t.id] = now; continue }
            if (before == now) continue
            val a = layout.along(b.cx, b.cy)
            if (a < -endSlack || a > 1 + endSlack) { side[t.id] = now; continue }
            side[t.id] = now
            out += Crossing(t.id, boarding = now == 1, box = b)
        }
        if (side.size > MAX_REMEMBERED) side.keys.retainAll(seen)
        return out
    }

    private companion object {
        // Tracks briefly unseen keep their side so a lost-and-found track does not recount;
        // the map is bounded so a long trip does not grow it without end.
        const val MAX_REMEMBERED = 256
    }
}
