# Google Play 스토어 배포 가이드 (Dbros / 운행일지관리)

이 문서는 **현재 레포(`dbros_app`) 기준**으로 Play Store 정식 배포 전에 필요한 작업을 정리한 것입니다.  
에이전트·개발자는 Play/배포 관련 질문 시 **이 파일을 먼저 참고**합니다.

**최종 갱신:** 2026-05-19  
**관련 규칙:** `.cursor/rules/play-store-deploy.mdc`

---

## 1. 결론 요약

| 항목 | 현재 상태 | Play 배포 전 |
|------|-----------|--------------|
| 앱 코드 | Flutter (Dart) | **언어 변환 불필요** |
| Application ID | `com.example.dbros_app` | **반드시 정식 ID로 변경** |
| 배포 산출물 | APK 듀얼 빌드 (`tools/build_dual_apk.ps1`) | **AAB(App Bundle)** 권장 |
| 서명 | `android/key.properties` + `keys/dbros-release.jks` | Play App Signing 등록 |
| 스토어 자료 | 미비 | 스크린샷·설명·개인정보처리방침 등 |

---

## 2. Play Console·계정

1. [Google Play Console](https://play.google.com/console) 개발자 등록 (1회 약 $25).
2. 개발자 계정 유형(개인/조직) 결정.
3. 앱 생성 → 스토어 등록 정보(한국어 필수).
4. 유료/인앱 시 결제·세금 프로필 설정.

---

## 3. Application ID 변경 (최우선)

Play에서는 **`com.example.*` 패키지를 실서비스에 사용하면 안 됩니다.**  
스토어에 등록한 뒤 Application ID는 **변경 불가**입니다.

### 수정이 필요한 위치 (체크리스트)

- [ ] `android/app/build.gradle.kts` — `applicationId`, `namespace`
- [ ] `android/app/src/main/kotlin/com/example/dbros_app/` — 패키지 경로·폴더명
- [ ] `AndroidManifest.xml` — 브로드캐스트 action (`com.example.dbros_app.*`)
- [ ] `lib/services/today_stats_notification_service.dart` — `_applicationId`
- [ ] Google Cloud Console — Maps API 키 Android 제한(새 패키지명 + SHA-1)

**권장 형식:** 역도메인 (예: `kr.co.dbros.ilji`, `com.dbros.drivelog`)

### 앱 이름·아이콘

- Manifest: `android:label="운행일지관리"`
- Play 스토어 아이콘: **512×512 PNG** (런처 아이콘과 별도 업로드 가능)

---

## 4. 빌드·서명

### 4.1 이미 갖춘 것

- Release 서명: `android/key.properties` (예시: `android/key.properties.example`)
- Keystore: `keys/dbros-release.jks`
- R8/ProGuard: `build.gradle.kts` `isMinifyEnabled`, `proguard-rules.pro`
- 버전: `pubspec.yaml` — 화면 `v{version}.{build 2자리}` (예: `1.0.03+1` → v1.0.03.01)
- `versionCode`: Gradle `monotonicVersionCode()` (이름+빌드 단조 증가)

### 4.2 Play 업로드: AAB

```powershell
cd <repo-root>
dart run tool/validate_notification_icon.dart
flutter build appbundle --release --dart-define=MAP_FEATURES_ENABLED=false
```

산출물: `build/app/outputs/bundle/release/app-release.aab`

### 4.3 Play App Signing

- 첫 업로드 시 **업로드 키** 등록 (`dbros-release.jks`).
- **앱 서명 키**는 Google 관리 권장.
- JKS·비밀번호 **백업 필수** (분실 시 업데이트 불가).

### 4.4 versionCode

매 업로드마다 이전보다 커야 함. 현재 공식:

`major×100000 + minor×1000 + patch×100 + build`

---

## 5. owner / public 2종 빌드 전략

| 빌드 | dart-define | 용도 |
|------|-------------|------|
| owner | `MAP_FEATURES_ENABLED=true` | 지도 + 개인지출 |
| public | `MAP_FEATURES_ENABLED=false` | 지도·개인지출 비활성 |

Play **한 앱 등록 = 하나의 applicationId**.

| 전략 | 설명 |
|------|------|
| **A (권장)** | 스토어는 **public AAB만**. owner는 사이드로드·내부 배포. |
| **B** | Gradle `productFlavors` — 동일 패키지, 내부 트랙에 owner / 프로덕션에 public. |
| **C (비권장)** | applicationId 2개로 앱 2개 등록. |

로컬 듀얼 APK: `tools/build_dual_apk.ps1` (배포용은 커밋·푸시 후 실행 — `git-commit.mdc` 참고).

---

## 6. 권한·심사 (이 앱)

`android/app/src/main/AndroidManifest.xml` 기준:

| 권한/기능 | 용도 | Play 대응 |
|-----------|------|-----------|
| 위치 | 지도·위치 (owner) | Data safety, 사용 목적. public만 올릴 때 manifest 권한 분리 검토. |
| 카메라·사진 | OCR·첨부 | Data safety |
| POST_NOTIFICATIONS | 오늘 요약 알림 | 런타임 권한·채널 설명 |
| SYSTEM_ALERT_WINDOW | 퀵등록 오버레이 | 민감 권한, 상세 justification, 동영상 요청 가능 |
| FGS specialUse | 오버레이 서비스 | Android 14+ FGS 유형·special use 선언 |
| INTERNET | Maps, YouTube, 웹훅 등 | Data safety |

### Google Maps

- API 키: 새 `applicationId` + Play App Signing **SHA-1** 로 Android 앱 제한.
- `local.properties` / `secret.properties`의 `MAPS_API_KEY`.

### 알림 아이콘

- PNG: `drawable-*/app_notification_icon.png`
- 생성: `tools/generate_notification_icon.ps1`
- 빌드 전 검증: `dart run tool/validate_notification_icon.dart`

---

## 7. 정책·법무

### 7.1 개인정보처리방침 (URL 필수)

포함 권장:

- 운행 일지 데이터(주소·요금·시간), 사진, 위치(사용 시)
- **로컬 DB(sqflite)** vs **외부 전송**(GAS 웹훅, YouTube RSS, Maps 등)
- 보관·삭제
- 제3자(Google Maps, ML Kit OCR 등)

### 7.2 Data safety (Play Console)

- 수집·공유·암호화·삭제 요청
- 기기 로컬 only vs 서버 전송 구분

### 7.3 기타

- 콘텐츠 등급(IARC), 타겟 연령, 광고 유무

---

## 8. 스토어 에셋

| 항목 | 규격 |
|------|------|
| 스토어 아이콘 | 512×512 PNG |
| 그래픽 이미지 | 1024×500 |
| 스크린샷 | 휴대폰 최소 2장 (권장 4~8) |
| 짧은 설명 | 80자 |
| 전체 설명 | 4000자 |

스크린샷은 **스토어에 올릴 빌드(public)** 기준으로 촬영.

---

## 9. 출시 순서

1. Application ID 확정 및 코드 반영  
2. Maps·API 키 프로덕션 제한  
3. public AAB 빌드 + 실기기 QA  
4. Play Console 앱 생성  
5. 스토어 등록 / Data safety / 개인정보처리방침 URL  
6. 콘텐츠 등급·국가  
7. 내부 테스트 → (비공개) → 프로덕션  
8. 심사 후 출시  

**업데이트:** `pubspec` 버전 bump → AAB → Play 새 버전 (versionCode 증가).

---

## 10. 언어·컨버전 추천

| 대상 | 컨버전? | 추천 |
|------|---------|------|
| Dart → Kotlin/Java 전체 재작성 | **아니오** | Flutter 유지 |
| 스토어 설명 | 선택 | 한국어 + 영어 |
| 앱 UI 다국어 | 선택 | `flutter gen-l10n` / ARB (해외 확장 시) |
| 개인정보처리방침 | 문서 | 한국어 필수 |
| 네이티브 | 일부 유지 | 알림·오버레이 Kotlin (`TodaySummaryNotifier.kt` 등) |

---

## 11. 작업 우선순위

1. `com.example.dbros_app` → 정식 applicationId  
2. Play용 public AAB 빌드 스크립트·문서화  
3. 개인정보처리방침 URL  
4. Data safety 초안  
5. public flavor / manifest 권한 분리 (심사 대비)  
6. 스토어 스크린샷·설명  
7. 내부 테스트 → 프로덕션  

---

## 12. 참고 링크

- [Flutter Android 배포](https://docs.flutter.dev/deployment/android)
- [Play Console 도움말](https://support.google.com/googleplay/android-developer/)
- [민감 앱 권한 정책](https://support.google.com/googleplay/android-developer/answer/9888170)
- [Android App Bundle](https://developer.android.com/guide/app-bundle)

---

## 13. 레포 내 관련 파일

| 경로 | 설명 |
|------|------|
| `pubspec.yaml` | 버전 (`version:`) |
| `tool/bump_pubspec_version.dart` | 버전 자동 증가 |
| `tools/build_dual_apk.ps1` | owner/public APK |
| `tools/build_release_apk.ps1` | 단일 APK + bump |
| `android/key.properties.example` | 서명 설정 예시 |
| `lib/config/feature_flags.dart` | `MAP_FEATURES_ENABLED` |
| `.cursor/rules/git-commit.mdc` | 커밋·릴리스 빌드 규칙 |
