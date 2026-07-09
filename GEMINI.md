# DbrosApp 개발 규칙 (GEMINI.md)

이 파일은 `c:\dbros_app` 워크스페이스에서 작업할 때 **항상 자동으로 적용**되는 규칙입니다.
사용자가 매번 언급하지 않아도 아래 모든 규칙을 준수하여 작업을 수행하세요.

---

## 1. 항상 적용할 개발 주의사항

### 작업 진행 전 사전 승인 규칙
- **선 보고 후 작업**: 사용자로부터 작업 요청을 받으면 즉시 코드를 수정하지 말고, 반드시 **먼저 분석 내용과 어떻게 보완할 것인지에 대한 계획(Implementation Plan)을 사용자에게 보고**한 뒤, 작업 승인을 득한 후에 실제 코드 수정을 진행할 것.

### 코드 수정 원칙
- **기존 기능 보호**: 수정 사항이 기존 기능을 깨트리지 않는지 항상 확인할 것.
- **Shorebird 원격 패치 방어(에셋 보호) 규칙**: Dart 로직 수정(원격 패치 배포)만이 목적인 경우, 불필요하게 `Icon(...)` 위젯의 종류를 변경/추가/삭제하지 않도록 극도로 주의할 것. 아이콘 사용 내역이 달라지면 `MaterialIcons-Regular.otf` 파일 트리쉐이킹 결과가 달라져 에셋 변경으로 간주되고 패치가 불가능해집니다. 어쩔 수 없이 건드리는 게 아니라면, UI 수정 시 아이콘을 함부로 바꾸지 마세요.
- **OCR 파싱 회귀 테스트**: `lib/utils/logi_colmanner_ocr.dart` 등 OCR 파싱 로직 수정 시,
  기존 정상 케이스(주소, 요금, 시간 등)가 여전히 올바르게 파싱되는지 시뮬레이션 후 결과를 명시할 것.
- **정규식 수정 시**: 수정한 정규식이 🟢성공 사례와 🔴오류 사례를 모두 통과하는지 검증 결과를 보고할 것.
- **Opacity/오버레이 주의**: `Scaffold` 전체를 `Opacity`, `Stack`, 또는 다른 투명도 위젯으로
  감싸면 터치 이벤트가 막히거나 배경 블러 버그가 발생할 수 있으므로 금지.
  반투명 배경이 필요할 경우 `backgroundColor: Color(0xCC000000)` 방식으로 처리할 것.
- **최소 범위 수정 원칙**: 요청된 내용 외의 코드는 건드리지 말 것.

### 커밋·푸시 규칙
- 작업 완료 후 반드시 `git add` → `git commit` → `git push origin main` 순서로 수행.
- **커밋 메시지는 한글로 상세하게** 작성. 아래 형식 준수:
  ```
  [태그] 제목 요약

  1. 변경 항목 상세 설명
  2. 변경 이유 및 근거
  3. 주의사항 또는 영향 범위
  ```
- 태그 종류: `[fix]`, `[feat]`, `[refactor]`, `[원복]`, `[chore]`, `[perf]`

### 작업 완료 보고 및 내역 기록
- 커밋·푸시 완료 후 **변경 파일, 변경 내용, 이유**를 한글로 정리하여 보고할 것.
- **작업 내역 기록**: 작업 완료 전, 반드시 `work` 폴더 내에 작업일자(예: `YYYYMMDD.md`) 파일에 상세한 작업 내역을 추가/업데이트할 것.

---

## 2. 커밋·푸시 완료 후 자동 판단 (반드시 수행)

커밋·푸시가 완료된 직후, 변경된 파일 목록을 분석하여 아래 기준으로 후속 작업을 **사용자에게 먼저 물어볼 것.**
사용자의 승인 없이 빌드나 패치를 자동으로 실행하지 말 것.

### 🔵 Shorebird 패치 제안 조건
다음 조건을 **모두** 만족할 때 → **"Shorebird 패치를 진행할까요?"** 라고 물어볼 것.
- `lib/` 내 Dart 파일만 변경됨
- `android/`, `ios/` 폴더 변경 없음
- `pubspec.yaml` 변경 없음 (또는 comments/formatting만 변경)
- `assets/` 폴더 변경 없음

Shorebird 패치 실행 명령어:
```powershell
$env:SKIP_JDK_VERSION_CHECK="true"; shorebird patch android
```

### 🟡 릴리즈 빌드 제안 조건
다음 중 하나라도 해당될 때 → **"릴리즈 빌드를 진행할까요?"** 라고 물어볼 것.
- `android/` 또는 `ios/` 폴더 변경
- `pubspec.yaml`의 `version`, `dependencies` 변경
- `assets/` 폴더 변경
- 신규 네이티브 플러그인 추가

릴리즈 빌드 실행 시 → `dbros-release` 스킬 절차에 따라 진행.

---

## 3. 릴리즈 빌드 표준 절차 (dbros-release 스킬)

사용자가 릴리즈 빌드를 승인하면 아래 순서대로 진행. 각 단계마다 결과를 보고하고 계속할지 확인할 것.

### 단계 1: 버전 확인 및 bump
1. `pubspec.yaml`의 현재 버전을 읽어 사용자에게 보여준다.
2. 새 버전을 사용자에게 물어본다. 
   - **버전 및 빌드 규칙**: `X.Y.Z+10ZZWW`
   - 앱 버전은 `X.Y.Z`, 맨 뒤 시퀀스(`WW`)는 `01`부터 `09`까지만 사용.
   - 시퀀스(`WW`)가 `09`에 도달하면 다음 버전업 시 `Z`를 1 올리고 `WW`를 `01`로 초기화.
   - 안드로이드 빌드코드(VersionCode)는 `10ZZWW` 형태 적용.
   - 예) `1.0.12+101209` → `1.0.13+101301`
3. 사용자가 승인한 버전으로 `pubspec.yaml`의 `version:` 값을 수정한다.

### 단계 2: Shorebird 릴리즈 빌드 (APK 전용)
```powershell
$env:SKIP_JDK_VERSION_CHECK="true"; shorebird release android --artifact apk
```
빌드 완료 후 APK 경로 확인:
`build\app\outputs\flutter-apk\app-release.apk`

### 단계 3: DbrosLanding APK 배포
APK 파일명 형식: `DbrosInstall_{YYYYMMDD}_v{X}_{Y}_{Z}_{BUILD}.apk`
예) `DbrosInstall_20260611_v1_0_11_101009.apk`

1. `C:\DbrosLanding\public\` 내 기존 `.apk` 파일 삭제
2. 새 APK를 위 형식으로 이름을 바꾸어 `C:\DbrosLanding\public\` 에 복사
3. `C:\DbrosLanding\public\version.json` 업데이트:
   ```json
   {
       "update_date": "YYYY-MM-DD",
       "download_url": "/DbrosInstall_{YYYYMMDD}_v{X}_{Y}_{Z}_{BUILD}.apk",
       "latest_version": "X.Y.Z.BUILD"
   }
   ```
4. DbrosLanding Firebase 배포:
   ```powershell
   firebase deploy
   ```
   (실행 위치: `C:\DbrosLanding`)
5. DbrosLanding git commit/push:
   ```
   [release] v{X.Y.Z+BUILD} APK 배포 및 설치 페이지 업데이트
   ```

### 단계 4: 최종 보고
- DbrosApp 버전, APK 파일명, 배포 URL, 완료 시각을 정리하여 보고.

---

## 4. 프로젝트 구조 참고

| 프로젝트 | 경로 | 용도 |
|---------|------|------|
| DbrosApp | `C:\dbros_app` | Flutter 메인 앱 |
| DbrosAdmin | `C:\DbrosAdmin` | 관리자 페이지 |
| DbrosLanding | `C:\DbrosLanding` | APK 배포 설치 페이지 (Firebase Hosting) |

- DbrosLanding APK 다운로드 URL 형식: `https://{hosting-domain}/DbrosInstall_...apk`
- `version.json`이 설치 페이지에 표시되는 버전 정보 및 다운로드 링크를 제어함.
