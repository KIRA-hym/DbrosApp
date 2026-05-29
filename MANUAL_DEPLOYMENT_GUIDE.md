# Dbros App - 수동 배포 및 터미널 명령어 가이드

## 1. 개요
이 문서는 AI 어시스턴트(Antigravity 등)를 사용할 수 없는 환경이거나, 개발자(사용자)가 직접 수동으로 앱 배포, 원격 업데이트, 필수 터미널 작업을 수행해야 할 때 참고할 수 있도록 모든 절차와 명령어를 상세히 정리한 문서입니다.

---

## 2. 신규 앱 배포 (Full Release Build)
앱에 완전히 새로운 기능이 추가되었거나 네이티브 코드(Android 설정, 권한 등)가 변경되어 새로운 버전의 APK를 추출하거나 스토어에 신규 업로드해야 할 때 사용하는 방법입니다.

### 2.1 스크립트를 통한 자동 빌드 (권장)
프로젝트 루트 폴더에 준비된 `build_release.ps1` 스크립트를 사용하면 `pubspec.yaml`의 빌드 번호 증가부터 최종 APK 추출까지 한 번에 안전하게 처리됩니다.

```powershell
# 1. 터미널(PowerShell)을 열고 프로젝트 루트로 이동
cd C:\dbros_app

# 2. 릴리스 빌드 스크립트 실행
.\build_release.ps1
```
> **스크립트 동작 원리:** 
> 1. `pubspec.yaml` 내 빌드 번호(+1) 자동 펌핑
> 2. 알림 아이콘 무결성 검증
> 3. `flutter pub get`
> 4. `shorebird release android --artifact apk` (Shorebird 원격 패치 지원 APK 생성)

### 2.2 수동으로 직접 빌드할 경우 (스크립트 미사용)
스크립트를 거치지 않고 직접 제어하고 싶을 때는 아래의 순서를 따릅니다.

1. **버전 수정:** `pubspec.yaml` 파일을 열고 `version: 1.0.06+12` 부분을 원하는 버전(예: `1.0.07+13`)으로 직접 변경합니다.
2. **패키지 업데이트:**
   ```powershell
   flutter pub get
   ```
3. **Shorebird 릴리스 빌드:** (일반 빌드가 아닌 Shorebird 빌드를 써야 이후 원격 업데이트를 먹일 수 있습니다.)
   ```powershell
   # 안드로이드 APK 추출용
   shorebird release android
   
   # 구글 플레이스토어 업로드용 AAB 파일 추출 시
   shorebird release android --artifact aab
   ```

---

## 3. 원격 업데이트 배포 (Shorebird Patch)
UI 수정, 로직 오류 수정(ex. OCR 파싱 수정), 텍스트 변경 등 **단순 Dart 코드 변경사항**을 스토어 심사 없이 사용자들의 앱에 실시간으로 즉시 반영하고 싶을 때 사용합니다.

### 3.1 현재 활성화된 배포 버전 확인
먼저 어떤 버전들이 현재 원격 업데이트를 받을 수 있는지 확인해야 합니다.
```powershell
shorebird releases list
```
> **출력 예시:**
> `1.0.06+100612  android: active`
> `1.0.05+100510  android: active`

### 3.2 특정 버전에 원격 패치 쏘기
코드 수정을 마쳤다면 위에서 확인한 버전 명칭을 복사하여 아래 명령어를 실행합니다.
```powershell
shorebird patch android --release-version 1.0.06+100612
```
> **Tip:** 
> - 명령어 실행 후 마지막에 `Would you like to publish this patch? (y/n)` 질문이 나오면 `y`를 입력하면 배포가 시작됩니다.
> - 질문 없이 강제로 묻지 않고 배포하게 하려면 파이프라인(`|`)을 씁니다:
>   `echo "y" | shorebird patch android --release-version 1.0.06+100612`

---

## 4. 자주 쓰는 필수 터미널 명령어 모음 (Troubleshooting)
개발 중 캐시가 꼬이거나, 빌드 에러가 나거나, 생성 파일이 꼬였을 때 직접 입력해야 하는 1순위 명령어들입니다.

### 4.1 프로젝트 청소 및 초기화 (빌드 오류 시 가장 먼저 할 일)
알 수 없는 빌드 에러가 나거나 빨간 줄이 안 없어질 때, 프로젝트의 캐시를 모두 날리고 백지에서 다시 불러옵니다.
```powershell
flutter clean
flutter pub get
```

### 4.2 Code Generation (빌드 러너)
`freezed`, `json_serializable`, `retrofit` 등 자동 생성 코드 파일(`.g.dart`, `.freezed.dart`) 구조를 변경했을 때 변경사항을 반영해주는 명령어입니다.
```powershell
# 기존에 잘못 꼬인 생성 파일들을 지우고 안전하게 새로 생성합니다.
dart run build_runner build --delete-conflicting-outputs
```

### 4.3 Git 수동 커밋 및 푸시
코드를 백업하고 싶거나, 다른 PC에서 작업하기 위해 클라우드(GitHub)에 코드를 올릴 때 씁니다.
```powershell
# 1. 변경된 모든 파일을 장바구니(Staging)에 담기
git add .

# 2. 어떤 작업을 했는지 메모(메시지)를 달아 확정(Commit)
git commit -m "여기에 작업 내용을 적습니다 (예: OCR 버그 수정)"

# 3. 원격 저장소에 올리기(Push)
git push
```

### 4.4 Shorebird 오류 대처 (Git Longpaths 설정)
Windows 환경에서 Shorebird 명령어 실행 중 '경로가 길다'는 에러가 뜰 경우 한 번만 실행해주면 됩니다.
```powershell
git config --system core.longpaths true
```

---

## 5. 작업 흐름 요약 (Cheatsheet)

1. **Dart 로직/UI만 조금 수정했을 때 (원격 업데이트용)**
   - 코드 수정 ➔ 테스트 완료 ➔ `git commit` / `git push` ➔ `shorebird patch android --release-version [버전]`
2. **새로운 플러그인(네이티브)을 추가했거나 완전한 새 버전일 때 (스토어 배포용)**
   - 코드 수정 ➔ `.\build_release.ps1` 스크립트 실행 ➔ 생성된 APK 추출 ➔ (필요시 AAB로 스토어 제출)
