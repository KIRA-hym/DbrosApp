package com.example.dbros_app

import android.content.ContentUris
import android.content.Context
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * MediaStore.EXTERNAL 이미지 삽입/변경 감지 → Flutter 로 알림 (삼성 Android 14+ 보완).
 */
object GalleryMediaBridge {
    private const val TAG = "GalleryMediaBridge"
    private const val CHANNEL_NAME = "dbros.app/gallery_observer"

    private var appContext: Context? = null
    private var channel: MethodChannel? = null
    private var observer: ContentObserver? = null
    private val handler = Handler(Looper.getMainLooper())
    private var emitRunnable: Runnable? = null

    fun register(flutterEngine: FlutterEngine, context: Context) {
        if (channel != null) return
        appContext = context.applicationContext
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        startObserver()
                        result.success(null)
                    }
                    "stop" -> {
                        stopObserver()
                        result.success(null)
                    }
                    "queryLatestScreenshot" -> {
                        try {
                            val maxAge = (call.argument<Int>("maxAgeSeconds") ?: 120).toLong().coerceAtLeast(15L)
                            val path = queryLatestScreenshotToCache(maxAge)
                            result.success(path)
                        } catch (e: Exception) {
                            Log.e(TAG, "queryLatestScreenshot", e)
                            result.error("query_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        Log.d(TAG, "Channel registered")
    }

    fun dispose() {
        stopObserver()
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
        Log.d(TAG, "Disposed")
    }

    private fun startObserver() {
        val ctx = appContext ?: return
        stopObserver()
        observer = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                if (selfChange) return
                Log.d(TAG, "Images.Media onChange uri=$uri")
                scheduleEmit()
            }
        }
        try {
            ctx.contentResolver.registerContentObserver(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                true,
                observer!!,
            )
            Log.d(TAG, "ContentObserver registered")
        } catch (e: Exception) {
            Log.e(TAG, "registerContentObserver failed", e)
        }
    }

    private fun stopObserver() {
        emitRunnable?.let { handler.removeCallbacks(it) }
        emitRunnable = null
        val ctx = appContext
        observer?.let { obs ->
            if (ctx != null) {
                try {
                    ctx.contentResolver.unregisterContentObserver(obs)
                } catch (_: Exception) {
                }
            }
        }
        observer = null
    }

    /**
     * photo_manager 에서 스크린샷을 못 찾을 때 MediaStore 로 직접 최신 이미지를 가져와
     * 앱 cacheDir 에 복사한 뒤 절대 경로를 반환한다 (READ_MEDIA_IMAGES 등 런타임 권한 전제).
     */
    private fun queryLatestScreenshotToCache(maxAgeSeconds: Long): String? {
        val ctx = appContext ?: return null
        val resolver = ctx.contentResolver
        val nowSec = System.currentTimeMillis() / 1000L
        val cutoff = (nowSec - maxAgeSeconds).coerceAtLeast(0L)

        fun copyUriToTempFile(id: Long, displayName: String?): String? {
            val uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)
            return try {
                resolver.openInputStream(uri)?.use { input ->
                    val ext = displayName
                        ?.substringAfterLast('.', "")
                        ?.takeIf { it.length in 1..5 && it.all { c -> c.isLetterOrDigit() } }
                        ?: "jpg"
                    val outFile = File(ctx.cacheDir, "auto_screenshot_$id.$ext")
                    FileOutputStream(outFile).use { output -> input.copyTo(output) }
                    outFile.absolutePath
                }
            } catch (e: Exception) {
                Log.e(TAG, "copyUriToTempFile id=$id", e)
                null
            }
        }

        val idCol = MediaStore.Images.Media._ID
        val nameCol = MediaStore.Images.Media.DISPLAY_NAME
        val addedCol = MediaStore.Images.Media.DATE_ADDED

        val projection =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                arrayOf(
                    idCol,
                    nameCol,
                    addedCol,
                    MediaStore.Images.Media.RELATIVE_PATH,
                    MediaStore.Images.Media.BUCKET_DISPLAY_NAME,
                )
            } else {
                @Suppress("DEPRECATION")
                arrayOf(idCol, nameCol, addedCol, MediaStore.Images.Media.DATA)
            }

        fun rowLooksLikeScreenshot(
            displayName: String?,
            relativePath: String?,
            dataPath: String?,
        ): Boolean {
            val dn = displayName ?: ""
            val rp = relativePath ?: ""
            val dp = dataPath ?: ""
            val blob = "${dn.lowercase()}|${rp.lowercase()}|${dp.lowercase()}"
            return blob.contains("screenshot") ||
                blob.contains("screen_shot") ||
                blob.contains("screencapture") ||
                blob.contains("capture") ||
                blob.contains("스크린") ||
                blob.contains("캡처") ||
                blob.contains("캡쳐")
        }

        fun pickFromCursor(
            cursor: android.database.Cursor,
            requireMatch: Boolean,
            maxRows: Int = 2048,
        ): String? {
            val iId = cursor.getColumnIndex(idCol)
            val iName = cursor.getColumnIndex(nameCol)
            val iRp = cursor.getColumnIndex(MediaStore.Images.Media.RELATIVE_PATH)
            val iBucket = cursor.getColumnIndex(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
            @Suppress("DEPRECATION")
            val iData = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
            var count = 0
            while (cursor.moveToNext() && count++ < maxRows) {
                val id = cursor.getLong(iId)
                val dn = if (iName >= 0) cursor.getString(iName) else null
                val rp = if (iRp >= 0) cursor.getString(iRp) else null
                val bucket = if (iBucket >= 0) cursor.getString(iBucket) else null
                val data = if (iData >= 0) cursor.getString(iData) else null
                if (requireMatch && !rowLooksLikeScreenshot(dn, rp ?: bucket, data)) continue
                val path = copyUriToTempFile(id, dn)
                if (path != null) return path
            }
            return null
        }

        try {
            // 1) Android Q+: 경로/앨범명이 스크린샷 폴더 패턴인 항목만
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val sel = (
                    "$addedCol >= ? AND (" +
                        "${MediaStore.Images.Media.RELATIVE_PATH} LIKE ? OR " +
                        "${MediaStore.Images.Media.RELATIVE_PATH} LIKE ? OR " +
                        "${MediaStore.Images.Media.BUCKET_DISPLAY_NAME} LIKE ? OR " +
                        "${MediaStore.Images.Media.BUCKET_DISPLAY_NAME} LIKE ? OR " +
                        "${MediaStore.Images.Media.DISPLAY_NAME} LIKE ? OR " +
                        "${MediaStore.Images.Media.DISPLAY_NAME} LIKE ?" +
                        ")"
                    )
                val args = arrayOf(
                    cutoff.toString(),
                    "%Screenshots%",
                    "%Screenshot%",
                    "%Screenshot%",
                    "%screenshot%",
                    "%Screenshot%",
                    "%screenshot%",
                )
                resolver.query(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    projection,
                    sel,
                    args,
                    "$addedCol DESC",
                )?.use { c ->
                    pickFromCursor(c, requireMatch = false)?.let { return it }
                }

                // 2) 최근 이미지 상위 N개에서 파일명/경로 힌트로 선별 (일부 제조사 대응)
                resolver.query(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    projection,
                    "$addedCol >= ?",
                    arrayOf(cutoff.toString()),
                    "$addedCol DESC",
                )?.use { c ->
                    pickFromCursor(c, requireMatch = true, maxRows = 50)?.let { return it }
                }
            } else {
                @Suppress("DEPRECATION")
                val dataCol = MediaStore.Images.Media.DATA
                val sel = "$addedCol >= ? AND ($dataCol LIKE ? OR $dataCol LIKE ? OR $nameCol LIKE ? OR $nameCol LIKE ?)"
                val args = arrayOf(
                    cutoff.toString(),
                    "%/Screenshots/%",
                    "%/screenshots/%",
                    "%Screenshot%",
                    "%screenshot%",
                )
                resolver.query(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    projection,
                    sel,
                    args,
                    "$addedCol DESC",
                )?.use { c ->
                    pickFromCursor(c, requireMatch = false)?.let { return it }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "queryLatestScreenshotToCache", e)
        }
        return null
    }

    private fun scheduleEmit() {
        emitRunnable?.let { handler.removeCallbacks(it) }
        emitRunnable = Runnable {
            emitRunnable = null
            try {
                channel?.invokeMethod("onChanged", null)
            } catch (e: Exception) {
                Log.e(TAG, "invokeMethod onChanged failed", e)
            }
        }
        handler.postDelayed(emitRunnable!!, 450L)
    }
}
