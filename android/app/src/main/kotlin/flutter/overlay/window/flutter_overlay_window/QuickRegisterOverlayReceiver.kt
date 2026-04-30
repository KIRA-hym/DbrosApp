package flutter.overlay.window.flutter_overlay_window

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import com.example.dbros_app.MainActivity
import com.example.dbros_app.TodaySummaryNotifier
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * 알림 퀵등록 액션을 앱 Activity를 전면 실행하지 않고 오버레이로 직접 띄우기 위한 리시버.
 */
class QuickRegisterOverlayReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        try {
            // 알림창이 열린 상태에서 퀵등록을 눌렀을 때 shade를 먼저 닫아
            // 오버레이가 바로 보이도록 합니다.
            context.sendBroadcast(Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS))

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) {
                // 권한이 없으면 기존 앱 화면으로 폴백
                val i = Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    putExtra("notification_action", "quick_register")
                }
                context.startActivity(i)
                return
            }

            // 오버레이 엔진 캐시 준비 (없으면 생성)
            if (FlutterEngineCache.getInstance().get(OverlayConstants.CACHED_TAG) == null) {
                val group = FlutterEngineGroup(context.applicationContext)
                val entryPoint = DartExecutor.DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    "overlayMain",
                )
                val engine: FlutterEngine = group.createAndRunEngine(context.applicationContext, entryPoint)
                FlutterEngineCache.getInstance().put(OverlayConstants.CACHED_TAG, engine)
            }

            // OverlayService 기본 설정 (패키지 동일로 WindowSetup 접근 가능)
            WindowSetup.width = -1
            WindowSetup.height = -1
            WindowSetup.enableDrag = false
            WindowSetup.setGravityFromAlignment("center")
            WindowSetup.setFlag("focusPointer")
            WindowSetup.overlayTitle = "Dbros Quick Register"
            WindowSetup.overlayContent = intent?.getStringExtra("workDate") ?: ""
            WindowSetup.setNotificationVisibility("visibilityPublic")

            // 퀵등록 중에는 오늘 요약 알림을 잠시 내려 중복(위아래 2개) 노출을 줄임.
            TodaySummaryNotifier.cancel(context)

            // 이전 오버레이 인스턴스가 남아있으면 먼저 정리 후 재기동
            context.stopService(Intent(context, OverlayService::class.java))
            val serviceIntent = Intent(context, OverlayService::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("startX", OverlayConstants.DEFAULT_XY)
                putExtra("startY", OverlayConstants.DEFAULT_XY)
            }
            context.startService(serviceIntent)
        } catch (_: Throwable) {
            val i = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra("notification_action", "quick_register")
            }
            context.startActivity(i)
        }
    }
}

