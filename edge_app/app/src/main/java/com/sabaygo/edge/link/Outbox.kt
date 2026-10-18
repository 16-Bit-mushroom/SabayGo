package com.sabaygo.edge.link

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException

/**
 * Everything the phone sends waits here first, so nothing seen offline is
 * lost (brief 5.1: "stores events and holds them until the connection
 * returns"). One SQLite table on the phone's own storage, kept in the
 * order written, each row one door event, GPS reading, status report or
 * blurred still (its file beside it).
 *
 * A row the server refuses for good (its fields rejected, its event
 * unknown) is set aside, not deleted: it stays on the phone for whoever
 * looks into why, and stops holding up the rows behind it.
 */
class Outbox(context: Context) : SQLiteOpenHelper(context, "outbox.db", null, 1) {

    enum class Kind { EVENT, FIX, REPORT, STILL }

    class Row(val id: Long, val body: String, val ref: String?, val file: String?)

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, " +
                "ref TEXT, body TEXT NOT NULL, file TEXT, set_aside INTEGER NOT NULL DEFAULT 0)"
        )
        db.execSQL("CREATE INDEX ix_outbox_kind ON outbox (set_aside, kind, id)")
    }

    override fun onUpgrade(db: SQLiteDatabase, old: Int, new: Int) = Unit

    fun add(kind: Kind, body: JSONObject, ref: String? = null, file: File? = null) {
        writableDatabase.insert("outbox", null, ContentValues().apply {
            put("kind", kind.name); put("ref", ref); put("body", body.toString()); put("file", file?.path)
        })
    }

    fun take(kind: Kind, limit: Int): List<Row> = readableDatabase.query(
        "outbox", arrayOf("id", "body", "ref", "file"), "set_aside = 0 AND kind = ?", arrayOf(kind.name),
        null, null, "id", limit.toString(),
    ).use { c ->
        buildList { while (c.moveToNext()) add(Row(c.getLong(0), c.getString(1), c.getString(2), c.getString(3))) }
    }

    fun delete(rows: List<Row>) = mark(rows, "DELETE FROM outbox")
    fun setAside(rows: List<Row>) = mark(rows, "UPDATE outbox SET set_aside = 1")

    /** True while the door event [eventId] has not reached the server: its still waits for it. */
    fun eventWaiting(eventId: String): Boolean = readableDatabase.rawQuery(
        "SELECT 1 FROM outbox WHERE set_aside = 0 AND kind = ? AND ref = ? LIMIT 1",
        arrayOf(Kind.EVENT.name, eventId),
    ).use { it.moveToFirst() }

    /** Rows waiting, by kind, for the screen. */
    fun waiting(): Map<Kind, Int> = readableDatabase.rawQuery(
        "SELECT kind, COUNT(*) FROM outbox WHERE set_aside = 0 GROUP BY kind", null,
    ).use { c -> buildMap { while (c.moveToNext()) put(Kind.valueOf(c.getString(0)), c.getInt(1)) } }

    private fun mark(rows: List<Row>, sql: String) {
        if (rows.isEmpty()) return
        writableDatabase.execSQL("$sql WHERE id IN (${rows.joinToString(",") { it.id.toString() }})")
    }
}

/**
 * Sends the outbox in order: door events first (the list check before
 * departure waits on them), then GPS readings (a departure seen by GPS
 * looks for the boardings), status reports, and stills once their event
 * is on the server. Every endpoint takes a resend safely.
 *
 * - 2xx: sent, removed.
 * - 401: the token is no longer valid; nothing more is sent until it is
 *   replaced.
 * - 422 "dated in the future": the clock is resynchronised; if it was
 *   just synchronised the rows' own times are wrong, and they are set
 *   aside.
 * - other 4xx: the server will never take these rows; set aside.
 * - 5xx or no network: kept, tried again next round.
 */
class Uploader(private val outbox: Outbox, private val api: () -> Api?, private val resync: () -> Unit) {
    @Volatile var lastSentAt = 0L; private set
    @Volatile var lastError: String? = null; private set
    @Volatile var tokenRefused = false; private set

    /** One round; returns false when it stopped early (offline, refused). */
    fun round(): Boolean {
        val api = api() ?: return false
        if (tokenRefused) return false
        return try {
            batch(api, Outbox.Kind.EVENT, "/edge/events", "events") &&
                batch(api, Outbox.Kind.FIX, "/edge/fixes", "fixes") &&
                batch(api, Outbox.Kind.REPORT, "/edge/heartbeats", "reports") &&
                stills(api)
        } catch (e: IOException) {
            lastError = "offline: ${e.message}"
            false
        }
    }

    /** The token was replaced in the settings: try again. */
    fun reset() { tokenRefused = false; lastError = null }

    private fun batch(api: Api, kind: Outbox.Kind, path: String, field: String): Boolean {
        while (true) {
            val rows = outbox.take(kind, BATCH)
            if (rows.isEmpty()) return true
            val reply = api.send("POST", path, JSONObject().put(field, JSONArray(rows.map { JSONObject(it.body) })))
            if (!handle(reply, rows)) return false
        }
    }

    private fun stills(api: Api): Boolean {
        for (row in outbox.take(Outbox.Kind.STILL, BATCH)) {
            val eventId = row.ref ?: continue
            if (outbox.eventWaiting(eventId)) continue
            val file = File(row.file ?: continue)
            if (!file.exists()) { outbox.setAside(listOf(row)); continue }
            val reply = api.putImage("/edge/events/$eventId/snapshot", file)
            if (!handle(reply, listOf(row))) return false
            if (reply.ok) file.delete()
        }
        return true
    }

    private fun handle(reply: Api.Reply, rows: List<Outbox.Row>): Boolean = when {
        reply.ok -> { outbox.delete(rows); lastSentAt = System.currentTimeMillis(); lastError = null; true }
        reply.code == 401 -> { tokenRefused = true; lastError = "token refused (401)"; false }
        reply.code == 422 && "future" in reply.body -> {
            if (System.currentTimeMillis() - ServerClock.syncedAt < 60_000) outbox.setAside(rows) else resync()
            lastError = "clock refused"; false
        }
        reply.code in 400..499 -> { outbox.setAside(rows); lastError = "refused ${reply.code}: ${reply.body.take(120)}"; true }
        else -> { lastError = "server ${reply.code}"; false }
    }

    private companion object { const val BATCH = 200 }
}
