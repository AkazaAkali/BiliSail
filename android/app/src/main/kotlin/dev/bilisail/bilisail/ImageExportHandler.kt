package dev.bilisail.bilisail

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

internal class ImageExportHandler(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "bilisail/image_export")
    private val worker = Executors.newSingleThreadExecutor()
    private var pendingPermission: Pair<MethodCall, MethodChannel.Result>? = null
    private var busy = false
    private var closed = false

    init { channel.setMethodCallHandler { call, result -> handle(call, result) } }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "save" && call.method != "copy") { result.notImplemented(); return }
        if (busy || closed) { result.error("busy", "Image export unavailable", null); return }
        val bytes = call.argument<ByteArray>("bytes")
        val extension = call.argument<String>("extension")
        val mime = call.argument<String>("mime")
        if (bytes == null || bytes.isEmpty() || bytes.size > 32 * 1024 * 1024 ||
            extension !in listOf("png", "jpg", "gif", "webp", "bmp", "avif") ||
            mime == null || !mime.startsWith("image/")) {
            result.error("invalid_image", "Invalid image data", null); return
        }
        busy = true
        if (call.method == "save" && Build.VERSION.SDK_INT < 29 &&
            activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            pendingPermission = Pair(call, result)
            activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), permissionRequest)
            return
        }
        worker.execute {
            try {
                val name = "BiliSail-${UUID.randomUUID()}.$extension"
                if (call.method == "copy") {
                    val directory = File(activity.cacheDir, "image_clipboard").apply { mkdirs() }
                    val file = File(directory, name)
                    try { file.writeBytes(bytes) } catch (error: Exception) { file.delete(); throw error }
                    // Retain four recent originals (at most 128 MiB). Keep the
                    // current URI alive after the viewer closes and after restart.
                    directory.listFiles()?.filter { it != file }?.sortedByDescending { it.lastModified() }
                        ?.drop(3)?.forEach { it.delete() }
                    val uri = ImageClipboardProvider.uri(activity, file.name)
                    activity.runOnUiThread {
                        try {
                            if (closed) { file.delete(); return@runOnUiThread }
                            val clipboard = activity.getSystemService(ClipboardManager::class.java)
                            clipboard.setPrimaryClip(ClipData.newUri(activity.contentResolver, "图片", uri))
                            result.success(null)
                        } catch (_: Exception) {
                            file.delete()
                            result.error("copy_failed", "Could not copy image", null)
                        } finally { busy = false }
                    }
                } else {
                    save(bytes, name, mime)
                    activity.runOnUiThread { busy = false; if (!closed) result.success("Pictures/BiliSail/$name") }
                }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    busy = false
                    if (!closed) result.error("export_failed", "Could not export image", null)
                }
            }
        }
    }

    private fun save(bytes: ByteArray, name: String, mime: String) {
        if (Build.VERSION.SDK_INT >= 29) {
            val resolver = activity.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, mime)
                put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/BiliSail")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = checkNotNull(resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values))
            try {
                checkNotNull(resolver.openOutputStream(uri)).use { it.write(bytes) }
                val published = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
                check(resolver.update(uri, published, null, null) == 1)
            } catch (error: Exception) { resolver.delete(uri, null, null); throw error }
        } else {
            @Suppress("DEPRECATION")
            val directory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "BiliSail")
            check(directory.isDirectory || directory.mkdirs())
            val file = File(directory, name)
            try { file.writeBytes(bytes) } catch (error: Exception) { file.delete(); throw error }
            MediaScannerConnection.scanFile(activity, arrayOf(file.absolutePath), arrayOf(mime), null)
        }
    }

    fun onPermissionResult(requestCode: Int, grants: IntArray) {
        if (requestCode != permissionRequest) return
        val pending = pendingPermission ?: return
        pendingPermission = null
        busy = false
        if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) handle(pending.first, pending.second)
        else pending.second.error("permission_denied", "Storage permission denied", null)
    }

    fun close() {
        closed = true
        pendingPermission?.second?.error("cancelled", "Activity closed", null)
        pendingPermission = null
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }

    private companion object { const val permissionRequest = 24025 }
}
