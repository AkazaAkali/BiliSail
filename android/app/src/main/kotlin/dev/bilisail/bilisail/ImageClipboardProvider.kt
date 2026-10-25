package dev.bilisail.bilisail

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileNotFoundException

// A read-only, URI-granted provider limited to the clipboard's bounded cache.
class ImageClipboardProvider : ContentProvider() {
    override fun onCreate() = true

    private fun file(uri: Uri): File {
        val ctx = context ?: throw FileNotFoundException()
        val name = uri.lastPathSegment ?: throw FileNotFoundException()
        if (uri.authority != "${ctx.packageName}.image_clipboard" || uri.pathSegments.size != 1 ||
            !Regex("BiliSail-[0-9a-fA-F-]{36}\\.(png|jpg|gif|webp|bmp|avif)").matches(name)) {
            throw FileNotFoundException()
        }
        return File(File(ctx.cacheDir, "image_clipboard"), name)
    }

    override fun getType(uri: Uri): String =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(file(uri).extension) ?: "image/*"

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("Read-only clipboard")
        return ParcelFileDescriptor.open(file(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
                       selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
        val file = file(uri)
        if (!file.isFile) throw FileNotFoundException()
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        return MatrixCursor(columns).apply {
            addRow(Array<Any?>(columns.size) { index -> when (columns[index]) {
                OpenableColumns.DISPLAY_NAME -> file.name
                OpenableColumns.SIZE -> file.length()
                else -> null
            } })
        }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) =
        throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) =
        throw UnsupportedOperationException()

    companion object {
        fun uri(context: Context, name: String): Uri = Uri.Builder().scheme("content")
            .authority("${context.packageName}.image_clipboard").appendPath(name).build()
    }
}
