// GEMINI_HYBRID_PARSE_BEGIN
import 'dart:io';

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

/// T맵 대리 화면: Gemini가 program 을 티맵으로 판별한 경우에만 필드 반환.
class TmapTripDetailOcr {
  TmapTripDetailOcr._();

  static Future<TmapTripDetailParsed?> tryParse(File imageFile) async {
    final r = await GeminiApiService.instance.parseCallCardImage(imageFile);
    if (r.usageExceeded || r.fields == null) return null;
    final f = r.fields!;
    if (f.program != '티맵') return null;
    if (f.grossFare == 0 && f.startLocation.isEmpty && f.endLocation.isEmpty) {
      return null;
    }
    final date = WorkDateUtils.effectiveWorkDateYmd();
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
