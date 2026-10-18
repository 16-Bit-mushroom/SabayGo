package com.sabaygo.edge.track

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The counting core on made-up frames: no camera, no model, no phone. */
class TrackingTest {

    private fun person(cx: Float, cy: Float, score: Float = 0.9f, w: Float = 0.12f, h: Float = 0.3f) =
        Box(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, score)

    /** Door line across y = 0.6, cabin above it (smaller y). */
    private val door = DoorLayout(0.2f, 0.6f, 0.8f, 0.6f, inside = -1, seatMask = Box(0f, 0f, 0.25f, 0.35f))

    /** Feed frames at 10 a second through the tracker and the counter; return every crossing. */
    private fun run(frames: List<List<Box>>, layout: DoorLayout = door): List<Crossing> {
        val tracker = ByteTrack()
        val counter = DoorCounter(layout)
        return frames.flatMapIndexed { i, dets ->
            counter.update(tracker.update(dets.filterNot(layout::masked), i * 0.1))
        }
    }

    private fun walk(fromY: Float, toY: Float, steps: Int, x: Float = 0.5f) =
        (0..steps).map { listOf(person(x, fromY + (toY - fromY) * it / steps)) }

    @Test fun `assignment finds the cheapest matching and drops pairs over the limit`() {
        val cost = arrayOf(floatArrayOf(4f, 1f, 3f), floatArrayOf(2f, 0f, 5f), floatArrayOf(3f, 2f, 2f))
        assertEquals(setOf(0 to 1, 1 to 0, 2 to 2), assign(cost, 10f).toSet())
        assertEquals(setOf(0 to 1, 1 to 0, 2 to 2), assign(cost, 2f).toSet())
        assertEquals(setOf(0 to 1), assign(cost, 1f).toSet())
        // More rows than columns: one row stays unmatched.
        assertEquals(setOf(1 to 0), assign(arrayOf(floatArrayOf(0.9f), floatArrayOf(0.1f)), 1f).toSet())
    }

    @Test fun `a person walking keeps one id`() {
        val tracker = ByteTrack()
        val ids = walk(0.9f, 0.3f, 20).mapIndexed { i, d -> tracker.update(d, i * 0.1).map { it.id } }
        assertEquals(setOf(1), ids.flatten().toSet())
    }

    @Test fun `a person hidden for a few frames comes back with the same id`() {
        val tracker = ByteTrack()
        val frames = walk(0.9f, 0.3f, 20).mapIndexed { i, d -> if (i in 8..11) emptyList() else d }
        val ids = frames.mapIndexed { i, d -> tracker.update(d, i * 0.1).map { it.id } }
        assertEquals(setOf(1), ids.flatten().toSet())
    }

    @Test fun `a weak detection keeps a person followed rather than starting a new one`() {
        val tracker = ByteTrack()
        val frames = walk(0.9f, 0.3f, 20).mapIndexed { i, d ->
            if (i in 8..11) d.map { it.copy(score = 0.2f) } else d
        }
        val ids = frames.mapIndexed { i, d -> tracker.update(d, i * 0.1).map { it.id } }
        assertEquals(setOf(1), ids.flatten().toSet())
        assertTrue("followed through the weak frames", ids.slice(8..11).all { it == listOf(1) })
    }

    @Test fun `two people side by side are two tracks`() {
        val tracker = ByteTrack()
        var last = emptyList<Int>()
        for (i in 0..10) last = tracker.update(listOf(person(0.35f, 0.5f), person(0.65f, 0.5f)), i * 0.1).map { it.id }
        assertEquals(listOf(1, 2), last.sorted())
    }

    @Test fun `walking in through the door is one boarding`() {
        val c = run(walk(0.9f, 0.3f, 20))
        assertEquals(1, c.size)
        assertTrue(c[0].boarding)
    }

    @Test fun `walking out is one alighting`() {
        val c = run(walk(0.3f, 0.9f, 20))
        assertEquals(1, c.size)
        assertFalse(c[0].boarding)
    }

    @Test fun `standing on the line, swaying, counts nothing`() {
        val frames = (0..40).map { listOf(person(0.5f, 0.6f + if (it % 2 == 0) 0.02f else -0.02f)) }
        assertEquals(0, run(frames).size)
    }

    @Test fun `someone already inside when counting starts did not board`() {
        val frames = (0..20).map { listOf(person(0.5f, 0.3f + it * 0.005f)) }
        assertEquals(0, run(frames).size)
    }

    @Test fun `in and back out is a boarding then an alighting`() {
        val c = run(walk(0.9f, 0.3f, 15) + walk(0.3f, 0.9f, 15).drop(1))
        assertEquals(listOf(true, false), c.map { it.boarding })
    }

    @Test fun `crossing the line's extension beside the door counts nothing`() {
        assertEquals(0, run(walk(0.9f, 0.3f, 20, x = 0.97f)).size)
    }

    @Test fun `the driver in the seat mask is never counted`() {
        // Moves across the line's height inside the mask region's x range but centred in the mask.
        val driver = (0..20).map { listOf(person(0.12f, 0.15f + (it % 4) * 0.02f)) }
        assertEquals(0, run(driver).size)
        assertTrue(door.masked(person(0.12f, 0.15f)))
        assertFalse(door.masked(person(0.5f, 0.5f)))
    }

    @Test fun `three people boarding one after another are three boardings`() {
        val frames = ArrayList<List<Box>>()
        repeat(3) { frames += walk(0.9f, 0.3f, 15); frames += List(5) { emptyList() } }
        assertEquals(listOf(true, true, true), run(frames).map { it.boarding })
    }

    @Test fun `the cabin side follows the sign`() {
        assertTrue(door.cabinward(0.5f, 0.3f) > 0)
        assertTrue(door.cabinward(0.5f, 0.9f) < 0)
        val flipped = door.copy(inside = 1)
        assertTrue(flipped.cabinward(0.5f, 0.9f) > 0)
    }
}
