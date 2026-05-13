package com.example.dbros_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import java.util.Locale
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "dbros.app/today_summary"

        @Volatile
        private var screenshotNotifyChannel: MethodChannel? = null

        fun attachScreenshotNotifyChannel(channel: MethodChannel) {
            screenshotNotifyChannel = channel
        }

        fun detachScreenshotNotifyChannel() {
            screenshotNotifyChannel = null
        }

        /** [DbrosApplication] MediaStore 변경 시 호출 — 메인 엔진이 살아 있을 때만 Dart로 전달 */
        fun notifyScreenshotMediaStoreChanged() {
            val ch = screenshotNotifyChannel ?: return
            try {
                ch.invokeMethod(
                    "onScreenshotMediaStoreChanged",
                    emptyMap<String, Any>(),
                    object : MethodChannel.Result {
                        override fun success(result: Any?) {}
                        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
                        override fun notImplemented() {}
                    },
                )
            } catch (_: Throwable) {
            }
        }
    }

    private var summaryChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        summaryChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        attachScreenshotNotifyChannel(summaryChannel!!)
        summaryChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    val income = call.argument<Int>("income") ?: 0
                    val expense = call.argument<Int>("expense") ?: 0
                    val workDate = call.argument<String>("workDate") ?: ""
                    TodaySummaryNotifier.show(this, income, expense, workDate)
                    result.success(null)
                }
                "cancel" -> {
                    TodaySummaryNotifier.cancel(this)
                    result.success(null)
                }
                "getLatestScreenshot" -> {
                    result.success(getLatestScreenshotForOcr())
                }
                // 퀵등록 오버레이 표시 직후: 포그라운드였던 메인 앱을 백그라운드로 보내
                // 사용자가 보고 있던 다른 앱 화면 위에 오버레이만 남기기 위함.
                "moveTaskToBackAfterOverlay" -> {
                    Handler(Looper.getMainLooper()).post {
                        moveTaskToBack(true)
                    }
                    result.success(null)
                }
                "writeTextToPublicDownloads" -> {
                    val fileName = call.argument<String>("fileName")?.trim().orEmpty()
                    val content = call.argument<String>("content") ?: ""
                    if (fileName.isEmpty()) {
                        result.error("INVALID", "fileName is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val path = PublicDownloadsWriter.writeText(this, fileName, content)
                        result.success(path)
                    } catch (e: Exception) {
                        result.error("WRITE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        Handler(Looper.getMainLooper()).postDelayed({
            dispatchPendingNotificationClick(intent)
        }, 450)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun onDestroy() {
        detachScreenshotNotifyChannel()
        summaryChannel = null
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        dispatchPendingNotificationClick(intent)
    }

    private fun dispatchPendingNotificationClick(intent: Intent?) {
        val action = intent?.getStringExtra("notification_action") ?: return
        val ch = summaryChannel ?: return
        val args = mapOf("action" to action)
        ch.invokeMethod(
            "onNotificationAction",
            args,
            object : MethodChannel.Result {
                override fun success(r: Any?) {}
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}
                override fun notImplemented() {}
            }
        )
    }

    private fun looksLikeScreenshot(displayName: String?, relativePath: String?, bucket: String?): Boolean {
        val n = displayName?.lowercase(Locale.ROOT) ?: ""
        val r = relativePath?.lowercase(Locale.ROOT) ?: ""
        val b = bucket?.lowercase(Locale.ROOT) ?: ""
        return n.contains("screenshot") || n.contains("screencapture") || n.contains("screen_capture") ||
            n.contains("스크린샷") || n.contains("캡처") ||
            r.contains("screenshot") || r.contains("screencapture") || r.contains("스크린샷") ||
            b.contains("screenshot") || b.contains("스크린샷") || b.contains("capture")
    }

    /**
     * 제조사별 파일명·경로 차이 대응: 최근 이미지 일부를 가져온 뒤 휴리스틱으로 스크린샷만 고름.
     * (기존 SQL OR + RELATIVE_PATH는 API/기기에 따라 쿼리 실패·빈 결과가 나오기 쉬움.)
     */
    private fun getLatestScreenshotForOcr(): Map<String, Any>? {
        return try {
            val resolver = applicationContext.contentResolver
            val projection = buildList {
                add(MediaStore.Images.Media._ID)
                add(MediaStore.Images.Media.DISPLAY_NAME)
                add(MediaStore.Images.Media.DATE_ADDED)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    add(MediaStore.Images.Media.RELATIVE_PATH)
                }
                add(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
            }.toTypedArray()

            val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"

            resolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                sortOrder,
            )?.use { cursor ->
                val idIndex = cursor.getColumnIndex(MediaStore.Images.Media._ID)
                val dateIndex = cursor.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
                val nameIndex = cursor.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
                val relIndex = cursor.getColumnIndex(MediaStore.Images.Media.RELATIVE_PATH)
                val bucketIndex = cursor.getColumnIndex(MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
                if (idIndex < 0) return null

                var scanned = 0
                while (cursor.moveToNext() && scanned < 60) {
                    scanned++
                    val name = if (nameIndex >= 0) cursor.getString(nameIndex) else null
                    val rel = if (relIndex >= 0) cursor.getString(relIndex) else null
                    val bucket = if (bucketIndex >= 0) cursor.getString(bucketIndex) else null
                    if (!looksLikeScreenshot(name, rel, bucket)) continue

                    val imageId = cursor.getLong(idIndex)
                    val dateAdded = if (dateIndex >= 0) cursor.getLong(dateIndex) else 0L
                    val contentUri: Uri = Uri.withAppendedPath(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        imageId.toString(),
                    )

                    val file = File(cacheDir, "latest_screenshot_for_ocr.jpg")
                    resolver.openInputStream(contentUri)?.use { input ->
                        file.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    } ?: continue

                    return mapOf(
                        "path" to file.absolutePath,
                        "dateAdded" to dateAdded,
                        "imageId" to imageId,
                    )
                }
                null
            }
            null
        } catch (_: Throwable) {
            null
        }
    }
}
