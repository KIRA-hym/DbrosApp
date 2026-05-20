package com.example.dbros_app

import android.content.Context
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
