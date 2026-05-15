// GEMINI_HYBRID_PARSE_BEGIN
import 'dart:io';

import '../services/gemini_api_service.dart';
import 'drive_time_format.dart';

/// 카카오 콜카드: Gemini 멀티모달 올인원 파싱 결과 매핑.
class KakaoCallCardOcr {
  KakaoCallCardOcr._();

  static const String programGeneral = '카카오(일반)';
  static const String programPro = '카카오(프콜)';
  static const String programAlliance = '카카오(제휴)';

  static Future<KakaoScreenParsed> parseScreen(File imageFile) async {
    final r = await GeminiApiService.instance.parseCallCardImage(imageFile);
    if (r.usageExceeded || r.fields == null) {
      return KakaoScreenParsed(
        driveDateYmd: null,
        driveTimeHm: null,
        waypoint: '',
        startLocation: '',
        endLocation: '',
        grossFare: null,
        paymentMethod: null,
      );
    }
    final f = r.fields!;
    final timeNorm = f.driveTimeHm.isEmpty
        ? null
        : (normalizeDriveTimeHm(f.driveTimeHm) ?? f.driveTimeHm);
    return KakaoScreenParsed(
      driveDateYmd: null,
      driveTimeHm: timeNorm,
      waypoint: f.waypoint,
      startLocation: f.startLocation,
      endLocation: f.endLocation,
      grossFare: f.grossFare > 0 ? f.grossFare : null,
      paymentMethod: null,
    );
  }
}

class KakaoScreenParsed {
  final String? driveDateYmd;
  final String? driveTimeHm;
  final String waypoint;
  final String startLocation;
  final String endLocation;
  final int? grossFare;
  final String? paymentMethod;

  KakaoScreenParsed({
    required this.driveDateYmd,
    required this.driveTimeHm,
    required this.waypoint,
    required this.startLocation,
    required this.endLocation,
    required this.grossFare,
    this.paymentMethod,
  });
}
// GEMINI_HYBRID_PARSE_END
