package com.example.dbros_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import java.text.DecimalFormat
import java.util.concurrent.atomic.AtomicReference

/** 오늘 요약 알림 — RemoteViews 한 줄 레이아웃 (플러그인 표준 액션은 줄이 늘어남). */
object TodaySummaryNotifier {

    // v2: 무음/무진동 채널로 분리 (기존 채널 중요도/진동 설정은 OS가 고정 보관)
    private const val CHANNEL_ID = "dbros_today_summary_silent_v2"
    private const val CHANNEL_NAME = "오늘 요약"
    private const val NOTIFICATION_ID = 94001
    private const val RC_SUMMARY_BODY = 94002
    private const val RC_QUICK = 94003
    private const val RC_UNDISMISS = 94004

    private val lastSnapshot = AtomicReference<Triple<Int, Int, String>?>(null)

    fun show(context: Context, income: Int, expense: Int, workDate: String) {
        ensureChannel(context)
        lastSnapshot.set(Triple(income, expense, workDate))

        val pkg = context.packageName
        val compact = RemoteViews(pkg, R.layout.notification_today_one_row)
        compact.setTextViewText(R.id.notification_summary, formatCompactLine(income, expense, workDate))
        val expanded = RemoteViews(pkg, R.layout.notification_today_expanded)
        expanded.setTextViewText(R.id.notification_summary_expanded, formatNetLine(income, expense))
        expanded.setTextViewText(R.id.notification_work_date, formatIncomeExpenseLine(income, expense))

        val intentFlags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP

        val intentFull = Intent(context, MainActivity::class.java).apply {
            flags = intentFlags
            putExtra("notification_action", "open_full_write")
        }
        val intentQuick = Intent(context, MainActivity::class.java).apply {
            flags = intentFlags
            putExtra("notification_action", "quick_register")
        }

        val piFull = PendingIntent.getActivity(
            context,
            RC_SUMMARY_BODY,
            intentFull,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val piQuick = PendingIntent.getActivity(
            context,
            RC_QUICK,
            intentQuick,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val undismissIntent = Intent(context, TodaySummaryUndismissReceiver::class.java)
        val piUndismiss = PendingIntent.getBroadcast(
            context,
            RC_UNDISMISS,
            undismissIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        compact.setOnClickPendingIntent(R.id.notification_summary, piFull)
        compact.setOnClickPendingIntent(R.id.notification_quick, piQuick)
        expanded.setOnClickPendingIntent(R.id.notification_summary_expanded, piFull)
        expanded.setOnClickPendingIntent(R.id.notification_quick_expanded, piQuick)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.app_notification_icon)
            .setContentTitle("")
            .setContentText("")
            .setShowWhen(false)
            .setWhen(0L)
            // ongoing + FLAG_NO_CLEAR 는 앱 강제 종료 후에도 알림이 남는 원인이 됨 (삭제 불가에 가깝게 유지)
            .setOngoing(false)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(piFull)
            .setDeleteIntent(piUndismiss)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(compact)
            .setCustomBigContentView(expanded)

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val built = builder.build()
        // Notification.FLAG_NO_CLEAR 는 시스템/설정에서 앱 종료 시 알림 정리를 막을 수 있음 — 설정하지 않음
        nm.notify(NOTIFICATION_ID, built)
    }

    fun cancel(context: Context) {
        lastSnapshot.set(null)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(NOTIFICATION_ID)
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "오늘 수입·지출 합계 (일지 등록·수정 시 갱신)"
                setShowBadge(true)
                enableVibration(false)
                enableLights(false)
                setSound(null, null)
            }
            val nm = context.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(ch)
        }
    }

    private fun formatCompactLine(income: Int, expense: Int, workDate: String): String {
        val df = DecimalFormat("#,###")
        val net = income - expense
        return "$workDate · 💰순익 ${df.format(net)}원"
    }

    private fun formatNetLine(income: Int, expense: Int): String {
        val df = DecimalFormat("#,###")
        val net = income - expense
        return "💰순익 ${df.format(net)}원"
    }

    private fun formatIncomeExpenseLine(income: Int, expense: Int): String {
        val df = DecimalFormat("#,###")
        return "수입 ${df.format(income)}원 · 지출 ${df.format(expense)}원"
    }
}
