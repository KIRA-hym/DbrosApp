package com.example.dbros_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationManagerCompat

/** 자동감지 FGS 알림 스와이프 제거 시, 앱·서비스가 살아 있으면 즉시 다시 표시. */
class GalleryObserverNotificationRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val app = context.applicationContext
        if (!GalleryObserverActiveStore.isActive(app)) return
        if (!NotificationManagerCompat.from(app).areNotificationsEnabled()) return

        val running = GalleryObserverService.runningInstance
        if (running != null) {
            running.restoreForegroundNotification()
            return
        }

        val svc = Intent(app, GalleryObserverService::class.java).apply {
            action = GalleryObserverService.ACTION_RESTORE_FOREGROUND
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                app.startForegroundService(svc)
            } else {
                app.startService(svc)
            }
        } catch (_: Exception) {
        }
    }
}
