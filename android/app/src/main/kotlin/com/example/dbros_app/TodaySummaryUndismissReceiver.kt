package com.example.dbros_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 알림을 스와이프해 제거하면 deleteIntent 로 호출됩니다.
 * 예전에는 고정 알림을 위해 곧바로 다시 띄웠는데, 강제 종료 후에도 알림이 남고
 * 스와이프해도 바로 복구되어 “앱이 계속 켜져 있는 것 같다”는 느낌이 생겨
 * 여기서는 제거만 하고, 앱을 다시 열면 Dart 쪽 resume 에서 필요 시 다시 표시합니다.
 */
class TodaySummaryUndismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        TodaySummaryNotifier.cancel(context.applicationContext)
    }
}
