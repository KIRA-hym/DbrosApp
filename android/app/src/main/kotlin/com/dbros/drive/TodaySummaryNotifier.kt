package com.dbros.drive

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.TypedValue
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.text.DecimalFormat
import java.util.concurrent.atomic.AtomicReference

/**
 * 오늘 요약 고정 알림:
 * - 좌측: 2단 부스트 상승 아이콘 + 10만 단위 고정폭(우측 정렬) 순익 + 원
 * - 우측: 근무일자 + 근무시간(초 단위 제거, HH:mm 분 단위 자동 갱신)
 * - 텍스트 크기는 dp 단위(values/sw360dp/sw390dp)로 고정하여 시스템 글꼴 확대(1.5x+) 시에도 깨지지 않음.
 */
object TodaySummaryNotifier {

    // v4: 오늘 요약을 무조건 최상단에 고정하기 위해 채널 분리 및 Importance 상향 (v3 -> v4)
    private const val CHANNEL_ID = "dbros_today_summary_v4"
    private const val CHANNEL_NAME = "오늘 요약"
    private const val SORT_KEY = "0_today_summary"
    private const val NOTIFICATION_ID = 94001
    private const val RC_SUMMARY_BODY = 94002
    private const val RC_QUICK = 94003
    private const val RC_UNDISMISS = 94004

    private val lastSnapshot = AtomicReference<Snapshot?>(null)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var minuteTickRunnable: Runnable? = null

    data class Snapshot(
        val income: Int,
        val expense: Int,
        val workDate: String,
        val elapsedSeconds: Int,
        val isClockedIn: Boolean,
        val recordedAtElapsedRealtimeMs: Long = SystemClock.elapsedRealtime()
    ) {
        fun currentElapsedSeconds(): Int {
            if (!isClockedIn) return 0
            val deltaSec = ((SystemClock.elapsedRealtime() - recordedAtElapsedRealtimeMs) / 1000L).toInt()
            return maxOf(0, elapsedSeconds + maxOf(0, deltaSec))
        }
    }

    fun show(
        context: Context,
        income: Int,
        expense: Int,
        workDate: String,
        elapsedSeconds: Int,
        isClockedIn: Boolean
    ) {
        val appContext = context.applicationContext
        if (!NotificationManagerCompat.from(appContext).areNotificationsEnabled()) {
            cancelMinuteTick()
            return
        }
        ensureChannel(appContext)
        val snap = Snapshot(
            income = income,
            expense = expense,
            workDate = workDate,
            elapsedSeconds = maxOf(0, elapsedSeconds),
            isClockedIn = isClockedIn,
            recordedAtElapsedRealtimeMs = SystemClock.elapsedRealtime()
        )
        lastSnapshot.set(snap)
        renderSnapshot(appContext, snap)
        scheduleNextMinuteTickIfNeeded(appContext, snap)
    }

    private fun renderSnapshot(context: Context, snap: Snapshot) {
        val pkg = context.packageName
        val compact = RemoteViews(pkg, R.layout.notification_today_one_row)
        val expanded = RemoteViews(pkg, R.layout.notification_today_expanded)

        val line1 = formatLine1(snap.workDate)
        compact.setTextViewText(R.id.notification_compact_line1, line1)
        expanded.setTextViewText(R.id.notification_expanded_line1, line1)

        val netValueStr = formatNetValue(snap.income, snap.expense)
        compact.setTextViewText(R.id.notification_compact_line2_net, netValueStr)
        expanded.setTextViewText(R.id.notification_expanded_line2_net, netValueStr)

        // 단말기 해상도(dp) 기준 고정 텍스트 크기 적용 (시스템 글꼴 확대 영향 차단 + 7자리 이상 예외 자동 축소)
        val density = context.resources.displayMetrics.density.coerceAtLeast(1f)
        val baseNetDp = context.resources.getDimension(R.dimen.notif_net_text_size) / density
        val baseUnitDp = context.resources.getDimension(R.dimen.notif_unit_text_size) / density
        val baseMetaDp = context.resources.getDimension(R.dimen.notif_meta_text_size) / density
        val adjustedNetDp = when {
            netValueStr.length >= 9 -> (baseNetDp - 4f).coerceAtLeast(15f)
            netValueStr.length >= 8 -> (baseNetDp - 2.5f).coerceAtLeast(16.5f)
            else -> baseNetDp
        }

        compact.setTextViewTextSize(R.id.notification_compact_line2_net, TypedValue.COMPLEX_UNIT_DIP, adjustedNetDp)
        expanded.setTextViewTextSize(R.id.notification_expanded_line2_net, TypedValue.COMPLEX_UNIT_DIP, adjustedNetDp)
        compact.setTextViewTextSize(R.id.notification_compact_net_unit, TypedValue.COMPLEX_UNIT_DIP, baseUnitDp)
        expanded.setTextViewTextSize(R.id.notification_expanded_net_unit, TypedValue.COMPLEX_UNIT_DIP, baseUnitDp)
        compact.setTextViewTextSize(R.id.notification_compact_line1, TypedValue.COMPLEX_UNIT_DIP, baseMetaDp)
        expanded.setTextViewTextSize(R.id.notification_expanded_line1, TypedValue.COMPLEX_UNIT_DIP, baseMetaDp)
        compact.setTextViewTextSize(R.id.notification_compact_line2_text, TypedValue.COMPLEX_UNIT_DIP, baseMetaDp)
        expanded.setTextViewTextSize(R.id.notification_expanded_line2_text, TypedValue.COMPLEX_UNIT_DIP, baseMetaDp)

        val timeText = if (snap.isClockedIn) {
            formatWorkDurationHm(snap.currentElapsedSeconds())
        } else {
            "⏰ 출근 전"
        }
        compact.setTextViewText(R.id.notification_compact_line2_text, timeText)
        expanded.setTextViewText(R.id.notification_expanded_line2_text, timeText)

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

        compact.setOnClickPendingIntent(R.id.notification_compact_root, piFull)
        compact.setOnClickPendingIntent(R.id.notification_compact_icon, piFull)
        compact.setOnClickPendingIntent(R.id.notification_compact_line2_net, piFull)
        compact.setOnClickPendingIntent(R.id.notification_compact_net_unit, piFull)
        compact.setOnClickPendingIntent(R.id.notification_compact_line1, piFull)
        compact.setOnClickPendingIntent(R.id.notification_compact_line2_text, piFull)
        compact.setOnClickPendingIntent(R.id.notification_quick, piQuick)

        expanded.setOnClickPendingIntent(R.id.notification_expanded_root, piFull)
        expanded.setOnClickPendingIntent(R.id.notification_expanded_icon, piFull)
        expanded.setOnClickPendingIntent(R.id.notification_expanded_line2_net, piFull)
        expanded.setOnClickPendingIntent(R.id.notification_expanded_net_unit, piFull)
        expanded.setOnClickPendingIntent(R.id.notification_expanded_line1, piFull)
        expanded.setOnClickPendingIntent(R.id.notification_expanded_line2_text, piFull)
        expanded.setOnClickPendingIntent(R.id.notification_quick_expanded, piQuick)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.app_notification_icon)
            .setContentTitle("")
            .setContentText("")
            .setWhen(0)
            .setShowWhen(false)
            // ongoing + FLAG_NO_CLEAR 는 앱 강제 종료 후에도 알림이 남는 원인이 됨 (삭제 불가에 가깝게 유지)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setSortKey(SORT_KEY)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setColorized(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(piFull)
            .setDeleteIntent(piUndismiss)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(compact)
            .setCustomBigContentView(expanded)

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, builder.build())
    }

    private fun scheduleNextMinuteTickIfNeeded(context: Context, snap: Snapshot) {
        cancelMinuteTick()
        if (!snap.isClockedIn) return

        val currentSec = snap.currentElapsedSeconds()
        val secondsUntilNextMinute = 60 - (currentSec % 60)
        val delayMs = (secondsUntilNextMinute * 1000L).coerceAtLeast(1000L)

        val runnable = Runnable {
            val latest = lastSnapshot.get() ?: return@Runnable
            if (!latest.isClockedIn) return@Runnable
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return@Runnable
            renderSnapshot(context, latest)
            scheduleNextMinuteTickIfNeeded(context, latest)
        }
        minuteTickRunnable = runnable
        mainHandler.postDelayed(runnable, delayMs)
    }

    private fun cancelMinuteTick() {
        minuteTickRunnable?.let { mainHandler.removeCallbacks(it) }
        minuteTickRunnable = null
    }

    fun cancel(context: Context) {
        cancelMinuteTick()
        lastSnapshot.set(null)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(NOTIFICATION_ID)
    }

    /** 스와이프 제거 직후 — 마지막 요약이 있고 앱이 살아 있으면 즉시 다시 표시. */
    fun reshowAfterDismiss(context: Context) {
        val snap = lastSnapshot.get() ?: return
        val appContext = context.applicationContext
        renderSnapshot(appContext, snap)
        scheduleNextMinuteTickIfNeeded(appContext, snap)
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "dbros app today summary"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            val nm = context.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun formatLine1(workDate: String): String {
        return "📅 $workDate"
    }

    private fun formatNetValue(income: Int, expense: Int): String {
        val df = DecimalFormat("#,###")
        val net = income - expense
        return df.format(net)
    }

    private fun formatWorkDurationHm(elapsedSeconds: Int): String {
        val totalMinutes = maxOf(0, elapsedSeconds / 60)
        val hours = totalMinutes / 60
        val minutes = totalMinutes % 60
        return String.format("⏰ %02d:%02d", hours, minutes)
    }
}
