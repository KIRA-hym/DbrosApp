# 스토어 배포 및 수익화(광고/구독) 시스템 구축 가이드

본 문서는 `dbros_app` 프로젝트를 바탕으로 양대 스토어(Google Play, Apple App Store) 배포를 위한 필수 준비 사항과 개인정보처리방침 작성 가이드, 그리고 향후 광고 및 구독(프리미엄) 모델 도입을 위한 아키텍처 및 로드맵을 상세히 다룹니다.

---

## 1. 스토어 배포 필수 준비 사항

### 1.1 앱 스토어 메타데이터 준비
- **앱 아이콘**: 1024x1024 해상도의 PNG 파일 (투명 배경 불가). (현재 `flutter_launcher_icons`로 기본 설정 완료)
- **스크린샷**: 
  - Android: 16:9 또는 9:16 비율 (최소 2장, 최대 8장)
  - iOS: 6.5형(iPhone 15 Pro Max 등) 및 5.5형 스크린샷 필수.
- **앱 정보**: 앱 이름(타이틀), 부제목, 간략한 설명, 상세 설명, 주요 기능 리스트.
- **지원 URL**: 앱 문의처(이메일 또는 웹사이트) 및 **개인정보처리방침 URL**.

### 1.2 개발자 계정 및 인증
- **Google Play Console**: 개발자 등록 비용 결제 ($25, 1회성). 신규 개인 계정의 경우 20명 이상의 테스터를 통한 14일 비공개 테스트가 필수 요건입니다.
- **Apple Developer Program**: 개발자 등록 비용 결제 (연 $99). Mac 환경 및 Xcode가 필수적입니다.

### 1.3 기술적 준비 (현재 코드 베이스 기준)
- **앱 서명(App Signing)**: 
  - Android용 `keystore.jks` 파일 생성 및 `build.gradle`에 Release Signing Config 작성.
  - 생성된 Keystore 파일과 비밀번호는 절대 분실하지 않도록 안전한 곳에 백업해야 합니다.
- **번들 생성**: Android는 `.aab` (Android App Bundle) 파일 추출. (`flutter build appbundle`)
- **버전 관리**: 배포 시마다 `pubspec.yaml`의 `version` 코드 증가 필수 (현재 `1.0.08+100803`).

---

## 2. 개인정보처리방침(Privacy Policy) 가이드라인

앱스토어 배포 시 개인정보처리방침 링크는 **필수**입니다. 별도의 웹사이트가 없다면 무료 서비스인 **Notion**, **GitHub Pages**, **Blogger** 등을 이용해 작성 후 퍼블릭 링크를 제출하시면 됩니다.

### 2.1 작성 전 필수 체크 리스트 (dbros_app 기준)
현재 앱에 포함된 라이브러리와 기능을 바탕으로 수집/접근하는 권한들은 다음과 같습니다.
1. **위치 정보 (`geolocator`, `google_maps_flutter`)**: 대리기사 콜 지도, 경로 파악.
2. **카메라 및 사진첩 (`image_picker`, `wechat_assets_picker`)**: 콜카드 이미지 캡처 및 OCR 파싱.
3. **광고 식별자 (`google_mobile_ads`)**: 맞춤형 광고(또는 일반 광고) 제공.
4. **분석 및 크래시 리포팅 (`firebase_core`, `cloud_firestore`)**: 오류 로깅 및 사용량 통계.

### 2.2 개인정보처리방침 필수 포함 항목
작성 시 아래의 목차를 포함해야 합니다.

1. **개인정보의 처리 목적**: (예: 콜카드 이미지 텍스트 추출, 사용자의 위치 기반 경로 제공, 앱 오류 분석 등)
2. **수집하는 개인정보 항목 및 방법**:
   - 위치 데이터 (정확한 위치, 대략적인 위치)
   - 사진/미디어 파일 (OCR 추출을 위해 업로드되는 이미지)
   - 기기 식별자 및 광고 ID (AdMob 연동 시)
3. **개인정보의 처리 및 보유 기간**: 앱 삭제 시 즉각 파기, 또는 서비스 제공 기간 동안 보유.
4. **개인정보의 제3자 제공에 관한 사항**: Google AdMob(광고), Firebase(DB 및 분석), Google ML Kit(텍스트 인식)에 데이터가 전달됨을 명시.
5. **이용자의 권리와 행사 방법**: 언제든 기기 설정에서 권한을 취소할 수 있음을 명시.
6. **동의 철회 및 문의처**: 개발자의 연락처(이메일 등) 기재.

> [!IMPORTANT]
> iOS 배포 시, **App Tracking Transparency (ATT)** 팝업을 띄워 광고 추적 권한을 사용자에게 명시적으로 요청해야 하며, 개인정보처리방침에도 이를 반영해야 Apple 심사에서 반려(Reject)되지 않습니다.

---

## 3. 광고 및 구독(프리미엄) 시스템 도입 구상 및 로드맵

현재 `dbros_app`에는 `google_mobile_ads` 패키지가 추가되어 있고, `FeatureUsageService` 및 `ProFeatureGuard`를 통해 **일일 사용 횟수 제한** 및 **보상형 광고 시청 후 횟수 추가** 로직이 이미 잘 설계되어 있습니다. 향후 구독(In-App Purchase) 모델을 확장하기 위한 구상은 다음과 같습니다.

### 3.1 수익화 아키텍처 구상
앱 내 결제(인앱 결제) 시스템을 직접 구현하면 Android와 iOS의 영수증 검증 로직이 매우 복잡합니다. 따라서 크로스플랫폼 구독 관리 솔루션인 **RevenueCat** (`purchases_flutter` 패키지) 도입을 강력히 권장합니다.

```mermaid
graph TD
    A[사용자] --> B{SettingsService.isPremiumUser?}
    B -- Yes --> C[모든 기능 무제한 사용 / 광고 제거]
    B -- No --> D{무료 횟수 남음?}
    D -- Yes --> E[기능 사용 & 횟수 차감]
    D -- No --> F[ProFeatureGuard 팝업]
    F --> |광고 시청| G[보상형 광고 1회 시청 후 기능 사용]
    F --> |구독 전환| H[RevenueCat 인앱결제 화면(Paywall)]
    H --> |결제 성공| I[Premium 전환 적용]
```

### 3.2 단계별 구현 로드맵 및 필요한 서비스

#### Phase 1: 사전 환경 설정 및 RevenueCat 도입 (진행자: 사용자)
1. **Google Play Console / App Store Connect 결제 세팅**:
   - 스토어에 세금 및 계좌 정보를 등록합니다.
   - 각 스토어에서 구독 상품(예: `pro_monthly`, `pro_yearly`)을 생성합니다.
2. **RevenueCat 세팅**:
   - RevenueCat에 가입 후 프로젝트를 생성합니다.
   - Play Store 및 App Store의 서비스 키를 연동하고 생성한 구독 상품을 등록합니다.
3. **AdMob 활성화**:
   - Google AdMob 계정에 앱을 등록하고, 보상형 광고(Rewarded Ad) 단위 ID 및 배너 광고 단위 ID를 발급받습니다.

#### Phase 2: 앱 내 로직 및 UI 연동 (진행자: AI / 개발자)
1. **패키지 추가**: `pubspec.yaml`에 `purchases_flutter` 및 `purchases_ui_flutter` 패키지 추가.
2. **구독 결제 화면(Paywall) 구현**:
   - 사용자가 PRO 업그레이드 버튼을 눌렀을 때, 혜택(무제한 OCR, 광고 제거, 지도 무제한 등)을 보여주고 구독 상품 가격을 표시하는 매력적인 결제 화면 구현.
3. **RevenueCat SDK 연동**:
   - 앱 실행 시 `Purchases.configure(apiKey)`로 초기화.
   - 유저의 결제 상태(Entitlement)를 주기적으로 확인하여 `SettingsService.isPremiumUser` 변수 업데이트.
4. **광고(AdMob) 단위 ID 교체**:
   - `ad_banner_widget.dart` 및 `rewarded_ad_service.dart`에 하드코딩된 테스트 ID를 실제 발급받은 광고 ID로 교체 (환경 변수 또는 원격 구성 사용 권장).

#### Phase 3: 테스트 및 심사 제출 (진행자: 사용자)
1. **인앱 결제 샌드박스 테스트**:
   - iOS: Sandbox 테스터 계정을 통해 결제 테스트.
   - Android: 라이선스 테스터 등록 후 테스트 카드로 결제 로직 테스트.
2. **스토어 심사 유의사항**:
   - 구독 혜택, 결제 취소 방법, 갱신 규정 등을 결제 화면 하단에 명확히 기재해야 앱 심사를 통과할 수 있습니다.

---

## 4. 요약 및 다음 단계 제안
1. **가장 먼저 하실 일**: 
   - Google Play Console / Apple Developer 계정을 만들고, 앱 메타데이터(설명, 스크린샷 등)를 준비해 주세요.
   - Notion 등에 [개인정보처리방침 필수 항목](#22-개인정보처리방침-필수-포함-항목)을 작성하여 링크를 생성해 주세요.
2. **수익화 도입 시점**: 
   - 스토어 초기 배포는 현재 완성된 버전(광고 기반 횟수 제한)으로 먼저 출시하여 사용자 반응을 살피는 것을 권장합니다. 
   - 이후 업데이트 버전에서 **RevenueCat** 연동 및 인앱 구독(프리미엄) 결제 기능을 도입하는 것이 안전합니다.
