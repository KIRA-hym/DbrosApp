// GEMINI_HYBRID_PARSE_BEGIN
import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';

import 'usage_limit_service.dart';

// ignore_for_file: constant_identifier_names
const String _apiKey = 'AIzaSyDRWDXyeNQe2EXEVEZ7xaH9nkdDBppIE1w';

class GeminiParsedFields {
  GeminiParsedFields({
    required this.driveTimeHm,
    required this.grossFare,
    required this.startLocation,
    required this.waypoint,
    required this.endLocation,
  });

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

/// Gemini Flash 기반 콜카드 필드 추출 + 일일 15건 제한.
class GeminiApiService {
  GeminiApiService._();
  static final GeminiApiService instance = GeminiApiService._();

  /// `gemini-1.5-flash`는 일부 프로젝트에서 REST 404 → 사용 가능 모델로 통일
  static const String _modelName = 'gemini-2.5-flash';

  String _buildPrompt(String detectedProgram, String ocrText) {
    return '''
너는 한국 대리운전 콜카드 분석 전문가야. 
이 콜카드는 [$detectedProgram] 프로그램의 화면이야. 아래의 [프로그램별 특성 및 추출 공식]을 엄격하게 적용해서 OCR 텍스트에서 5가지 항목을 추출해. 대리운전 도메인의 맥락을 이해하고 주소와 요금을 완벽하게 분리해 내.

[요금 추출 공식]
- 카카오: 텍스트 내 결제 방식을 먼저 파악해. 
  1) '현금' 문구가 있다면: '수익 [금액] P' 문구 주변을 찾고, '지원금 [금액] P'가 함께 표기되어 있다면 반드시 두 금액의 숫자를 합산하여 총요금으로 해.
  2) '카드' 문구가 있다면: 'P' 글자 바로 앞에 있는 숫자를 요금으로 해.
  3) 맞춤콜의 경우 '실제 수익' 문구 옆의 금액을 추출해. 주소지의 번지수(예: 105-1)를 요금으로 착각하지 마.
- 로지 및 콜마너: '요금' 라벨 근처의 금액이 총요금이야. '입금액', '차감', '잔액' 옆에 있는 금액은 기사 수수료 항목이니 절대 요금으로 잡지 마. (금액 끝에 OCR 노이즈로 1, 2가 붙어 비정상적으로 큰 숫자라면 타당성을 추론해 보정해)
- 티맵(Tmap): '실수익' 또는 '수익' 우측 금액을 추출해.

[주소 및 경유지 추출 공식]
- 출발지/도착지 조립: 로지의 경우 '상세:' 문구 앞의 상호명과 뒤의 행정주소를 자연스럽게 합쳐서 하나의 주소로 만들어.
- 경유지: 콜마너는 '경유지' 라벨 옆을 추출하고, 로지는 '적요'나 '메모' 내용 중에 숨어있는 경유지를 맥락으로 파악해 분리해.
- 도착지 분할: OCR 오류로 '도착지'라는 단어가 안 보이더라도, 텍스트 중간에 새로운 지명(시/군/구/동)이 시작되면 그곳을 기점으로 도착지를 분리해.
- 노이즈 텍스트 제거: 주소를 추출할 때, 하트 이모지 등 특수 아이콘이나 배차 시스템 UI 문구('상황실', '고객과 통화', '출발지 도착', '지사명', '길안내' 등)는 주소에 절대 포함하지 마.

[일반 사항]
- 운행시간: 텍스트 최상단 좌측에 'XX:XX' 또는 'X:XX' 형식으로 표기됨.

결과는 반드시 아래 JSON 형식으로만 답변해. (마크다운 기호나 추가 설명 절대 금지)

{
  "driveTime": "운행시간 (예: 19:30, 없으면 null)",
  "grossFare": 총요금 (숫자만, 예: 25000),
  "startLocation": "출발지 주소 및 상호",
  "waypoint": "경유지 주소 (없으면 빈 문자열)",
  "endLocation": "도착지 주소 및 상호"
}

OCR 텍스트:
$ocrText
''';
  }

  Future<GeminiParseResult> parseCallCard({
    required String fullText,
    required String detectedProgram,
  }) async {
    final allowed = await UsageLimitService.instance.checkAndIncrementUsage();
    if (!allowed) {
      return GeminiParseResult(usageExceeded: true);
    }

    try {
      final model = GenerativeModel(model: _modelName, apiKey: _apiKey);
      final prompt = _buildPrompt(detectedProgram, fullText);
      final response = await model.generateContent([Content.text(prompt)]);
      final raw = response.text?.trim();
      if (raw == null || raw.isEmpty) {
        return GeminiParseResult(
          usageExceeded: false,
          errorMessage: 'Gemini 응답이 비어 있습니다.',
        );
      }
      final jsonStr = _extractJsonObject(raw);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final fields = _fieldsFromJson(map);
      return GeminiParseResult(usageExceeded: false, fields: fields);
    } catch (e) {
      return GeminiParseResult(
        usageExceeded: false,
        errorMessage: e.toString(),
      );
    }
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

  GeminiParsedFields _fieldsFromJson(Map<String, dynamic> map) {
    final driveRaw = map['driveTime'];
    String driveTimeHm = '';
    if (driveRaw != null && driveRaw is! List) {
      final t = driveRaw.toString().trim();
      if (t.isNotEmpty && t.toLowerCase() != 'null') {
        driveTimeHm = t;
      }
    }

    final fareRaw = map['grossFare'];
    int grossFare = 0;
    if (fareRaw is int) {
      grossFare = fareRaw;
    } else if (fareRaw is double) {
      grossFare = fareRaw.round();
    } else if (fareRaw != null) {
      grossFare = int.tryParse(fareRaw.toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    }

    String readStr(Object? v) {
      if (v == null) return '';
      final t = v.toString().trim();
      if (t.toLowerCase() == 'null') return '';
      return t;
    }

    return GeminiParsedFields(
      driveTimeHm: driveTimeHm,
      grossFare: grossFare,
      startLocation: readStr(map['startLocation']),
      waypoint: readStr(map['waypoint']),
      endLocation: readStr(map['endLocation']),
    );
  }
}
// GEMINI_HYBRID_PARSE_END
