package com.dbros.drive

import android.content.Context

/** Flutter [GalleryMediaBridge] start/stop 과 동기화 — 제거 후 즉시 복구 여부 판단. */
object GalleryObserverActiveStore {
    private const val PREFS = "dbros_gallery_observer"
    private const val KEY_ACTIVE = "observer_active"

    fun setActive(context: Context, active: Boolean) {
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ACTIVE, active)
            .apply()
    }

    fun isActive(context: Context): Boolean {
        return context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ACTIVE, false)
    }
}
