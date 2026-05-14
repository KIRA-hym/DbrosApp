// GEMINI_HYBRID_PARSE_BEGIN
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../services/gemini_api_service.dart';
import 'drive_time_format.dart';
import 'work_date_utils.dart';

/// T맵 대리 「운행 상세 정보」 파싱 결과
class TmapTripDetailParsed {
  TmapTripDetailParsed({
    required this.driveDateYmd,
    required this.driveStartTimeHm,
    required this.grossFare,
    required this.startAddress,
    required this.endAddress,
  });

  final String driveDateYmd;
  final String driveStartTimeHm;
  final int grossFare;
  final String startAddress;
  final String endAddress;
}

/// T맵 대리 화면 판별 + Gemini 필드 추출.
class TmapTripDetailOcr {
  TmapTripDetailOcr._();

  static bool isTripDetailScreen(String fullText) {
    final c = fullText.replaceAll(RegExp(r'\s'), '');
    if (c.contains('운행상세정보')) return true;
    if ((c.contains('운행중') || c.contains('운행완료')) &&
        c.contains('실수익') &&
        (c.contains('티맵으로길안내') || c.contains('티맵'))) {
      return true;
    }
    if (fullText.contains('TMAP대리') ||
        fullText.contains('TMAP') ||
        fullText.contains('티맵')) {
      if (fullText.contains('실수익') || fullText.contains('운행일자')) return true;
    }
    if (fullText.contains('출발') &&
        fullText.contains('도착') &&
        fullText.contains('실수익') &&
        fullText.contains('운행일자')) {
      return true;
    }
    return false;
  }

  static String? _tryExtractDateYmd(String full) {
    final m = RegExp(r'(\d{4})[-./](\d{1,2})[-./](\d{1,2})').firstMatch(full);
    if (m == null) return null;
    return '${m.group(1)}-${m.group(2)!.padLeft(2, '0')}-${m.group(3)!.padLeft(2, '0')}';
  }

  static Future<TmapTripDetailParsed?> tryParse(String fullText, {List<TextBlock>? blocks}) async {
    if (!isTripDetailScreen(fullText)) return null;
    final r = await GeminiApiService.instance.parseCallCard(
      fullText: fullText,
      detectedProgram: '티맵',
    );
    if (r.usageExceeded || r.fields == null) return null;
    final f = r.fields!;
    if (f.grossFare == 0 && f.startLocation.isEmpty && f.endLocation.isEmpty) {
      return null;
    }
    final date = _tryExtractDateYmd(fullText) ?? WorkDateUtils.effectiveWorkDateYmd();
    final timeHm = f.driveTimeHm.isEmpty
        ? ''
        : (normalizeDriveTimeHm(f.driveTimeHm) ?? f.driveTimeHm);
    return TmapTripDetailParsed(
      driveDateYmd: date,
      driveStartTimeHm: timeHm,
      grossFare: f.grossFare,
      startAddress: f.startLocation,
      endAddress: f.endLocation,
    );
  }
}
// GEMINI_HYBRID_PARSE_END
