package com.example.dbros_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 오늘 요약(고정 알림) 스와이프 제거 시 deleteIntent.
 * 앱 프로세스가 살아 있고 마지막 요약 스냅샷이 있으면 즉시 다시 표시합니다.
 */
class TodaySummaryUndismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        TodaySummaryNotifier.reshowAfterDismiss(context.applicationContext)
    }
}
