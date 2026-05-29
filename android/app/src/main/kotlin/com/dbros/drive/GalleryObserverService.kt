package com.dbros.drive

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class GalleryObserverService : Service() {
    companion object {
        const val ACTION_RESTORE_FOREGROUND = "com.dbros.drive.RESTORE_GALLERY_FG"

        /** v2: IMPORTANCE_MIN — 오늘 요약 알림보다 아래에 두기 위함 */
        private const val CHANNEL_ID = "dbros_gallery_observer_channel_v2"
        private const val NOTIFICATION_ID = 94005
        private const val SORT_KEY = "9_gallery_observer"
        private const val RC_DELETE = 94006

        @Volatile
        var runningInstance: GalleryObserverService? = null
            private set
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        runningInstance = this
    }

    override fun onDestroy() {
        runningInstance = null
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        try {
            // 포그라운드 서비스 알림 제거 및 서비스 종료
            stopForeground(true)
            stopSelf()
            
            // 등록된 모든 알림(투데이 요약, 퀵등록 등) 싹 제거
            NotificationManagerCompat.from(this).cancelAll()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            createNotificationChannel()
            restoreForegroundNotification()

            if (!GalleryObserverActiveStore.isActive(this) || 
                !NotificationManagerCompat.from(this).areNotificationsEnabled()) {
                stopForeground(true)
                stopSelf()
                return START_NOT_STICKY
            }

            restoreForegroundNotification()
            
            // "자동감지 실행중" 알림이 뒤늦게 떠서 기존 퀵등록 알림을 밀어내는 현상 방지:
            // 알림을 띄운 직후 투데이 요약을 갱신하여 최상단으로 끌어올림
            TodaySummaryNotifier.reshowAfterDismiss(this)
            
            return START_STICKY
        } catch (e: Exception) {
            e.printStackTrace()
            stopSelf()
            return START_NOT_STICKY
        }
    }

    fun restoreForegroundNotification() {
        val notification = buildForegroundNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildForegroundNotification(): Notification {
        val restoreIntent = Intent(this, GalleryObserverNotificationRestoreReceiver::class.java)
        val deletePi = PendingIntent.getBroadcast(
            this,
            RC_DELETE,
            restoreIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.app_notification_icon)
            .setContentTitle("자동감지 실행중")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setSortKey(SORT_KEY)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setSilent(true)
            .setDeleteIntent(deletePi)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "스크린샷 자동저장",
                NotificationManager.IMPORTANCE_MIN,
            ).apply {
                description = "백그라운드 감지용(알림창 하단). 제거 시 앱이 살아 있으면 즉시 복구합니다."
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }
}
