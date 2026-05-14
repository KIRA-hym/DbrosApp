// GEMINI_HYBRID_PARSE_BEGIN
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../services/gemini_api_service.dart';
import 'drive_time_format.dart';

/// 카카오 콜카드: 프로그램 구분(일반·프콜·제휴) + Gemini 하이브리드 필드 추출.
class KakaoCallCardOcr {
  KakaoCallCardOcr._();

  static const String programGeneral = '카카오(일반)';
  static const String programPro = '카카오(프콜)';
  static const String programAlliance = '카카오(제휴)';

  static final RegExp _driverScorePointsInText = RegExp(
    r'(?<![0-9,])([0-9]{1,5}(?:,[0-9]{3})*|[0-9]{1,5})\s*점(?![0-9])',
  );

  static bool hasCallCardDriverScoreMarker(String fullText, [List<TextBlock>? blocks]) {
    final flat = fullText.replaceAll(RegExp(r'[\r\n]+'), ' ');
    if (_driverScorePointsInText.hasMatch(flat)) return true;
    if (blocks != null) {
      for (final b in blocks) {
        final t = b.text.trim().replaceAll(',', '');
        if (RegExp(r'^[0-9]{1,5}점$').hasMatch(t)) return true;
      }
    }
    return false;
  }

  static String refineProgramByAllianceHeuristic(
    String fullText,
    List<TextBlock> blocks,
    String detected,
  ) {
    if (detected != programGeneral) return detected;
    if (hasCallCardDriverScoreMarker(fullText, blocks)) return programGeneral;
    return programAlliance;
  }

  static String _compact(String s) => s.replaceAll(RegExp(r'\s+'), '');

  static bool _assignmentComplete(String n) =>
      n.contains('배정완료') || (n.contains('배정') && n.contains('완료'));

  static bool _tPhone(String n) =>
      n.contains('T전화') || RegExp(r'T.{0,3}전화').hasMatch(n);

  static bool _hasForm2UiMarkers(String n) {
    if (n.contains('상황실')) return true;
    if (n.contains('고객') && n.contains('메모')) return true;
    if (n.contains('배정취소') && n.contains('잔여') && n.contains('시간')) return true;
    if (n.contains('취소불가')) return true;
    if (n.contains('고객과만날장소') || n.contains('만날장소길찾기')) return true;
    if (n.contains('밀어서고객에게') || n.contains('도착알림')) return true;
    if (n.contains('출발지에도착')) return true;
    return false;
  }

  static bool _hasCorporateInsurance(String n) =>
      n.contains('법인무료보험') || (n.contains('법인') && n.contains('무료보험'));

  static String? detectKakaoProgram(String fullText) {
    final n = _compact(fullText);
    if (n.isEmpty) return null;

    final hasCallCustomer = n.contains('고객과통화');
    final assignment = _assignmentComplete(n);
    final tPhone = _tPhone(n);
    final hasOpsCenter = n.contains('운영센터');
    final form2Ui = _hasForm2UiMarkers(n);
    final corporateInsurance = _hasCorporateInsurance(n);

    if (hasCallCustomer && assignment) {
      return programGeneral;
    }

    if (assignment && hasOpsCenter) {
      return programPro;
    }

    if (tPhone && form2Ui && corporateInsurance && !hasOpsCenter) {
      return programPro;
    }

    if (tPhone && !hasOpsCenter && !corporateInsurance && (form2Ui || assignment)) {
      return programGeneral;
    }

    if (!hasOpsCenter && !corporateInsurance && form2Ui && assignment) {
      return programGeneral;
    }

    if (hasCallCustomer) {
      return programGeneral;
    }

    if ((n.contains('카카오T') || n.contains('카카오')) &&
        (assignment || form2Ui || hasCallCustomer)) {
      return programGeneral;
    }

    return null;
  }

  static String? _tryExtractDateYmd(String full) {
    final m = RegExp(r'(\d{4})[-./](\d{1,2})[-./](\d{1,2})').firstMatch(full);
    if (m == null) return null;
    return '${m.group(1)}-${m.group(2)!.padLeft(2, '0')}-${m.group(3)!.padLeft(2, '0')}';
  }

  static Future<KakaoScreenParsed> parseScreen(
    List<TextBlock> blocks,
    String fullText,
    String detectedProgram, {
    String? paymentMethodHint,
  }) async {
    final r = await GeminiApiService.instance.parseCallCard(
      fullText: fullText,
      detectedProgram: detectedProgram,
    );
    if (r.usageExceeded || r.fields == null) {
      return KakaoScreenParsed(
        driveDateYmd: _tryExtractDateYmd(fullText),
        driveTimeHm: null,
        waypoint: '',
        startLocation: '',
        endLocation: '',
        grossFare: null,
        paymentMethod: paymentMethodHint,
      );
    }
    final f = r.fields!;
    final timeNorm = f.driveTimeHm.isEmpty
        ? null
        : (normalizeDriveTimeHm(f.driveTimeHm) ?? f.driveTimeHm);
    return KakaoScreenParsed(
      driveDateYmd: _tryExtractDateYmd(fullText),
      driveTimeHm: timeNorm,
      waypoint: f.waypoint,
      startLocation: f.startLocation,
      endLocation: f.endLocation,
      grossFare: f.grossFare > 0 ? f.grossFare : null,
      paymentMethod: paymentMethodHint,
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
