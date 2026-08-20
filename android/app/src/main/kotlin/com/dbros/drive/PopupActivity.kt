package com.dbros.drive

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs

class PopupActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName(): String {
        return "popupMain"
    }

    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode {
        return FlutterActivityLaunchConfigs.BackgroundMode.transparent
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        // 팝업이 이미 떠있는 상태에서 오버레이 버튼이 한 번 더 클릭되면 닫힘 (토글)
        finish()
    }
}
