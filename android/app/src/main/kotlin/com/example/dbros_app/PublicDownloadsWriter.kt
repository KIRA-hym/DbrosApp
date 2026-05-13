package com.example.dbros_app

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.IOException

object PublicDownloadsWriter {
    fun writeText(context: Context, fileName: String, text: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("Downloads insert failed")
            resolver.openOutputStream(uri)?.use { stream ->
                stream.write(text.toByteArray(Charsets.UTF_8))
            } ?: throw IOException("Downloads open failed")
            return "${Environment.DIRECTORY_DOWNLOADS}/$fileName"
        }

        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!dir.exists() && !dir.mkdirs()) {
            throw IOException("Downloads directory unavailable")
        }
        val file = File(dir, fileName)
        file.writeText(text, Charsets.UTF_8)
        return file.absolutePath
    }
}
