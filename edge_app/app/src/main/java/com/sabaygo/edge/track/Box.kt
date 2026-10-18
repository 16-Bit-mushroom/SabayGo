package com.sabaygo.edge.track

import kotlin.math.max
import kotlin.math.min

/**
 * A person box in fractions of the upright camera frame (0..1, y down),
 * with the detector's score. Every geometry in the edge app uses these
 * units, so the door line drawn on one frame size holds on another.
 */
data class Box(val x1: Float, val y1: Float, val x2: Float, val y2: Float, val score: Float = 1f) {
    val cx: Float get() = (x1 + x2) / 2
    val cy: Float get() = (y1 + y2) / 2
    val w: Float get() = x2 - x1
    val h: Float get() = y2 - y1

    fun contains(x: Float, y: Float) = x in min(x1, x2)..max(x1, x2) && y in min(y1, y2)..max(y1, y2)
}

/** Intersection over union. Scaling either axis changes neither, so fractions give the pixel answer. */
fun iou(a: Box, b: Box): Float {
    val iw = max(0f, min(a.x2, b.x2) - max(a.x1, b.x1))
    val ih = max(0f, min(a.y2, b.y2) - max(a.y1, b.y1))
    val inter = iw * ih
    val union = a.w * a.h + b.w * b.h - inter
    return if (union <= 0f) 0f else inter / union
}
