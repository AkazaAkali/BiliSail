package dev.bilisail.bilisail

import android.app.Activity
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.OrientationEventListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/** Physical orientation remains available while Flutter locks the UI landscape. */
class DeviceOrientationHandler(private val activity: Activity, messenger: BinaryMessenger) :
    EventChannel.StreamHandler {
    private val channel = EventChannel(messenger, "bilisail/device_orientation")
    private var sink: EventChannel.EventSink? = null
    private var resumed = false
    private var listening = false
    private var orientation = "unknown"
    private var lastEvent: Map<String, Any>? = null
    private val rotationSetting = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) = publish()
    }
    private val sensor = object : OrientationEventListener(activity) {
        override fun onOrientationChanged(angle: Int) {
            // Leave a 30-degree dead zone between axes; flat/ambiguous samples
            // never count as a physical turn or an app-forced orientation.
            orientation = when (angle) {
                in 0..30, in 330..359, in 150..210 -> "portrait"
                in 60..120, in 240..300 -> "landscape"
                else -> "unknown"
            }
            publish()
        }
    }

    init {
        channel.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        lastEvent = null
        updateListening()
        publish()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        updateListening()
        lastEvent = null
    }

    fun setResumed(value: Boolean) {
        resumed = value
        updateListening()
        publish()
    }

    fun configurationChanged() {
        updateListening()
        publish()
    }

    private fun updateListening() {
        val enabled = resumed && sink != null && isFullScreenPhone() && sensor.canDetectOrientation()
        if (enabled == listening) return
        listening = enabled
        orientation = "unknown"
        if (enabled) {
            activity.contentResolver.registerContentObserver(
                Settings.System.getUriFor(Settings.System.ACCELEROMETER_ROTATION),
                false,
                rotationSetting,
            )
            sensor.enable()
        } else {
            sensor.disable()
            activity.contentResolver.unregisterContentObserver(rotationSetting)
        }
    }

    @Suppress("DEPRECATION")
    private fun isFullScreenPhone(): Boolean {
        if (activity.isInMultiWindowMode || activity.isInPictureInPictureMode) return false
        // Configuration smallestScreenWidthDp describes the current split pane;
        // the display size prevents a small tablet pane being mistaken for a phone.
        val metrics = DisplayMetrics()
        activity.windowManager.defaultDisplay.getRealMetrics(metrics)
        return metrics.density > 0 &&
            minOf(metrics.widthPixels, metrics.heightPixels) / metrics.density < 600
    }

    private fun publish() {
        val events = sink ?: return
        val supported = isFullScreenPhone()
        val event = mapOf(
            "supported" to supported,
            "orientation" to if (listening && supported) orientation else "unknown",
            "autoRotate" to (Settings.System.getInt(
                activity.contentResolver,
                Settings.System.ACCELEROMETER_ROTATION,
                0,
            ) == 1),
        )
        if (event == lastEvent) return
        lastEvent = event
        events.success(event)
    }

    fun close() {
        sink = null
        updateListening()
        channel.setStreamHandler(null)
    }
}
