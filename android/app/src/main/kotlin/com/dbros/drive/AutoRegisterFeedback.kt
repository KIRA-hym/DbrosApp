package com.dbros.drive

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.Gravity
import android.widget.Toast

/** 스크린샷 자동등록 완료: 화면 상단 Toast + 짧은 진동. */
object AutoRegisterFeedback {
    private const val TOAST_Y_OFFSET_DP = 28
    private const val VIBRATE_MS = 90L

    fun showComplete(context: Context, message: String) {
        val app = context.applicationContext
        vibrateShort(app)
        showTopToast(app, message)
    }

    private fun showTopToast(context: Context, message: String) {
        val density = context.resources.displayMetrics.density
        val statusBarId = context.resources.getIdentifier("status_bar_height", "dimen", "android")
        val statusBarPx = if (statusBarId > 0) {
            context.resources.getDimensionPixelSize(statusBarId)
        } else {
            (24 * density).toInt()
        }
        val yOffset = statusBarPx + (TOAST_Y_OFFSET_DP * density).toInt()

        val toast = Toast.makeText(context, message, Toast.LENGTH_LONG)
        toast.setGravity(Gravity.TOP or Gravity.CENTER_HORIZONTAL, 0, yOffset)
        toast.show()
    }

    private fun vibrateShort(context: Context) {
        val vibrator = getVibrator(context) ?: return
        if (!vibrator.hasVibrator()) return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(
                    VibrationEffect.createOneShot(
                        VIBRATE_MS,
                        VibrationEffect.DEFAULT_AMPLITUDE,
                    ),
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(VIBRATE_MS)
            }
        } catch (_: Exception) {
        }
    }

    private fun getVibrator(context: Context): Vibrator? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                manager?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
        } catch (_: Exception) {
            null
        }
    }
}
