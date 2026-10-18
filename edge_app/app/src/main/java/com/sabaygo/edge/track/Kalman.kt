package com.sabaygo.edge.track

/**
 * ByteTrack's Kalman filter (`kalman_filter.py`, as Ultralytics ships it):
 * constant velocity in (centre x, centre y, aspect w/h, height), noise
 * proportional to the box height. One step per frame.
 *
 * State is 8 values, covariance an 8 x 8 row-major array.
 */
internal object Kalman {
    private const val POS = 1.0 / 20
    private const val VEL = 1.0 / 160

    class State(val mean: DoubleArray, val cov: DoubleArray)

    fun initiate(z: DoubleArray): State {
        val h = z[3]
        val std = doubleArrayOf(
            2 * POS * h, 2 * POS * h, 1e-2, 2 * POS * h,
            10 * VEL * h, 10 * VEL * h, 1e-5, 10 * VEL * h,
        )
        return State(doubleArrayOf(z[0], z[1], z[2], z[3], 0.0, 0.0, 0.0, 0.0), diag(std))
    }

    /** x' = F x, P' = F P F^T + Q, F adding each velocity to its value. */
    fun predict(s: State) {
        val h = s.mean[3]
        for (i in 0 until 4) s.mean[i] += s.mean[4 + i]
        val p = s.cov
        // P F^T then F (P F^T): with F = [I I; 0 I] both are row/column additions.
        for (r in 0 until 8) for (c in 0 until 4) p[r * 8 + c] += p[r * 8 + 4 + c]
        for (r in 0 until 4) for (c in 0 until 8) p[r * 8 + c] += p[(4 + r) * 8 + c]
        val q = doubleArrayOf(POS * h, POS * h, 1e-2, POS * h, VEL * h, VEL * h, 1e-5, VEL * h)
        for (i in 0 until 8) p[i * 8 + i] += q[i] * q[i]
    }

    /** Correct with measurement z (x, y, a, h). */
    fun update(s: State, z: DoubleArray) {
        val h = s.mean[3]
        val r = doubleArrayOf(POS * h, POS * h, 1e-1, POS * h)
        // S = H P H^T + R: the top-left 4 x 4 of P.
        val sm = DoubleArray(16)
        for (i in 0 until 4) for (j in 0 until 4) sm[i * 4 + j] = s.cov[i * 8 + j]
        for (i in 0 until 4) sm[i * 4 + i] += r[i] * r[i]
        val si = invert4(sm)
        // K = P H^T S^-1: P's first four columns times S^-1 (8 x 4).
        val k = DoubleArray(32)
        for (i in 0 until 8) for (j in 0 until 4) {
            var v = 0.0
            for (m in 0 until 4) v += s.cov[i * 8 + m] * si[m * 4 + j]
            k[i * 4 + j] = v
        }
        val y = DoubleArray(4) { z[it] - s.mean[it] }
        for (i in 0 until 8) for (j in 0 until 4) s.mean[i] += k[i * 4 + j] * y[j]
        // P -= K S K^T, which equals K (H P) for the optimal gain.
        val hp = DoubleArray(32)
        for (i in 0 until 4) for (j in 0 until 8) hp[i * 8 + j] = s.cov[i * 8 + j]
        for (i in 0 until 8) for (j in 0 until 8) {
            var v = 0.0
            for (m in 0 until 4) v += k[i * 4 + m] * hp[m * 8 + j]
            s.cov[i * 8 + j] -= v
        }
    }

    private fun diag(std: DoubleArray) = DoubleArray(64).also { for (i in 0 until 8) it[i * 8 + i] = std[i] * std[i] }

    /** Gauss-Jordan with partial pivoting; S is symmetric positive definite. */
    private fun invert4(a: DoubleArray): DoubleArray {
        val m = a.copyOf()
        val inv = DoubleArray(16).also { for (i in 0 until 4) it[i * 4 + i] = 1.0 }
        for (c in 0 until 4) {
            var piv = c
            for (r in c + 1 until 4) if (kotlin.math.abs(m[r * 4 + c]) > kotlin.math.abs(m[piv * 4 + c])) piv = r
            if (piv != c) for (j in 0 until 4) {
                m[c * 4 + j] = m[piv * 4 + j].also { m[piv * 4 + j] = m[c * 4 + j] }
                inv[c * 4 + j] = inv[piv * 4 + j].also { inv[piv * 4 + j] = inv[c * 4 + j] }
            }
            val d = m[c * 4 + c]
            for (j in 0 until 4) { m[c * 4 + j] /= d; inv[c * 4 + j] /= d }
            for (r in 0 until 4) if (r != c) {
                val f = m[r * 4 + c]
                if (f != 0.0) for (j in 0 until 4) {
                    m[r * 4 + j] -= f * m[c * 4 + j]
                    inv[r * 4 + j] -= f * inv[c * 4 + j]
                }
            }
        }
        return inv
    }
}
