package com.example.dbros_app

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
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
