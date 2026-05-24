package com.example.dbros_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class GalleryObserverService : Service() {
    companion object {
        private const val CHANNEL_ID = "dbros_gallery_observer_channel"
        private const val NOTIFICATION_ID = 94005
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createNotificationChannel()
        
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.app_notification_icon)
            .setContentTitle("자동감지 실행중")
            .setPriority(NotificationCompat.PRIORITY_MIN) // 최소 중요도 (알림창 맨 아래 숨김)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 14+ requires foregroundServiceType in startForeground
            startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "스크린샷 자동저장",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "스크린샷을 감지하기 위해 백그라운드에서 대기합니다."
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }
}
