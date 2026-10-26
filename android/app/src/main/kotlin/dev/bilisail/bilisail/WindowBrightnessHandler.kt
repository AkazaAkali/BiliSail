package dev.bilisail.bilisail

import android.app.Activity
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** A window-only override requires no WRITE_SETTINGS permission. */
class WindowBrightnessHandler(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "bilisail/window_brightness")
    private var original: Float? = null
    private var latestOwner = 0L
    private var activeOwner: Long? = null

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "get" -> {
                        val override = activity.window.attributes.screenBrightness
                        val value = if (override >= 0) override else
                            Settings.System.getInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128) / 255f
                        result.success(value.coerceIn(0f, 1f).toDouble())
                    }
                    "set", "reset" -> {
                        val owner = call.argument<Number>("owner")?.toLong()
                        val value = call.argument<Number>("value")?.toFloat()
                        if (owner == null || (call.method == "set" &&
                            (value == null || !value.isFinite() || value < 0.01f || value > 1f))) {
                            result.error("invalid_argument", "Invalid brightness command", null)
                        } else {
                            if (call.method == "set" && owner >= latestOwner) {
                                latestOwner = owner
                                activeOwner = owner
                                if (original == null) original = activity.window.attributes.screenBrightness
                                val attributes = activity.window.attributes
                                attributes.screenBrightness = requireNotNull(value)
                                activity.window.attributes = attributes
                            } else if (call.method == "reset" && activeOwner == owner) {
                                restore()
                            }
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: RuntimeException) {
                result.error("brightness_failed", "Unable to change window brightness", null)
            }
        }
    }

    private fun restore() {
        val previous = original ?: return
        val attributes = activity.window.attributes
        attributes.screenBrightness = previous
        activity.window.attributes = attributes
        original = null
        activeOwner = null
    }

    fun close() {
        channel.setMethodCallHandler(null)
        restore()
    }
}
