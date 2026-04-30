# ML Kit 관련 미사용 클래스 경고 무시
-dontwarn com.google.mlkit.vision.text.**
-keep class com.google.mlkit.vision.text.** { *; }

# Google Play services / Google Sign-In (R8 릴리스 빌드에서 sign_in_failed 방지)
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.auth.api.signin.** { *; }
-dontwarn com.google.android.gms.**