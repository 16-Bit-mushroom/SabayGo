package com.sabaygo.edge.link

import android.content.Context
import com.sabaygo.edge.track.Box
import com.sabaygo.edge.track.DoorLayout
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID

/**
 * The phone's settings: the server's API address and the token the
 * Terminal Manager was shown once when adding the phone (POST /devices).
 * The model is chosen here until the van Run settles it (docs/benchmarks/).
 */
class Config(context: Context) {
    private val p = context.getSharedPreferences("edge", Context.MODE_PRIVATE)

    var server: String
        get() = p.getString("server", "")!!
        set(v) = p.edit().putString("server", v.trim().trimEnd('/')).apply()
    var token: String
        get() = p.getString("token", "")!!
        set(v) = p.edit().putString("token", v.trim()).apply()
    var model: String
        get() = p.getString("model", MODELS.first())!!
        set(v) = p.edit().putString("model", v).apply()
    /** 0 runs the model on every camera frame it can. */
    var minIntervalMs: Long
        get() = p.getLong("min_interval_ms", 0L)
        set(v) = p.edit().putLong("min_interval_ms", v.coerceAtLeast(0)).apply()

    val ready get() = server.isNotBlank() && token.isNotBlank()

    companion object {
        val MODELS = listOf("models/yolov8n_320.tflite", "models/yolov8n_416.tflite")
    }
}

/**
 * The server's clock, which every time the phone sends is on. The server
 * matches a boarding to a ticket scan within two minutes (brief 6.1) and
 * refuses a batch dated more than 2 min ahead, so the phone's own clock
 * is not trusted: GET /edge/session gives the server's time (Manila wall
 * time, as its DATETIME columns hold it), and the offset is kept from the
 * request's midpoint.
 */
object ServerClock {
    private val MANILA: ZoneId = ZoneId.of("Asia/Manila")
    @Volatile var offsetMs = 0L; private set
    @Volatile var syncedAt = 0L; private set

    fun now(): Instant = Instant.ofEpochMilli(System.currentTimeMillis() + offsetMs)
    fun iso(at: Instant = now()): String = at.toString()

    fun sync(serverTime: String, sentMs: Long, receivedMs: Long) {
        val server = LocalDateTime.parse(serverTime).atZone(MANILA).toInstant().toEpochMilli()
        offsetMs = server - (sentMs + receivedMs) / 2
        syncedAt = receivedMs
    }
}

/** HTTP to the /edge endpoints, authenticated by the phone's token. Throws IOException when the network is down. */
class Api(private val base: String, private val token: String) {
    class Reply(val code: Int, val body: String) {
        val ok get() = code in 200..299
        fun json() = JSONObject(body)
    }

    fun get(path: String) = call("GET", path, null)
    fun send(method: String, path: String, json: JSONObject) = call(method, path, json.toString())

    /** One image as multipart field `image`, as PUT /edge/events/{id}/snapshot takes it. */
    fun putImage(path: String, file: File): Reply {
        val boundary = "sabaygo-" + UUID.randomUUID()
        val c = open("PUT", path)
        c.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
        c.doOutput = true
        c.outputStream.use { out ->
            out.write("--$boundary\r\nContent-Disposition: form-data; name=\"image\"; filename=\"${file.name}\"\r\n".toByteArray())
            out.write("Content-Type: image/jpeg\r\n\r\n".toByteArray())
            file.inputStream().use { it.copyTo(out) }
            out.write("\r\n--$boundary--\r\n".toByteArray())
        }
        return reply(c)
    }

    private fun call(method: String, path: String, body: String?): Reply {
        val c = open(method, path)
        if (body != null) {
            c.setRequestProperty("Content-Type", "application/json")
            c.doOutput = true
            c.outputStream.use { it.write(body.toByteArray()) }
        }
        return reply(c)
    }

    private fun open(method: String, path: String): HttpURLConnection =
        (URL(base + path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 10_000
            readTimeout = 20_000
            setRequestProperty("X-Device-Token", token)
        }

    private fun reply(c: HttpURLConnection): Reply = try {
        val code = c.responseCode
        val stream = if (code >= 400) c.errorStream else c.inputStream
        Reply(code, stream?.bufferedReader()?.use { it.readText() } ?: "")
    } finally {
        c.disconnect()
    }
}

/** What GET /edge/session says: the phone's van, and whether to count now (brief 4.2 rule 13). */
data class SessionInfo(
    val deviceStatus: String,
    val heartbeatGapS: Int,
    val vanId: String?,
    val plate: String?,
    val dispatcher: String?,
    val counting: Boolean,
    val tripId: String?,
    val layout: DoorLayout?,
) {
    companion object {
        fun parse(j: JSONObject) = SessionInfo(
            deviceStatus = j.getString("status"),
            heartbeatGapS = j.getInt("heartbeat_gap_seconds"),
            vanId = j.optStringOrNull("van_id"),
            plate = j.optStringOrNull("plate_number"),
            dispatcher = j.optStringOrNull("dispatcher_name"),
            counting = j.getBoolean("counting"),
            tripId = j.optStringOrNull("trip_id"),
            layout = j.optJSONObject("door_layout")?.let(::layoutFrom),
        )
    }
}

fun JSONObject.optStringOrNull(key: String): String? = if (isNull(key)) null else optString(key)

/** Migration 031's JSON: {"door_line": [[x1,y1],[x2,y2]], "inside": 1|-1, "seat_mask": [[..],[..]] | null}. */
fun layoutFrom(j: JSONObject): DoorLayout {
    val line = j.getJSONArray("door_line")
    val mask = j.optJSONArray("seat_mask")
    fun pt(a: JSONArray, i: Int) = a.getJSONArray(i).let { it.getDouble(0).toFloat() to it.getDouble(1).toFloat() }
    val (x1, y1) = pt(line, 0)
    val (x2, y2) = pt(line, 1)
    return DoorLayout(x1, y1, x2, y2, j.getInt("inside"), mask?.let {
        val (a, b) = pt(it, 0); val (c, d) = pt(it, 1)
        Box(minOf(a, c), minOf(b, d), maxOf(a, c), maxOf(b, d))
    })
}

fun layoutJson(l: DoorLayout): JSONObject = JSONObject()
    .put("door_line", JSONArray().put(JSONArray().put(l.x1).put(l.y1)).put(JSONArray().put(l.x2).put(l.y2)))
    .put("inside", l.inside)
    .put("seat_mask", l.seatMask?.let {
        JSONArray().put(JSONArray().put(it.x1).put(it.y1)).put(JSONArray().put(it.x2).put(it.y2))
    } ?: JSONObject.NULL)
