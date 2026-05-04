package com.example.dbros_app

import android.app.Application
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore

/**
 * 갤러리/스크린샷 저장(MediaStore 이미지) 변경을 감지해 메인 Flutter 엔진으로 넘깁니다.
 * 자동 OCR은 주기 폴링 없이 이 이벤트(및 기능 켤 때 1회 확인)만 사용합니다.
 */
class DbrosApplication : Application() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val notifyRunnable = Runnable {
        MainActivity.notifyScreenshotMediaStoreChanged()
    }

    override fun onCreate() {
        super.onCreate()
        contentResolver.registerContentObserver(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            true,
            object : ContentObserver(mainHandler) {
                override fun onChange(selfChange: Boolean) {
                    onChange(selfChange, null)
                }

                override fun onChange(selfChange: Boolean, uri: Uri?) {
                    mainHandler.removeCallbacks(notifyRunnable)
                    mainHandler.postDelayed(notifyRunnable, 450L)
                }
            },
        )
    }
}
