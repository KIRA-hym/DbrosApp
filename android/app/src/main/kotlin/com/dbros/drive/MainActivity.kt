package com.dbros.drive

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "dbros.app/today_summary"
        var isAppRunning = false
    }

    private var summaryChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GalleryMediaBridge.register(flutterEngine, this)
        summaryChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        summaryChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    val income = call.argument<Int>("income") ?: 0
                    val expense = call.argument<Int>("expense") ?: 0
                    val workDate = call.argument<String>("workDate") ?: ""
                    val elapsedSeconds = call.argument<Int>("elapsedSeconds") ?: 0
                    val isClockedIn = call.argument<Boolean>("isClockedIn") ?: false
                    TodaySummaryNotifier.show(this, income, expense, workDate, elapsedSeconds, isClockedIn)
                    result.success(null)
                }
                "cancel" -> {
                    TodaySummaryNotifier.cancel(this)
                    result.success(null)
                }
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
                "writeBytesToPublicDownloads" -> {
                    val fileName = call.argument<String>("fileName")?.trim().orEmpty()
                    val content = call.argument<ByteArray>("content")
                    val mimeType = call.argument<String>("mimeType")?.trim() ?: "application/octet-stream"
                    if (fileName.isEmpty() || content == null) {
                        result.error("INVALID", "fileName and content are required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val path = PublicDownloadsWriter.writeBytes(this, fileName, content, mimeType)
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
        // Android 15 Edge-to-Edge 수동 호환성 처리 (플러터 하위 호환)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        
        isAppRunning = true
        try {
            startService(Intent(this, AppKillObserverService::class.java))
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        isAppRunning = false
        GalleryMediaBridge.dispose()
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
            },
        )
    }
}
