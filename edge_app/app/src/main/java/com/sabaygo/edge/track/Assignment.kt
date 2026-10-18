package com.sabaygo.edge.track

/**
 * Minimum-cost matching of rows to columns (Hungarian method, O(n^3)),
 * then pairs costing more than [limit] dropped. That is Ultralytics'
 * `linear_assignment` on its scipy path: solve, then filter.
 *
 * Returns matched (row, column) pairs; rows and columns not listed are
 * unmatched. A cabin holds tens of boxes at most, so cubic time is nothing.
 */
internal fun assign(cost: Array<FloatArray>, limit: Float): List<Pair<Int, Int>> {
    val rows = cost.size
    if (rows == 0) return emptyList()
    val cols = cost[0].size
    if (cols == 0) return emptyList()
    if (rows > cols) {
        val t = Array(cols) { c -> FloatArray(rows) { r -> cost[r][c] } }
        return assign(t, limit).map { (c, r) -> r to c }
    }
    // e-maxx formulation, 1-indexed, rows <= cols: u, v potentials, p[j] row matched to column j.
    val inf = Double.MAX_VALUE / 4
    val u = DoubleArray(rows + 1)
    val v = DoubleArray(cols + 1)
    val p = IntArray(cols + 1)
    val way = IntArray(cols + 1)
    for (i in 1..rows) {
        p[0] = i
        var j0 = 0
        val minv = DoubleArray(cols + 1) { inf }
        val used = BooleanArray(cols + 1)
        do {
            used[j0] = true
            val i0 = p[j0]
            var delta = inf
            var j1 = 0
            for (j in 1..cols) if (!used[j]) {
                val cur = cost[i0 - 1][j - 1] - u[i0] - v[j]
                if (cur < minv[j]) { minv[j] = cur; way[j] = j0 }
                if (minv[j] < delta) { delta = minv[j]; j1 = j }
            }
            for (j in 0..cols) {
                if (used[j]) { u[p[j]] += delta; v[j] -= delta } else minv[j] -= delta
            }
            j0 = j1
        } while (p[j0] != 0)
        do {
            val j1 = way[j0]
            p[j0] = p[j1]
            j0 = j1
        } while (j0 != 0)
    }
    val out = ArrayList<Pair<Int, Int>>()
    for (j in 1..cols) if (p[j] != 0 && cost[p[j] - 1][j - 1] <= limit) out += (p[j] - 1) to (j - 1)
    return out
}
