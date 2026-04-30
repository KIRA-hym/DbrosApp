package com.example.dbros_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 오버레이(별도 Flutter 엔진) 등에서도 고정 알림을 갱신하기 위한 명시적 브로드캐스트.
 * MethodChannel은 메인 Activity 엔진에만 연결되는 경우가 있어 이 경로를 둡니다.
 */
class TodaySummaryRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ACTION) return
        val income = intent.getIntExtra(EXTRA_INCOME, 0)
        val expense = intent.getIntExtra(EXTRA_EXPENSE, 0)
        val workDate = intent.getStringExtra(EXTRA_WORK_DATE) ?: return
        TodaySummaryNotifier.show(context.applicationContext, income, expense, workDate)
    }

    companion object {
        const val ACTION = "com.example.dbros_app.REFRESH_TODAY_SUMMARY"
        const val EXTRA_INCOME = "income"
        const val EXTRA_EXPENSE = "expense"
        const val EXTRA_WORK_DATE = "workDate"
    }
}
