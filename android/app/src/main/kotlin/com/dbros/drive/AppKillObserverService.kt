package com.dbros.drive

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.app.NotificationManager

class AppKillObserverService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        try {
            // 앱이 스와이프 종료(Kill) 되었을 때, 투데이 요약 알림(퀵등록 포함) 및 기타 일반 알림을 모두 날림
            TodaySummaryNotifier.cancel(this)
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancelAll()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        stopSelf()
    }
}
