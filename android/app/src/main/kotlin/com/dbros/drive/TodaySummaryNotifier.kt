package com.dbros.drive

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.text.DecimalFormat
import java.util.concurrent.atomic.AtomicReference

/** 오늘 요약 알림 — 접힌: 근무일자/순익 2줄, 펼침: 동일 2줄 + 수입·지출 한 줄 + 퀵등록. */
object TodaySummaryNotifier {

    // v3: 오늘 요약을 자동감지 FGS보다 알림창 상단에 두기 위해 중요도·sortKey 상향
    private const val CHANNEL_ID = "dbros_today_summary_v3"
    private const val CHANNEL_NAME = "오늘 요약"
    private const val SORT_KEY = "0_today_summary"
    private const val NOTIFICATION_ID = 94001
    private const val RC_SUMMARY_BODY = 94002
    private const val RC_QUICK = 94003
    private const val RC_UNDISMISS = 94004

    private val lastSnapshot = AtomicReference<Snapshot?>(null)

    data class Snapshot(
        val income: Int,
        val expense: Int,
        val workDate: String,
        val elapsedSeconds: Int,
        val isClockedIn: Boolean
    )

    fun show(
        context: Context,
        income: Int,
        expense: Int,
        workDate: String,
        elapsedSeconds: Int,
        isClockedIn: Boolean
    ) {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            return
        }
        ensureChannel(context)
        lastSnapshot.set(Snapshot(income, expense, workDate, elapsedSeconds, isClockedIn))

        val pkg = context.packageName
        val compact = RemoteViews(pkg, R.layout.notification_today_one_row)
        val expanded = RemoteViews(pkg, R.layout.notification_today_expanded)

        val line1 = formatLine1(workDate, income, expense)
        compact.setTextViewText(R.id.notification_compact_line1, line1)
        expanded.setTextViewText(R.id.notification_expanded_line1, line1)

        if (isClockedIn) {
            val baseTime = android.os.SystemClock.elapsedRealtime() - (elapsedSeconds * 1000L)
            compact.setChronometer(R.id.notification_chronometer, baseTime, "%s", true)
            expanded.setChronometer(R.id.notification_expanded_chronometer, baseTime, "%s", true)
            compact.setViewVisibility(R.id.notification_chronometer, android.view.View.VISIBLE)
            expanded.setViewVisibility(R.id.notification_expanded_chronometer, android.view.View.VISIBLE)
        } else {
            compact.setChronometer(R.id.notification_chronometer, 0L, "-", false)
            expanded.setChronometer(R.id.notification_expanded_chronometer, 0L, "-", false)
            // Or just leave it stopped with 00:00 format, or show "-" by setting text on a standard TextView instead.
            // setChronometer with format "-" is supported, but to be safe we can just stop it.
            // Since we set format to "%s" above, we just stop it and it might show 00:00.
            // Actually, we can just hide chronometer and show text "-" in the Line2 text if we wanted, but Chronometer format "-" works.
        }

        expanded.setTextViewText(
            R.id.notification_expanded_income_expense,
            formatIncomeExpenseOneLine(income, expense)
        )

        val intentFlags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP

        val intentFull = Intent(context, MainActivity::class.java).apply {
            flags = intentFlags
            putExtra("notification_action", "open_home")
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
        compact.setOnClickPendingIntent(R.id.notification_compact_line2_text, piFull)
        compact.setOnClickPendingIntent(R.id.notification_chronometer, piFull)
        compact.setOnClickPendingIntent(R.id.notification_quick, piQuick)
        expanded.setOnClickPendingIntent(R.id.notification_expanded_line1, piFull)
        expanded.setOnClickPendingIntent(R.id.notification_expanded_line2_text, piFull)
        expanded.setOnClickPendingIntent(R.id.notification_expanded_chronometer, piFull)
        expanded.setOnClickPendingIntent(R.id.notification_expanded_income_expense, piFull)
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
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setSortKey(SORT_KEY)
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

    /** 스와이프 제거 직후 — 마지막 요약이 있고 앱이 살아 있으면 즉시 다시 표시. */
    fun reshowAfterDismiss(context: Context) {
        val snap = lastSnapshot.get() ?: return
        show(context, snap.income, snap.expense, snap.workDate, snap.elapsedSeconds, snap.isClockedIn)
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "오늘 수입·지출 합계 (일지 등록·수정 시 갱신). 알림창 상단에 표시됩니다."
                setShowBadge(true)
                enableVibration(false)
                enableLights(false)
                setSound(null, null)
            }
            val nm = context.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(ch)
        }
    }

    private fun formatLine1(workDate: String, income: Int, expense: Int): String {
        val df = DecimalFormat("#,###")
        val net = income - expense
        return "근무일자 : $workDate  |  💰순익 ${df.format(net)}원"
    }

    /** 펼침 하단 한 줄: 수입 · 지출 */
    private fun formatIncomeExpenseOneLine(income: Int, expense: Int): String {
        val df = DecimalFormat("#,###")
        return "수입 ${df.format(income)}원 · 지출 ${df.format(expense)}원"
    }
}
