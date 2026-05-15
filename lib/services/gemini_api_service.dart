// GEMINI_HYBRID_PARSE_BEGIN
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';

import 'call_card_image_compress.dart';
import 'usage_limit_service.dart';

// ignore_for_file: constant_identifier_names

/// 키: `--dart-define` / 환경 변수 `GEMINI_API_KEY` / 프로젝트 루트 `defines.local.json`(VM·로컬 실행 시)
String _resolveGeminiApiKey() {
  const fromDefine = String.fromEnvironment('GEMINI_API_KEY');
  if (fromDefine.isNotEmpty) return fromDefine;
  final fromEnv = Platform.environment['GEMINI_API_KEY']?.trim() ?? '';
  if (fromEnv.isNotEmpty) return fromEnv;
  try {
    final f = File('defines.local.json');
    if (f.existsSync()) {
      final map = jsonDecode(f.readAsStringSync());
      if (map is Map<String, dynamic>) {
        final k = map['GEMINI_API_KEY']?.toString().trim();
        if (k != null && k.isNotEmpty) return k;
      }
    }
  } catch (_) {}
  return '';
}

class GeminiParsedFields {
  GeminiParsedFields({
    required this.program,
    required this.driveTimeHm,
    required this.grossFare,
    required this.startLocation,
    required this.waypoint,
    required this.endLocation,
  });

  /// `카카오(일반)` 등. JSON null·미식별이면 빈 문자열.
  final String program;
  final String driveTimeHm;
  final int grossFare;
  final String startLocation;
  final String waypoint;
  final String endLocation;
}

class GeminiParseResult {
  GeminiParseResult({
    required this.usageExceeded,
    this.fields,
    this.errorMessage,
  });

  final bool usageExceeded;
  final GeminiParsedFields? fields;
  final String? errorMessage;
}

/// Gemini 멀티모달(이미지+프롬프트) 콜카드 올인원 파싱 + 일일 사용 제한.
class GeminiApiService {
  GeminiApiService._();
  static final GeminiApiService instance = GeminiApiService._();

  /// SDK가 `models/{id}` 를 붙이므로, 여기서는 **`models/` 접두 없이** 순수 id 만 넣는다.
  static const List<String> _modelCandidates = [
    'gemini-2.5-flash',
    'gemini-1.5-flash-latest',
    'gemini-2.0-flash',
  ];

  /// `GenerativeModel(model: …)` 에 `models/` 가 들어가면 API 경로가 중복될 수 있어 제거한다.
  static String _normalizeModelId(String raw) {
    var s = raw.trim();
    while (s.startsWith('models/')) {
      s = s.substring('models/'.length).trim();
    }
    if (s.startsWith('/')) s = s.substring(1).trim();
    return s;
  }

  static const String _multimodalPrompt = r'''
너는 한국 대리운전 콜카드 분석 전문가야. 
첨부된 콜카드 이미지(레이아웃 및 텍스트)를 분석해서 어떤 대리운전 프로그램인지 먼저 판별하고, 그 프로그램의 특성에 맞춰 6가지 핵심 데이터를 추출해.

[1단계: 프로그램 판별 상세 규칙 (우선순위 적용)]
아래 조건들을 순서대로 확인하여 가장 먼저 일치하는 프로그램을 찾고, 최종적으로 "program" 항목에 기재해. (어느 것도 아니면 null)

1. 로지(Logi):
   - '갱신'이라는 단어가 있거나,
   - ['운행시작', '출발지', '도착지']가 있으면서 '입금액' 또는 '고객과의거리'가 포함된 경우.

2. 콜마너(CallManner):
   - '출도'라는 단어가 단독으로 있거나,
   - ['지사명', '출도', '출발지', '도착지']가 모두 포함된 경우.

3. 티맵(Tmap):
   - '실수익' 단어가 있으면서 ['운행중', '운행완료', '티맵', 'TMAP', '운행일자'] 중 하나라도 연관되어 있는 경우.

4. 카카오(Kakao) - 세부 판별:
   * 카카오 마커(Form2): '상황실', '고객메모', '배정취소', '잔여시간', '취소불가', '만날장소', '길찾기', '밀어서고객에게', '도착알림', '출발지에도착'
   
   - 카카오(맞춤): 텍스트에 '맞춤콜'이 포함된 경우.
   - 카카오(프콜): '배정완료'와 '운영센터'가 함께 있거나, [T전화, 법인무료보험, Form2 마커]가 있으면서 '운영센터'가 없는 경우.
   - 카카오(일반) 및 카카오(제휴):
     위 맞춤/프콜이 아니면서, '고객과 통화', '배정완료', 'Form2 마커', '카카오T' 중 하나라도 존재하여 카카오 콜로 판단될 때 다음 기준으로 분류해.
     -> 화면 텍스트 어딘가에 기사의 점수를 나타내는 숫자 패턴(예: '98점', '100점' 등 숫자+점 형식)이 보이면 **"카카오(일반)"**
     -> 기사 점수 패턴이 전혀 보이지 않으면 **"카카오(제휴)"**

[2단계: 요금 및 주소 추출 공식]
- 카카오: '현금'이면 수익(+지원금) 합산, '카드'면 P 앞의 숫자를 요금으로 해.
- 로지/콜마너: '요금' 또는 '운행요금' 주변 금액이 진짜 요금이야. 수수료(입금액, 차감)는 무시해.
- 주소 추출: 상호명(롯데백화점, 전담네컷 등)은 절대 자르지 말고 끝까지 추출해. 로지는 적요에 숨은 경유지를 문맥으로 잘 찾아내.

결과는 반드시 아래 JSON 형식으로만 답변해. 마크다운 기호(코드펜스 등)나 다른 설명은 절대 추가하지 마.
program 값은 반드시 다음 중 정확히 하나의 문자열이거나 JSON null 이어야 해:
"카카오(일반)", "카카오(제휴)", "카카오(프콜)", "카카오(맞춤)", "로지", "콜마너", "티맵"
grossFare는 JSON 숫자형만. driveTime은 "HH:mm" 문자열 또는 JSON null. waypoint는 없으면 "".

{
  "program": "카카오(일반) | 카카오(제휴) | 카카오(프콜) | 카카오(맞춤) | 로지 | 콜마너 | 티맵 | null",
  "driveTime": "19:30 또는 null",
  "grossFare": 25000,
  "startLocation": "출발지 주소 및 상호명 전체",
  "waypoint": "경유지 주소 (없으면 빈 문자열)",
  "endLocation": "도착지 주소 및 상호명 전체"
}
''';

  GenerativeModel _modelForImage(String rawModelId, String apiKey) {
    final model = _normalizeModelId(rawModelId);
    return GenerativeModel(
      model: model,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        maxOutputTokens: 400,
        responseMimeType: 'application/json',
      ),
    );
  }

  /// 압축 JPEG + 올인원 프롬프트로 프로그램·필드 한 번에 파싱.
  Future<GeminiParseResult> parseCallCardImage(File imageFile) async {
    final apiKey = _resolveGeminiApiKey();
    if (apiKey.isEmpty) {
      return GeminiParseResult(
        usageExceeded: false,
        errorMessage:
            'GEMINI_API_KEY가 비어 있습니다. 프로젝트 루트에 defines.local.json 을 두고 '
            '(defines.local.example.json 참고) flutter run 시 '
            '--dart-define-from-file=defines.local.json 을 쓰거나 tools/flutter_run_dev.ps1 을 실행하세요.',
      );
    }

    late final Uint8List jpeg;
    try {
      jpeg = await CallCardImageCompress.compressForGemini(imageFile.path);
    } catch (e) {
      return GeminiParseResult(
        usageExceeded: false,
        errorMessage: '이미지 압축 실패: $e',
      );
    }

    final allowed = await UsageLimitService.instance.checkAndIncrementUsage();
    if (!allowed) {
      return GeminiParseResult(usageExceeded: true);
    }

    final content = [
      Content.multi([
        TextPart(_multimodalPrompt),
        DataPart('image/jpeg', jpeg),
      ]),
    ];

    Object? lastError;
    for (final modelId in _modelCandidates) {
      try {
        final model = _modelForImage(modelId, apiKey);
        final response = await model.generateContent(content);
        final raw = response.text?.trim();
        if (raw == null || raw.isEmpty) {
          lastError = 'Gemini 응답이 비어 있습니다. ($modelId)';
          continue;
        }
        final jsonStr = _extractJsonObject(raw);
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final fields = _fieldsFromJson(map);
        return GeminiParseResult(usageExceeded: false, fields: fields);
      } catch (e) {
        lastError = e;
      }
    }
    return GeminiParseResult(
      usageExceeded: false,
      errorMessage: lastError?.toString() ?? 'Gemini 호출 실패',
    );
  }

  String _extractJsonObject(String raw) {
    var s = raw.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', multiLine: true);
    final m = fence.firstMatch(s);
    if (m != null) {
      s = m.group(1)!.trim();
    }
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start >= 0 && end > start) {
      s = s.substring(start, end + 1);
    }
    return s;
  }

  static String _normalizeDriveTimeToHm(String raw) {
    var t = raw.trim().replaceAll('.', ':').replaceAll('：', ':');
    if (t.isEmpty || t.toLowerCase() == 'null') return '';
    final m = RegExp(r'^(\d{1,2})\s*:\s*(\d{1,2})$').firstMatch(t);
    if (m == null) return '';
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    if (h == null || min == null) return '';
    if (h < 0 || h > 23 || min < 0 || min > 59) return '';
    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  static int _normalizeGrossFare(Object? fareRaw) {
    if (fareRaw == null) return 0;
    if (fareRaw is int) return fareRaw;
    if (fareRaw is double) return fareRaw.round();
    final digits = fareRaw.toString().replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  static String _normalizeProgram(Object? p) {
    if (p == null) return '';
    var s = p.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return '';
    if (s == '카카오') return '카카오(일반)';
    return s;
  }

  GeminiParsedFields _fieldsFromJson(Map<String, dynamic> map) {
    final driveRaw = map['driveTime'];
    String driveTimeHm = '';
    if (driveRaw != null && driveRaw is! List) {
      driveTimeHm = _normalizeDriveTimeToHm(driveRaw.toString());
    }

    final grossFare = _normalizeGrossFare(map['grossFare']);

    String readStr(Object? v) {
      if (v == null) return '';
      final t = v.toString().trim();
      if (t.toLowerCase() == 'null') return '';
      return t;
    }

    return GeminiParsedFields(
      program: _normalizeProgram(map['program']),
      driveTimeHm: driveTimeHm,
      grossFare: grossFare,
      startLocation: readStr(map['startLocation']),
      waypoint: readStr(map['waypoint']),
      endLocation: readStr(map['endLocation']),
    );
  }
}
// GEMINI_HYBRID_PARSE_END
