package com.example.dbros_app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "dbros.app/today_summary"
    }

    private var summaryChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        summaryChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
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

    private fun getLatestScreenshotForOcr(): Map<String, Any>? {
        return try {
            val resolver = applicationContext.contentResolver
            val projection = arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.DATE_ADDED
            )
            val selection = "${MediaStore.Images.Media.DISPLAY_NAME} LIKE ? OR " +
                    "${MediaStore.Images.Media.DISPLAY_NAME} LIKE ? OR " +
                    "${MediaStore.Images.Media.DISPLAY_NAME} LIKE ? OR " +
                    "${MediaStore.Images.Media.RELATIVE_PATH} LIKE ?"
            val selectionArgs = arrayOf("%Screenshot%", "%ScreenCapture%", "%스크린샷%", "%Screenshots%")
            val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"

            resolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return null
                val idIndex = cursor.getColumnIndex(MediaStore.Images.Media._ID)
                val dateIndex = cursor.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
                if (idIndex < 0) return null
                val imageId = cursor.getLong(idIndex)
                val dateAdded = if (dateIndex >= 0) cursor.getLong(dateIndex) else 0L
                val contentUri: Uri = Uri.withAppendedPath(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    imageId.toString()
                )

                val file = File(cacheDir, "latest_screenshot_for_ocr.jpg")
                resolver.openInputStream(contentUri)?.use { input ->
                    file.outputStream().use { output ->
                        input.copyTo(output)
                    }
                } ?: return null

                return mapOf(
                    "path" to file.absolutePath,
                    "dateAdded" to dateAdded,
                    "imageId" to imageId
                )
            }
            null
        } catch (_: Throwable) {
            null
        }
    }
}
