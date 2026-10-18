package com.sabaygo.edge.track

/** One person followed across frames. The id is a tracker number within the trip, never an identity (brief 5.2). */
class Track internal constructor(private val detected: Box) {
    var id = 0; private set
    var score = detected.score; private set
    /** Seen in two frames running (or in the first frame): only these may count a crossing. */
    var confirmed = false; private set
    internal var state = State.New
    internal var lastSeen = 0.0
    internal var startFrame = 0
    private var kf: Kalman.State? = null

    internal enum class State { New, Tracked, Lost, Removed }

    /** The filter's estimate once tracked, the detection before that. */
    val box: Box get() = kf?.mean?.let {
        val h = it[3].toFloat(); val w = (it[2] * it[3]).toFloat()
        val cx = it[0].toFloat(); val cy = it[1].toFloat()
        Box(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, score)
    } ?: detected

    internal fun predict() {
        val s = kf ?: return
        if (state != State.Tracked) s.mean[7] = 0.0
        Kalman.predict(s)
    }

    internal fun activate(id: Int, frame: Int, t: Double, confirmNow: Boolean) {
        this.id = id
        kf = Kalman.initiate(measure(detected))
        state = State.Tracked
        confirmed = confirmNow
        lastSeen = t
        startFrame = frame
    }

    /** A new detection of this person, found again or followed (ByteTrack's update and re_activate). */
    internal fun update(det: Track, t: Double) {
        Kalman.update(kf!!, measure(det.detected))
        state = State.Tracked
        confirmed = true
        score = det.score
        lastSeen = t
    }

    private fun measure(b: Box) = doubleArrayOf(b.cx.toDouble(), b.cy.toDouble(), (b.w / b.h).toDouble(), b.h.toDouble())
}

/**
 * ByteTrack (Zhang et al., 2022) as Ultralytics' `BYTETracker` runs it:
 * high-score detections matched first to every track by IoU fused with
 * the score, then low-score detections to the tracks still unmatched (a
 * person half hidden in the doorway keeps their track), new tracks
 * confirmed by a second sighting, lost tracks kept for [lostSeconds] and
 * duplicates of a lost track dropped.
 *
 * Differences from Ultralytics, both because the phone's frame rate is not
 * fixed: a lost track expires by time rather than by frame count, and the
 * thresholds are given here, not read from a YAML file. The high and new
 * thresholds are the counting rule's 0.45 (ai_service/inference.py), so
 * a box too weak to be counted is never a new person; the low one is
 * Ultralytics' 0.1.
 */
class ByteTrack(
    private val highScore: Float = 0.45f,
    private val lowScore: Float = 0.1f,
    private val newTrackScore: Float = 0.45f,
    private val matchCost: Float = 0.8f,
    private val lostSeconds: Double = 1.0,
) {
    private var tracked = mutableListOf<Track>()
    private var lost = mutableListOf<Track>()
    private var nextId = 1
    private var frame = 0

    /** A new trip: ids start again at 1. */
    fun reset() {
        tracked.clear(); lost.clear(); nextId = 1; frame = 0
    }

    /** One frame's detections, taken at [t] seconds. Returns the confirmed tracks seen in it. */
    fun update(detections: List<Box>, t: Double): List<Track> {
        frame++
        val activated = mutableListOf<Track>()
        val newlyLost = mutableListOf<Track>()
        val removed = mutableListOf<Track>()

        val high = detections.filter { it.score >= highScore }.map(::Track)
        val low = detections.filter { it.score > lowScore && it.score < highScore }.map(::Track)
        val unconfirmed = tracked.filter { !it.confirmed }
        val pool = (tracked.filter { it.confirmed } + lost).distinctBy { it.id }
        pool.forEach { it.predict() }

        // 1. High-score detections against every confirmed and lost track.
        val m1 = assign(cost(pool, high, fuse = true), matchCost)
        m1.forEach { (ti, di) -> pool[ti].update(high[di], t); activated += pool[ti] }
        val leftTracks = pool.indices.toSet() - m1.map { it.first }.toSet()
        val leftHigh = (high.indices.toSet() - m1.map { it.second }.toSet()).sorted().map { high[it] }

        // 2. Low-score detections against tracks that were being followed.
        val following = leftTracks.sorted().map { pool[it] }.filter { it.state == Track.State.Tracked }
        val m2 = assign(cost(following, low, fuse = false), 0.5f)
        m2.forEach { (ti, di) -> following[ti].update(low[di], t); activated += following[ti] }
        (following.indices.toSet() - m2.map { it.first }.toSet()).forEach { i ->
            following[i].state = Track.State.Lost
            newlyLost += following[i]
        }

        // 3. Tracks seen once, against the high-score detections left.
        val m3 = assign(cost(unconfirmed, leftHigh, fuse = true), 0.7f)
        m3.forEach { (ti, di) -> unconfirmed[ti].update(leftHigh[di], t); activated += unconfirmed[ti] }
        (unconfirmed.indices.toSet() - m3.map { it.first }.toSet()).forEach { i ->
            unconfirmed[i].state = Track.State.Removed
            removed += unconfirmed[i]
        }

        // 4. What is still unmatched and strong enough starts a track.
        (leftHigh.indices.toSet() - m3.map { it.second }.toSet()).sorted().forEach { i ->
            val tr = leftHigh[i]
            if (tr.score >= newTrackScore) {
                tr.activate(nextId++, frame, t, confirmNow = frame == 1)
                activated += tr
            }
        }

        for (tr in lost) if (tr.state == Track.State.Lost && t - tr.lastSeen > lostSeconds) {
            tr.state = Track.State.Removed
            removed += tr
        }

        tracked = (tracked + activated).filter { it.state == Track.State.Tracked }.distinctBy { it.id }.toMutableList()
        lost = (lost + newlyLost).filter { it.state == Track.State.Lost }.distinctBy { it.id }.toMutableList()
        dropDuplicates()
        return tracked.filter { it.confirmed }
    }

    /** A lost track and a followed one over the same person: keep the one followed longer. */
    private fun dropDuplicates() {
        val c = cost(tracked, lost, fuse = false)
        val dupTracked = HashSet<Int>()
        val dupLost = HashSet<Int>()
        for (i in tracked.indices) for (j in lost.indices) if (c[i][j] < 0.15f) {
            if (frame - tracked[i].startFrame > frame - lost[j].startFrame) dupLost += j else dupTracked += i
        }
        tracked = tracked.filterIndexed { i, _ -> i !in dupTracked }.toMutableList()
        lost = lost.filterIndexed { j, _ -> j !in dupLost }.toMutableList()
    }

    private fun cost(tracks: List<Track>, dets: List<Track>, fuse: Boolean) =
        Array(tracks.size) { i ->
            FloatArray(dets.size) { j ->
                val sim = iou(tracks[i].box, dets[j].box)
                1f - if (fuse) sim * dets[j].score else sim
            }
        }
}
