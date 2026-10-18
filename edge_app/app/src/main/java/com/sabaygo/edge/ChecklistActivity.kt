package com.sabaygo.edge

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.ComponentActivity
import com.sabaygo.edge.count.Live
import com.sabaygo.edge.link.Config

/**
 * The phone's set-up check (brief 5.3, 5.5): what the office runs before
 * a check-out, and what keeps a Realme from killing the app on the road.
 * Each line says whether it is done; where Android lets an app look, it
 * looks, and the Realme-only switches (auto-launch, background activity)
 * cannot be read by an app, so they say "check by hand" and open the
 * app's settings page.
 */
class ChecklistActivity : ComponentActivity() {
    private lateinit var list: LinearLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(pad(), pad(), pad(), pad()) }
        setContentView(ScrollView(this).apply { addView(list) })
    }

    override fun onResume() {
        super.onResume()
        render()
    }

    private fun render() {
        list.removeAllViews()
        list.addView(TextView(this).apply {
            text = "Phone set-up check"; textSize = 20f; setPadding(0, 0, 0, pad())
        })
        val now = System.currentTimeMillis()
        val s = Live.session
        row(granted(Manifest.permission.CAMERA), "Camera allowed", "Open", ::appSettings)
        row(granted(Manifest.permission.ACCESS_FINE_LOCATION), "Precise location allowed", "Open", ::appSettings)
        row(granted(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
            "Location: Allow all the time (Permissions → Location)", "Open", ::appSettings)
        if (Build.VERSION.SDK_INT >= 33) {
            row(granted(Manifest.permission.POST_NOTIFICATIONS), "Notifications allowed", "Open", ::appSettings)
        }
        row(getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName),
            "Battery optimisation off for this app", "Change", ::batterySetting)
        row(null, "Realme: Auto launch on (Settings → Apps → Auto launch)", "Open", ::appSettings)
        row(null, "Realme: Allow background activity and foreground activity (App info → Battery usage)",
            "Open", ::appSettings)
        row(null, "Realme: not frozen, not in power-saving or sleep standby optimisation", "Open", ::appSettings)
        row(Config(this).ready && Live.sessionError == null && s != null,
            "Server reached and this phone's token accepted", null, null)
        row(s?.vanId != null, "Checked out to a van" + (s?.plate?.let { " ($it)" } ?: ""), null, null)
        row(s?.layout != null, "Door line drawn for this van", null, null)
        row(Live.running && now - Live.lastFrameAt < 5_000, "Camera reporting", null, null)
        row(Live.running && now - Live.lastFixAt < 10_000, "GPS reporting (outdoors or by a window)", null, null)
        row(!Live.lensBlocked, "Lens clear", null, null)
    }

    /** [done] null: Android does not let an app read it; check it by hand. */
    private fun row(done: Boolean?, label: String, action: String?, onClick: (() -> Unit)?) {
        val line = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(0, pad() / 2, 0, pad() / 2) }
        line.addView(TextView(this).apply {
            text = "${when (done) { true -> "✓"; false -> "✗"; null -> "?" }}  $label" +
                if (done == null) "\n    check by hand" else ""
            textSize = 15f
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        })
        if (action != null && onClick != null) line.addView(Button(this).apply { text = action; setOnClickListener { onClick() } })
        list.addView(line)
    }

    private fun granted(p: String) = checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    private fun appSettings() = startActivity(
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))

    @SuppressLint("BatteryLife")   // a dedicated in-van phone is the case this request exists for
    private fun batterySetting() = startActivity(
        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.fromParts("package", packageName, null)))

    private fun pad() = (16 * resources.displayMetrics.density).toInt()
}
