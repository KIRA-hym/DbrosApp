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

/** 오늘 요약 알림 — 접힌: 근무일자/순익 2줄, 펼침: 동일 2줄 + 수입·지출 + 퀵등록. */
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
        val line1 = formatWorkDateLine(workDate)
        compact.setTextViewText(R.id.notification_compact_line1, line1)
        compact.setTextViewText(R.id.notification_compact_line2, formatNetLine(income, expense))
        val expanded = RemoteViews(pkg, R.layout.notification_today_expanded)
        val line2 = formatNetLine(income, expense)
        expanded.setTextViewText(R.id.notification_expanded_line1, line1)
        expanded.setTextViewText(R.id.notification_expanded_line2, line2)
        expanded.setTextViewText(R.id.notification_expanded_income, formatIncomeLine(income))
        expanded.setTextViewText(R.id.notification_expanded_expense, formatExpenseLine(expense))

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

        compact.setOnClickPendingIntent(R.id.notification_compact_line1, piFull)
        compact.setOnClickPendingIntent(R.id.notification_compact_line2, piFull)
        compact.setOnClickPendingIntent(R.id.notification_quick, piQuick)
        expanded.setOnClickPendingIntent(R.id.notification_expanded_line1, piFull)
        expanded.setOnClickPendingIntent(R.id.notification_expanded_line2, piFull)
        expanded.setOnClickPendingIntent(R.id.notification_expanded_income, piFull)
        expanded.setOnClickPendingIntent(R.id.notification_expanded_expense, piFull)
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

    /** 접힌·펼침 1줄 공통: 근무일자 라벨 + 날짜 */
    private fun formatWorkDateLine(workDate: String): String = "근무일자 : $workDate"

    /** 접힌 2줄·펼침 2줄 공통: 순익만 */
    private fun formatNetLine(income: Int, expense: Int): String {
        val df = DecimalFormat("#,###")
        val net = income - expense
        return "💰순익 ${df.format(net)}원"
    }

    /** 펼침 1행 본문: 수입 */
    private fun formatIncomeLine(income: Int): String {
        val df = DecimalFormat("#,###")
        return "수입 ${df.format(income)}원"
    }

    /** 펼침 2행: 지출 */
    private fun formatExpenseLine(expense: Int): String {
        val df = DecimalFormat("#,###")
        return "지출 ${df.format(expense)}원"
    }
}
