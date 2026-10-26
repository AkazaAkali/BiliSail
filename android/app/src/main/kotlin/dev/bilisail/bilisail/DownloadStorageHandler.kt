package dev.bilisail.bilisail

import android.app.Activity
import android.app.AlertDialog
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.CancellationSignal
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.system.Os
import android.system.OsConstants
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Owns exact provider objects, never a path guessed from a content URI. */
internal class DownloadStorageHandler(private val activity: Activity, messenger: BinaryMessenger) {
    private val resolver = activity.contentResolver
    private val prefs = activity.getSharedPreferences("download_storage_v1", Activity.MODE_PRIVATE)
    private val channel = MethodChannel(messenger, "dev.bilisail/download_storage")
    private val worker = Executors.newFixedThreadPool(5)
    private val main = Handler(Looper.getMainLooper())
    private val cancellations = ConcurrentHashMap<String, AtomicBoolean>()
    private val leases = ConcurrentHashMap<String, ParcelFileDescriptor>()
    private val taskLocks = ConcurrentHashMap<String, Any>()
    private var picker: MethodChannel.Result? = null
    private val requestCode = 5714
    private val names = setOf("video.m4s", "audio.m4s", "media.mp4", "media.mkv")

    init { channel.setMethodCallHandler(::call) }

    private fun call(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "choose") {
            if (call.argument<Boolean>("force") != true && prefs.contains("destination")) {
                result.success(true)
            } else choose(result)
            return
        }
        if (call.method == "cancel") {
            cancellations[key(call)]?.set(true); result.success(null); return
        }
        val cancel = if (call.method == "publish") AtomicBoolean(false) else null
        if (cancel != null) cancellations[key(call)] = cancel
        worker.execute {
            try {
                val value: Any? = when (call.method) {
                    "destination" -> {
                        val destination = prefs.getString("destination", null)
                        if (destination != null && destination != "downloads") root(destination, write = true)
                        destination
                    }
                    "publish" -> synchronized(taskLocks.getOrPut(key(call)) { Any() }) { publish(call, cancel!!) }
                    "verify" -> synchronized(taskLocks.getOrPut(key(call)) { Any() }) { verify(call); null }
                    "delete" -> synchronized(taskLocks.getOrPut(key(call)) { Any() }) { delete(call); null }
                    "openMedia" -> openMedia(call.argument<String>("uri")!!)
                    "closeMedia" -> { leases.remove(call.argument<String>("lease"))?.close(); null }
                    else -> throw IllegalArgumentException("不支持的存储操作")
                }
                main.post { result.success(value) }
            } catch (e: Exception) {
                val message = when (e) {
                    is SecurityException -> "下载位置授权已失效，请在设置中重新选择原目录"
                    is java.io.FileNotFoundException -> "公共音视频文件不存在，或存储设备已离线"
                    is UnsupportedOperationException -> "此位置不支持本地视频随机读取，请选择设备上的目录"
                    is IllegalArgumentException -> "下载文件归属或保存位置无效"
                    else -> e.message ?: "公共保存失败，请检查剩余空间、目录授权和存储设备"
                }
                main.post { result.error(if (e is SecurityException) "permission" else "storage", message, null) }
            } finally {
                if (cancel != null) cancellations.remove(key(call), cancel)
            }
        }
    }

    private fun choose(result: MethodChannel.Result) {
        if (picker != null) { result.error("busy", "请先完成当前目录选择", null); return }
        picker = result
        AlertDialog.Builder(activity)
            .setTitle("下载保存位置")
            .setMessage("记住此选择，仅影响新任务。分轨保存会生成独立的视频和音频文件。")
            .setPositiveButton("Downloads/BiliSail") { _, _ ->
                if (Build.VERSION.SDK_INT >= 29) {
                    if (prefs.edit().putString("destination", "downloads").commit()) finishPicker(true)
                    else { picker?.error("storage", "保存下载位置失败", null); picker = null }
                } else launchTree()
            }
            .setNeutralButton("选择其他位置") { _, _ -> launchTree() }
            .setNegativeButton("取消") { _, _ -> finishPicker(false) }
            .setOnCancelListener { finishPicker(false) }.show()
    }

    private fun finishPicker(value: Boolean) { picker?.success(value); picker = null }

    private fun launchTree() {
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }, requestCode)
        } catch (_: Exception) { picker?.error("storage", "系统目录选择器不可用", null); picker = null }
    }

    fun onActivityResult(code: Int, result: Int, data: Intent?): Boolean {
        if (code != requestCode) return false
        val uri = data?.data
        if (result != Activity.RESULT_OK || uri == null) { finishPicker(false); return true }
        try {
            val required = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            val flags = (data?.flags ?: 0) and required
            if (flags != required || uri.scheme != "content" || !DocumentsContract.isTreeUri(uri)) {
                throw SecurityException()
            }
            resolver.takePersistableUriPermission(uri, flags)
            val root = DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
            resolver.query(root, arrayOf(DocumentsContract.Document.COLUMN_FLAGS), null, null, null)?.use {
                if (!it.moveToFirst() || it.getInt(0) and DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE == 0) {
                    throw SecurityException()
                }
            } ?: throw SecurityException()
            if (!prefs.edit().putString("destination", uri.toString()).commit()) throw IOException("保存下载位置失败")
            finishPicker(true)
        } catch (_: Exception) { picker?.error("permission", "无法保留目录读写授权，请重新选择", null); picker = null }
        return true
    }

    private fun key(call: MethodCall): String {
        val id = call.argument<String>("id") ?: throw IllegalArgumentException()
        require(Regex("[0-9a-f]{32}").matches(id))
        val scope = call.argument<String>("scope") ?: throw IllegalArgumentException()
        val digest = MessageDigest.getInstance("SHA-256").digest(scope.toByteArray())
            .joinToString("") { "%02x".format(it) }
        return "task_${digest}_$id"
    }

    private fun read(key: String): JSONObject? = prefs.getString(key, null)?.let(::JSONObject)
    private fun save(key: String, record: JSONObject) {
        if (!prefs.edit().putString(key, record.toString()).commit()) throw IOException("保存公共文件索引失败")
    }
    private fun items(record: JSONObject): Map<String, String> {
        val obj = record.getJSONObject("items")
        return obj.keys().asSequence().associateWith { obj.getString(it) }
    }
    private fun root(destination: String, write: Boolean = false): Uri {
        val tree = Uri.parse(destination)
        require(tree.scheme == "content" && DocumentsContract.isTreeUri(tree))
        if (resolver.persistedUriPermissions.none { it.uri == tree && it.isReadPermission && (!write || it.isWritePermission) }) {
            throw SecurityException()
        }
        return DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
    }

    private fun checkBoundary(record: JSONObject, uri: Uri) {
        val destination = record.getString("destination")
        require(uri.scheme == "content" && items(record).containsValue(uri.toString()))
        if (destination == "downloads") {
            require(Build.VERSION.SDK_INT >= 29 && uri.authority == MediaStore.AUTHORITY)
            resolver.query(uri, arrayOf(MediaStore.MediaColumns.RELATIVE_PATH), null, null, null)?.use {
                if (!it.moveToFirst()) throw java.io.FileNotFoundException()
                require(it.getString(0) == record.getString("relativePath"))
            } ?: throw java.io.FileNotFoundException()
        } else {
            val parent = root(destination)
            resolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)?.use {
                if (!it.moveToFirst()) throw java.io.FileNotFoundException()
            } ?: throw java.io.FileNotFoundException()
            require(uri.authority == parent.authority && DocumentsContract.isChildDocument(resolver, parent, uri))
        }
    }

    private fun readable(uri: Uri): ParcelFileDescriptor {
        val signal = CancellationSignal()
        val timeout = Runnable { signal.cancel() }
        main.postDelayed(timeout, 15000)
        val fd = try {
            resolver.openFileDescriptor(uri, "r", signal) ?: throw java.io.FileNotFoundException()
        } finally { main.removeCallbacks(timeout) }
        try { Os.lseek(fd.fileDescriptor, 0, OsConstants.SEEK_CUR) }
        catch (_: Exception) { fd.close(); throw UnsupportedOperationException() }
        return fd
    }

    private fun verify(call: MethodCall) {
        val record = read(key(call)) ?: throw IllegalArgumentException()
        require(record.getBoolean("ready") && record.getString("destination") == call.argument<String>("destination"))
        val actual = items(record)
        require(actual == call.argument<Map<String, String>>("uris"))
        for ((name, value) in actual) {
            val uri = Uri.parse(value)
            try { checkBoundary(record, uri); readable(uri).close() }
            catch (e: java.io.FileNotFoundException) {
                throw IOException(if (name == "audio.m4s") "公共音频文件不存在或设备已离线" else "公共视频文件不存在或设备已离线")
            }
        }
    }

    private fun publish(call: MethodCall, cancelled: AtomicBoolean): Map<String, String> {
        val key = key(call)
        val destination = call.argument<String>("destination") ?: throw IllegalArgumentException()
        val files = call.argument<Map<String, String>>("files") ?: throw IllegalArgumentException()
        require(files.keys == setOf("video.m4s", "audio.m4s") ||
            files.keys == setOf("media.mp4") || files.keys == setOf("media.mkv"))
        var record = read(key)
        if (record != null) {
            require(record.getString("destination") == destination)
            if (record.getBoolean("ready")) {
                for (value in items(record).values) { val uri = Uri.parse(value); checkBoundary(record, uri); readable(uri).close() }
                return items(record)
            }
            deleteRecord(key, record)
        }
        if (destination == "downloads") require(Build.VERSION.SDK_INT >= 29) else root(destination, write = true)
        val id = call.argument<String>("id")!!
        val relative = "${Environment.DIRECTORY_DOWNLOADS}/BiliSail/$id/"
        record = JSONObject().put("destination", destination).put("relativePath", relative)
            .put("ready", false).put("items", JSONObject())
        save(key, record)
        for ((name, path) in files) {
            if (cancelled.get()) throw IOException("保存已暂停，临时文件已保留")
            require(name in names)
            val source = File(path)
            val anchor = File(activity.applicationInfo.dataDir, "app_flutter").canonicalFile
            require(source.canonicalPath.startsWith(anchor.path + File.separator) && source.name == name && source.parentFile?.name == id)
            // Data-layer path checks already reject links throughout the task subtree.
            val platformAnchor = activity.getDir("flutter", Activity.MODE_PRIVATE).absoluteFile
            val boundary = if (source.absolutePath.startsWith(platformAnchor.path + File.separator)) platformAnchor else anchor
            require(source.absolutePath.startsWith(boundary.path + File.separator))
            var component = source.absoluteFile
            while (component != boundary) {
                require(!OsConstants.S_ISLNK(Os.lstat(component.path).st_mode))
                component = component.parentFile ?: throw IllegalArgumentException()
            }
            val mime = if (name == "audio.m4s") "audio/mp4" else if (name.endsWith("mkv")) "video/x-matroska" else "video/mp4"
            val uri = if (destination == "downloads") {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                    put(MediaStore.MediaColumns.MIME_TYPE, mime)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: throw IOException("无法创建下载文件")
            } else {
                // Unique per-task names avoid collisions without deleting existing documents.
                DocumentsContract.createDocument(resolver, root(destination, write = true), mime, "${id}_$name")
                    ?: throw IOException("无法创建下载文件")
            }
            record.getJSONObject("items").put(name, uri.toString())
            save(key, record)
            // Reject stream-only providers before copying a large media file.
            readable(uri).close()
            source.inputStream().use { input ->
                (resolver.openOutputStream(uri, "w") ?: throw IOException("无法写入下载位置")).use { output ->
                    val buffer = ByteArray(256 * 1024)
                    while (true) {
                        if (cancelled.get()) throw IOException("保存已暂停，临时文件已保留")
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                    }
                    output.flush()
                }
            }
            readable(uri).close()
        }
        if (cancelled.get()) throw IOException("保存已暂停，临时文件已保留")
        if (destination == "downloads") {
            for (value in items(record).values) {
                val values = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
                if (resolver.update(Uri.parse(value), values, null, null) != 1) throw IOException("公开下载文件失败")
            }
        }
        save(key, record.put("ready", true))
        return items(record)
    }

    private fun deleteRecord(key: String, record: JSONObject) {
        for ((name, value) in items(record)) {
            val uri = Uri.parse(value)
            try {
                checkBoundary(record, uri)
                if (record.getString("destination") == "downloads") {
                    if (resolver.delete(uri, null, null) != 1) throw IOException("删除下载文件失败")
                }
                else if (!DocumentsContract.deleteDocument(resolver, uri)) throw IOException("删除下载文件失败")
            } catch (_: java.io.FileNotFoundException) { /* Already removed by the user. */ }
            record.getJSONObject("items").remove(name)
            save(key, record)
        }
        if (!prefs.edit().remove(key).commit()) throw IOException("保存删除结果失败")
    }

    private fun delete(call: MethodCall) {
        val key = key(call)
        val record = read(key) ?: return
        require(record.getString("destination") == call.argument<String>("destination"))
        deleteRecord(key, record)
    }

    private fun openMedia(value: String): Map<String, Any> {
        val record = prefs.all.entries.asSequence().filter { it.key.startsWith("task_") }
            .map { JSONObject(it.value as String) }.firstOrNull { it.optBoolean("ready") && items(it).containsValue(value) }
            ?: throw SecurityException()
        val uri = Uri.parse(value)
        checkBoundary(record, uri)
        val fd = readable(uri)
        val lease = UUID.randomUUID().toString()
        leases[lease] = fd
        return mapOf("lease" to lease, "fd" to fd.fd)
    }

    fun close() {
        channel.setMethodCallHandler(null)
        cancellations.values.forEach { it.set(true) }
        finishPicker(false)
        worker.execute { leases.values.forEach { it.close() }; leases.clear() }
        worker.shutdown()
    }
}
